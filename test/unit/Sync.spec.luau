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
	w.joinAll()
	local mine = w.clients[1].sync.Name
	mine("hi")
	w.settle()
	expect(mine() == "[Player1] hi", `the client sees the server's value, got {mine()}`)
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
	actions = {
		serverWriteV = {
			gen = { 1, 2, 6, 14, 28, 39 },
			next = function(state, val)
				state.expectedOverrides = table.clone(state.own)
				state.v = val
			end,
		},
		serverWritePlayerV = {
			gen = {
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
			gen = { 1, 2, 3 },
			next = function(state, idx)
				state.own[idx] = nil
				state.expectedOverrides[idx] = nil
			end,
		},
		clientWriteV = {
			gen = {
				{ player = 1, value = 5 },
				{ player = 1, value = 12 },
				{ player = 2, value = 45 },
			},
			next = function() end,
		},
		serverWriteOther = {
			gen = { "a", "b", "c" },
			next = function(state, val)
				state.other = val
			end,
		},
		touchPlayerV = {
			gen = { 1, 2, 3 },
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
			gen = { 1, 2, 3 },
			next = function() end,
		},
		deliverServer = {
			gen = {
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
			gen = { 1, 2, 3 },
			next = function() end,
		},
	},
	never = {
		unvalidatedServerValue = function(state)
			if state.v % 5 == 0 or state.v > 40 then
				return true
			end
			for _, v in state.own do
				if v % 5 == 0 or v > 40 then
					return true
				end
			end
			return false
		end,
		sharedWriteClobbersOverride = function(state)
			for idx, expected in state.expectedOverrides do
				if state.own[idx] ~= expected then
					return true
				end
			end
			return false
		end,
	},
	invariants = {
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

sert.sim.checkSpec("sync · pure state specification holds", FluxSyncSpec, {
	maxStates = 200,
	maxDepth = 6,
})

local syncModelSpec = {
	init = function()
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
			serverInst:leave(player)
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

		local state = {
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
		local sut = {
			simWorld = simWorld,
			srv = srv,
			net = simWorld:remotes(srv),
			serverSync = serverSync,
			serverInst = serverInst,
			pub = pub,
			map = map,
			priv = priv,
			aim = aim,
			peers = peers,
		}
		return state, sut
	end,
	teardown = function(sut)
		sut.serverInst:destroy()
		for _, peer in sut.peers do
			peer.inst:destroy()
		end
	end,
	commands = {
		ServerSetPublic = {
			gen = function(g)
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
			gen = function(g)
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
			gen = function(g)
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
			gen = function(g)
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
			gen = function(g)
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
			gen = function(g)
				return g:pick({ "step", "settle" })
			end,
			run = function(sut, mode)
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
			end,
			next = function(state, mode, _, sut)
				if mode == "settle" then
					for idx = 1, 3 do
						state.joined[idx] = true
						state.pendingAllowed[idx] = false
					end
					if sut ~= nil then
						state.pub = sut.pub:peek()
					end
					state.converged = true
				else
					state.converged = false
				end
			end,
		},
		DeliverOrDropPacket = {
			gen = function(g)
				return {
					dropUnreliable = g:bool(0.5),
					advance = g:bool(0.75),
				}
			end,
			run = function(sut, arg)
				if arg.dropUnreliable then
					local q = sut.net.queue
					for i = #q, 1, -1 do
						if q[i].channel == "SyncUnreliable" then
							table.remove(q, i)
							break
						end
					end
				end
				if arg.advance then
					sut.simWorld:step()
				else
					sut.net:flush()
				end
			end,
			next = function(state, _, _, sut)
				if sut ~= nil then
					state.pub = sut.pub:peek()
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
			end,
			next = function(state, _, _, sut)
				state.joined[3] = true
				if sut ~= nil then
					state.pub = sut.pub:peek()
				end
				state.converged = false
			end,
		},
	},
	never = {
		divergedAfterConverge = function(state, sut)
			if not state.converged then
				return false
			end
			for idx, peer in sut.peers do
				if not peer.inst.joined then
					return true
				end
				local expectedPriv = state.priv[idx] or 0
				if peer.pub:peek() ~= sut.pub:peek() or peer.priv:peek() ~= expectedPriv then
					return true
				end
				local m = peer.map:peek()
				local sm = sut.map:peek()
				if m.a ~= sm.a or m.b ~= sm.b then
					return true
				end
			end
			return false
		end,
		privateStateLeakedToOtherPeer = function(state, sut)
			for idx, peer in sut.peers do
				local observed = peer.priv:peek()
				if not state.privHistory[idx][observed] then
					return true
				end
			end
			return false
		end,
		rejectedClientPatchPersistedAfterAck = function(state, sut)
			if not state.converged then
				return false
			end
			for idx, peer in sut.peers do
				local rejected = state.lastRejected[idx]
				if rejected ~= nil and peer.pub:peek() == rejected then
					return true
				end
			end
			return false
		end,
	},
	invariants = {
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
		serverInst:leave(player)
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

sert.rtest("sync · the default instance creates its remotes on the server without yielding", function()
	local RunService = game:GetService("RunService")
	if not RunService:IsServer() then
		return
	end
	local signal = Flux.Sync("SyncSpecDefault", 1)
	expect(signal() == 1, "created synchronously")
	local module = game:GetService("ReplicatedStorage").Flux.Sync
	expect(module:FindFirstChild("SyncEvent") and module.SyncEvent:IsA("RemoteEvent"), "SyncEvent exists")
	expect(
		module:FindFirstChild("SyncUnreliable") and module.SyncUnreliable:IsA("UnreliableRemoteEvent"),
		"SyncUnreliable exists"
	)
	signal(2)
	Flux.Sync.flush()
	expect(Flux.Sync.SyncSpecDefault == signal, "lazy indexing finds it")
end)

return {}
