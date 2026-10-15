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
local untrack = Flux.untrack
local retrack = Flux.retrack

test("value · read/write and call sugar", function()
	local v = Flux(10)
	expect(v:get() == 10, ":get() returns the value")
	expect(v() == 10, "calling with no args reads")
	v:set(20)
	expect(v() == 20, ":set() writes")
	v(30)
	expect(v:get() == 30, "calling with an arg writes")

	local a, b = Flux(1), Flux(1)
	a:set(50)
	b(50)
	expect(a:get() == b(), "set()/() and get()/() are interchangeable")
end)

test("value · isNode detection", function()
	expect(Flux.isNode(Flux(1)) == true, "value node is a node")
	expect(Flux.isNode(Flux(function()
		return 1
	end)) == true, "computed is a node")
	expect(Flux.isNode(5) == false, "number is not a node")
	expect(Flux.isNode("x") == false, "string is not a node")
	expect(Flux.isNode({}) == false, "plain table is not a node")
	expect(Flux.isNode(nil) == false, "nil is not a node")
end)

test("value · operator overloading", function()
	local x = Flux(6)
	expect(x + 4 == 10, "__add")
	expect(x - 1 == 5, "__sub")
	expect(x * 2 == 12, "__mul")
	expect(x / 2 == 3, "__div")
	expect(x // 4 == 1, "__idiv")
	expect(x % 4 == 2, "__mod")
	expect(x ^ 2 == 36, "__pow")
	expect(-x == -6, "__unm")
	expect((x .. "!") == "6!", "__concat")
	expect(tostring(x) == "6", "__tostring")

	local y = Flux(5)
	expect(x + y == 11, "node + node")
	expect((x < y) == false, "__lt")
	expect((x > y) == true, "__lt (swapped)")
	expect((y <= x) == true, "__le")
end)

test("value · equals option short-circuits; force bypasses", function()
	local v = Flux.signal(10, function()
		return true -- always "equal": writes never propagate
	end)
	local runs = 0
	local c = Flux(function()
		runs += 1
		return v()
	end)
	expect(c() == 10 and runs == 1, "computed evaluates once")
	v(999)
	expect(v:get() == 10, "value unchanged because equals reported equal")
	expect(c() == 10 and runs == 1, "no recompute since nothing changed")
	v:set(20, true)
	expect(v:get() == 20, "force write updates the value")
	expect(c() == 20 and runs == 2, "force write propagates to observers")
end)

test("value · update() re-fires dependents without writing", function()
	local items = Flux({ "Sword" })
	local runs, seen = 0, 0
	local c = Flux(function()
		runs += 1
		return #items()
	end)
	Flux.effect(function()
		seen = #items()
	end)
	flush()
	expect(c() == 1 and runs == 1 and seen == 1, "baseline evaluation")

	table.insert(items:peek(), "Shield")
	expect(c() == 1 and runs == 1, "in-place mutation alone does not propagate")

	expect(items:update() == items, "update() returns the node")
	flush()
	expect(c() == 2 and runs == 2, "computed observer re-runs with the same reference")
	expect(seen == 2, "effect observer re-runs on flush")
end)

test("value · redundant write on default equality is a no-op", function()
	local v = Flux(10) -- plain value node, no custom equals
	local runs = 0
	local c = Flux(function()
		runs += 1
		return v()
	end)
	expect(c() == 10 and runs == 1, "computed evaluates once initially")

	v(10) -- write the SAME value it already holds
	flush()
	expect(c() == 10 and runs == 1, "redundant write does not re-run observer (changed short-circuit)")

	v(20) -- write a DIFFERENT value
	flush()
	expect(c() == 20 and runs == 2, "distinct write re-runs the observer")
end)

test("computed · lazy, memoized, invalidated", function()
	local a = new(1)
	local runs = 0
	local b = new(function()
		runs += 1
		return a:get() * 2
	end)
	expect(runs == 0, "computed lazy until read")
	expect(b:get() == 2, "computed value")
	b:get()
	expect(runs == 1, "computed memoized")
	a:set(5)
	expect(runs == 1, "computed not eager")
	expect(b:get() == 10 and runs == 2, "computed updates on read")
end)

test("computed · dynamic dependency tracking", function()
	local useA = Flux(true)
	local a = Flux(1)
	local b = Flux(100)
	local runs = 0
	local c = Flux(function()
		runs += 1
		if useA() then
			return a()
		else
			return b()
		end
	end)
	expect(c() == 1 and runs == 1, "initial: tracks useA and a")
	b(200)
	expect(c() == 1 and runs == 1, "changing untracked b does not invalidate")
	useA(false)
	expect(c() == 200 and runs == 2, "switching branches re-tracks dependencies")
	a(5)
	expect(c() == 200 and runs == 2, "a is no longer tracked")
	b(300)
	expect(c() == 300 and runs == 3, "b is now tracked")
end)

test("computed · chaining", function()
	local n = Flux(2)
	local doubled = Flux(function()
		return n * 2
	end)
	local quad = Flux(function()
		return doubled * 2
	end)
	expect(quad() == 8, "2 -> 4 -> 8")
	n(3)
	expect(doubled() == 6, "intermediate updated")
	expect(quad() == 12, "downstream updated")
end)

test("computed · raw vs read tracking", function()
	local v = Flux(5)
	local rawRuns = 0
	local cRaw = Flux(function()
		rawRuns += 1
		return Flux.raw(v) + 100
	end)
	expect(cRaw() == 105 and rawRuns == 1, "raw baseline")
	v(6)
	expect(cRaw() == 105 and rawRuns == 1, "raw read created no dependency")

	local v2 = Flux(5)
	local readRuns = 0
	local cRead = Flux(function()
		readRuns += 1
		return Flux.read(v2) + 100
	end)
	expect(cRead() == 105 and readRuns == 1, "read baseline")
	v2(6)
	expect(cRead() == 106 and readRuns == 2, "read created a dependency")

	expect(Flux.raw(7) == 7, "raw passes through plain values")
	expect(Flux.read(7) == 7, "read passes through plain values")
end)

test("graph · diamond is glitch-free (single recompute)", function()
	local a = Flux(1)
	local b = Flux(function()
		return a + 1
	end)
	local c = Flux(function()
		return a + 2
	end)
	local dRuns = 0
	local d = Flux(function()
		dRuns += 1
		return b + c
	end)
	expect(d() == 5 and dRuns == 1, "1 -> b=2,c=3 -> d=5")
	a(5)
	expect(d() == 13, "5 -> b=6,c=7 -> d=13")
	expect(dRuns == 2, "d recomputes exactly once despite two changed parents")
	expect(d() == 13 and dRuns == 2, "still cached")
end)

test("effect · deferred, runs on flush, re-runs on change", function()
	local v = Flux(0)
	local runs, last = 0, nil
	Flux.effect(function()
		runs += 1
		last = v()
	end)
	expect(runs == 0, "effect is deferred, not run on creation")
	flush()
	expect(runs == 1 and last == 0, "effect runs on flush")
	v(7)
	flush()
	expect(runs == 2 and last == 7, "effect re-runs after dependency change")
end)

test("effect · survives a suppressed error and stays reactive (expected warn)", function()
	local v = Flux(1)
	local runs = 0
	Flux.effect(function()
		runs += 1
		if v() == 2 then
			error("effect failure (expected warn)")
		end
	end)
	flush()
	expect(runs == 1, "baseline run")
	v(2)
	flush()
	expect(runs == 2, "erroring run still happened")
	v(3)
	flush()
	expect(runs == 3, "effect re-runs after a suppressed error")
end)

test("effect · survives an error on its very first run (expected warn)", function()
	local v = Flux(2)
	local runs = 0
	Flux.effect(function()
		runs += 1
		if v() == 2 then
			error("first-run failure (expected warn)")
		end
	end)
	flush()
	expect(runs == 1, "first run errored")
	v(3)
	flush()
	expect(runs == 2, "effect stays subscribed to sources read before the error")
end)

test("effect · batches multiple writes per flush", function()
	local v = Flux(0)
	local runs, last = 0, nil
	Flux.effect(function()
		runs += 1
		last = v()
	end)
	flush()
	expect(runs == 1 and last == 0, "baseline")
	v(1)
	v(2)
	v(3)
	flush()
	expect(runs == 2, "three writes in one frame -> one effect run")
	expect(last == 3, "effect observes the final value only")
end)

test("effect · cleanup runs before each re-run", function()
	local trigger = Flux(0)
	local effectRuns, cleanups = 0, 0
	Flux.effect(function()
		effectRuns += 1
		local _ = trigger()
		Flux.cleanup(function()
			cleanups += 1
		end)
	end)
	flush()
	expect(effectRuns == 1 and cleanups == 0, "no cleanup before first re-run")
	trigger(1)
	flush()
	expect(effectRuns == 2 and cleanups == 1, "cleanup fires before the re-run")
	trigger(2)
	flush()
	expect(effectRuns == 3 and cleanups == 2, "cleanup fires again")
end)

test("effect · cleanup errors outside a reactive context", function()
	expectError(function()
		Flux.cleanup(function() end)
	end, "reactive")
end)

test("effect · cleanup rejects uncleanable objects, naming the type", function()
	local scope = Flux.scope(function()
		expectError(function()
			Flux.cleanup({ a = 1 } :: any)
		end, "cannot cleanup given object: table")
		expectError(function()
			Flux.cleanup(5 :: any)
		end, "cannot cleanup given object: number")
	end)
	scope:Destroy()
end)

test("node · onDestroy and Destroy", function()
	local destroyed = false
	local n = Flux(1)
	n:onDestroy(function()
		destroyed = true
	end)
	n:Destroy()
	expect(destroyed, "onDestroy callback fired on Destroy")
end)

test("effect · stops re-running after Destroy", function()
	local v = Flux(0)
	local runs = 0
	local e = Flux.effect(function()
		runs += 1
		local _ = v()
	end)
	flush()
	expect(runs == 1, "baseline")
	e:Destroy()
	v(5)
	flush()
	expect(runs == 1, "destroyed effect is unsubscribed and never re-runs")
end)

test("node · cleanup runs exactly once on Destroy", function()
	local trigger = Flux(0)
	local cleanups = 0
	local e = Flux.effect(function()
		local _ = trigger()
		Flux.cleanup(function()
			cleanups += 1
		end)
	end)
	flush()
	expect(cleanups == 0, "cleanup has not run before Destroy")
	e:Destroy()
	expect(cleanups == 1, "cleanup runs exactly once as a result of Destroy")

	-- A computed's cleanup must also run when the computed is Destroyed.
	local src = Flux(1)
	local cCleanups = 0
	local c = Flux(function()
		local _ = src()
		Flux.cleanup(function()
			cCleanups += 1
		end)
		return 0
	end)
	c() -- force evaluation so the computed's body (and cleanup) registers
	expect(cCleanups == 0, "computed cleanup has not run before Destroy")
	c:Destroy()
	expect(cCleanups == 1, "computed cleanup runs exactly once on Destroy")
end)

test("flush · re-entrant flush from an effect is a no-op", function()
	-- the inner flush must no-op: draining the outer buffer would re-enter the
	-- BUSY caller and throw a spurious cyclic-read
	local a = new(1)
	local b = new(0)
	local innerRuns = 0
	local _inner = Flux.effect(function()
		b:get()
		innerRuns += 1
	end)
	flush()
	local tailRan = 0
	local _outer = Flux.effect(function()
		a:get()
		b:set(b:peek() + 1)
		flush() -- re-entrant: must be a no-op, not a cyclic-read error
		tailRan += 1
	end)
	flush()
	expect(tailRan == 1, "effect body completes")
	a:set(2)
	flush()
	expect(tailRan == 2 and innerRuns >= 2, "completes on re-run, inner kept flowing")
end)

test("untrack · reads inside are not captured", function()
	local tracked = new(1)
	local untracked = new(100)
	local runs = 0
	local c = new(function()
		runs += 1
		return tracked:get() + untrack(function()
			return untracked:get()
		end)
	end)
	expect(c:get() == 101 and runs == 1, "initial")
	untracked:set(200)
	expect(c:get() == 101 and runs == 1, "untracked dep ignored")
	tracked:set(2)
	expect(c:get() == 202 and runs == 2, "tracked dep still live")
end)

test("untrack · restores context on error and rethrows", function()
	local dep = new(1)
	local caught = false
	local c = new(function()
		pcall(function()
			untrack(function()
				error("boom")
			end)
		end)
		caught = true
		return dep:get() -- read AFTER the failed untrack must still track
	end)
	expect(c:get() == 1 and caught, "untrack error contained")
	dep:set(2)
	expect(c:get() == 2, "tracking restored after untrack error")
end)

test("untrack · preserves the reactive owner (cleanup)", function()
	local dep = new(1)
	local cleanups = 0
	local c = new(function()
		local v = dep:get()
		untrack(function()
			Flux.cleanup(function()
				cleanups += 1
			end)
		end)
		return v
	end)
	expect(c:get() == 1 and cleanups == 0, "cleanup inside untrack registers")
	dep:set(2)
	expect(c:get() == 2 and cleanups == 1, "cleanup inside untrack runs on re-eval")
end)

test("untrack · multi-return passthrough", function()
	local a, b, c = untrack(function()
		return 1, nil, 3
	end)
	expect(a == 1 and b == nil and c == 3, "untrack multi-return")
end)

test("untrack · zero-arg pair suppresses reads until track()", function()
	-- untrack() suppresses tracking until track() (or the computation finishes):
	-- reads inside the bracket aren't dependencies, reads outside it still are.
	local tracked = new(1)
	local suppressed = new(10)
	local runs = 0
	local c = Flux.computed(function()
		runs += 1
		local a = tracked:get() -- dependency
		untrack()
		local b = suppressed:get() -- inside the bracket: NOT a dependency
		retrack()
		return a + b
	end)
	expect(c:get() == 11 and runs == 1, "initial")
	suppressed:set(20)
	expect(c:get() == 11 and runs == 1, "read between untrack()/track() never became a dependency")
	tracked:set(2)
	expect(c:get() == 22 and runs == 2, "a tracked read still re-triggers; bracketed read re-evaluated")
end)

test("scope · owns reactions; plain signals survive for the GC", function()
	-- A scope owns the REACTIONS (computeds/effects) and cleanups created inside it and tears them
	-- down on Destroy. A plain signal is not owned: it outlives the scope and the GC reclaims it.
	local reactionDestroyed = false
	local node, sig = Flux.scope(function()
		local derived = Flux(function()
			return 1
		end)
		derived() -- evaluate so the reaction is live
		derived:onDestroy(function()
			reactionDestroyed = true
		end)
		return Flux(5)
	end)
	expect(Flux.isNode(sig) and sig() == 5, "scope ran and returned the signal created inside it")
	node:Destroy()
	expect(reactionDestroyed, "scope:Destroy() destroys reactions created inside the scope")
	expect(
		Flux.isNode(sig) == true and sig() == 5,
		"a plain signal survives scope teardown (it is GC-managed, not scope-owned)"
	)
end)

test("scope · cleanup callbacks run when the scope is destroyed", function()
	local cleaned = 0
	local node = Flux.scope(function()
		Flux.cleanup(function()
			cleaned += 1
		end)
	end)
	expect(cleaned == 0, "cleanup is deferred until destroy")
	node:Destroy()
	expect(cleaned == 1, "cleanup ran once on scope destroy")
end)

test("scope · destroying the scope stops effects created in it", function()
	local src = Flux(0)
	local runs = 0
	local node = Flux.scope(function()
		Flux.effect(function()
			runs += 1
			local _ = src()
		end)
	end)
	flush()
	expect(runs == 1, "baseline")
	node:Destroy()
	src(1)
	flush()
	expect(runs == 1, "scoped effect no longer fires after the scope is destroyed")
end)

test("scope · a nested scope is torn down with its parent", function()
	local childCleaned = false
	local parent = Flux.scope(function()
		Flux.scope(function()
			Flux.cleanup(function()
				childCleaned = true
			end)
		end)
	end)
	parent:Destroy()
	expect(childCleaned, "destroying the parent cascades into the nested scope's cleanups")
end)

test("scope · a nested scope can be destroyed independently of its parent", function()
	local childCleaned = false
	local child
	local parent = Flux.scope(function()
		child = Flux.scope(function()
			Flux.cleanup(function()
				childCleaned = true
			end)
		end)
	end)
	child:Destroy()
	expect(childCleaned, "child Destroy tears down the child's own cleanups")
	-- the child unlinked from the parent on its own Destroy, so the parent's is a safe no-op
	expect((pcall(function()
		parent:Destroy()
	end)) == true, "parent Destroy after an independent child Destroy is safe")
end)

test("scope · nested scopes cascade on root destroy", function()
	local leafGone = false
	local root = Flux.scope(function()
		Flux.scope(function()
			Flux.scope(function()
				Flux.cleanup(function()
					leafGone = true
				end)
			end)
		end)
	end)
	root:Destroy()
	expect(leafGone, "root destroy cascades through every nested scope")
end)

test("scope · cascade teardown strips owned reactions like a direct Destroy; signals survive", function()
	-- Destroying a reaction (direct or via an owning scope) clears its FN/VALUE/OBSERVERS but leaves
	-- the wrapper + metatable intact, so isNode stays true and the GC reclaims the wrapper. A plain
	-- signal is not owned, so the cascade leaves it intact (the GC reclaims it once unreferenced).
	local direct = Flux(function()
		return 1
	end)
	direct() -- evaluate the reaction
	direct:Destroy()
	expect(Flux.isNode(direct) == true, "directly destroyed reaction keeps its metatable")
	expect(direct() == nil and direct[1][7] == nil, "its inner table is present and its fn is cleared")

	local leaf, nested, signal
	local root = Flux.scope(function()
		leaf = Flux(function()
			return 2
		end)
		leaf()
		signal = Flux(99)
		Flux.scope(function()
			nested = Flux(function()
				return 3
			end)
			nested()
		end)
	end)
	expect(Flux.isNode(leaf) and Flux.isNode(nested), "both reactions live before teardown")
	root:Destroy()
	expect(Flux.isNode(leaf) == true and Flux.isNode(nested) == true, "cascade leaves metatables intact")
	expect(leaf() == nil and nested() == nil, "cascade strips the reactions, like a direct Destroy")
	expect(Flux.isNode(signal) == true and signal() == 99, "a plain signal survives the cascade (GC-managed)")
end)

test("prev · computed receives its previous value as the first arg", function()
	local trigger = new(0)
	local prevs = {}
	local runs = 0
	-- index by `runs`, not #prevs: a nil prev at [1] wouldn't grow the array
	local c = new(function(prev)
		runs += 1
		prevs[runs] = prev
		return trigger:get()
	end)
	expect(c:get() == 0, "first eval value")
	expect(runs == 1 and prevs[1] == nil, "first run prev is nil (no prior value)")
	trigger:set(5)
	expect(c:get() == 5, "second eval value")
	expect(runs == 2 and prevs[2] == 0, "second run sees the prior value 0")
end)

test("prev · computed accumulator pattern across multiple updates", function()
	local input = new(10)
	local deltas = {}
	local c = new(function(prev)
		local v = input:get()
		deltas[#deltas + 1] = if prev ~= nil then v - prev else v
		return v
	end)
	expect(c:get() == 10, "first evaluation")
	input:set(25)
	expect(c:get() == 25, "second evaluation")
	input:set(20)
	expect(c:get() == 20, "third evaluation")
	expect(deltas[1] == 10, "first run delta is the value itself")
	expect(deltas[2] == 15, "delta from 10 to 25")
	expect(deltas[3] == -5, "delta from 25 to 20")
	c:Destroy()
end)

test("dispose · destroying a source prunes only that source from observers", function()
	-- The dependency-list invariant: disposing a node must remove ONLY that node from each
	-- observer's source list, never a live sibling.
	local a = new(1)
	local b = new(2)
	local c = Flux.computed(function()
		return a() + b()
	end)
	local eff = Flux.effect(function()
		c()
	end)
	flush()
	expect(c() == 3, "computed reads both sources")

	a:Destroy()

	local inner = c[1]
	local hasLive, hasDead = false, false
	for i = 11, inner[8] - 2, 2 do
		hasLive = hasLive or inner[i] == b[1]
		hasDead = hasDead or inner[i] == a[1]
	end
	expect(hasLive, "the live sibling source b is retained")
	expect(not hasDead, "the destroyed source a is pruned")
	eff:Destroy()
end)

test("value · node(nil) is a read; force or :set writes nil", function()
	-- The call shorthand uses `value ~= nil` to tell a write from a read (kept deliberately
	-- cheap), so node(nil) READS. nil is written with force or the explicit setter.
	local s = new(42)
	expect(s() == 42, "node() reads the value")
	expect(s(nil) == 42, "node(nil) is a read, not a write")
	expect(s() == 42, "node(nil) left the value unchanged")
	s(nil, true)
	expect(s() == nil, "node(nil, true) force-writes nil")
	s:set(99)
	s:set(nil)
	expect(s() == nil, "node:set(nil) writes nil without force")
end)

test("cleanup · rejects a bare array (use Flux.dispose for nested teardown)", function()
	-- Flux.cleanup takes ONE cleanable; arrays with functions are cleanable via Flux.dispose.
	-- A plain table with non-cleanable elements or non-empty keys without a teardown method is not cleanable.
	local threw
	local s = Flux.scope(function()
		threw = not pcall(Flux.cleanup, { a = 1 })
	end)
	s:Destroy()
	expect(threw, "Flux.cleanup of a plain map errors")
end)

test("createSignal, createMemo & createEffect · lightweight tuple and function primitives", function()
	local count, setCount = Flux.createSignal(2, function(a, b)
		return math.abs(a - b) < 2
	end)
	local memoRuns = 0
	local effectSeen = 0
	local scope = Flux.scope(function()
		local doubled = Flux.createMemo(function()
			memoRuns += 1
			return count() * 2
		end, function(a, b)
			return a == b
		end)
		Flux.createEffect(function()
			effectSeen = doubled()
		end)
		expect(doubled() == 4 and memoRuns == 1, "createMemo evaluates lazily")
	end)
	flush()
	expect(effectSeen == 4, "createEffect ran on flush")

	-- Within custom equals tolerance (< 2): skipped unless forced
	setCount(3)
	flush()
	expect(effectSeen == 4 and memoRuns == 1, "createSignal custom equals skipped propagation")

	setCount(3, true)
	flush()
	expect(effectSeen == 6 and memoRuns == 2, "forced setCount propagated")

	setCount(10)
	flush()
	expect(effectSeen == 20 and memoRuns == 3, "setCount beyond tolerance propagated")

	scope:Destroy()
	setCount(50)
	flush()
	expect(effectSeen == 20 and memoRuns == 3, "scope teardown stopped createEffect and createMemo")
end)

test("getter & setter · extract fast reader and writer functions from nodes", function()
	local sig = Flux.signal(10)
	local getSig = Flux.getter(sig)
	local setSig = Flux.setter(sig)
	expect(getSig() == 10, "signal getter reads value")
	setSig(25)
	expect(getSig() == 25 and sig:peek() == 25, "signal setter writes value")
	setSig(nil :: any)
	expect(getSig() == nil, "signal setter writes nil without force")
	setSig(4)

	local comp = Flux.computed(function()
		return getSig() * 3
	end)
	local getComp = Flux.getter(comp)
	local setComp = Flux.setter(comp)
	expect(getComp() == 12, "computed getter reads and pulls")
	setComp(99)
	expect(getComp() == 99 and comp:peek() == 99, "computed setter overrides cached value")
	setSig(5)
	expect(getComp() == 15, "upstream change recomputes overridden computed")

	-- Generic Node metatable path (mt == Graph.Node)
	local sc = Flux.scope(function() end)
	local nodeMT = getmetatable(sc :: any)
	local genericNode: any = setmetatable({ (sig :: any)[1] }, nodeMT)
	local getGeneric = Flux.getter(genericNode)
	local setGeneric = Flux.setter(genericNode)
	setGeneric(77)
	expect(getGeneric() == 77 and genericNode:get() == 77 and genericNode:peek() == 77, "generic node getter/setter")

	-- Scope node setter is a safe no-op
	local setScope = Flux.setter(sc :: any)
	expect(setScope("ignored") == "ignored", "scope setter returns value without mutating scope")
	sc:Destroy()

	sert.fails(function()
		Flux.getter("not a node" :: any)
	end, "Flux.getter expects a node")
	sert.fails(function()
		Flux.setter("not a node" :: any)
	end, "Flux.setter expects a node")
end)

test("onObserved & onUnobserved · fire when a node gains and loses transitive effect observers", function()
	local sig = Flux.signal(1)
	local mid = Flux.computed(function()
		return sig() * 10
	end)
	local sigObs, sigUnobs = 0, 0
	local midObs, midUnobs = 0, 0
	sig:onObserved(function()
		sigObs += 1
	end)
	sig:onUnobserved(function()
		sigUnobs += 1
	end)
	mid:onObserved(function()
		midObs += 1
	end)
	mid:onUnobserved(function()
		midUnobs += 1
	end)

	-- Reading mid outside an effect does not make it observed by an effect
	expect(mid() == 10, "pulled value")
	expect(sigObs == 0 and midObs == 0, "unobserved before any effect subscribes")

	local eff = Flux.effect(function()
		mid()
	end)
	flush()
	expect(sigObs == 1 and midObs == 1, "both signal and intermediate computed became observed")
	expect(sigUnobs == 0 and midUnobs == 0, "not unobserved while effect is alive")

	eff:Destroy()
	expect(sigUnobs == 1 and midUnobs == 1, "destroying the effect fires onUnobserved through the chain")
end)

test("computed · direct write via :set and call shorthand notifies observers", function()
	local base = Flux.signal(2)
	local comp = Flux.computed(function()
		return base() * 5
	end)
	local seen = 0
	local eff = Flux.effect(function()
		seen = comp()
	end)
	flush()
	expect(seen == 10, "initial computed value")

	comp:set(42)
	flush()
	expect(seen == 42 and comp:peek() == 42, "computed:set(42) overrides and notifies effect")

	comp(77)
	flush()
	expect(seen == 77, "computed(77) call-write overrides and notifies effect")

	base:set(3)
	flush()
	expect(seen == 15, "upstream signal change re-evaluates the computed")
	eff:Destroy()
end)

test("operators · arithmetic, comparison, concat, and tostring on nodes", function()
	local a = Flux.signal(10)
	local b = Flux.computed(function()
		return 3
	end)
	expect(tostring(a) == "10" and tostring(b) == "3", "__tostring")
	expect((a .. "px") == "10px" and ("v=" .. b) == "v=3" and (a .. b) == "103", "__concat")
	expect(-a == -10 and -b == -3, "__unm")
	expect(a + b == 13 and a + 5 == 15, "__add")
	expect(a - b == 7 and 20 - a == 10, "__sub")
	expect(a * b == 30, "__mul")
	expect(a / 2 == 5, "__div")
	expect(a // b == 3, "__idiv")
	expect(a % b == 1, "__mod")
	expect(b ^ 2 == 9, "__pow")
	expect(b < a and not (a < b), "__lt")
	expect(b <= a and a <= a and not (a <= b), "__le")
end)

test("withOwner & getOwner · rebind ownership and immediately dispose work on a destroyed owner", function()
	expect(Flux.getOwner() == nil, "no owner at root")
	local capturedOwner
	local cleaned = 0
	local scope = Flux.scope(function()
		capturedOwner = Flux.getOwner()
		expect(capturedOwner ~= nil, "getOwner returns active scope")
	end)

	-- Attach work to the live scope from outside
	Flux.withOwner(capturedOwner, function()
		Flux.cleanup(function()
			cleaned += 1
		end)
	end)
	expect(cleaned == 0, "cleanup attached to live owner waits for owner teardown")
	scope:Destroy()
	expect(cleaned == 1, "destroying the scope ran the withOwner cleanup")

	-- Running withOwner on an already-destroyed owner disposes created work immediately
	local lateCleaned = 0
	Flux.withOwner(capturedOwner, function()
		Flux.cleanup(function()
			lateCleaned += 1
		end)
	end)
	expect(lateCleaned == 1, "work registered on a destroyed owner is disposed as soon as fn returns")
end)

test("effect · nested synchronous effect creation does not clobber outer selfWritten requeue", function()
	local sig = Flux.signal(0)
	local outerRuns = 0
	local innerRuns = 0
	local outer = Flux.effect(function()
		outerRuns += 1
		local v = sig()
		if v == 1 then
			sig:set(2) -- marks outer as selfWritten
			-- Create and synchronously evaluate a nested effect via untrack/scope or computed
			local inner = Flux.effect(function()
				innerRuns += 1
			end)
			inner:Destroy()
		end
	end)
	flush()
	expect(outerRuns == 1, "initial outer run")

	sig:set(1)
	flush()
	expect(outerRuns == 3, "outer effect re-ran for v=1 and again for its self-write v=2")
	expect(sig:peek() == 2, "self-write landed")
	outer:Destroy()
end)

test("computed · self-referential computed does not overflow stack on upstream write", function()
	local trigger = Flux.signal(1)
	local comp: any
	comp = Flux.computed(function(prev)
		local t = trigger()
		if t > 1 then
			-- Reading comp() inside its own evaluation should not add a self-edge
			local _ = comp()
		end
		return (prev or 0) + t
	end)
	expect(comp() == 1, "first evaluation")
	trigger:set(2)
	expect(comp() == 3, "second evaluation with self-read")
	trigger:set(3)
	expect(comp() == 6, "third evaluation did not cycle in raise()")
	comp:Destroy()
end)

test("onObserved & onUnobserved · only fire on 0->1 and 1->0 effect observer transitions", function()
	local sig = Flux.signal(10)
	local obs, unobs = 0, 0
	sig:onObserved(function()
		obs += 1
	end)
	sig:onUnobserved(function()
		unobs += 1
	end)

	local e1 = Flux.effect(function()
		sig()
	end)
	local e2 = Flux.effect(function()
		sig()
	end)
	flush()
	expect(obs == 1 and unobs == 0, "onObserved fired once when 2 effects subscribed")

	e1:Destroy()
	expect(obs == 1 and unobs == 0, "destroying first of two effects does not fire onUnobserved")

	e2:Destroy()
	expect(obs == 1 and unobs == 1, "destroying last effect fires onUnobserved")
end)

return {}
