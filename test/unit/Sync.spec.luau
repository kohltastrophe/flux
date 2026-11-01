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

sert.prop("sync · random writes and delivery orders converge to the server's values", function(g)
	local w = world(3)
	local players = w.clients
	local value = w.server("V", 0, function(_, v)
		if type(v) ~= "number" or v % 5 == 0 then
			return false
		end
		return true, math.min(v, 40)
	end)
	local other = w.server("Other", "a")
	for _, client in players do
		if g:bool() then
			client.inst:start()
		end
	end
	for _ = 1, g:int(1, g.size) do
		local client = g:pick(players)
		local op = g:int(1, 10)
		if op == 1 then
			value(g:int(0, 60))
		elseif op == 2 then
			value:of(client)(g:int(0, 60))
		elseif op == 3 then
			value:clear(client)
		elseif op == 4 then
			client.sync.V(g:int(0, 60))
		elseif op == 5 then
			other(g:pick({ "a", "b", "c" }))
		elseif op == 6 then
			w.serverInst:flush()
		elseif op == 7 then
			client.inst:flush()
		elseif op == 8 then
			w.deliverServer()
		elseif op == 9 then
			value:of(client) -- per-player use without a write
		else
			w.deliverClient(client)
		end
	end
	for _, client in players do
		client.inst:start()
	end
	w.settle()
	for _, client in players do
		local want = value:of(client)()
		sert.eq(client.sync.V(), want, `{client.Name} converges on V`)
		sert.eq(client.sync.Other(), other(), `{client.Name} converges on Other`)
	end
	w.destroy()
end, { runs = 150, size = 40 })

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
