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
local untrack = Flux.untrack
local retrack = Flux.retrack
local Graph = Flux.Graph

-- Run `fn` with strict ON, always restoring the flag afterward (a leaked-ON
-- flag would double-run every later test). Re-raises any error after restoring.
local function withStrict(fn: () -> ())
	Flux.strict(true)
	local ok, err = pcall(fn)
	Flux.strict(false)
	if ok == false then
		error(err, 2)
	end
end

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
	Flux(function()
		runs += 1
		last = v()
	end, true)
	expect(runs == 0, "effect is deferred, not run on creation")
	flush()
	expect(runs == 1 and last == 0, "effect runs on flush")
	v(7)
	flush()
	expect(runs == 2 and last == 7, "effect re-runs after dependency change")
end)

test("effect · batches multiple writes per flush", function()
	local v = Flux(0)
	local runs, last = 0, nil
	Flux(function()
		runs += 1
		last = v()
	end, true)
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
	Flux(function()
		effectRuns += 1
		local _ = trigger()
		Flux.cleanup(function()
			cleanups += 1
		end)
	end, true)
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
	local e = Flux(function()
		runs += 1
		local _ = v()
	end, true)
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
	local e = Flux(function()
		local _ = trigger()
		Flux.cleanup(function()
			cleanups += 1
		end)
	end, true)
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
	local _inner = new(function()
		b:get()
		innerRuns += 1
	end, true)
	flush()
	local tailRan = 0
	local _outer = new(function()
		a:get()
		b:set(b:peek() + 1)
		flush() -- re-entrant: must be a no-op, not a cyclic-read error
		tailRan += 1
	end, true)
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
	local c = new(function()
		runs += 1
		local a = tracked:get() -- dependency
		untrack()
		local b = suppressed:get() -- inside the bracket: NOT a dependency
		retrack()
		return a + b
	end, true)
	flush()
	expect(runs == 1 and c:get() == 11, "initial")
	suppressed:set(20)
	flush()
	expect(runs == 1, "read between untrack()/track() never became a dependency")
	tracked:set(2)
	flush()
	expect(runs == 2 and c:get() == 22, "a tracked read still re-triggers; bracketed read re-evaluated")
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
	-- Destroying a reaction (direct or via an owning scope) strips its inner node table but leaves
	-- the wrapper + metatable intact, so isNode stays true and the GC reclaims the wrapper. A plain
	-- signal is not owned, so the cascade leaves it intact (the GC reclaims it once unreferenced).
	local direct = Flux(function()
		return 1
	end)
	direct() -- evaluate the reaction
	direct:Destroy()
	expect(Flux.isNode(direct) == true, "directly destroyed reaction keeps its metatable")
	expect(direct() == nil and next(direct._) == nil, "its inner table is present but stripped")

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

test("prev · effect receives its previous value (accumulator pattern)", function()
	local input = new(10)
	local deltas = {}
	local e = new(function(prev)
		local v = input:get()
		deltas[#deltas + 1] = if prev ~= nil then v - prev else v
		return v
	end, true)
	flush()
	input:set(25)
	flush()
	input:set(20)
	flush()
	expect(deltas[1] == 10, "first run delta is the value itself")
	expect(deltas[2] == 15, "delta from 10 to 25")
	expect(deltas[3] == -5, "delta from 25 to 20")
	e:Destroy()
end)

test("strict · off by default; toggle via Flux.strict", function()
	expect(Flux.strict() == false, "strict defaults off")
	Flux.strict(true)
	expect(Flux.strict() == true, "Flux.strict(true) enables")
end)

test("strict · pure computation runs twice but is silent and correct", function()
	withStrict(function()
		local a = new(2)
		local runs = 0
		local c = new(function()
			runs += 1
			return a:get() * 10
		end)
		expect(c:get() == 20, "value correct under strict")
		expect(runs == 2, "strict double-runs the body on first evaluation")
		a:set(3)
		expect(c:get() == 30 and runs == 4, "re-eval double-runs again")
	end)
end)

test("strict · impure body keeps the graph usable", function()
	-- A non-pure body just runs twice; the value is the second pass's. The graph stays usable.
	withStrict(function()
		local a = new(1)
		local hidden = 0
		local c = new(function()
			hidden += 1
			return a:get() + hidden
		end)
		local _ = c:get()
		expect(Graph.isReactive() == false, "context restored after the strict double-run")
		a:set(2)
		expect(type(c:get()) == "number", "graph stays usable after an impure double-run")
	end)
end)

test("strict · dependency-set stays consistent across a branch flip", function()
	withStrict(function()
		local cond = new(true)
		local x = new(1)
		local y = new(100)
		local c = new(function()
			return if cond:get() then x:get() else y:get()
		end)
		expect(c:get() == 1, "branch true reads x")
		expect(c() == 1, "stable re-read")
		cond:set(false)
		expect(c:get() == 100, "branch flip re-evaluates correctly under strict")
	end)
end)

test("strict · accumulator body double-applies (feed-forward, like Vide)", function()
	-- The second pass is fed the first pass's result, so a body that builds on its prev value
	-- advances twice under strict, surfacing that it is not safe to run more than once.
	withStrict(function()
		local tick = new(0)
		local c = new(function(prev)
			tick:get()
			return (prev or 0) + 1
		end)
		expect(c:get() == 2, "first eval: nil -> 1 -> 2 across the two passes")
		tick:set(1)
		expect(c:get() == 4, "second eval: 2 -> 3 -> 4 across the two passes")
	end)
end)

test("strict · table-returning body re-evaluates cleanly", function()
	-- The double-run doesn't compare results, so a body returning a fresh table each pass is fine;
	-- the node simply keeps the second pass's table.
	withStrict(function()
		local a = new(1)
		local c = new(function()
			return { a:get() }
		end)
		expect(c:get()[1] == 1, "table memo value correct under strict")
		a:set(2)
		expect(c:get()[1] == 2, "table memo re-evaluates under strict")
	end)
end)

test("strict · effects run twice per evaluation, like Vide", function()
	-- Vide-style strict re-runs every reactive scope, effects included, so a non-idempotent
	-- effect body surfaces its double-fire in dev rather than hiding behind a single run.
	withStrict(function()
		local a = new(1)
		local fires = 0
		local e = new(function()
			a:get()
			fires += 1
		end, true)
		flush()
		expect(fires == 2, "effect body double-runs on creation under strict")
		a:set(2)
		flush()
		expect(fires == 4, "effect double-runs again on change")
		e:Destroy()
	end)
end)

test("strict · a body that errors on the second pass propagates the error", function()
	-- Unlike the old sandboxed diagnostic, the Vide-style double-run is authoritative: an error
	-- on either pass propagates out of the read rather than being swallowed.
	withStrict(function()
		local calls = 0
		local c = new(function()
			calls += 1
			if calls == 2 then
				error("boom on the second pass")
			end
			return 42
		end)
		expectError(function()
			return c:get()
		end, "boom on the second pass", "second-pass error propagates out of the read")
	end)
end)

test("strict · re-entrant computation errors as an active scope", function()
	-- Reading a computed from within its own body means a dependency it should subscribe to is
	-- still evaluating, a reactive cycle. Strict catches it via the active-scope stack.
	withStrict(function()
		local c
		c = new(function()
			return c:get() + 1
		end)
		expectError(function()
			return c:get()
		end, "already active", "self-referential computed errors under strict")
	end)
end)

test("strict · destroying the running scope errors", function()
	-- A body that destroys its own scope mid-run is caught instead of corrupting the graph.
	withStrict(function()
		local c
		c = new(function()
			c:Destroy()
			return 1
		end)
		expectError(function()
			return c:get()
		end, "active scope", "destroying the active scope mid-run errors")
	end)
end)

test("strict · disabling restores the single-run fast path", function()
	Flux.strict(false)
	local a = new(5)
	local runs = 0
	local c = new(function()
		runs += 1
		return a:get()
	end)
	expect(c:get() == 5 and runs == 1, "exactly one run when strict is off")
	a:set(6)
	expect(c:get() == 6 and runs == 2, "still single-run per eval")
end)

test("dispose · destroying a source prunes only that source from observers", function()
	-- The dependency-list invariant: disposing a node must remove ONLY that node from each
	-- observer's source list, never a live sibling. Regression for the swap that assigned
	-- the loop-local variable instead of the array slot in normalDispose.
	local SOURCES = 7 -- node-data slot for the source array (Graph.luau field layout)
	local a = new(1)
	local b = new(2)
	local c = Flux.computed(function()
		return a() + b()
	end)
	expect(c() == 3, "computed reads both sources")

	a:Destroy()

	local sources = c._[SOURCES]
	local hasLive, hasDead = false, false
	for _, node in sources do
		hasLive = hasLive or node == b._
		hasDead = hasDead or node == a._
	end
	expect(hasLive, "the live sibling source b is retained")
	expect(not hasDead, "the destroyed source a is pruned")
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

test("cleanup · rejects a bare array (use Flux.clean for nested teardown)", function()
	-- Flux.cleanup takes ONE cleanable; arrays are not recursed (that's Flux.clean's job).
	-- A plain table without a Destroy/destroy/Disconnect/disconnect method is not cleanable.
	local threw
	local s = Flux.scope(function()
		threw = not pcall(Flux.cleanup, { function() end, function() end })
	end)
	s:Destroy()
	expect(threw, "Flux.cleanup of a plain array errors; use Flux.clean for arrays")
end)

return {}
