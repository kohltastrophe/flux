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
local flush = Flux.flush

test("show · mounts truthy, swaps to fallback, caches on equal truthiness", function()
	local cond = Flux.signal(true)
	local builds = { a = 0, b = 0 }
	local node = Flux.show(cond, function()
		builds.a += 1
		return { tag = "A" }
	end, function()
		builds.b += 1
		return { tag = "B" }
	end)
	flush()
	expect(node().tag == "A" and builds.a == 1, "truthy branch mounted")
	cond:set(1) -- still truthy
	flush()
	expect(builds.a == 1, "equal truthiness does not rebuild")
	expect(node().tag == "A", "same branch retained")
	cond:set(false)
	flush()
	expect(node().tag == "B" and builds.b == 1, "fallback mounted on falsy")
	cond:set(true)
	flush()
	expect(builds.a == 2, "re-truthy rebuilds the truthy branch")
end)

test("show · falsy with no fallback yields nil", function()
	local cond = Flux.signal(false)
	local node = Flux.show(cond, function()
		return { tag = "A" }
	end)
	flush()
	expect(node() == nil, "no fallback -> nil branch")
	cond:set(true)
	flush()
	expect(node().tag == "A", "becomes the component when truthy")
end)

test("show · function condition is tracked", function()
	local flag = Flux.signal(false)
	local node = Flux.show(function()
		return flag()
	end, function()
		return { tag = "A" }
	end)
	flush()
	expect(node() == nil, "fn condition initially falsy")
	flag:set(true)
	flush()
	expect(node() ~= nil and node().tag == "A", "fn-condition branch reacts")
end)

test("show · branch scope torn down on swap (factory owns via its scope)", function()
	local cond = Flux.signal(true)
	local cleaned = 0
	local node = Flux.show(cond, function()
		local inner = Flux(0)
		Flux.cleanup(function() -- the branch scope owns this cleanup
			cleaned += 1
		end)
		return { node = inner }
	end, function()
		return { tag = "fallback" }
	end)
	flush()
	expect(node().node ~= nil and cleaned == 0, "branch alive while truthy")
	cond:set(false)
	flush()
	expect(cleaned == 1, "branch-owned node destroyed when branch unmounts")
end)

test("show · throwing component does not strand tracking (expected warn)", function()
	local cond = Flux.signal(true)
	local node = Flux.show(cond, function()
		error("component boom")
	end)
	flush() -- driver effect catches + warns
	local probe = Flux.signal(1)
	local seen = 0
	Flux.effect(function()
		probe()
		seen += 1
	end)
	flush()
	probe:set(2)
	flush()
	expect(seen == 2, "tracking restored after a throwing component")
	expect(node() == nil, "output is nil after the failed build")
end)

test("scope · show is owned by the enclosing scope, torn down on its Destroy", function()
	local cond = Flux.signal(true)
	local cleaned = 0
	-- A show created inside a scope is owned by it: destroying the scope tears down
	-- the show's output node, whose onDestroy cascades into the live branch.
	local s, node = Flux.scope(function()
		return Flux.show(cond, function()
			local inner = Flux(0)
			Flux.cleanup(function() -- the branch scope owns this cleanup
				cleaned += 1
			end)
			return { node = inner }
		end)
	end)
	flush()
	expect(node().node ~= nil and cleaned == 0, "scoped show mounted")
	s:Destroy()
	expect(cleaned == 1, "scope Destroy cascades through the show to the branch")
end)

test("switch · keyed mount and per-key cache", function()
	local key = Flux.signal("x")
	local builds = {}
	local node = Flux.switch(key)({
		x = function()
			builds.x = (builds.x or 0) + 1
			return { tag = "X" }
		end,
		y = function()
			builds.y = (builds.y or 0) + 1
			return { tag = "Y" }
		end,
	})
	flush()
	expect(node().tag == "X" and builds.x == 1, "initial key mounted")
	key:set("y")
	flush()
	expect(node().tag == "Y" and builds.y == 1, "switched to y")
	key:set("y")
	flush()
	expect(builds.y == 1, "same key does not rebuild")
	key:set("z") -- no entry
	flush()
	expect(node() == nil, "missing key -> nil branch")
end)

test("switch · destroying the node tears down the live branch", function()
	local key = Flux.signal("a")
	local cleaned = 0
	local node = Flux.switch(key)({
		a = function()
			local n = Flux(0)
			Flux.cleanup(function()
				cleaned += 1
			end)
			return n
		end,
	})
	flush()
	node:Destroy()
	expect(cleaned == 1, "node Destroy cascades to the branch scope")
end)

test("switch · prior branch scope torn down on key change", function()
	-- a key change Destroys the old branch's scope once (running its onDestroy
	-- callbacks) before mounting the new branch
	local key = Flux.signal("x")
	local xDestroyed = 0
	local yDestroyed = 0
	local node = Flux.switch(key)({
		x = function()
			local n = Flux(0)
			Flux.cleanup(function()
				xDestroyed += 1
			end)
			return { tag = "X", n = n }
		end,
		y = function()
			local n = Flux(0)
			Flux.cleanup(function()
				yDestroyed += 1
			end)
			return { tag = "Y", n = n }
		end,
	})
	flush()
	expect(node().tag == "X" and xDestroyed == 0, "x branch mounted and alive")

	key:set("y")
	flush()
	expect(node().tag == "Y", "switched to y")
	expect(xDestroyed == 1, "x branch scope torn down exactly once on key change")
	expect(yDestroyed == 0, "new y branch is alive, not torn down")
end)

test("switch · changing to an unmapped key tears down prior branch and nulls output", function()
	-- x -> z (no entry): the live x branch must be Destroyed and output() == nil.
	local key = Flux.signal("x")
	local xDestroyed = 0
	local node = Flux.switch(key)({
		x = function()
			Flux.cleanup(function()
				xDestroyed += 1
			end)
			return { tag = "X" }
		end,
	})
	flush()
	expect(node().tag == "X" and xDestroyed == 0, "x branch mounted")

	key:set("z") -- no factory for z
	flush()
	expect(xDestroyed == 1, "prior x branch torn down exactly once")
	expect(node() == nil, "output nil for unmapped key")
end)

test("switch · Flux.default mounts for unmapped keys without rebuilding", function()
	local key = Flux.signal("x")
	local builds = { x = 0, fallback = 0 }
	local node = Flux.switch(key)({
		x = function()
			builds.x += 1
			return { tag = "X" }
		end,
		[Flux.default] = function()
			builds.fallback += 1
			return { tag = "DEFAULT" }
		end,
	})
	flush()
	expect(node().tag == "X" and builds.x == 1, "a matched key wins over the default")

	key:set("y") -- unmapped -> default
	flush()
	expect(node().tag == "DEFAULT" and builds.fallback == 1, "unmapped key mounts the default factory")

	key:set("z") -- another unmapped value: SAME default mount, no rebuild
	flush()
	expect(builds.fallback == 1, "switching between unmapped values reuses one default mount")

	key:set("x") -- back to a real key
	flush()
	expect(node().tag == "X" and builds.x == 2, "returns to the matched branch from the default")
end)

test("show · the value accessor tracks the live condition without remounting", function()
	-- SolidJS non-keyed <Show>: the branch is kept across truthy -> truthy changes and the
	-- value accessor (2nd factory arg) updates reactively, like Solid's accessor children.
	local user = Flux.signal({ name = "Ada" })
	local builds, seen = 0, nil
	Flux.show(user, function(value)
		builds += 1
		Flux.effect(function()
			seen = value().name -- tracked read -> re-runs when `user` changes
		end)
		return "panel"
	end)
	flush()
	expect(builds == 1 and seen == "Ada", "mounted once; accessor effect saw the initial value")

	user:set({ name = "Grace" }) -- truthy -> truthy: no remount
	flush()
	expect(builds == 1, "no rebuild across a truthy -> truthy change")
	expect(seen == "Grace", "accessor effect re-ran with the live value")
end)

test("showKeyed · keys on identity where show keys on truthiness", function()
	-- SolidJS <Show keyed> (equals a == b) vs <Show> (equals !a == !b): a truthy -> truthy
	-- identity change rebuilds the keyed branch but is a no-op for the plain one.
	local a, b = { id = 1 }, { id = 2 }
	local sel = Flux.signal(a)
	local showBuilds, keyedBuilds = 0, 0

	Flux.show(sel, function()
		showBuilds += 1
		return "x"
	end)
	local keyed = Flux.showKeyed(sel, function(value)
		keyedBuilds += 1
		return value().id -- snapshot of the matched value, fixed for this mount
	end)
	flush()
	expect(showBuilds == 1 and keyedBuilds == 1, "both branches mount once")
	expect(keyed() == 1, "keyed factory read the initial value via value()")

	sel:set(b) -- truthy -> truthy, new identity
	flush()
	expect(showBuilds == 1, "plain show keeps its branch across truthy -> truthy")
	expect(keyedBuilds == 2 and keyed() == 2, "showKeyed remounts and value() is the new identity")
end)

test("showKeyed · swaps to fallback on falsy and rebuilds on the next identity", function()
	local sel = Flux.signal({ id = 1 })
	local comp, fb = 0, 0
	local node = Flux.showKeyed(sel, function()
		comp += 1
		return "C"
	end, function()
		fb += 1
		return "F"
	end)
	flush()
	expect(node() == "C" and comp == 1, "truthy value mounts the component")

	sel:set(nil) -- truthy -> falsy
	flush()
	expect(node() == "F" and fb == 1, "falsy mounts the fallback")

	sel:set({ id = 2 }) -- falsy -> truthy, new identity
	flush()
	expect(node() == "C" and comp == 2, "a new truthy identity rebuilds the component")
end)

test("switch · the default branch value accessor tracks the live unmatched value", function()
	-- The single default mount is reused across unmatched values, so the only way to render
	-- the current value is the tracked accessor; a keyed branch's value() is its own key.
	local route = Flux.signal("home")
	local defaultBuilds, seen = 0, {}
	local node = Flux.switch(route)({
		home = function(value)
			return "home:" .. value() -- keyed branch: value() == the matched key
		end,
		[Flux.default] = function(value)
			defaultBuilds += 1
			Flux.effect(function()
				seen[#seen + 1] = value()
			end)
			return "default"
		end,
	})
	flush()
	expect(node() == "home:home", "keyed branch value() returns the matched key")

	route:set("about") -- unmatched -> default mounts
	flush()
	route:set("contact") -- still unmatched: same default mount reused
	flush()
	expect(defaultBuilds == 1, "the one default mount is reused across unmatched values")
	expect(table.concat(seen, ",") == "about,contact", "default accessor tracked each live unmatched value")
end)

rtest("show · mounts/unmounts real instances under a parent", function()
	local cond = Flux.signal(true)
	local parent
	local s = Flux.scope(function()
		local shown = Flux.show(cond, function()
			return Flux.new("Frame")({ Name = "Branch" })
		end)
		parent = Flux.new("Frame")({ Name = "Root", shown })
	end)
	flush()
	expect(parent:FindFirstChild("Branch") ~= nil, "branch instance parented via Bind.children")
	cond:set(false)
	flush()
	expect(parent:FindFirstChild("Branch") == nil, "branch unparented when falsy")
	s:Destroy()
end)

rtest("switch · reparents the selected instance on key change", function()
	local key = Flux.signal("red")
	local root
	local s = Flux.scope(function()
		local view = Flux.switch(key)({
			red = function()
				return Flux.new("Frame")({ Name = "Red" })
			end,
			blue = function()
				return Flux.new("Frame")({ Name = "Blue" })
			end,
		})
		root = Flux.new("Frame")({ Name = "Root", view })
	end)
	flush()
	expect(root:FindFirstChild("Red") ~= nil, "red mounted")
	key:set("blue")
	flush()
	expect(root:FindFirstChild("Red") == nil and root:FindFirstChild("Blue") ~= nil, "swapped to blue")
	s:Destroy()
end)

return {}
