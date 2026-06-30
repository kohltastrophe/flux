--!nonstrict
local IS_ROBLOX = game ~= nil

local Flux
local sert
if IS_ROBLOX then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	Flux = require(ReplicatedStorage:WaitForChild("Flux")) :: any
	sert = require(ReplicatedStorage:WaitForChild("sert")) :: any
else
	Flux = require("../../src") :: any
	sert = require("../sert") :: any
end

local test = sert.test
local rtest = sert.rtest
local expect = sert
local expectError = sert.fails
local flush = Flux.flush

test("listen · receives updates until disconnected", function()
	local v = Flux(1)
	local received = {}
	local disconnect = Flux.listen(v, function(val)
		table.insert(received, val)
	end)
	expect(type(disconnect) == "function", "listen returns a disconnect function")
	v(2)
	flush()
	v(3)
	flush()
	expect(received[#received] == 3, "listener observed the latest value")
	disconnect()
	v(4)
	flush()
	expect(table.find(received, 4) == nil, "listener stops firing after disconnect")
end)

test("model · rejects a non-node", function()
	expectError(function()
		Flux.model("not a node")
	end, "expects a reactive node")
end)

rtest("bind.children · stale disconnect doesn't sever the live binding", function()
	local Bind = Flux.Bind
	local screen = Instance.new("ScreenGui")
	local parentA = Instance.new("Frame")
	parentA.Name = "A"
	parentA.Parent = screen
	local parentB = Instance.new("Frame")
	parentB.Name = "B"
	parentB.Parent = screen

	local c1 = Instance.new("Frame")
	local node = Flux.signal(c1)
	local discA = Bind.children(node, parentA)
	expect(c1.Parent == parentA, "bound to A")

	local discB = Bind.children(node, parentB) -- remount: rebind to B
	expect(c1.Parent == parentB, "rebound to B")

	discA() -- STALE disconnect (e.g. A's _CLEAN flushing later): must be a no-op
	local c2 = Instance.new("Frame")
	node:set(c2)
	flush()
	expect(c2.Parent == parentB, "B binding survives the stale unbind")

	discB() -- the CURRENT disconnect must still tear down
	local c3 = Instance.new("Frame")
	node:set(c3)
	flush()
	expect(c3.Parent == nil and c2.Parent == nil, "current unbind still works")
	screen:Destroy()
end)

rtest("bind.children · stale disconnect after same-parent rebind doesn't sever the live binding", function()
	-- The parent-identity guard alone could not tell a stale disconnect from the
	-- live one when both target the SAME parent; the per-call token does.
	local Bind = Flux.Bind
	local screen = Instance.new("ScreenGui")
	local parent = Instance.new("Frame")
	parent.Parent = screen

	local c1 = Instance.new("Frame")
	local node = Flux.signal(c1)
	local discA = Bind.children(node, parent)
	expect(c1.Parent == parent, "bound to parent")

	local discB = Bind.children(node, parent) -- rebind to the SAME parent
	expect(c1.Parent == parent, "still under parent after same-parent rebind")

	discA() -- STALE: must be a no-op, NOT tear down the live discB binding
	local c2 = Instance.new("Frame")
	node:set(c2)
	flush()
	expect(c2.Parent == parent, "live binding survives the stale same-parent unbind")

	discB() -- the CURRENT disconnect must still tear down
	local c3 = Instance.new("Frame")
	node:set(c3)
	flush()
	expect(c3.Parent == nil and c2.Parent == nil, "current same-parent unbind still works")
	screen:Destroy()
end)

test("listen · a shared node keeps notifying after the first listener's scope dies", function()
	-- getBindData lazily creates the node's single propagation effect on the FIRST bind.
	-- It must be rooted, not owned by whatever scope is active then, otherwise that scope
	-- dying disposes the effect while bindData survives, freezing every later bind/listen.
	local node = Flux.signal("one")
	local seen = {}
	local scopeA = Flux.scope(function()
		Flux.listen(node, function() end) -- first bind: creates the shared effect under scopeA
	end)
	Flux.listen(node, function(v)
		table.insert(seen, v)
	end)

	node:set("two")
	flush()
	expect(seen[#seen] == "two", "listener notified while scopeA is alive")

	scopeA:Destroy()
	node:set("three")
	flush()
	expect(seen[#seen] == "three", "surviving listener still notified after scopeA dies")
end)

rtest("bind.children · re-parenting before a change flushes doesn't leak old children", function()
	-- If the value changed but its bind effect hasn't flushed, re-targeting to a new parent
	-- must still clear the stale child off the OLD parent (applyChildren's orphan sweep only
	-- matches the new parent).
	local Bind = Flux.Bind
	local screen = Instance.new("ScreenGui")
	local A = Instance.new("Frame")
	A.Name = "A"
	A.Parent = screen
	local B = Instance.new("Frame")
	B.Name = "B"
	B.Parent = screen

	local c1 = Instance.new("Frame")
	local c2 = Instance.new("Frame")
	local node = Flux.signal(c1)

	Bind.children(node, A)
	expect(c1.Parent == A, "c1 parented under A")

	node:set(c2) -- change the value but do NOT flush the bind effect
	Bind.children(node, B) -- retarget to B before the change syncs

	expect(c2.Parent == B, "c2 parented under B")
	expect(c1.Parent == nil, "stale c1 is not left behind under A")
	screen:Destroy()
end)

return {}
