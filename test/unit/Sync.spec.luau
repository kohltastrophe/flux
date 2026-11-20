--!nonstrict
local env = if game ~= nil
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Flux, sert = env.Flux, env.sert

local test = sert.test
local expect = sert
local flush = Flux.flush
local create = Flux.Sync._internal.create

-- A loopback network: one server and `count` clients in this VM. Messages queue per direction (FIFO, like reliable
-- remotes) until `deliver` hands them over, so tests control latency and interleaving.
local function world(count: number)
	local w = { clients = {}, toServer = {}, log = {} }
	-- remote-shaped tables, like the RemoteEvent and UnreliableRemoteEvent the default instance uses
	local function serverRemote(unreliable: boolean)
		return {
			FireClient = function(_, player, ...)
				local entry = table.pack(...)
				entry.to, entry.unreliable = player, unreliable
				table.insert(w.log, entry)
				table.insert(player.inbox, table.pack(...))
			end,
			FireAllClients = function(_, ...)
				local entry = table.pack(...)
				entry.to, entry.unreliable = "all", unreliable
				table.insert(w.log, entry)
				for _, client in w.clients do
					table.insert(client.inbox, table.pack(...))
				end
			end,
		}
	end
	local server, serverInst = create(true, serverRemote(false), serverRemote(true))
	w.server, w.serverInst = server, serverInst

	function w.addClient()
		local client = { Name = `Player{#w.clients + 1}`, inbox = {} }
		client.sync, client.inst = create(false, {
			FireServer = function(_, ...)
				table.insert(w.toServer, table.pack(client, ...))
			end,
		})
		table.insert(w.clients, client)
		return client
	end
	for _ = 1, count do
		w.addClient()
	end

	function w.deliverServer(): boolean
		local message = table.remove(w.toServer, 1)
		if message then
			serverInst:receive(table.unpack(message, 1, message.n))
		end
		return message ~= nil
	end
	function w.deliverClient(client): boolean
		local message = table.remove(client.inbox, 1)
		if message then
			client.inst:receive(table.unpack(message, 1, message.n))
		end
		return message ~= nil
	end
	function w.deliver()
		local busy = true
		while busy do
			busy = w.deliverServer()
			for _, client in w.clients do
				while w.deliverClient(client) do
					busy = true
				end
			end
		end
	end
	-- one network frame: everyone flushes, then everything in flight arrives
	function w.step()
		flush()
		serverInst:flush()
		for _, client in w.clients do
			client.inst:flush()
		end
		w.deliver()
	end
	function w.settle()
		for _ = 1, 4 do
			w.step()
		end
	end
	function w.join(client)
		client.inst:start()
		w.settle()
	end
	function w.joinAll()
		for _, client in w.clients do
			client.inst:start()
		end
		w.settle()
	end
	function w.destroy()
		serverInst:destroy()
		for _, client in w.clients do
			client.inst:destroy()
		end
	end
	return w
end

test("sync · Flux.Sync(key, initial), and lazy .Key return one node", function()
	local w = world(0)
	local a = w.server("Gold", 10)
	expect(w.server.Gold == a, "every form returns the same signal")
	expect(a() == 10 and a:peek() == 10 and Flux.read(a) == 10, "it reads like a signal")
	expect(Flux.isNode(a), "it is a Flux node")
	local lazy = w.server.Later
	expect(lazy() == nil, "a lazy key starts nil")
	w.server("Later", 5)
	expect(lazy() == 5, "a later initial applies while nothing wrote it")
	lazy(7)
	w.server("Later", 99)
	expect(lazy() == 7, "an initial never overwrites a written value")
	w.destroy()
end)

test("sync · ids pack into 1 byte below 256 and 2 bytes after", function()
	local w = world(0)
	local first, last
	for i = 0, 300 do
		w.server(`k{i}`, i)
	end
	local client = w.addClient()
	w.join(client)
	for id, data in w.log[1][1] do
		if data[1] == "k0" then
			first = id
		elseif data[1] == "k300" then
			last = id
		end
	end
	expect(#first == 1 and #last == 2, `ids are {#first} and {#last} bytes`)
	expect(client.sync.k300() == 300, "the handshake carries every value")
	w.destroy()
end)

test("sync · join syncs current values; client signals made early fill in", function()
	local w = world(1)
	local client = w.clients[1]
	local early = client.sync("Round", "Waiting")
	expect(early() == "Waiting", "a client signal reads its default before joining")
	w.server("Round", "Lobby")
	w.server("Nil", nil)
	w.joinAll()
	expect(early() == "Lobby", "the handshake replaces the default")
	expect(client.sync("Round", "ignored") == early and early() == "Lobby", "a late initial does not clobber")
	w.destroy()
end)

test("sync · server writes coalesce into one batch per frame and reach every client", function()
	local w = world(2)
	local round = w.server("Round", "Lobby")
	local hp = w.server("HP", 100)
	w.joinAll()
	table.clear(w.log)
	round("Starting")
	round("Fighting")
	hp(50)
	hp(40)
	w.step()
	expect(#w.log == 1 and w.log[1].to == "all", `one broadcast, got {#w.log}`)
	expect(w.log[1].n == 4, "two ids and two values")
	for _, client in w.clients do
		expect(client.sync.Round() == "Fighting" and client.sync.HP() == 40, "each client has the last values")
	end
	table.clear(w.log)
	w.step()
	expect(#w.log == 0, "an idle frame sends nothing")
	w.destroy()
end)

test("sync · nil writes replicate", function()
	local w = world(1)
	local target = w.server("Target", "a")
	w.joinAll()
	target:set(nil)
	w.step()
	expect(w.clients[1].sync.Target() == nil, "the client sees nil")
	w.destroy()
end)

test("sync · a table changed in place replicates with :update()", function()
	local w = world(1)
	local items = w.server("Items", { "Sword" })
	w.joinAll()
	table.clear(w.log)
	table.insert(items:peek(), "Shield")
	items:update()
	w.step()
	-- the loopback hands the client the same table, so check that it was sent
	expect(#w.log == 1 and w.log[1][2] == items:peek(), "the mutated table is sent")
	w.destroy()
end)

test("sync · new keys created after join are announced", function()
	local w = world(1)
	w.joinAll()
	local client = w.clients[1]
	local waiting = client.sync.Later
	w.server("Later", 3)
	w.step()
	expect(waiting() == 3, "the client signal links and takes the value")
	w.destroy()
end)

test("sync · reactive on the client: computeds and effects follow remote updates", function()
	local w = world(1)
	local score = w.server("Score", 1)
	w.joinAll()
	local local_ = w.clients[1].sync.Score
	local doubled = Flux.computed(function()
		return local_() * 2
	end)
	local seen = {}
	local e = Flux.effect(function()
		table.insert(seen, doubled())
	end)
	flush()
	score(5)
	w.step()
	flush()
	expect(seen[#seen] == 10 and #seen == 2, `effect saw {table.concat(seen, ",")}`)
	e:Destroy()
	w.destroy()
end)

test("sync · per-player values reach only their player; clear falls back", function()
	local w = world(2)
	local coins = w.server("Coins", 0)
	w.joinAll()
	local a, b = w.clients[1], w.clients[2]
	local mine = coins:of(a)
	expect(coins:of(a) == mine and mine() == 0, "one node per player, seeded from the shared value")
	mine(250)
	w.step()
	expect(a.sync.Coins() == 250 and b.sync.Coins() == 0, "only player 1 sees 250")
	coins(10)
	w.step()
	expect(a.sync.Coins() == 250 and b.sync.Coins() == 10, "a shared write skips players with their own value")
	coins:clear(a)
	w.step()
	expect(a.sync.Coins() == 10, "clearing falls back to the shared value")
	expect(a.sync.Coins:of(a) == a.sync.Coins, "on a client :of is the signal itself")
	a.sync.Coins:clear(a)
	expect(a.sync.Coins() == 10, "on a client :clear does nothing")
	w.destroy()
end)

test("sync · a per-player value made after a shared write in the same frame reaches its player", function()
	local w = world(2)
	local coins = w.server("Coins", 0)
	w.joinAll()
	local a, b = w.clients[1], w.clients[2]
	coins(10)
	local mine = coins:of(a) -- seeded with 10, which a has not been sent yet
	coins(20)
	w.step()
	expect(mine() == 10 and a.sync.Coins() == 10, `player 1 sees its own 10, got {a.sync.Coins()}`)
	expect(b.sync.Coins() == 20, "player 2 sees the shared value")
	w.destroy()
end)

test("sync · per-player state joins correctly and is dropped on leave", function()
	local w = world(1)
	local coins = w.server("Coins", 0)
	local client = w.clients[1]
	local own = coins:of(client)
	own(42)
	w.join(client)
	expect(client.sync.Coins() == 42, "the handshake uses the player's own value")
	w.serverInst:playerRemoving(client)
	expect(own() == nil, "the per-player node is destroyed")
	local ok, err = pcall(coins.of, coins, client)
	expect(not ok and string.find(err, "left", 1, true) ~= nil, "a player who left has no per-player value")
	client.inst:start()
	w.settle()
	expect(next(w.serverInst.received) == nil, "a hello from a player who left is ignored")
	w.destroy()
end)

test("sync · ready is true on the server and turns true on a client after the handshake", function()
	local w = world(1)
	local client = w.clients[1]
	expect(w.server.ready() == true, "the server is always ready")
	expect(client.sync.ready() == false, "a client waits for the handshake")
	local seen = {}
	local e = Flux.effect(function()
		table.insert(seen, client.sync.ready())
	end)
	flush()
	w.joinAll()
	flush()
	expect(client.sync.ready() == true and #seen == 2, "the handshake flips ready once")
	e:Destroy()
	w.destroy()
end)

test("sync · server-only by default: client writes roll back", function()
	local w = world(1)
	local gold = w.server("Gold", 100)
	w.joinAll()
	local mine = w.clients[1].sync.Gold
	mine(999999)
	expect(mine() == 999999, "the write is optimistic")
	w.settle()
	expect(gold() == 100 and mine() == 100, "the server ignores it and corrects the client")
	w.destroy()
end)

test("sync · validator accepts, rejects and sanitizes", function()
	local w = world(2)
	local volume = w.server("Volume", 5, function(_, value)
		if type(value) ~= "number" then
			return false
		end
		return true, math.clamp(value, 0, 10)
	end)
	w.joinAll()
	local a, b = w.clients[1], w.clients[2]
	a.sync.Volume(7)
	w.settle()
	expect(volume() == 7 and b.sync.Volume() == 7, "accepted writes go shared without per-player use")
	a.sync.Volume("loud")
	w.settle()
	expect(volume() == 7 and a.sync.Volume() == 7, "a rejected write rolls back")
	a.sync.Volume(50)
	w.settle()
	expect(volume() == 10 and a.sync.Volume() == 10 and b.sync.Volume() == 10, "a sanitized write corrects the sender")
	w.destroy()
end)

test("sync · accepted writes do not echo; per-player use routes accepts to the player", function()
	local w = world(2)
	local theme = w.server("Theme", "Dark", function(_, value)
		return value == "Dark" or value == "Light"
	end)
	w.joinAll()
	local a, b = w.clients[1], w.clients[2]
	theme:of(b) -- per-player use turns accepted writes into per-player writes
	table.clear(w.log)
	a.sync.Theme("Light")
	w.settle()
	expect(theme:of(a)() == "Light" and theme() == "Dark", "stored on the sender's own value")
	expect(b.sync.Theme() == "Dark", "other players are unaffected")
	for _, entry in w.log do
		if entry.to == a then
			expect(entry.n == 1, "the sender only gets an ack, not its value back")
		end
	end
	w.destroy()
end)

test("sync · validators may write the signal directly", function()
	local w = world(1)
	local name
	name = w.server("Name", "", function(player, value)
		name:of(player)(`[{player.Name}] {value}`)
		return false
	end)
	local clamped
	clamped = w.server("Clamped", 10, function(_, value)
		if type(value) ~= "number" then
			return false
		end
		clamped(math.clamp(value, 0, 10))
		return true
	end)
	local perPlayerClamp
	perPlayerClamp = w.server("PerPlayerClamp", 10, function(player, value)
		if type(value) ~= "number" then
			return false
		end
		perPlayerClamp:of(player)(math.clamp(value, 0, 10))
		return true
	end)
	local clearedNoOp
	clearedNoOp = w.server("ClearedNoOp", 10, function(player, _value)
		clearedNoOp:clear(player)
		return true
	end)
	w.joinAll()
	local client = w.clients[1]
	perPlayerClamp:of(client)(10)
	w.settle()
	local mine = client.sync.Name
	mine("hi")
	client.sync.Clamped(50)
	client.sync.PerPlayerClamp(50)
	client.sync.ClearedNoOp(99)
	w.settle()
	expect(mine() == "[Player1] hi", `the client sees the server's value, got {mine()}`)
	expect(
		clamped() == 10 and client.sync.Clamped() == 10,
		`direct no-op clamp overrides return true, got server={clamped()} client={client.sync.Clamped()}`
	)
	expect(
		perPlayerClamp:of(client)() == 10 and client.sync.PerPlayerClamp() == 10,
		`direct per-player no-op clamp overrides return true, got server={perPlayerClamp:of(client)()} client={client.sync.PerPlayerClamp()}`
	)
	expect(
		clearedNoOp() == 10 and client.sync.ClearedNoOp() == 10,
		`direct no-op :clear(player) suppresses fallback write, got server={clearedNoOp()} client={client.sync.ClearedNoOp()}`
	)
	w.destroy()
end)

test("sync · a validator error warns and rolls back", function()
	local w = world(1)
	local value = w.server("V", 1, function()
		error("boom")
	end)
	w.joinAll()
	local messages = env.warnings(function()
		w.clients[1].sync.V(2)
		w.settle()
	end)
	expect(value() == 1 and w.clients[1].sync.V() == 1, "rolled back")
	expect(#messages == 1 and string.find(messages[1], "boom", 1, true) ~= nil, "warned once")
	w.destroy()
end)

test("sync · a validator that yields rejects the write and warns once", function()
	local w = world(1)
	local value = w.server("V", 1, function()
		coroutine.yield()
		return true
	end)
	w.joinAll()
	local mine = w.clients[1].sync.V
	local messages = env.warnings(function()
		mine(2)
		w.settle()
		mine(3)
		w.settle()
	end)
	expect(value() == 1 and mine() == 1, "both writes rolled back")
	expect(#messages == 1 and string.find(messages[1], "yield", 1, true) ~= nil, "warned once")
	w.destroy()
end)

test("sync · writes before joining are sent once linked", function()
	local w = world(1)
	w.server("Ready", false, function()
		return true
	end)
	local client = w.clients[1]
	client.sync.Ready(true)
	w.join(client)
	expect(w.server.Ready() == true and client.sync.Ready() == true, "the queued write reached the server")
	w.destroy()
end)

test("sync · a stale rollback never clobbers a newer accepted write", function()
	local w = world(1)
	local n = w.server("N", 0, function(_, value)
		return value ~= 1
	end)
	w.joinAll()
	local client = w.clients[1]
	n:of(client) -- per-player, so the accepted write is not broadcast back
	local mine = client.sync.N
	mine(1) -- will be rejected
	client.inst:flush()
	mine(2) -- will be accepted, with no echo
	client.inst:flush()
	w.deliverServer() -- server rejects 1
	w.serverInst:flush() -- correction (0) heads to the client
	w.deliverServer() -- server accepts 2
	w.serverInst:flush()
	w.deliver()
	expect(n:of(client)() == 2 and mine() == 2, `server {n:of(client)()}, client {mine()}`)
	w.destroy()
end)

test("sync · unreliable signals use the unreliable transport", function()
	local w = world(1)
	local pos = w.server("Pos", 0):unreliable()
	w.joinAll()
	table.clear(w.log)
	pos(5)
	w.step()
	expect(#w.log == 1 and w.log[1].unreliable == true, "sent unreliably")
	expect(w.clients[1].sync.Pos() == 5, "and applied")
	pos:unreliable(false)
	table.clear(w.log)
	pos(6)
	w.step()
	expect(w.log[1].unreliable == false, "switched back to reliable")
	w.destroy()
end)

test("sync · the Flux frame flushes Sync instances", function()
	local w = world(1)
	local value = w.server("Frame", 0)
	w.joinAll()
	value(9)
	w.server.flush()
	expect(#w.clients[1].inbox == 1, "a namespace's flush sends now")
	w.clients[1].inbox = {}
	value(10)
	local arrived = env.frames(function()
		w.deliver()
		return w.clients[1].sync.Frame() == 10
	end, 10)
	expect(arrived, "the frame step flushed the server")
	w.destroy()
end)

test("sync · untrusted messages are ignored", function()
	local w = world(1)
	local value = w.server("Safe", 1, function()
		return true
	end)
	w.joinAll()
	local client = w.clients[1]
	w.serverInst:receive(client, {}, 1, "\255\255", 2, nil, 3)
	w.serverInst:receive({ Name = "Stranger" }, "\0", 5)
	expect(value() == 1, "bad ids and players that never joined change nothing")
	w.destroy()
end)

local function validateSyncV(_, v): (boolean, number?)
	if type(v) ~= "number" or v % 5 == 0 then
		return false
	end
	return true, math.min(v, 39)
end

local function validServerInt(g: any): number
	local v = g:int(1, 38)
	if v % 5 == 0 then
		v += 1
	end
	return v
end

local FluxSyncSpec = sert.sim.spec({
	name = "FluxSync",
	init = function()
		return {
			v = 1,
			other = "a",
			hasOwn = false,
			own = {},
			expectedOverrides = {},
		}
	end,
	project = function(sut: any)
		local own = {}
		local rawOwn = sut.value._own
		if rawOwn ~= nil then
			for idx, client in sut.players do
				local node = rawOwn[client]
				if node ~= nil then
					own[idx] = node:peek()
				end
			end
		end
		return {
			v = sut.value:peek(),
			other = sut.other:peek(),
			hasOwn = rawOwn ~= nil,
			own = own,
			expectedOverrides = table.clone(sut.expectedOverrides),
		}
	end,
	commands = {
		serverWriteV = {
			args = { 1, 2, 6, 14, 28, 39 },
			next = function(state, val)
				state.expectedOverrides = table.clone(state.own)
				state.v = val
			end,
		},
		serverWritePlayerV = {
			args = {
				{ player = 1, value = 2 },
				{ player = 2, value = 7 },
				{ player = 3, value = 19 },
			},
			next = function(state, arg)
				state.hasOwn = true
				state.own[arg.player] = arg.value
				state.expectedOverrides[arg.player] = arg.value
			end,
		},
		serverClearPlayerV = {
			args = { 1, 2, 3 },
			next = function(state, idx)
				state.own[idx] = nil
				state.expectedOverrides[idx] = nil
			end,
		},
		clientWriteV = {
			args = {
				{ player = 1, value = 5 },
				{ player = 1, value = 12 },
				{ player = 2, value = 45 },
			},
			next = function() end,
		},
		serverWriteOther = {
			args = { "a", "b", "c" },
			next = function(state, val)
				state.other = val
			end,
		},
		touchPlayerV = {
			args = { 1, 2, 3 },
			next = function(state, idx)
				state.hasOwn = true
				if state.own[idx] == nil then
					state.own[idx] = state.v
				end
				state.expectedOverrides[idx] = state.own[idx]
			end,
		},
		flushServer = {
			next = function() end,
		},
		flushClient = {
			args = { 1, 2, 3 },
			next = function() end,
		},
		deliverServer = {
			args = {
				{ joined = false, hasValue = false, player = 1, value = 0 },
				{ joined = true, hasValue = true, player = 1, value = 5 },
				{ joined = true, hasValue = true, player = 1, value = 12 },
				{ joined = true, hasValue = true, player = 2, value = 45 },
			},
			next = function(state, arg, result)
				local packet = if result ~= nil then result else arg
				if packet ~= nil and packet.joined and packet.hasValue then
					local ok, sanitized = validateSyncV(nil, packet.value)
					if ok and sanitized ~= nil then
						if state.hasOwn then
							state.own[packet.player] = sanitized
							state.expectedOverrides[packet.player] = sanitized
						else
							state.v = sanitized
						end
					end
				end
			end,
		},
		deliverClient = {
			args = { 1, 2, 3 },
			next = function() end,
		},
	},
	invariants = {
		neverUnvalidatedServerValue = function(state)
			sert(state.v % 5 ~= 0 and state.v <= 40, "server V never holds unvalidated value")
			for _, v in state.own do
				sert(v % 5 ~= 0 and v <= 40, "per-player override never holds unvalidated value")
			end
		end,
		sharedWriteNeverClobbersOverride = function(state)
			for idx, expected in state.expectedOverrides do
				sert.eq(state.own[idx], expected, `shared write never clobbers player {idx} override`)
			end
		end,
		authoritativeStateValid = function(state, sut)
			sert(state.v >= 1 and state.v <= 39 and state.v % 5 ~= 0, "server V stays sanitized")
			sert(state.other == "a" or state.other == "b" or state.other == "c", "server Other stays valid")
			if sut ~= nil then
				sert.eq(sut.value:peek(), state.v, "sut.value matches spec state.v")
				sert.eq(sut.other:peek(), state.other, "sut.other matches spec state.other")
			end
		end,
	},
})

test("sync · pure state specification holds", function()
	sert.sim.check(FluxSyncSpec, {
		maxStates = 200,
		maxDepth = 6,
	})
end)

local syncModelSpec = {
	init = function()
		return {
			pub = 1,
			map = { a = 1, b = 1 },
			priv = { [1] = nil :: number?, [2] = nil :: number?, [3] = nil :: number? },
			privHistory = { [1] = { [0] = true }, [2] = { [0] = true }, [3] = { [0] = true } },
			aim = 0,
			joined = { [1] = true, [2] = true, [3] = false },
			pendingAllowed = { [1] = false, [2] = false, [3] = false },
			lastRejected = { [1] = nil :: number?, [2] = nil :: number?, [3] = nil :: number? },
			converged = false,
		}
	end,
	setup = function()
		local simWorld = sert.sim.new({ mode = "manual", faults = "none" })
		local srv = simWorld:server()
		local srvEnv = srv:env()
		local c1 = srv:client(101)
		local c2 = srv:client(102)
		local c3 = srv:client(103)

		local srvRep = srvEnv.game:GetService("ReplicatedStorage")
		local srvReliable = srvEnv.Instance.new("RemoteEvent", srvRep)
		srvReliable.Name = "SyncEvent"
		local srvUnreliable = srvEnv.Instance.new("UnreliableRemoteEvent", srvRep)
		srvUnreliable.Name = "SyncUnreliable"

		local serverSync, serverInst = create(true, srvReliable, srvUnreliable)
		srvReliable.OnServerEvent:Connect(function(player, ...)
			serverInst:receive(player, ...)
		end)
		srvEnv.game:GetService("Players").PlayerRemoving:Connect(function(player)
			serverInst:playerRemoving(player)
		end)

		local pub = serverSync("Public", 1, validateSyncV)
		local map = serverSync("Map", { a = 1, b = 1 })
		local priv = serverSync("Private", 0)
		local aim = serverSync("Aim", 0):unreliable()

		local srvPlayers = srvEnv.game:GetService("Players")
		local peers = {}
		for idx, simClient in { c1, c2, c3 } do
			local cEnv = simClient:env()
			local rep = cEnv.game:GetService("ReplicatedStorage")
			local rel = rep:FindFirstChild("SyncEvent")
			local unrel = rep:FindFirstChild("SyncUnreliable")
			local cSync, cInst = create(false, rel, unrel)
			rel.OnClientEvent:Connect(function(...)
				cInst:receive(...)
			end)
			unrel.OnClientEvent:Connect(function(...)
				cInst:receive(...)
			end)
			local userId = 100 + idx
			local srvPlayer = srvPlayers:GetPlayerByUserId(userId)
			peers[idx] = {
				idx = idx,
				userId = userId,
				simClient = simClient,
				srvPlayer = srvPlayer,
				sync = cSync,
				inst = cInst,
				pub = cSync("Public", 0, true),
				map = cSync("Map", { a = 0, b = 0 }),
				priv = cSync("Private", 0),
				aim = cSync("Aim", 0),
			}
		end

		peers[1].inst:start()
		peers[2].inst:start()
		simWorld:step()

		return {
			simWorld = simWorld,
			srv = srv,
			serverSync = serverSync,
			serverInst = serverInst,
			pub = pub,
			map = map,
			priv = priv,
			aim = aim,
			peers = peers,
		}
	end,
	teardown = function(sut)
		sut.serverInst:destroy()
		for _, peer in sut.peers do
			peer.inst:destroy()
		end
	end,
	commands = {
		ServerSetPublic = {
			gen = function(_state, g)
				return {
					pub = validServerInt(g),
					aim = g:int(1, 50),
				}
			end,
			run = function(sut, arg)
				sut.pub(arg.pub)
				sut.aim(arg.aim)
			end,
			next = function(state, arg)
				state.pub = arg.pub
				state.aim = arg.aim
				state.converged = false
			end,
		},
		ServerUpdateMap = {
			gen = function(_state, g)
				return {
					key = g:pick({ "a", "b" }),
					val = g:int(1, 30),
				}
			end,
			run = function(sut, arg)
				local cur = sut.map:peek()
				cur[arg.key] = arg.val
				sut.map:update()
			end,
			next = function(state, arg)
				state.map[arg.key] = arg.val
				state.converged = false
			end,
		},
		ServerSetPrivate = {
			gen = function(_state, g)
				local peer = g:int(1, 3)
				return {
					peer = peer,
					clear = g:bool(0.25),
					val = peer * 100 + g:int(1, 30),
				}
			end,
			run = function(sut, arg)
				local srvPlayer = sut.peers[arg.peer].srvPlayer
				if arg.clear then
					sut.priv:clear(srvPlayer)
				else
					sut.priv:of(srvPlayer)(arg.val)
				end
			end,
			next = function(state, arg)
				state.priv[arg.peer] = if arg.clear then nil else arg.val
				if not arg.clear then
					state.privHistory[arg.peer][arg.val] = true
				end
				state.converged = false
			end,
		},
		ClientPatchAllowed = {
			gen = function(_state, g)
				return {
					peer = g:int(1, 3),
					val = validServerInt(g) + g:pick({ 0, 20 }),
				}
			end,
			run = function(sut, arg)
				sut.peers[arg.peer].pub(arg.val)
			end,
			next = function(state, arg)
				local peer = arg.peer
				if state.joined[peer] then
					state.pendingAllowed[peer] = true
				end
				state.lastRejected[peer] = nil
				state.converged = false
			end,
		},
		ClientPatchRejected = {
			gen = function(_state, g)
				return {
					peer = g:int(1, 3),
					val = g:int(1, 10) * 5,
				}
			end,
			run = function(sut, arg)
				sut.peers[arg.peer].pub(arg.val)
			end,
			next = function(state, arg)
				local peer = arg.peer
				state.lastRejected[peer] = arg.val
				state.converged = false
			end,
		},
		FlushFrame = {
			gen = function(_state, g)
				return g:pick({ "step", "settle" })
			end,
			run = function(sut, mode)
				if mode == "settle" then
					sut.simWorld.faults.drop = 0
				end
				sut.serverInst:flush()
				for _, peer in sut.peers do
					peer.inst:flush()
				end
				if mode == "settle" then
					for _, peer in sut.peers do
						if not peer.inst.joined then
							peer.inst:start()
						end
					end
					for _ = 1, 4 do
						sut.serverInst:flush()
						for _, peer in sut.peers do
							peer.inst:flush()
						end
						sut.simWorld:step()
					end
				end
				return sut.pub:peek()
			end,
			next = function(state, mode, pubVal)
				if mode == "settle" then
					for idx = 1, 3 do
						state.joined[idx] = true
						state.pendingAllowed[idx] = false
					end
					if pubVal ~= nil then
						state.pub = pubVal
					end
					state.converged = true
				else
					state.converged = false
				end
			end,
		},
		DeliverOrDropPacket = {
			gen = function(_state, g)
				return {
					dropUnreliable = g:bool(0.5),
					advance = g:bool(0.75),
				}
			end,
			run = function(sut, arg)
				sut.simWorld.faults.drop = if arg.dropUnreliable then 1 else 0
				if arg.advance then
					sut.simWorld:step()
				else
					sut.simWorld.scheduler:drain()
				end
				return sut.pub:peek()
			end,
			next = function(state, _, pubVal)
				if pubVal ~= nil then
					state.pub = pubVal
				end
				state.converged = false
			end,
		},
		JoinLateClient = {
			run = function(sut)
				local peer = sut.peers[3]
				if not peer.inst.joined then
					peer.inst:start()
					sut.simWorld:step()
					sut.serverInst:flush()
					sut.simWorld:step()
				end
				return sut.pub:peek()
			end,
			next = function(state, _, pubVal)
				state.joined[3] = true
				if pubVal ~= nil then
					state.pub = pubVal
				end
				state.converged = false
			end,
		},
	},
	invariants = {
		convergesAfterSettle = function(state, sut)
			if not state.converged then
				return
			end
			for idx, peer in sut.peers do
				sert(peer.inst.joined, `peer {idx} joined on settle`)
				local expectedPriv = state.priv[idx] or 0
				sert.eq(peer.pub:peek(), sut.pub:peek(), `peer {idx} Public converged to server`)
				sert.eq(peer.priv:peek(), expectedPriv, `peer {idx} Private converged to server`)
				local m = peer.map:peek()
				local sm = sut.map:peek()
				sert.eq(m.a, sm.a, `peer {idx} Map.a converged`)
				sert.eq(m.b, sm.b, `peer {idx} Map.b converged`)
				local rejected = state.lastRejected[idx]
				if rejected ~= nil then
					sert.ne(peer.pub:peek(), rejected, `rejected client patch reverted on peer {idx}`)
				end
			end
		end,
		serverAuthoritativeNeverCorrupted = function(_, sut)
			local v = sut.pub:peek()
			sert(type(v) == "number" and v >= 1 and v <= 39 and v % 5 ~= 0, "server Public stays valid and sanitized")
		end,
		privateStateIsolated = function(state, sut)
			for idx, peer in sut.peers do
				local srvVal = sut.priv:of(peer.srvPlayer):peek()
				local expected = state.priv[idx] or 0
				sert.eq(srvVal, expected, `server Private:of(p{idx}) matches model`)
				local clientVal = peer.priv:peek()
				sert(
					state.privHistory[idx][clientVal] == true,
					`client {idx} never observes another peer's Private value`
				)
			end
		end,
	},
}

sert.model("sync · random writes and delivery orders converge to the server's values", syncModelSpec, {
	runs = 120,
	length = 30,
})

test("sync · replicates across sert.sim server and client peers over RemoteEvents", function()
	local simWorld = sert.sim.new({ mode = "random", faults = "light", seed = 0x51A0 })
	local srv = simWorld:server()
	local srvEnv = srv:env()
	local c1 = srv:client(101)
	local c2 = srv:client(102)
	local c1Env = c1:env()
	local c2Env = c2:env()

	local srvRep = srvEnv.game:GetService("ReplicatedStorage")
	local srvReliable = srvEnv.Instance.new("RemoteEvent", srvRep)
	srvReliable.Name = "SyncEvent"
	local srvUnreliable = srvEnv.Instance.new("UnreliableRemoteEvent", srvRep)
	srvUnreliable.Name = "SyncUnreliable"

	local serverSync, serverInst = create(true, srvReliable, srvUnreliable)
	srvReliable.OnServerEvent:Connect(function(player, ...)
		serverInst:receive(player, ...)
	end)
	srvEnv.game:GetService("Players").PlayerRemoving:Connect(function(player)
		serverInst:playerRemoving(player)
	end)

	local score = serverSync("Score", 10)
	local bid = serverSync("Bid", 1, function(_, v)
		if type(v) ~= "number" or v < 0 then
			return false
		end
		return true, math.min(v, 100)
	end)
	local aim = serverSync("Aim", 0):unreliable()

	local function bindClient(cEnv: any)
		local rep = cEnv.game:GetService("ReplicatedStorage")
		local rel = rep:FindFirstChild("SyncEvent")
		local unrel = rep:FindFirstChild("SyncUnreliable")
		local cSync, cInst = create(false, rel, unrel)
		rel.OnClientEvent:Connect(function(...)
			cInst:receive(...)
		end)
		unrel.OnClientEvent:Connect(function(...)
			cInst:receive(...)
		end)
		return cSync, cInst
	end

	local c1Sync, c1Inst = bindClient(c1Env)
	local c2Sync, c2Inst = bindClient(c2Env)
	local c1Score = c1Sync("Score", 0)
	local c2Score = c2Sync("Score", 0)
	local c1Bid = c1Sync("Bid", 0, true)
	local c2Bid = c2Sync("Bid", 0, true)
	local c1Aim = c1Sync("Aim", 0)

	local sendAim = false
	simWorld:onFrame(function()
		if sendAim then
			aim(42)
			aim:update()
		end
		serverInst:flush()
		c1Inst:flush()
		c2Inst:flush()
	end)

	-- 1. Handshake & initial state sync
	c1Inst:start()
	c2Inst:start()
	simWorld:runUntil(function()
		return c1Inst.joined and c2Inst.joined and c1Score() == 10 and c2Score() == 10
	end, 2)
	expect.eq(c1Score(), 10, "client 1 received initial Score on handshake")
	expect.eq(c2Score(), 10, "client 2 received initial Score on handshake")

	-- 2. Server broadcast & per-player :of(player) override
	local p1OnServer = srvEnv.game:GetService("Players"):GetPlayerByUserId(101)
	score(25)
	score:of(p1OnServer)(99)
	simWorld:runUntil(function()
		return c1Score() == 99 and c2Score() == 25
	end, 2)
	expect.eq(c1Score(), 99, "client 1 receives per-player override")
	expect.eq(c2Score(), 25, "client 2 receives shared broadcast")

	-- 3. Client-to-server validated write (clamped to 100) and rejected write (< 0)
	c1Bid(250)
	simWorld:runUntil(function()
		return bid() == 100 and c2Bid() == 100
	end, 2)
	expect.eq(bid(), 100, "server clamps client 1 bid to 100")
	expect.eq(c2Bid(), 100, "client 2 receives sanitized bid")

	c2Bid(-50)
	simWorld:run(0.5)
	expect.eq(bid(), 100, "negative client write is rejected by server validator")

	-- 4. Unreliable sync updates
	sendAim = true
	simWorld:runUntil(function()
		return c1Aim() == 42
	end, 2)
	sendAim = false
	expect.eq(c1Aim(), 42, "unreliable sync value arrives at client 1")

	serverInst:destroy()
	c1Inst:destroy()
	c2Inst:destroy()
end)

sert.test.roblox("sync · the default instance creates its remotes on the server without yielding", function()
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end
	local key = env.fresh("SyncSpecDefault")
	local signal = Flux.Sync(key, 1)
	expect(signal() == 1, "created synchronously")
	local module = game:GetService("ReplicatedStorage").Flux.Sync
	expect(module:FindFirstChild("SyncEvent") and module.SyncEvent:IsA("RemoteEvent"), "SyncEvent exists")
	expect(
		module:FindFirstChild("SyncUnreliable") and module.SyncUnreliable:IsA("UnreliableRemoteEvent"),
		"SyncUnreliable exists"
	)
	signal(2)
	Flux.Sync.flush()
	expect(Flux.Sync[key] == signal, "lazy indexing finds it")
end)

test("sync · functional update computes untracked, skips no-op writes, and supports player signals", function()
	local w = world(1)
	local c1 = w.clients[1]
	local bonus = Flux.signal(5)
	local serverScore = w.server("Score", 10)
	local clientScore = c1.sync("Score")
	w.joinAll()

	local readCount = 0
	local eff = Flux.effect(function()
		serverScore:update(function(cur)
			readCount += 1
			return cur + bonus()
		end)
	end)
	w.settle()
	expect.eq(clientScore(), 15, "functional update replicates new score")

	-- changing bonus must not re-run eff since fn ran untracked
	bonus:set(100)
	w.settle()
	expect.eq(readCount, 1, "Sync:update runs fn untracked")

	-- returning current value is a clean no-op without dirtying remotes
	local logBefore = #w.log
	expect.eq(
		serverScore:update(function(cur)
			return cur
		end),
		serverScore,
		"Sync:update returns self"
	)
	w.settle()
	expect.eq(#w.log, logBefore, "identical Sync:update skips batch replication")

	-- per-player PlayerMT also supports functional update
	local own = serverScore:of(c1)
	expect.eq(
		own:update(function(cur)
			return cur + 10
		end),
		own,
		"PlayerMT:update returns self"
	)
	w.settle()
	expect.eq(clientScore(), 25, "per-player functional update replicates to target player")

	sert.throws(function()
		serverScore:update("bad" :: any)
	end, "expected a function or nil")

	eff:Destroy()
	bonus:Destroy()
	w.destroy()
end)

test(
	"sync · validator returning true, nil clears nullable signal while return true preserves incoming value",
	function()
		local w = world(1)
		local c1 = w.clients[1]
		local nullable = w.server("Nullable", "init" :: string?, function(_, value)
			if value == "clear" then
				return true, nil
			end
			return false
		end)
		local keep = w.server("Keep", "init", function(_, _value)
			return true
		end)
		local cNullable = c1.sync("Nullable")
		local cKeep = c1.sync("Keep")
		w.joinAll()

		cNullable("clear")
		cKeep("accepted")
		w.settle()

		expect.eq(nullable(), nil, "returning true, nil clears nullable signal on server")
		expect.eq(cNullable(), nil, "returning true, nil replicates nil to client")
		expect.eq(keep(), "accepted", "returning true without second return accepts client value")
		expect.eq(cKeep(), "accepted", "returning true keeps accepted value on client")
		w.destroy()
	end
)

sert.test.roblox("sync · sweeping remotes under ReplicatedStorage recreates them without orphaning signals", function()
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end
	local key1 = env.fresh("SweepResilient1")
	local key2 = env.fresh("SweepResilient2")
	local sig1 = Flux.Sync(key1, 10)
	Flux.Sync.flush()

	local syncFolder = game:GetService("ReplicatedStorage").Flux.Sync
	local rel = syncFolder:FindFirstChild("SyncEvent")
	local unrel = syncFolder:FindFirstChild("SyncUnreliable")
	expect(rel ~= nil and unrel ~= nil, "initial server remotes exist under Flux.Sync")
	if rel then
		rel:Destroy()
	end
	if unrel then
		unrel:Destroy()
	end
	expect(
		syncFolder:FindFirstChild("SyncEvent") == nil and syncFolder:FindFirstChild("SyncUnreliable") == nil,
		"remotes removed cleanly by sweep simulation"
	)

	sig1(25)
	Flux.Sync.flush()
	expect(sig1() == 25 and Flux.Sync[key1] == sig1, "pre-existing default Sync signal remains alive after sweep")
	expect(
		syncFolder:FindFirstChild("SyncEvent") ~= nil and syncFolder:FindFirstChild("SyncUnreliable") ~= nil,
		"flushServer recreates destroyed remotes under ReplicatedStorage"
	)

	local rel2 = syncFolder:FindFirstChild("SyncEvent")
	if rel2 then
		rel2:Destroy()
	end
	local sig2 = Flux.Sync(key2, 99)
	Flux.Sync.flush()
	expect(sig2() == 99 and Flux.Sync[key2] == sig2, "newly created signal works after partial remote sweep")
	expect(syncFolder:FindFirstChild("SyncEvent") ~= nil, "getDefault recreates missing remote cleanly")
end)

test(
	"sync · SyncMT/PlayerMT Destroy, read-only namespace, validator scoping, 256-pair cap, and duplicate-nil coalescing",
	function()
		local w = world(2)
		local gold = w.server("Gold", 10)
		local other = w.server("Other", "init")
		local c1, c2 = w.clients[1], w.clients[2]
		w.joinAll()

		-- 1. SyncMT.Destroy errors on shared synced signal; namespace __newindex rejects direct assignment
		local okDestroyShared = pcall(function()
			gold:Destroy()
		end)
		expect(not okDestroyShared, "calling :Destroy() on shared Sync signal errors")

		local okAssignNs = pcall(function()
			(w.server :: any).Illegal = 123
		end)
		expect(not okAssignNs, "Sync namespace rejects direct field writes")

		-- 2. PlayerMT.Destroy delegates to clear(player) and reverts override to shared value
		local p1Gold = gold:of(c1)
		p1Gold(999)
		w.step()
		expect(c1.sync.Gold() == 999 and c2.sync.Gold() == 10, "per-player override replicated")
		p1Gold:Destroy()
		w.step()
		expect(c1.sync.Gold() == 10, "PlayerMT:Destroy clears override and replicates fallback to shared value")

		-- Writing a disposed PlayerMT signal after player left throws / does not crash or leak
		local p2Gold = gold:of(c2)
		p2Gold(55)
		w.serverInst:playerRemoving(c2) -- leave while p2Gold was dirty before step() clears playerDirty
		w.step()
		local okWriteDead, _ = pcall(function()
			p2Gold(77)
		end)
		expect(not okWriteDead or p2Gold() == nil, "disposed per-player signal is torn down cleanly")

		-- 3. Validator mutating another player's :of(other) does not swallow sending player's validator return
		local valSig = w.server("Validated", 0, function(player, val)
			if player == c1 then
				other:of(c1)("side-effect")
				return true, math.clamp(val :: number, 0, 100)
			end
			return false
		end)
		w.settle()
		c1.sync.Validated(500)
		w.settle()
		expect(
			valSig() == 100 and c1.sync.Validated() == 100 and c1.sync.Other() == "side-effect",
			"validator return still commits when validator writes another signal"
		)

		-- 4. MAX_BATCH_PAIRS = 256 cap + duplicate-ID coalescing including nil payload
		local keys = {}
		for i = 1, 260 do
			keys[i] = w.server(`cap{i}`, 0, function(_p, v)
				return true, v
			end)
		end
		local sigValidatorCalls = 0
		local dupKey = w.server("DupNil", "start", function(_p, v)
			sigValidatorCalls += 1
			return true, v
		end)
		table.clear(w.log)
		local lateClient = w.addClient()
		w.join(lateClient)
		local dupId: any = nil
		for id, meta in w.log[1][1] do
			if meta[1] == "DupNil" then
				dupId = id
				break
			end
		end
		expect(dupId ~= nil, "resolved signal ID for DupNil")

		for i = 1, 260 do
			c1.sync[`cap{i}`](9)
		end
		w.settle()
		local acceptedCap = 0
		for i = 1, 260 do
			if keys[i]() == 9 then
				acceptedCap += 1
			end
		end
		expect(acceptedCap == 256, `MAX_BATCH_PAIRS caps single packet at 256 pairs, got {acceptedCap}`)

		w.serverInst:receive(c1, dupId, "first", dupId, nil)
		w.settle()
		expect(
			dupKey() == nil and sigValidatorCalls == 1,
			"duplicate-ID pair coalesces to final nil value and runs validator once"
		)

		-- 5. announce with 0 clients does not send broadcasts
		local w0 = world(0)
		table.clear(w0.log)
		local s0 = w0.server("Lonely", 5)
		s0(10)
		w0.step()
		expect(#w0.log == 0, "0 connected clients emits no remote packets")
		w0.destroy()
		w.destroy()
	end
)

test(
	"sync · client leave with pending playerDirty, client :of/:clear/:update/:validate no-ops, and client packet handling",
	function()
		local w = world(2)
		local gold = w.server("Gold", 0, function(_, v)
			return true, v
		end)
		local c1, c2 = w.clients[1], w.clients[2]
		w.joinAll()

		-- 1. Server writes per-player dirty override and player leaves BEFORE w.step() (cleans playerDirty)
		gold:of(c2)(777)
		w.serverInst:playerRemoving(c2)
		w.step()
		expect(c1.sync.Gold() == 0, "c2 leaving before flush cleans dirty entry without corrupting c1")

		-- 2. Client-side helpers (:validate, :update, :unreliable, :clear)
		c1.sync.Gold:validate(function()
			return false
		end)
		c1.sync.Gold:unreliable(true)
		c1.sync.Gold:clear(c1)
		c1.sync.Gold:update(function(v)
			return (v :: number) + 5
		end)
		w.settle()
		expect(
			gold:of(c1)() == 5 and c1.sync.Gold() == 5 and gold() == 0,
			"client :update replicates per-player override when server entered :of mode and ignores server-only config methods"
		)

		local lateScoped = w.server("LateScoped", 1)
		local p1Late = lateScoped:of(c1)
		p1Late(42)
		w.step()
		expect(c1.sync.LateScoped() == 42, "late-announced signal with per-player override sends per-player announce")

		-- 3. Disposed per-player signals after player leave stay nil on write attempts
		w.serverInst:playerRemoving(c1)
		pcall(function()
			p1Late:set(99)
		end)
		expect(p1Late() == nil, "writes to disposed per-player Sync signal after leave do not revive value")
		w.destroy()
	end
)

test(
	"sync · unreliable rollback packet, validator clamp/cross-write, validator error recovery, and leaving with rollbackDirty",
	function()
		local w = world(2)
		local c1, c2 = w.clients[1], w.clients[2]
		local allow = true
		local shouldThrow = false
		local crossSignal = w.server("Cross", 0)
		local fastPos = w.server("FastPos", 10, function(player, val)
			if shouldThrow then
				error("validator crash")
			end
			if not allow then
				return false
			end
			crossSignal:of(c2)(val :: number + 1)
			return true, math.min(val :: number, 100)
		end):unreliable(true)
		w.joinAll()

		-- 1. Valid client write clamped & updates crossSignal for c2
		c1.sync.FastPos(250)
		w.settle()
		expect(
			fastPos() == 100 and crossSignal:of(c2)() == 251,
			"validator clamps accepted value and supports cross-player write"
		)

		-- 2. Rejected unreliable write emits reliable rollback packet directly to offending client
		allow = false
		table.clear(w.log)
		c1.sync.FastPos(999)
		w.settle()
		local sawReliableRollback = false
		for _, entry in w.log do
			if entry.unreliable == false and entry.to == c1 then
				sawReliableRollback = true
				break
			end
		end
		expect(
			sawReliableRollback and fastPos() == 100 and c1.sync.FastPos() == 100,
			"rejected unreliable client update rolls back reliably to server value"
		)

		-- 3. Validator error clears validating state so subsequent valid client writes work
		shouldThrow = true
		c1.sync.FastPos(5)
		flush()
		c1.inst:flush()
		pcall(function()
			w.deliverServer()
		end)
		shouldThrow = false
		allow = true
		c1.sync.FastPos(42)
		w.settle()
		expect(fastPos() == 42, "validator error clears validating state cleanly for later updates")

		-- 4. Leaving with pending rollbackDirty cleans rollbackDirty cleanly & destroying synced signal directly errors
		allow = false
		c2.sync.FastPos(888)
		flush()
		c2.inst:flush()
		w.deliverServer()
		w.serverInst:playerRemoving(c2) -- leaves BEFORE w.serverInst:flush() drains rollbackDirty[c2]
		w.step()
		expect(c1.sync.FastPos() == 42, "leaving before rollback flush cleans rollbackDirty without error")

		local okDestroy = pcall(function()
			fastPos:Destroy()
		end)
		expect(not okDestroy, "direct Destroy on synced signal raises explicit error")
		w.destroy()
	end
)
