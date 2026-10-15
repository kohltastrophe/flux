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
local new = Flux
local flush = Flux.flush
local Context = Flux.context

test("context · default outside provide", function()
	local ctx = Context("base")
	expect(ctx:get() == "base", ":get() returns default outside provide")
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

test("context · reactions remember the context provided where they were created", function()
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
	expect(lateRead == "scoped", "deferred effect remembers creation-time context")
end)

test("bindContext · captures active context frames for deferred callbacks and passes through at root", function()
	local Theme = Context("dark")
	local Lang = Context("en")

	local rootFn = function(x: number)
		return Theme:get() .. ":" .. tostring(x)
	end
	expect(Flux.bindContext(rootFn) == rootFn, "outside any provide, bindContext returns fn unchanged")

	local bound
	Theme:provide("light", function()
		Lang:provide("fr", function()
			bound = Flux.bindContext(function(suffix: string)
				return `{Theme:get()}-{Lang:get()}-{suffix}`
			end)
		end)
	end)

	expect(Theme:get() == "dark" and Lang:get() == "en", "outer context restored")
	expect(bound("ok") == "light-fr-ok", "bound callback sees the context snapshot from where it was wrapped")

	local throwingBound
	Theme:provide("solarized", function()
		throwingBound = Flux.bindContext(function()
			error("handler boom")
		end)
	end)
	expectError(function()
		throwingBound()
	end, "handler boom")
	expect(Theme:get() == "dark", "context restored after a throwing bound callback")
end)

test("context · provide and untrack restore fast-path ownership and flush state", function()
	local ctx = Context("root")
	local seenInProvidedEffect
	local seenInRootEffect
	local rootScope = Flux.scope(function()
		ctx:provide("branch", function()
			Flux.untrack(function()
				expect(ctx:get() == "branch", "untrack inside provide still sees provided context")
			end)
			Flux.effect(function()
				seenInProvidedEffect = ctx:get()
			end)
		end)
		-- After exiting provide and untrack, root reactions should not inherit stale context
		Flux.effect(function()
			seenInRootEffect = ctx:get()
		end)
	end)
	flush()
	expect(seenInProvidedEffect == "branch", "effect created inside provide captured branch context")
	expect(seenInRootEffect == "root", "effect created after provide exited sees root default")
	rootScope:Destroy()
end)

return {}
