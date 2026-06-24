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
local expectError = sert.fails
local new = Flux.Graph.new
local flush = Flux.flush
local Context = Flux.context

test("context · default outside provide", function()
	local ctx = Context("base")
	expect(ctx:get() == "base", ":get() returns default outside provide")
	expect(ctx() == "base", "call sugar reads default")
end)

test("context · provide shadows for the synchronous extent, then restores", function()
	local ctx = Context("base")
	local inside
	local ret = ctx:provide("scoped", function()
		inside = ctx:get()
		return 42
	end)
	expect(inside == "scoped", "read inside provide sees provided value")
	expect(ret == 42, "provide returns fn's result")
	expect(ctx:get() == "base", "value restored after provide")
end)

test("context · call sugar provides", function()
	local ctx = Context(1)
	local seen
	ctx(99, function()
		seen = ctx()
	end)
	expect(seen == 99, "ctx(value, fn) provides; ctx() reads")
	expect(ctx() == 1, "restored after call-sugar provide")
end)

test("context · nesting pushes/pops innermost", function()
	local ctx = Context("a")
	local mid, inner
	ctx:provide("b", function()
		ctx:provide("c", function()
			inner = ctx:get()
		end)
		mid = ctx:get()
	end)
	expect(inner == "c", "innermost provide wins")
	expect(mid == "b", "outer value restored when inner pops")
	expect(ctx:get() == "a", "default restored after all pop")
end)

test("context · nil and false values shadow the default", function()
	local ctx = Context("default")
	local nilSeen, gotInside = "untouched", true
	ctx:provide(nil, function()
		nilSeen = ctx:get()
	end)
	expect(nilSeen == nil, "nil value shadows the default")
	ctx:provide(false, function()
		gotInside = ctx:get()
	end)
	expect(gotInside == false, "false value shadows the default")
	expect(ctx:get() == "default", "default restored")
end)

test("context · provide pops and re-raises on error", function()
	local ctx = Context("base")
	expectError(function()
		ctx:provide("scoped", function()
			error("boom")
		end)
	end, "boom")
	expect(ctx:get() == "base", "value popped even though fn threw")
end)

test("context · independent contexts don't interfere", function()
	local a = Context("a0")
	local b = Context("b0")
	local seenA, seenB
	a:provide("a1", function()
		b:provide("b1", function()
			seenA, seenB = a:get(), b:get()
		end)
	end)
	expect(seenA == "a1" and seenB == "b1", "each context tracks its own stack")
	expect(a:get() == "a0" and b:get() == "b0", "both restored")
end)

test("context · value may be a Node; stored opaquely", function()
	local node = new(7)
	local ctx = Context(node)
	local seen
	ctx:provide(node, function()
		seen = ctx:get()
	end)
	expect(seen == node, "context stores the Node itself, does not unwrap it")
	expect(ctx:get() == node, "default is the same node, returned as-is")
end)

test("context · capture-at-construction idiom survives deferred reads", function()
	local ctx = Context("default")
	local captured, lateRead
	ctx:provide("scoped", function()
		captured = ctx:get()
		Flux.effect(function()
			lateRead = ctx:get()
		end)
	end)
	flush()
	expect(captured == "scoped", "synchronous capture sees provided value")
	expect(lateRead == "default", "deferred effect sees default (run-once caveat)")
end)

return {}
