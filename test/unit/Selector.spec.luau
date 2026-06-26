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
local expect = sert
local new = Flux.Graph.new
local flush = Flux.flush

test("selector · O(1) flip touches only the two affected keys", function()
	local active = new(1)
	local sel = Flux.selector(active)
	local evals = { [1] = 0, [2] = 0, [3] = 0 }
	local memos = {}
	for k = 1, 3 do
		memos[k] = new(function()
			evals[k] += 1
			return sel(k)
		end, true)
	end
	flush()
	expect(memos[1]() == true and memos[2]() == false and memos[3]() == false, "initial selection")
	local base1, base2, base3 = evals[1], evals[2], evals[3]
	active(2)
	flush()
	expect(memos[1]() == false and memos[2]() == true, "selection moved")
	expect(evals[1] == base1 + 1 and evals[2] == base2 + 1, "only affected rows re-ran")
	expect(evals[3] == base3, "untouched row did NOT re-evaluate")
end)

test("selector · lazy per-key nodes; unread keys allocate nothing", function()
	local active = new("a")
	local sel = Flux.selector(active)
	expect(next(sel._nodes) == nil, "no nodes before any read")

	-- A non-reactive read returns the answer without allocating a per-key node.
	expect(sel("a") == true, "non-reactive read of the active key is true")
	expect(sel("b") == false, "non-reactive read of another key is false")
	expect(next(sel._nodes) == nil, "non-reactive reads allocate nothing")

	-- A tracked read allocates exactly one node per key actually read.
	local ra = new(function()
		return sel("a")
	end, true)
	local rb = new(function()
		return sel("b")
	end, true)
	flush()
	expect(ra() == true and rb() == false, "tracked reads return the right selection")
	local count = 0
	for _ in sel._nodes do
		count += 1
	end
	expect(count == 2, "only the two tracked keys allocated; unread keys allocate nothing")
end)

test("selector · key read while already active is born true", function()
	local active = new("x")
	local sel = Flux.selector(active)
	expect(sel("x") == true, "first read of the active key is true without a flush")
end)

test("selector · nothing-selected and nil transitions are safe", function()
	local active = new(nil :: any)
	local sel = Flux.selector(active)
	expect(sel("a") == false, "nothing selected reads false")
	active:set("a") -- call sugar treats `active(nil)` as a read, so write nil explicitly
	flush()
	expect(sel("a") == true, "transition from nil selects")
	active:set(nil)
	flush()
	expect(sel("a") == false, "transition back to nil deselects")
end)

test("selector · custom equals matches source value to key", function()
	local active = new(2)
	local rowA, rowB = { id = 1 }, { id = 2 }
	local sel = Flux.selector(active, function(value, key)
		return key.id == value
	end)
	expect(sel(rowA) == false and sel(rowB) == true, "matched by comparator (eager seed)")
	active(1)
	flush()
	expect(sel(rowA) == true and sel(rowB) == false, "comparator re-evaluated on change")
end)

test("selector · function source is the only tracked dependency", function()
	local active = new(5)
	local other = new(99)
	local runs = 0
	local sel = Flux.selector(function()
		runs += 1
		return active()
	end)
	sel(5)
	flush()
	local base = runs
	other(100)
	flush()
	expect(runs == base, "watcher does not depend on unrelated state")
	active(6)
	flush()
	expect(runs == base + 1, "watcher re-runs on source change")
end)

test("selector · destroy tears down watcher and per-key nodes", function()
	local active = new(1)
	local sel = Flux.selector(active)
	new(function()
		return sel(1)
	end, true)
	flush()
	local n1 = sel._nodes[1]
	expect(next(n1[Flux.Graph.Node.__type]) ~= nil, "per-key node live")
	sel:destroy()
	expect(
		Flux.isNode(n1) and next(n1[Flux.Graph.Node.__type]) == nil,
		"per-key node destroyed (metatable kept, inner table stripped)"
	)
	expect((pcall(function()
		sel(1)
	end)) == false, "post-destroy read errors")
	expect((pcall(function()
		sel:destroy()
	end)) == true, "double destroy is a safe no-op")
end)

test("scope · a selector created in a scope is cleaned up on destroy", function()
	local active = new(1)
	local sel
	local s = Flux.scope(function()
		sel = Flux.selector(active)
		new(function()
			return sel(1)
		end, true)
	end)
	flush()
	local node = sel._nodes[1]
	expect(next(node[Flux.Graph.Node.__type]) ~= nil, "selector per-key node live under scope")
	s:Destroy()
	expect(
		Flux.isNode(node) and next(node[Flux.Graph.Node.__type]) == nil,
		"scope:Destroy() stripped the selector's per-key nodes"
	)
end)

return {}
