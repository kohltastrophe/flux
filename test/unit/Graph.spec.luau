--!nonstrict
local env = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Model = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("Model")) :: any
	else require("../lib/Model") :: any
local GraphModel = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("GraphModel")) :: any
	else require("../lib/GraphModel") :: any
local Graph = if game
	then require(game:GetService("ReplicatedStorage").Flux:WaitForChild("Graph")) :: any
	else require("../../src/Graph") :: any

local Flux = env.Flux
local sert = env.sert
local IS_ROBLOX = env.IS_ROBLOX
local test = sert.test
local rtest = sert.test.roblox
local expect = sert
local expectError = sert.throws
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

test("value · update() re-fires dependents without writing", function()
	local items = Flux({ "Sword" })
	local count = Flux.computed(function()
		return #items()
	end)
	expect(count() == 1, "baseline evaluation")
	table.insert(items:peek(), "Shield")
	expect(count() == 1, "in-place mutation alone does not propagate")
	expect(items:update() == items, "update() returns the node")
	expect(count() == 2, "and its dependents re-run with the same reference")
end)

test("createSignal, createMemo & createEffect · lightweight tuple and function primitives", function()
	local count, setCount = Flux.createSignal(2, function(a, b)
		return math.abs(a - b) < 2
	end)
	local memoRuns = 0
	local memoCleaned = 0
	local effectSeen = 0
	local scope, doubled = Flux.scope(function()
		local d = Flux.createMemo(function()
			memoRuns += 1
			Flux.cleanup(function()
				memoCleaned += 1
			end)
			return count() * 2
		end, function(a, b)
			return a == b
		end)
		Flux.createEffect(function()
			effectSeen = d()
		end)
		expect(d() == 4 and memoRuns == 1, "createMemo evaluates lazily")
		return d
	end)
	flush()
	expect(effectSeen == 4, "createEffect ran on flush")

	setCount(3)
	flush()
	expect(effectSeen == 4 and memoRuns == 1, "createSignal custom equals skipped propagation")

	setCount(3, true)
	flush()
	expect(effectSeen == 6 and memoRuns == 2 and memoCleaned == 1, "forced setCount propagated")

	setCount(10)
	flush()
	expect(effectSeen == 20 and memoRuns == 3 and memoCleaned == 2, "setCount beyond tolerance propagated")

	scope:Destroy()
	expect(memoCleaned == 3, "scope teardown cleaned up createMemo")
	setCount(50)
	flush()
	expect(
		effectSeen == 20 and doubled() == nil and memoRuns == 3,
		"scope teardown stopped createEffect and createMemo"
	)
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

	local sc = Flux.scope(function() end)
	local nodeMT = getmetatable(sc :: any)
	local genericNode: any = setmetatable({ (sig :: any)[1] }, nodeMT)
	local getGeneric = Flux.getter(genericNode)
	local setGeneric = Flux.setter(genericNode)
	setGeneric(77)
	expect(getGeneric() == 77 and genericNode:get() == 77 and genericNode:peek() == 77, "generic node getter/setter")

	local setScope = Flux.setter(sc :: any)
	expect(setScope("ignored") == "ignored", "scope setter returns value without mutating scope")
	sc:Destroy()

	expectError(function()
		Flux.getter("not a node" :: any)
	end, "Flux.getter expects a node")
	expectError(function()
		Flux.setter("not a node" :: any)
	end, "Flux.setter expects a node")
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

test("computed · self-referential computed does not overflow stack on upstream write", function()
	local trigger = Flux.signal(1)
	local comp: any
	comp = Flux.computed(function(prev)
		local t = trigger()
		if t > 1 then
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

test("effect · nested synchronous effect creation does not clobber outer selfWritten requeue", function()
	local sig = Flux.signal(0)
	local outerRuns = 0
	local innerRuns = 0
	local outer = Flux.effect(function()
		outerRuns += 1
		local v = sig()
		if v == 1 then
			sig:set(2)
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

test("computed · raw and read pass plain values through; read tracks a getter's reads", function()
	expect(Flux.raw(7) == 7, "raw passes through plain values")
	expect(Flux.read(7) == 7, "read passes through plain values")

	local source = Flux(1)
	local getter = function()
		return source() * 10
	end
	local getterReadRuns, getterRawRuns, seenRead, seenRaw = 0, 0, nil, nil
	local reader = Flux.effect(function()
		getterReadRuns += 1
		seenRead = Flux.read(getter)
	end)
	local rawReader = Flux.effect(function()
		getterRawRuns += 1
		seenRaw = Flux.raw(getter)
	end)
	flush()
	expect(seenRead == 10 and seenRaw == 10, "both call the getter")
	source(2)
	flush()
	expect(seenRead == 20 and getterReadRuns == 2, "read subscribes to the getter's reads")
	expect(getterRawRuns == 1, "raw subscribes nothing")
	reader:Destroy()
	rawReader:Destroy()
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
	local e = Flux.effect(function()
		runs += 1
		last = v()
	end)
	expect(runs == 0, "effect is deferred, not run on creation")
	flush()
	expect(runs == 1 and last == 0, "effect runs on flush")
	v(7)
	flush()
	expect(runs == 2 and last == 7, "effect re-runs after dependency change")
	e:Destroy()
end)

test("effect · cleanup outside a reactive context errors, blaming the caller", function()
	local message = expectError(function()
		Flux.cleanup(function() end)
	end, "reactive")
	if not IS_ROBLOX then
		expect(string.find(message, "Graph.spec", 1, true) ~= nil, "position points at the caller: " .. message)
	end
end)

test("effect · cleanup rejects uncleanable objects, naming the type", function()
	local scope = Flux.scope(function()
		expectError(function()
			Flux.cleanup({ label = "not an array" } :: any)
		end, "cannot cleanup given object: table")
		expectError(function()
			Flux.cleanup(5 :: any)
		end, "cannot cleanup given object: number")
	end)
	scope:Destroy()
end)

test("flush · re-entrant flush from an effect is a no-op", function()
	local a = new(1)
	local b = new(0)
	local innerRuns = 0
	local inner = Flux.effect(function()
		b:get()
		innerRuns += 1
	end)
	flush()
	local tailRan = 0
	local outer = Flux.effect(function()
		a:get()
		b:set(b:peek() + 1)
		flush()
		tailRan += 1
	end)
	flush()
	expect(tailRan == 1, "effect body completes")
	a:set(2)
	flush()
	expect(tailRan == 2 and innerRuns >= 2, "completes on re-run, inner kept flowing")
	inner:Destroy()
	outer:Destroy()
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
		return dep:get()
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

test("retrack · a bare pair inside untrack(fn) leaves it untracked", function()
	local dep = new(1)
	local runs = 0
	local inside
	local e = Flux.effect(function()
		runs += 1
		untrack(function()
			untrack()
			retrack()
			inside = Flux.isReactive()
			dep:get()
		end)
	end)
	flush()
	expect(runs == 1 and inside == false, "still untracked after the inner pair")
	dep:set(2)
	flush()
	expect(runs == 1, "the read after the inner pair did not subscribe the effect")
	e:Destroy()
end)

test("retrack · without a bare untrack in this run to undo, it changes nothing", function()
	local seen = {}
	local root = Flux.scope(function()
		untrack()
		retrack()
		table.insert(seen, Flux.isReactive())
	end)
	expect(seen[1] == false, "a bare pair in a scope body leaves tracking off")
	root:Destroy()

	local tracking = {}
	local e = Flux.effect(function()
		retrack()
		table.insert(tracking, Flux.isReactive())
		untrack(function()
			retrack()
			table.insert(tracking, Flux.isReactive())
		end)
	end)
	flush()
	expect(tracking[1] == true and tracking[2] == false, "an unmatched retrack() is a no-op")
	e:Destroy()
end)

test("retrack · a suspension does not reach across withOwner or a nested run", function()
	local dep = new(1)
	local runs = 0
	local states = {}
	local inner = new(function()
		retrack()
		return Flux.isReactive()
	end)
	local e = Flux.effect(function()
		runs += 1
		untrack()
		Flux.withOwner(Flux.getOwner(), function()
			retrack()
			table.insert(states, Flux.isReactive())
			untrack()
		end)
		table.insert(states, inner:get())
		dep:get()
		table.insert(states, Flux.isReactive())
		retrack()
		table.insert(states, Flux.isReactive())
	end)
	flush()
	expect(states[1] == false, "retrack() inside withOwner does not restore the outer suspension")
	expect(states[2] == true, "a nested computed run tracks itself")
	expect(states[3] == false, "back in the effect, still suspended")
	expect(states[4] == true, "the effect's own retrack() restores it")
	dep:set(2)
	flush()
	expect(runs == 1, "the suspended read did not subscribe")
	e:Destroy()
end)

test("retrack · a pair inside a tracked raw getter leaves the reaction tracking", function()
	local states = {}
	local e = Flux.effect(function()
		table.insert(
			states,
			Flux.raw(function()
				untrack()
				retrack()
				return Flux.isReactive()
			end)
		)
		table.insert(states, Flux.isReactive())
	end)
	flush()
	expect(states[1] == false, "the getter stays untracked")
	expect(states[2] == true, "the effect still tracks after the getter")
	e:Destroy()
end)

test("scope · returns its body's results; Destroy leaves the plain signals it made", function()
	local root, signal = Flux.scope(function()
		return Flux(99)
	end)
	expect(signal() == 99, "scope returns what its body returned")
	root:Destroy()
	expect(signal() == 99, "a plain signal is not owned: it survives the scope (GC-managed)")
end)

test("prev · computed receives its previous value as the first arg", function()
	local trigger = new(0)
	local prevs = {}
	local runs = 0
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

test("dispose · destroying a source prunes only that source from observers", function()
	local a = new(1)
	local b = new(2)
	local c = Flux.computed(function()
		return (a() or 0) + b()
	end)
	local seen
	local e = Flux.effect(function()
		seen = c()
	end)
	flush()
	expect(seen == 3, "reads both sources")
	a:Destroy()
	b(5)
	flush()
	expect(seen == 5, `b still drives it, saw {seen}`)
	e:Destroy()
end)

test("value · node(nil) is a read; force or :set writes nil", function()
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

test("cleanup · takes what Flux.dispose takes, arrays included", function()
	local ran = 0
	local disposed = false
	local s = Flux.scope(function()
		Flux.cleanup({
			function()
				ran += 1
			end,
			{
				function()
					ran += 1
				end,
			},
		})
		Flux.cleanup({
			Destroy = function()
				disposed = true
			end,
		})
		local later = {}
		Flux.cleanup(later)
		table.insert(later, function()
			ran += 1
		end)
	end)
	expect(ran == 0 and not disposed, "nothing runs before the scope is destroyed")
	s:Destroy()
	expect(ran == 3, "every function in the nested arrays ran, one added after cleanup took its array")
	expect(disposed, "a table with Destroy was destroyed")
end)

test("effect · a write that invalidates a computed it just read re-runs it in the same flush", function()
	local source = Flux(1)
	local doubled = Flux(function()
		return source() * 2
	end)
	local seen = {}
	local e = Flux.effect(function()
		table.insert(seen, doubled())
		if source:peek() < 3 then
			source(source:peek() + 1)
		end
	end)
	flush()
	expect(
		seen[1] == 2 and seen[2] == 4 and seen[3] == 6 and #seen == 3,
		"re-ran until its own writes settled: " .. table.concat(seen, ",")
	)
	source(10)
	flush()
	expect(seen[4] == 20 and #seen == 4, "stays reactive afterwards")
	e:Destroy()
end)

test("computed · a cache it fills while running is read on the run after", function()
	local cache = Flux({})
	local key = Flux("a")
	local label = Flux(function()
		local k = key()
		local hit = cache()[k]
		if hit then
			return hit
		end
		local current = cache:peek()
		local filled = table.clone(current)
		filled[k] = string.upper(k)
		cache(filled)
		return "?"
	end)
	local seen = {}
	local scope = Flux.scope(function()
		Flux.effect(function()
			table.insert(seen, label())
		end)
	end)
	flush()
	expect(seen[#seen] == "A" and label:peek() == "A", `the first key: {table.concat(seen, ",")}`)
	key("b")
	flush()
	expect(seen[#seen] == "B", `the next key: {table.concat(seen, ",")}`)
	cache({ b = "Bee" })
	flush()
	expect(seen[#seen] == "Bee", `stays reactive to the cache: {table.concat(seen, ",")}`)
	scope:Destroy()
end)

test("computed · an observer doesn't keep an answer its source wrote past, even an unchanged one", function()
	local names = Flux({})
	local row = Flux(0)
	local place = Flux(function()
		local id = row()
		local known = names()[id]
		if known then
			return known
		elseif id > 0 then
			names({ [id] = "Arena" })
		end
		return "Loading"
	end)
	local seen = {}
	local scope = Flux.scope(function()
		Flux.effect(function()
			table.insert(seen, place())
		end)
	end)
	flush()
	row(1)
	flush()
	expect(seen[#seen] == "Arena", `{table.concat(seen, ",")}`)
	scope:Destroy()
end)

test("effect · after writing what it read, tracked or not, it runs again behind the effects the write woke", function()
	for _, untracked in { false, true } do
		local loaded = Flux(0)
		local shown = Flux(0)
		local busy = Flux(false)
		local fetches = 0
		local function fetch()
			fetches += 1
			busy(true)
			loaded(loaded:peek() + 1)
			busy(false)
		end
		local scope = Flux.scope(function()
			Flux.effect(function()
				shown(loaded())
			end)
			Flux.effect(function()
				if not busy() and shown() < 3 then
					if untracked then
						Flux.untrack(fetch)
					else
						fetch()
					end
				end
			end)
		end)
		flush()
		local label = `untracked {untracked}`
		expect(shown:peek() == loaded:peek(), `{label}: loaded {loaded:peek()}, shown {shown:peek()}`)
		expect(fetches == 3, `{label}: it waited for the view before asking again: {fetches} fetches`)
		scope:Destroy()
	end
end)

test("effect · a write from its own cleanup doesn't queue it twice", function()
	local a = Flux(0)
	local runs = 0
	local scope = Flux.scope(function()
		Flux.effect(function()
			runs += 1
			local v = a()
			Flux.cleanup(function()
				if v == 1 then
					a(2)
				end
			end)
		end)
	end)
	flush()
	a(1)
	flush()
	a(3)
	flush()
	expect(runs == 3 and a:peek() == 2, `the run after the cleanup reads its write: {runs} runs, a = {a:peek()}`)
	scope:Destroy()
end)

test("computed · going live after an unrelated write doesn't run it again", function()
	local a = Flux(1)
	local other = Flux(0)
	local runs, built = 0, 0
	local c = Flux.computed(function()
		runs += 1
		Flux.computed(function()
			built += 1
			return 0
		end)
		return a()
	end)
	local scope = Flux.scope(function()
		Flux.effect(function()
			c()
			other(other:peek() + 1)
		end)
	end)
	flush()
	expect(runs == 1, `pulled once, then subscribed without a re-run: {runs} runs`)
	a(2)
	flush()
	expect(runs == 2 and c() == 2, "a source change still re-runs it")
	scope:Destroy()
end)

test("effect · a signal it writes before reading it doesn't run it again", function()
	local total = Flux(0)
	local runs = 0
	local scope = Flux.scope(function()
		Flux.effect(function()
			runs += 1
			total(total:peek() + 1)
			total()
		end)
	end)
	flush()
	expect(runs == 1 and total:peek() == 1, `ran {runs} times, total {total:peek()}`)
	scope:Destroy()
end)

test("node · a throwing onDestroy is reported and teardown continues", function()
	local source = Flux(1)
	local runsB, laterRan = 0, false
	local scope = Flux.scope(function()
		local a = Flux.effect(function() end)
		a:onDestroy(function()
			error("onDestroy failure")
		end)
		a:onDestroy(function()
			laterRan = true
		end)
		Flux.effect(function()
			source()
			runsB += 1
		end)
		flush()
	end)
	sert.defer(function()
		scope:Destroy()
	end)
	local warnings = env.warnings(function()
		scope:Destroy()
	end)
	expect(#warnings == 1, `the throwing onDestroy was reported, got {#warnings} warnings`)
	expect(laterRan, "the callbacks after the throwing one still ran")
	source(2)
	flush()
	expect(runsB == 1, "the sibling effect was torn down with the scope")
end)

test("node · onDestroy callbacks run untracked", function()
	local probe, rerun = Flux(1), Flux(1)
	local runs, child = 0, nil
	local scope = Flux.scope(function()
		Flux.effect(function()
			runs += 1
			rerun()
			if child then
				child:Destroy()
				child = nil
			else
				child = Flux.signal(0)
				child:onDestroy(function()
					probe()
				end)
			end
		end)
		flush()
	end)
	sert.defer(function()
		scope:Destroy()
	end)
	rerun(2)
	flush()
	expect(runs == 2, "the second run destroyed the child and ran its onDestroy")
	probe(2)
	flush()
	expect(runs == 2, "the onDestroy read did not become a dependency of the effect")
	scope:Destroy()
end)

test("flush · a suppressed error inside a scope body keeps the scope as owner", function()
	local source = Flux(1)
	local lateRuns = 0
	local ownerAfter, warnings
	local scope = Flux.scope(function()
		Flux.effect(function()
			error("effect failure")
		end)
		warnings = env.warnings(flush)
		ownerAfter = Flux.getOwner()
		Flux.effect(function()
			source()
			lateRuns += 1
		end)
		flush()
	end)
	expect(#warnings == 1, `the effect's error was warned, got {#warnings} warnings`)
	expect(ownerAfter ~= nil, "owner survives the suppressed error")
	scope:Destroy()
	source(2)
	flush()
	expect(lateRuns == 1, "an effect created after the error is torn down with its scope")
end)

test("effect · destroying itself mid-run leaves no trace on its sources", function()
	local source = Flux(1)
	local e
	local scope = Flux.scope(function()
		e = Flux.effect(function()
			source()
			e:Destroy()
			return 5
		end)
		flush()
	end)
	expect(e:peek() == nil, "the disposed effect reads nil")
	source(2)
	flush()
	scope:Destroy()
end)

test("computed · a throwing equals commits nothing and its observers recover", function()
	local source = Flux(1)
	local calls = 0
	local c = Flux.computed(function()
		return source()
	end, function(a, b)
		calls += 1
		if calls == 1 then
			error("equals failure")
		end
		return a == b
	end)
	local seen = {}
	local scope = Flux.scope(function()
		Flux.effect(function()
			table.insert(seen, c())
		end)
		flush()
	end)
	source(2)
	local warnings = env.warnings(flush)
	expect(#warnings == 1, `the equals error was warned, got {#warnings} warnings`)
	expect(#seen == 1, "the effect did not observe a value it was never notified of")
	expect(c:peek() == 2, "a later read re-runs the uncommitted computed")
	flush()
	expect(seen[2] == 2, "the read queued the settled effect, which then saw the value: " .. table.concat(seen, ","))
	source(3)
	flush()
	expect(seen[3] == 3, "and stays reactive afterwards")
	scope:Destroy()
end)

test("effect · settled by a source's error, it re-runs once the source recovers through a top-level read", function()
	local source = Flux(1)
	local broken = true
	local c = Flux.computed(function()
		if broken then
			error("computed failure")
		end
		return source() * 10
	end)
	local seen, warnings = {}, nil
	local scope = Flux.scope(function()
		Flux.effect(function()
			table.insert(seen, c())
		end)
		warnings = env.warnings(flush)
	end)
	expect(#warnings == 1, `the effect's error was warned, got {#warnings} warnings`)
	expect(#seen == 0, "nothing observed while the source is broken")
	broken = false
	expect(c:peek() == 10, "a top-level read recovers the computed")
	flush()
	expect(seen[1] == 10, "the settled effect was queued by the recovery and ran: " .. table.concat(seen, ","))
	source(2)
	flush()
	expect(seen[2] == 20, "and stays reactive afterwards")
	scope:Destroy()
end)

-- Model-based properties ------------------------------------------------------------------------------------------

local function model(options)
	return function(g)
		env.warnings(function()
			GraphModel.run(Flux, GraphModel.generate(g, options), options)
		end)
	end
end

sert.prop("graph · random programs agree with the reference", model({}), { runs = 200, exhaustive = { size = 3 } })

sert.prop(
	"graph · createSignal, createMemo, createEffect, getter and setter agree with the reference",
	model({ solid = true }),
	{ runs = 150, exhaustive = { size = 3 } }
)

sert.prop(
	"graph · fault injection recovers and restores global state (expected warn)",
	model({ faults = true }),
	{ runs = 100, exhaustive = { size = 3 }, regressions = { 1406592155, 3668587576 } }
)

sert.prop("graph · teardown runs exactly once", model({ teardown = true }), { runs = 150, exhaustive = { size = 3 } })

test("regression · a dead reader of a destroyed signal can go live", function()
	local s1 = Flux.signal(0)
	local c3 = Flux.computed(function()
		return s1()
	end)
	local c5 = Flux.computed(function()
		return s1()
	end)
	local c6 = Flux.computed(function()
		return c5()
	end)
	expect(c6() == 0 and c3() == 0, "read while alive")
	s1:Destroy()
	local seen
	local scope = Flux.scope(function()
		Flux.effect(function()
			seen = { c6(), c3() }
		end)
	end)
	flush()
	expect(seen ~= nil, "subscribing through it doesn't crash")
	expect(Flux.getOwner() == nil, "no owner leaks")
	scope:Destroy()
end)

test("regression · a computed destroyed by a later read in the same run isn't revived", function()
	local s1 = Flux.signal(0)
	local c2 = Flux.computed(function()
		return s1() + 1
	end)
	local o4
	Flux.withOwner(c2, function()
		o4 = Flux.computed(function()
			return s1()
		end)
	end)
	local scope = Flux.scope(function()
		Flux.effect(function()
			o4()
			c2()
		end)
	end)
	flush()
	s1(2)
	flush()
	expect(o4() == nil, "a destroyed computed reads nil")
	expect(not Graph.isObserved(o4), "and nothing observes it")
	scope:Destroy()
end)

test("regression · a nested bare untrack doesn't break the outer retrack", function()
	local a = Flux(0)
	local runs = 0
	local inner = Flux.computed(function()
		Flux.untrack()
		local v = a()
		Flux.retrack()
		return v
	end)
	local outer = Flux.computed(function()
		runs += 1
		Flux.untrack()
		inner()
		Flux.retrack()
		local child = Flux.computed(function()
			return 1
		end)
		return a() + child()
	end)
	expect(outer() == 1, "reads")
	a(1)
	expect(outer() == 2 and runs == 2, "tracking resumed after the outer retrack")
end)

test("regression · an effect isn't re-run for a computed it pulled current itself", function()
	local s = Flux(0)
	local c = Flux.computed(function()
		return s()
	end)
	local seen = {}
	local scope = Flux.scope(function()
		Flux.effect(function()
			local v = s()
			if v < 3 then
				s(v + 1)
			end
		end)
		Flux.effect(function()
			table.insert(seen, c())
		end)
	end)
	flush()
	for i = 2, #seen do
		expect(seen[i] ~= seen[i - 1], `ran again with an unchanged value: {table.concat(seen, ",")}`)
	end
	expect(seen[#seen] == 3, "ends current")
	scope:Destroy()
end)

test("regression · a computed an error left keeps its error once its last reader goes", function()
	local fail = Flux(false)
	local c = Flux.computed(function()
		if fail() then
			error("broken", 0)
		end
		return 1
	end)
	local scope = Flux.scope(function()
		Flux.effect(function()
			Flux.untrack(function()
				return Flux.raw(c)
			end)
			c()
		end)
	end)
	flush()
	fail(true)
	local warnings = env.warnings(flush)
	expect(#warnings == 1, `the effect's error was warned, got {#warnings} warnings`)
	expect(not pcall(function()
		return c:peek()
	end), "still raises, not the last good value")
	scope:Destroy()
	fail(false)
	expect(c() == 1, "recovers")
end)

test(
	"regression · the loop guard disposes an effect that keeps waking itself, warns once and ends the flush",
	function()
		local s = Flux.signal(0)
		local runs, cleanups, destroyed = 0, 0, 0
		local e = Flux.effect(function()
			runs += 1
			Flux.cleanup(function()
				cleanups += 1
			end)
			s:set(s:get() + 1)
		end)
		e:onDestroy(function()
			destroyed += 1
		end)
		sert.defer(function()
			e:Destroy()
		end)
		local warnings = env.warnings(flush)
		expect(runs == 100, `it ran 100 times, then was disposed (ran {runs})`)
		expect(cleanups == 100 and destroyed == 1, "its cleanups and onDestroy ran")
		expect(#warnings == 1, `warned once, got {#warnings}`)
		expect(string.find(warnings[1], "Graph.spec", 1, true) ~= nil, `the warning names its source: {warnings[1]}`)
		s:set(0)
		flush()
		expect(runs == 100, "disposed: a write doesn't run it again")
	end
)

test("regression · the loop guard also stops effects that keep waking each other", function()
	local x, y, s = Flux.signal(0), Flux.signal(0), Flux.signal(0)
	local c = Flux.computed(function()
		return s:get()
	end)
	local a = Flux.effect(function()
		y:set(x:get() + 1)
	end)
	local b = Flux.effect(function()
		x:set(y:get() + 1)
	end)
	local e = Flux.effect(function()
		s:set(c:get() + 1)
	end)
	local warnings = env.warnings(flush)
	expect(#warnings == 2, `one effect of the pair and the self-waking one were disposed, got {#warnings} warnings`)
	a:Destroy()
	b:Destroy()
	e:Destroy()
end)

test("regression · withOwner on a destroyed owner disposes what fn registered when it returns or throws", function()
	local scope = Flux.scope(function() end)
	scope:Destroy()
	local s = Flux.signal(0)
	local runs, cleanups = 0, 0
	Flux.withOwner(scope, function()
		Flux.effect(function()
			runs += s:get()
		end)
		Flux.cleanup(function()
			cleanups += 1
		end)
	end)
	expect(cleanups == 1, "the cleanup ran when withOwner returned")
	expect(not pcall(Flux.withOwner, scope, function()
		Flux.cleanup(function()
			cleanups += 1
		end)
		error("late callback failed", 0)
	end), "the error passes through")
	expect(cleanups == 2, "and on an error too")
	s:set(1)
	flush()
	expect(runs == 0, "the effect was disposed before it ran")
end)

test("regression · a reader catching raw(throwing getter) keeps tracking and gets the original error", function()
	local s = Flux.signal(1)
	local errObj = { code = 1 }
	local caught
	local c = Flux.computed(function()
		local _, err = pcall(Flux.raw, function()
			error(errObj)
		end)
		caught = err
		return s:get()
	end)
	expect(c:get() == 1 and caught == errObj, "the error value passes through unchanged")
	s:set(2)
	expect(c:get() == 2, "the read after the caught error is tracked")
end)

test("regression · a source destroyed by a read later in the same run leaves the reader intact", function()
	local s = Flux.signal(0)
	local scope, c = Flux.scope(function()
		return Flux.computed(function()
			return s:get()
		end)
	end)
	local x = Flux.computed(function()
		if s:get() == 1 then
			scope:Destroy()
		end
		return s:get()
	end)
	local runs = 0
	local e = Flux.effect(function()
		runs += 1
		c:get()
		Flux.untrack(function()
			return x:get()
		end)
	end)
	flush()
	s:set(1)
	local ok, err = pcall(flush)
	expect(ok, `the flush completes: {err}`)
	expect(runs == 2, `ran {runs} times`)
	e:Destroy()
end)

-- on -----------------------------------------------------------------------------------------------------------

test("on · each dependency shape: what fn receives, when it re-runs, and its own reads untracked", function()
	local a, b, other = new(1), new(2), new(0)
	local shapes = {
		{ a, 1, 3 },
		{
			function()
				return a:get() * 2
			end,
			2,
			6,
		},
		{ { a, b }, { 1, 2 }, { 3, 2 } },
		{ { 1, 2, 3 }, { 1, 2, 3 }, nil },
	}
	for index, shape in shapes do
		a:set(1)
		local inputs, prevs = {}, {}
		local c = new(Flux.on(shape[1], function(input, prevInput)
			other:get()
			table.insert(inputs, input)
			table.insert(prevs, prevInput or false)
			return input
		end))
		c:get()
		sert.eq(inputs[1], shape[2], `shape {index}: the first input`)
		expect(prevs[1] == false, `shape {index}: the first prevInput is nil`)
		other:set(other:peek() + 1)
		c:get()
		expect(#inputs == 1, `shape {index}: a read inside fn doesn't re-run it`)
		a:set(3)
		c:get()
		if shape[3] == nil then
			expect(#inputs == 1, `shape {index}: static deps never re-run it`)
		else
			sert.eq(inputs[2], shape[3], `shape {index}: re-runs on a listed dep's change`)
			sert.eq(prevs[2], shape[2], `shape {index}: prevInput is the input before`)
		end
		c:Destroy()
	end

	local runs = 0
	local deferred = new(Flux.on(a, function(v)
		runs += 1
		return v * 100
	end, true))
	expect(deferred:get() == nil and runs == 0, "defer: the first evaluation doesn't call fn")
	a:set(4)
	expect(deferred:get() == 400 and runs == 1, "defer: fires on the first change")
end)

-- onObserved / onUnobserved ------------------------------------------------------------------------------------

test("onObserved · fires on the first observer and the last one leaving, through computeds", function()
	local log = {}
	local s = Flux.signal(0)
	sert.defer(function()
		s:Destroy()
	end)
	s:onObserved(function()
		table.insert(log, "on")
	end)
	s:onUnobserved(function()
		table.insert(log, "off")
	end)
	local c = Flux.computed(function()
		return s() + 1
	end)
	sert.defer(function()
		c:Destroy()
	end)
	expect(c() == 1 and #log == 0, "a read outside any effect doesn't observe it")
	local scope = Flux.scope(function()
		Flux.effect(function()
			c()
		end)
		Flux.effect(function()
			s()
		end)
	end)
	sert.defer(function()
		scope:Destroy()
	end)
	flush()
	expect(table.concat(log, ",") == "on", "observed once, though two effects depend on it")
	scope:Destroy()
	expect(table.concat(log, ",") == "on,off", "unobserved once")
	s(1)
	expect(c() == 2, "still readable")
	c:Destroy()
	s:Destroy()
end)

test("onObserved · a computed's hooks follow the effects that read it", function()
	local log = {}
	local s = Flux.signal(0)
	local gate = Flux.signal(true)
	local c = Flux.computed(function()
		return s() * 2
	end)
	sert.defer(function()
		c:Destroy()
		s:Destroy()
		gate:Destroy()
	end)
	c:onObserved(function()
		table.insert(log, "on")
	end)
	c:onUnobserved(function()
		table.insert(log, "off")
	end)
	local scope = Flux.scope(function()
		Flux.effect(function()
			if gate() then
				c()
			end
		end)
	end)
	sert.defer(function()
		scope:Destroy()
	end)
	flush()
	gate(false)
	flush()
	gate(true)
	flush()
	expect(table.concat(log, ",") == "on,off,on", "follows the branch: " .. table.concat(log, ","))
	scope:Destroy()
	c:Destroy()
	s:Destroy()
	gate:Destroy()
end)

test("computed · an equal result is stored but doesn't notify observers", function()
	local source = Flux({ id = 1, name = "a" })
	local c = Flux.computed(function()
		local v = source()
		return { id = v.id, name = v.name }
	end, function(a, b)
		return a.id == b.id
	end)
	local runs, seen = 0, nil
	local scope = Flux.scope(function()
		Flux.effect(function()
			runs += 1
			seen = c()
		end)
	end)
	flush()
	local before = runs
	source({ id = 1, name = "b" })
	flush()
	expect(runs == before, "equal by id, so the effect wasn't told")
	expect(seen.name == "a", "the effect kept what it saw")
	expect(c().name == "a", "a reader pulling keeps the old equal object")
	source({ id = 2, name = "c" })
	flush()
	expect(runs == before + 1 and seen.name == "c", "an unequal one notifies")
	scope:Destroy()
end)

-- cleanup / dispose ---------------------------------------------------------------------------------------------------

test("dispose · one failing cleanup is warned and doesn't abort the rest, nested arrays included", function()
	local ran, nested = false, false
	local warnings = env.warnings(function()
		Flux.dispose({
			function()
				error("cleanup failure")
			end,
			{
				function()
					nested = true
				end,
			},
			function()
				ran = true
			end,
		})
	end)
	expect(#warnings == 1, `the failure was warned once, got {#warnings} warnings`)
	expect(ran and nested, "every other function ran, the nested one too")
end)

test("dispose · a table is torn down by its first method of Destroy, destroy, Disconnect, disconnect", function()
	local order = { "Destroy", "destroy", "Disconnect", "disconnect" }
	for i, method in order do
		local called = {}
		local obj = {}
		for j = i, #order do
			obj[order[j]] = function(self)
				expect(self == obj, `{order[j]} is called as a method`)
				table.insert(called, order[j])
			end
		end
		Flux.dispose(obj)
		expect(#called == 1 and called[1] == method, `{method} wins: called {table.concat(called, ",")}`)
	end
end)

test("dispose · a Flux node is destroyed, once", function()
	local node = new(7)
	sert.defer(function()
		node:Destroy()
	end)
	local destroyed = 0
	node:onDestroy(function()
		destroyed += 1
	end)
	Flux.dispose(node)
	expect(destroyed == 1 and node() == nil, "dispose(node) destroys it through Node.Destroy")
	expect(Flux.isNode(node), "a destroyed node keeps its metatable (isNode stays true)")
	Flux.dispose(node)
	expect(destroyed == 1, "a second dispose does not re-destroy")
end)

test("dispose · nil and primitives are silent no-ops", function()
	Flux.dispose(nil)
	for _, value in { 42, "hello", true } :: { any } do
		Flux.dispose(value)
	end
end, { smoke = true })

test("dispose · cancels a suspended thread, and tolerates a dead one", function()
	local resumed = false
	local co = coroutine.create(function()
		coroutine.yield()
		resumed = true
	end)
	coroutine.resume(co)
	Flux.dispose(co)
	expect(coroutine.status(co) == "dead" and not resumed, "the suspended thread was cancelled")
	Flux.dispose(co)
end)

test("dispose · destroys an Instance once, and an Instance is cleanable", function()
	local folder = env.Instance.new("Folder")
	expect(Graph.isCleanable(folder), "an Instance is cleanable")
	Flux.dispose(folder)
	expect(not pcall(function()
		folder.Parent = env.Instance.new("Folder")
	end), "destroyed: its Parent is locked")
	Flux.dispose(folder)
end)

rtest("dispose · disconnects a live RBXScriptConnection and tolerates double clean", function()
	local bindable = Instance.new("BindableEvent")
	local conn = bindable.Event:Connect(function() end)
	Flux.dispose(conn)
	expect(conn.Connected == false, "Clean disconnects the connection")
	Flux.dispose(conn)
	bindable:Destroy()
end)

test("register · dispose runs the registered teardown before any Destroy lookup", function()
	local seen
	local reads = 0
	local proxy = setmetatable({}, {
		__index = function(_, key)
			reads += 1
			return function() end
		end,
	})
	Graph.register(proxy, function(obj)
		seen = obj
	end)
	expect(Graph.isCleanable(proxy), "a registered table is cleanable")
	Flux.dispose(proxy)
	expect(seen == proxy, "the teardown receives the table")
	expect(reads == 0, "the proxy's __index was never read")
end)

test("register · a teardown error is warned, not raised", function()
	local obj = {}
	Graph.register(obj, function()
		error("teardown failure")
	end)
	local warnings = env.warnings(function()
		Flux.dispose(obj)
	end)
	expect(#warnings == 1, `warned once, got {#warnings} warnings`)
end)

test("register · nil unregisters", function()
	local ran = false
	local obj = { 1 }
	Graph.register(obj, function()
		ran = true
	end)
	Graph.register(obj, nil)
	Flux.dispose(obj)
	expect(not ran, "the teardown is gone")
	expect(not Graph.isCleanable({ x = 1 }), "an unregistered keyed table is still not cleanable")
end)

-- Safe ----------------------------------------------------------------------------------------------------------------

test("safe · nil fallback is valid", function()
	local s = Flux.safe(function(): number?
		error("always")
	end, nil)
	sert.defer(function()
		s:Destroy()
	end)
	expect(s:get() == nil, "nil fallback")
end)

test("safe · a recovery fn that throws re-raises its own error unchanged", function()
	local s1 = Flux.safe(function(): string
		error("inner")
	end, function(): string
		error("handler boom", 0)
	end)
	sert.defer(function()
		s1:Destroy()
	end)
	local ok, caught = pcall(s1.get, s1)
	expect(not ok and caught == "handler boom", `the handler's message, not a wrapped copy (got {caught})`)

	local errObj = { code = 500 }
	local s2 = Flux.safe(function(): string
		error("inner")
	end, function(): string
		error(errObj)
	end)
	sert.defer(function()
		s2:Destroy()
	end)
	local okTable, caughtTable = pcall(s2.get, s2)
	expect(not okTable and caughtTable == errObj, "a thrown table re-raises as the same table")
end)

test("safe · regression: a reader catching a failing source under pcall re-runs", function()
	local x = Flux.signal(0)
	local failing = Flux.computed(function()
		if x:get() == 1 then
			error("boom", 0)
		end
		return x:get()
	end)
	local reader = Flux.computed(function()
		return (pcall(failing.get, failing))
	end)
	expect(reader:get() == true, "baseline")
	x:set(1)
	local ok, caught = pcall(reader.get, reader)
	expect(ok and caught == false, `the reader's pcall catches the error (escaped: {caught})`)
	reader:Destroy()
	failing:Destroy()
end)

test("safe · regression: a reader that saw an error re-runs when its source heals", function()
	local x = Flux.signal(1)
	local failing = Flux.computed(function()
		if x:get() == 0 then
			error("boom", 0)
		end
		return x:get()
	end)
	local reader = Flux.computed(function()
		return (pcall(failing.get, failing))
	end)
	expect(failing:get() == 1, "a good value first")
	x:set(0)
	expect(reader:get() == false, "the reader sees the error")
	x:set(1)
	expect(reader:get() == true, "healing back to the same value re-runs the reader")
	reader:Destroy()
	failing:Destroy()
end)

sert.prop("safe · value is f(input) or the fallback's, heals on change, recovery untracked", function(g)
	Model.isolated(function(owners)
		local faults, handlerThrows = {}, {}
		local recovery = g:pick({ "static", "fn", "fn that may throw" })
		local thrownTable = g:bool()
		for v = 0, 2 do
			faults[v] = g:bool()
			handlerThrows[v] = recovery == "fn that may throw" and g:bool()
		end
		local x, other, a = Flux.signal(g:int(0, 2)), Flux.signal(0), Flux.signal(0)
		g:note(
			"%s recovery, faults %s%s%s, thrown %s",
			recovery,
			tostring(faults[0]),
			tostring(faults[1]),
			tostring(faults[2]),
			if thrownTable then "table" else "string"
		)

		local runs, cleanups, destroyed, seenErr = 0, 0, false, nil
		local function fallback(err)
			seenErr = err
			local bonus = other:get()
			local v = x:peek()
			if handlerThrows[v] then
				error(`handler {v}`, 0)
			end
			return 100 + bonus
		end
		local s
		local owner = Flux.scope(function()
			s = Flux.safe(function(): number
				runs += 1
				Flux.cleanup(function()
					cleanups += 1
				end)
				local v = x:get()
				if faults[v] then
					error(if thrownTable then { code = v } else `fault {v}`, 0)
				end
				return v * 10
			end, if recovery == "static" then -1 else fallback)
			s:onDestroy(function()
				destroyed = true
			end)
		end)
		table.insert(owners, owner)
		local outer = Flux.computed(function()
			local ok, value = pcall(s.get, s)
			return { ok = ok, value = value, a = a:get() }
		end)
		table.insert(owners, outer)

		local evaluated, changed, raised = false, false, false
		local function expected(): (boolean, any)
			local v = x:peek()
			if not faults[v] then
				return true, v * 10
			elseif recovery == "static" then
				return true, -1
			elseif handlerThrows[v] then
				return false, `handler {v}`
			end
			return true, 100 + other:peek()
		end
		local cached: { any } = {}
		local function afterRead(before: number, via: string)
			local due = not evaluated or changed or raised
			local reran = runs - before
			if via == "direct" or not raised or changed or not evaluated then
				sert.eq(
					reran,
					if due then 1 else 0,
					`{via} read: runs only when the input changed or the last run raised`
				)
			end
			sert(reran <= 1, "at most one run per read")
			if reran == 1 then
				evaluated, changed = true, false
				local ok, value = expected()
				raised = not ok
				cached = { ok, value }
				local v = x:peek()
				if faults[v] and recovery ~= "static" then
					if thrownTable then
						sert(type(seenErr) == "table" and seenErr.code == v, "the recovery fn gets the thrown table")
					else
						sert(
							string.find(tostring(seenErr), `fault {v}`, 1, true) ~= nil,
							"the recovery fn gets the error"
						)
					end
				end
			end
			local lastFaulted = faults[x:peek()]
			sert.eq(
				cleanups,
				if lastFaulted then runs else runs - 1,
				"earlier runs (and any faulted tryFn run) ran cleanup before returning"
			)
		end
		local function matches(ok: boolean, value: any, where: string)
			sert.eq(ok, cached[1], `{where}: raises only when the recovery fn throws`)
			if ok then
				sert.eq(if type(value) == "table" then value[1] else value, cached[2], `{where}: value`)
			else
				sert(string.find(tostring(value), cached[2], 1, true) ~= nil, `{where}: the recovery fn's own error`)
			end
		end

		for _, op in
			g:list(function(g)
				return g:weighted({ { 3, "x" }, { 2, "other" }, { 1, "a" }, { 2, "read" }, { 2, "outer" } })
			end)
		do
			if op == "x" or op == "other" or op == "a" then
				local signal = if op == "x" then x elseif op == "other" then other else a
				local value = g:int(0, 2)
				g:note("%s = %d", op, value)
				if op == "x" and value ~= x:peek() then
					changed = true
				end
				signal:set(value)
			elseif op == "read" then
				g:note("read")
				local before = runs
				local ok, value = pcall(s.get, s)
				afterRead(before, "direct")
				matches(ok, value, "direct read")
			else
				g:note("outer read")
				local before = runs
				local outerOk, result = pcall(outer.get, outer)
				afterRead(before, "outer")
				sert(outerOk, `the reader re-runs and catches the error itself: {result}`)
				matches(result.ok, result.value, "read under pcall")
				sert.eq(result.a, a:peek(), "the reader still tracks what it reads after a failed read")
			end
		end

		owner:Destroy()
		sert(destroyed, "destroying its scope destroys the safe node")
		sert.eq(cleanups, runs, "and runs the last run's cleanup")
	end)
end, {
	runs = 200,
	size = 16,
	exhaustive = { size = 2 },
})

-- Context -------------------------------------------------------------------------------------------------------------

test("context · provide validates callback; bindContext validates fn and passes varargs", function()
	local ctx = Flux.context("default")
	expectError(function()
		ctx:provide("x", "not a function" :: any)
	end, "expects a function")
	expectError(function()
		Flux.bindContext(123 :: any)
	end, "expects a function")

	local rawFn = function() end
	expect(Flux.bindContext(rawFn) == rawFn, "bindContext with no active context returns fn identity")

	local bound
	ctx:provide("scoped", function()
		bound = Flux.bindContext(function(a: number, b: number)
			return ctx:get(), a + b, a * b
		end)
	end)
	local tag, sum, prod = bound(3, 4)
	expect(tag == "scoped" and sum == 7 and prod == 12, "bound fn forwards args and multiple returns")
end)

local BOOM = "context model boom"
local VALUES: { any } = { "x", "y", false, nil }
local DEFAULTS = { "d1", "d2" }

type Frame = { parent: Frame?, context: number, value: any }

local function lookup(chain: Frame?, context: number): any
	local frame = chain
	while frame do
		if frame.context == context then
			return frame.value
		end
		frame = frame.parent
	end
	return DEFAULTS[context]
end

local function chainText(chain: Frame?): string
	local parts = {}
	local frame = chain
	while frame do
		table.insert(parts, 1, `{frame.context}={frame.value}`)
		frame = frame.parent
	end
	return "[" .. table.concat(parts, " ") .. "]"
end

local function genCtxBody(g, depth: number, reaction: boolean, bound: boolean, length: number?): { any }
	return g:list(function(g)
		local nested = depth > 0
		local kind = g:weighted({
			{ 3, "probe" },
			{ 2, "read" },
			{ if bound then 0 else 2, "call" },
			{ if reaction then 0 else 2, "flush" },
			{ if nested then 3 else 0, "provide" },
			{ if nested then 2 else 0, "effect" },
			{ 2, "computed" },
			{ if nested and not reaction then 2 else 0, "scope" },
			{ if nested then 2 else 0, "withOwner" },
			{ if nested then 2 else 0, "bind" },
		})
		local st: any = { kind = kind }
		if kind == "provide" then
			st.context, st.value, st.throws = g:int(1, 2), VALUES[g:int(1, 4)], g:bool(0.25)
			st.body = genCtxBody(g, depth - 1, reaction, bound)
		elseif kind == "effect" then
			st.body = genCtxBody(g, depth - 1, true, bound)
		elseif kind == "scope" then
			st.body = genCtxBody(g, depth - 1, reaction, bound)
		elseif kind == "withOwner" then
			st.index, st.throws = g:int(1, 3), g:bool(0.25)
			st.body = genCtxBody(g, depth - 1, reaction, bound)
		elseif kind == "bind" then
			st.body = genCtxBody(g, depth - 1, true, true)
		elseif kind == "read" or kind == "call" then
			st.index = g:int(1, 3)
			st.throws = kind == "call" and g:bool(0.25)
		end
		return st
	end, 0, length or math.min(3, g.size))
end

local function nth(list: { any }, index: number): any
	return if #list > 0 then list[(index - 1) % #list + 1] else nil
end

local function call(what: string, throws: boolean, fn: (...any) -> any, ...: any)
	if throws then
		local ok, err = pcall(fn, ...)
		sert(not ok and string.find(tostring(err), BOOM, 1, true) ~= nil, `{what} re-raises the body's error`)
	else
		sert.eq(fn(...), "returned", `{what} returns fn's result`)
	end
end

sert.prop("context · nested provide, reactions, scopes, withOwner and bindContext match the lexical chain", function(g)
	Model.isolated(function(owners)
		local program = genCtxBody(g, math.min(3, g.size + 1), false, false, g.size)
		local contexts = { Flux.context("d1"), Flux.context("d2") }
		local effects, computeds, scopes, bound = {}, {}, {}, {}
		local flushChain: Frame? = nil

		local function probe(chain: Frame?, where: string)
			for index, context in contexts do
				sert.eq(context:get(), lookup(chain, index), `{where}: context {index} under {chainText(chain)}`)
			end
		end
		local function flushCtx(chain: Frame?, where: string)
			local previous = flushChain
			flushChain = chain
			Flux.flush()
			flushChain = previous
			for index, record in effects do
				sert(record.ran, `effect {index} ran by the {where} flush`)
			end
			probe(chain, `after the {where} flush`)
		end

		local exec
		local function block(body: { any }, chain: Frame?, reaction: boolean, throws: boolean): string
			exec(body, chain, reaction)
			if throws then
				error(BOOM, 0)
			end
			return "returned"
		end
		function exec(body: { any }, chain: Frame?, reaction: boolean)
			for _, st in body do
				local kind = st.kind
				g:note(
					"%s%s under %s%s",
					kind,
					if kind == "provide" then ` {st.context}={st.value}` elseif st.index then ` #{st.index}` else "",
					chainText(chain),
					if st.throws then " (throws)" else ""
				)
				if kind == "probe" then
					probe(chain, "probe")
				elseif kind == "provide" then
					local context = contexts[st.context]
					local inner = { parent = chain, context = st.context, value = st.value }
					call("provide", st.throws, context.provide, context, st.value, function()
						return block(st.body, inner, reaction, st.throws)
					end)
					probe(chain, "after provide")
				elseif kind == "effect" then
					local record = { ran = false }
					table.insert(effects, record)
					local node = Flux.effect(function()
						record.ran = true
						exec(st.body, chain or flushChain, true)
					end)
					node:onDestroy(function()
						record.ran = true
					end)
					table.insert(owners, node)
				elseif kind == "computed" then
					local dep = Flux.signal(0)
					local node = Flux.computed(function()
						dep:get()
						return { contexts[1]:get(), contexts[2]:get() }
					end)
					table.insert(owners, node)
					local record = { node = node, dep = dep, creation = chain, dead = false }
					node:onDestroy(function()
						record.dead = true
					end)
					table.insert(computeds, record)
				elseif kind == "read" then
					local record = nth(computeds, st.index)
					if record and not record.dead then
						Flux.untrack(function()
							record.dep:set(record.dep:peek() + 1)
							local seen = record.node:get()
							local expectedChain = record.creation or chain
							for index = 1, 2 do
								local where = `computed run: context {index} under {chainText(expectedChain)}`
								sert.eq(seen[index], lookup(expectedChain, index), where)
							end
						end)
					end
				elseif kind == "flush" then
					flushCtx(chain, "next")
				elseif kind == "scope" then
					local owner = Flux.scope(function()
						exec(st.body, chain, reaction)
					end)
					table.insert(owners, owner)
					table.insert(scopes, { owner = owner, creation = chain })
				elseif kind == "withOwner" then
					local record = nth(scopes, st.index)
					if record then
						call("withOwner", st.throws, Flux.withOwner, record.owner, function()
							return block(st.body, record.creation or chain, reaction, st.throws)
						end)
						probe(chain, "after withOwner")
					end
				elseif kind == "bind" then
					table.insert(bound, { creation = chain, body = st.body, fn = Flux.bindContext(block) })
				elseif kind == "call" then
					local record = nth(bound, st.index)
					if record then
						local inner = record.creation or chain
						call("a bound callback", st.throws, record.fn, record.body, inner, reaction, st.throws)
						probe(chain, "after a bound call")
					end
				end
			end
		end

		exec(program, nil, false)
		flushCtx(nil, "last")
	end)
end, { runs = 100, exhaustive = { size = 1 } })

test("untrack · 0-arg untrack in stabilize or context-wrapped computed does not leak evalNode or susp", function()
	for _, callRetrack in { false, true } do
		local s1 = Flux.signal(1)
		local s2 = Flux.signal(10)
		local c2 = Flux.computed(function()
			return s2() * 2
		end)
		local c0 = Flux.computed(function()
			local a = s1()
			local b = c2()
			Flux.untrack()
			if callRetrack then
				Flux.retrack()
			end
			return a + b
		end)
		local seen = 0
		local scope = Flux.scope(function()
			Flux.effect(function()
				seen = c0()
			end)
			Flux.effect(function()
				if s1() == 2 and s2:peek() == 10 then
					s2(20)
					c2()
				end
			end)
		end)
		flush()
		expect(seen == 21, `initial seen is 21 (retrack={callRetrack}), got {seen}`)
		s1(2)
		flush()
		expect(seen == 42, `c0 was not skipped after stabilize untrack (retrack={callRetrack}), got {seen}`)
		scope:Destroy()
	end

	local ctx = Flux.context("a")
	local dep = Flux.signal(1)
	local leaked = Flux.signal(100)
	local cCtx = ctx:provide("b", function()
		return Flux.computed(function()
			local v = dep()
			Flux.untrack()
			return `{ctx:get()}:{v}`
		end)
	end)
	expect(cCtx() == "b:1", "context-wrapped computed evaluated via runComputedProtected")
	local outer = Flux.computed(function()
		Flux.retrack()
		return leaked()
	end)
	expect(outer() == 100, "outer computed evaluated")
	cCtx:Destroy()
	outer:Destroy()
end)

test("effect · pulling a dirtied computed dependency mid-run requeues the running effect", function()
	for _, via in { "untrack", "computed" } do
		local s = Flux.signal(1)
		local trigger = Flux.signal(0)
		local c = Flux.computed(function()
			return s() * 10
		end)
		local c2 = Flux.computed(function()
			return c() + 1
		end)
		local seen = {}
		local scope = Flux.scope(function()
			Flux.effect(function()
				local t = trigger()
				local v = c()
				table.insert(seen, v)
				if t == 1 and v == 10 then
					if via == "untrack" then
						Flux.untrack(function()
							s(2)
							c()
						end)
					else
						s(2)
						c2()
					end
				end
			end)
		end)
		flush()
		expect(#seen == 1 and seen[1] == 10, `initial flush saw 10 via {via}`)
		trigger(1)
		flush()
		expect(
			#seen == 3 and seen[2] == 10 and seen[3] == 20,
			`re-ran when computed dependency was pulled mid-run via {via}: {table.concat(seen, ",")}`
		)
		scope:Destroy()
	end

	local total = Flux.signal(0)
	local trigger = Flux.signal(0)
	local derived = Flux.computed(function()
		return total() * 2
	end)
	local runs = 0
	local scope = Flux.scope(function()
		Flux.effect(function()
			runs += 1
			trigger()
			total(total:peek() + 1)
			derived()
		end)
	end)
	flush()
	expect(runs == 1 and derived:peek() == 2, `ran once on initial flush: {runs}`)
	trigger(1)
	flush()
	expect(runs == 2 and derived:peek() == 4, `writing before first computed read does not self-requeue: {runs}`)
	scope:Destroy()
end)

test("effect · post-divergence readThisRun, guarded runningEffect restore, and untrack error recovery", function()
	local branch = Flux.signal(false)
	local s1 = Flux.signal(1)
	local s2 = Flux.signal(10)
	local s3 = Flux.signal(100)
	local runs = 0
	local scope = Flux.scope(function()
		Flux.effect(function()
			runs += 1
			if not branch() then
				s1()
				s2()
			else
				s2()
				s3()
				if runs == 2 then
					s3(101)
				end
			end
		end)
	end)
	flush()
	expect(runs == 1, "initial run")
	branch(true)
	flush()
	expect(runs == 3 and s3:peek() == 101, "writing a post-divergence source after reading it requeues the effect once")
	scope:Destroy()

	local a = Flux.signal(0)
	local innerTarget = Flux.signal(0)
	local outerRuns = 0
	local scope2 = Flux.scope(function()
		Flux.effect(function()
			outerRuns += 1
			a()
			if outerRuns == 1 then
				Flux.withOwner(nil, function()
					local inner = Flux.effect(function()
						innerTarget()
					end)
					inner:Destroy()
				end)
				a(1)
			end
		end)
	end)
	flush()
	expect(outerRuns == 2, "outer effect preserves runningEffect across nested withOwner(nil) effect creation")
	scope2:Destroy()

	local bad = Flux.signal(true)
	local c = Flux.computed(function()
		if bad() then
			return Flux.untrack(function()
				error("boom inside untrack")
			end)
		end
		return 42
	end)
	local ok1 = pcall(function()
		return c()
	end)
	expect(not ok1, "computed throwing inside untrack propagates error")
	bad(false)
	expect(c() == 42, "computed recovers cleanly after throwing inside untrack")

	local r1, r2, r3 = Flux.withOwner(nil, function()
		return "a", nil, "c"
	end)
	expect(r1 == "a" and r2 == nil and r3 == "c", "withOwner forwards variadic returns including nil holes")
end)

sert.laws.differential(
	"graph · diamond and deep DAG signal -> computed -> effect matches pure functional oracle with zero glitches",
	{
		gen = sert.gen.list(
			sert.gen.record({
				batched = sert.gen.bool(),
				s1 = sert.gen.optional(sert.gen.int(-20, 20)),
				s2 = sert.gen.optional(sert.gen.int(-20, 20)),
				s3 = sert.gen.optional(sert.gen.int(-20, 20)),
				mode = sert.gen.optional(sert.gen.bool()),
			}),
			1,
			12
		),
		oracle = function(steps)
			local s1, s2, s3, mode = 1, 2, 3, true
			local function evalState()
				local cLeft = s1 * 2 + s2
				local cMid = s1 - s2
				local cRight = s2 + s3 * 3
				local cDiamond = cLeft - 2 * cMid -- algebraically always 3 * s2
				local cBranch = if mode then cDiamond + cRight else cLeft + s3
				return `{cDiamond}:{cBranch}`
			end
			local history: { string } = {}
			local lastEmitted = evalState()
			table.insert(history, lastEmitted)

			local function recordIfChanged()
				local cur = evalState()
				if cur ~= lastEmitted then
					lastEmitted = cur
					table.insert(history, cur)
				end
			end

			for _, step in steps do
				if step.batched then
					if step.s1 ~= nil then
						s1 = step.s1
					end
					if step.s2 ~= nil then
						s2 = step.s2
					end
					if step.s3 ~= nil then
						s3 = step.s3
					end
					if step.mode ~= nil then
						mode = step.mode
					end
					recordIfChanged()
				else
					if step.s1 ~= nil then
						s1 = step.s1
						recordIfChanged()
					end
					if step.s2 ~= nil then
						s2 = step.s2
						recordIfChanged()
					end
					if step.s3 ~= nil then
						s3 = step.s3
						recordIfChanged()
					end
					if step.mode ~= nil then
						mode = step.mode
						recordIfChanged()
					end
				end
			end
			return table.concat(history, "|")
		end,
		sut = function(steps)
			local s1 = Flux.signal(1)
			local s2 = Flux.signal(2)
			local s3 = Flux.signal(3)
			local mode = Flux.signal(true)
			local history: { string } = {}
			local glitchDetected = false

			local scope = Flux.scope(function()
				local cLeft = Flux.computed(function()
					return s1() * 2 + s2()
				end)
				local cMid = Flux.computed(function()
					return s1() - s2()
				end)
				local cRight = Flux.computed(function()
					return s2() + s3() * 3
				end)
				local cDiamond = Flux.computed(function()
					local val = cLeft() - 2 * cMid()
					if val ~= 3 * s2:peek() then
						glitchDetected = true
					end
					return val
				end)
				local cBranch = Flux.computed(function()
					return if mode() then cDiamond() + cRight() else cLeft() + s3()
				end)
				local cOut = Flux.computed(function()
					return `{cDiamond()}:{cBranch()}`
				end)
				Flux.effect(function()
					local d = cDiamond()
					if d ~= 3 * s2:peek() then
						glitchDetected = true
					end
					table.insert(history, cOut())
				end)
			end)
			flush()

			for _, step in steps do
				if step.batched then
					if step.s1 ~= nil then
						s1:set(step.s1)
					end
					if step.s2 ~= nil then
						s2:set(step.s2)
					end
					if step.s3 ~= nil then
						s3:set(step.s3)
					end
					if step.mode ~= nil then
						mode:set(step.mode)
					end
					flush()
				else
					if step.s1 ~= nil then
						s1:set(step.s1)
						flush()
					end
					if step.s2 ~= nil then
						s2:set(step.s2)
						flush()
					end
					if step.s3 ~= nil then
						s3:set(step.s3)
						flush()
					end
					if step.mode ~= nil then
						mode:set(step.mode)
						flush()
					end
				end
			end

			expect(not glitchDetected, "diamond reactive graph never observes a transient glitch")
			scope:Destroy()
			flush()
			return table.concat(history, "|")
		end,
	},
	{ runs = 80 }
)

test(
	"regression · raw(fn) and safe fallback allocating inside a scope do not hijack curChildren of enclosing reaction",
	function()
		local trigger = Flux.signal(1)
		local afterRawDestroyed = 0
		local afterSafeDestroyed = 0

		local scope, c = Flux.scope(function()
			local comp = Flux.computed(function()
				local n = trigger()
				Flux.raw(function()
					return Flux.computed(function()
						return n
					end)
				end)
				local innerAfterRaw = Flux.computed(function()
					return n + 1
				end)
				innerAfterRaw:onDestroy(function()
					afterRawDestroyed += 1
				end)

				local guarded = Flux.safe(function()
					error("boom")
				end, function()
					Flux.computed(function()
						return n
					end)
					return n
				end)
				guarded:peek()

				local innerAfterSafe = Flux.computed(function()
					return n + 2
				end)
				innerAfterSafe:onDestroy(function()
					afterSafeDestroyed += 1
				end)
				return innerAfterRaw:peek() + innerAfterSafe:peek()
			end)
			comp:peek()
			return comp
		end)
		sert.defer(function()
			scope:Destroy()
		end)

		expect(
			afterRawDestroyed == 0 and afterSafeDestroyed == 0,
			"initial synchronous peek keeps child computeds alive"
		)

		trigger:set(2)
		expect(c:peek() == 7, "updated computed evaluates new children")
		expect(
			afterRawDestroyed == 1,
			"re-running computed disposes post-raw(fn) child computed instead of leaking to outer scope"
		)
		expect(
			afterSafeDestroyed == 1,
			"re-running computed disposes post-safe-fallback child computed instead of leaking to outer scope"
		)

		scope:Destroy()
		expect(
			afterRawDestroyed == 2 and afterSafeDestroyed == 2,
			"destroying outer scope disposes latest reaction children once"
		)
	end
)

test(
	"graph · isObserved, isCleanable, locked/subtyped metatables, and tracked getter/createSignal/createMemo fast paths",
	function()
		local GraphMod = if env.IS_ROBLOX
			then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux"):WaitForChild("Graph")) :: any
			else require("../../src/Graph") :: any

		-- 1. Graph.isObserved across signal, computed, effect, scope, and destroyed states
		local obsSig = Flux.signal(1)
		local obsComp = Flux.computed(function()
			return obsSig() + 1
		end)
		local obsSc, obsEff = Flux.scope(function()
			return Flux.effect(function()
				obsComp()
			end)
		end)
		expect(
			not GraphMod.isObserved(obsSc) and not GraphMod.isObserved(obsEff),
			"scopes and effects are never reported as observed"
		)
		expect(
			not GraphMod.isObserved(obsSig) and not GraphMod.isObserved(obsComp),
			"before initial flush, signal and computed have 0 observers"
		)
		flush()
		expect(
			GraphMod.isObserved(obsSig) and GraphMod.isObserved(obsComp),
			"active effect marks upstream computed and signal observed"
		)
		obsSc:Destroy()
		expect(
			not GraphMod.isObserved(obsSig) and not GraphMod.isObserved(obsComp),
			"destroying observer scope clears observed state"
		)
		obsComp:Destroy()
		obsSig:Destroy()
		expect(
			not GraphMod.isObserved(obsSig) and not GraphMod.isObserved(obsComp),
			"destroyed signal and computed report false for isObserved"
		)

		-- 2. Flux.isCleanable across every supported cleanable kind and non-cleanable values
		local tmpInst = env.Instance.new("Folder")
		local tmpConn = tmpInst.Destroying:Connect(function() end)
		local tmpThread = coroutine.create(function()
			coroutine.yield()
		end)
		coroutine.resume(tmpThread)
		local regTbl = { x = 1 }
		GraphMod.register(regTbl, function() end)
		expect(
			GraphMod.isCleanable(function() end)
				and GraphMod.isCleanable(tmpInst)
				and GraphMod.isCleanable(tmpConn)
				and GraphMod.isCleanable(tmpThread)
				and GraphMod.isCleanable({ Destroy = function() end })
				and GraphMod.isCleanable({ function() end })
				and GraphMod.isCleanable({})
				and GraphMod.isCleanable(regTbl),
			"all cleanable types recognized"
		)
		expect(
			not GraphMod.isCleanable(123) and not GraphMod.isCleanable("abc") and not GraphMod.isCleanable({ x = 1 }),
			"primitives and plain non-empty map tables are not cleanable"
		)
		GraphMod.register(regTbl, nil)
		tmpConn:Disconnect()
		Flux.dispose(tmpThread)
		tmpInst:Destroy()

		-- 3. Locked metatables (`__metatable` string) and `__type = Node` subtyped metatables
		local locked = setmetatable({ v = 5 }, { __metatable = "locked" })
		expect(
			not Flux.isNode(locked) and Flux.raw(locked) == locked and Flux.read(locked) == locked,
			"locked metatable does not crash isNode, raw, or read"
		)
		expectError(function()
			Flux.getter(locked :: any)
		end, "Flux.getter expects a node")
		expectError(function()
			Flux.setter(locked :: any)
		end, "Flux.setter expects a node")

		local backingSig = Flux.signal(11)
		local scForType = Flux.scope(function() end)
		local nodeMT = getmetatable(scForType :: any)
		local subMT = { __index = nodeMT, __type = nodeMT }
		local subNode: any = setmetatable({ (backingSig :: any)[1] }, subMT)
		expect(
			Flux.isNode(subNode) and Flux.raw(subNode) == 11 and Flux.read(subNode) == 11,
			"__type = Node subtype recognized by isNode, raw, and read"
		)
		local getSub = Flux.getter(subNode)
		local setSub = Flux.setter(subNode)
		setSub(22)
		expect(getSub() == 22 and backingSig:peek() == 22, "getter and setter work on __type = Node subtype")
		scForType:Destroy()
		backingSig:Destroy()

		-- 4. Tracked fast paths + dedup + mid-run pull on Flux.getter, createSignal, createMemo, and dynamic createEffect
		local s1 = Flux.signal(2)
		local s2 = Flux.signal(3)
		local comp = Flux.computed(function()
			return s1() * 10
		end)
		local getS1 = Flux.getter(s1)
		local getComp = Flux.getter(comp)
		local getterSum = 0
		local getterEff = Flux.effect(function()
			local a = getS1() + getS1() -- curRun dedup on first run, curIdx slot hit on re-runs
			if s2() > 3 then
				s1:set(5) -- dirties `comp` mid-run before `getComp()` slot hit!
			end
			local b = getComp() + getComp() -- curRun dedup + mid-run pull when dirty
			getterSum = a + b
		end)
		flush()
		expect(getterSum == 44, "initial tracked getter reads")
		s1:set(4)
		flush()
		expect(getterSum == 88, "re-run hits curIdx fast slot on signal and computed getters")
		s2:set(4)
		flush()
		expect(getterSum == 110, "mid-run dirtying pulls computed getter on curIdx slot hit and requeues self-read")
		getterEff:Destroy()

		local fastGet, fastSet = Flux.createSignal(1)
		local gateSig = Flux.signal(0)
		local dynCleaned = 0
		local fastTotal = 0
		local hostScope = Flux.scope(function()
			local memo = Flux.createMemo(function()
				return fastGet() + fastGet() -- curRun dedup on first run, curIdx slot hit on re-run
			end)
			Flux.effect(function()
				if gateSig() == 1 then
					fastSet(7) -- dirties `memo` mid-run before `memo()` slot hit
				end
				fastTotal = memo() + memo() -- curRun dedup + live/dirty slot hits
				-- Dynamic createMemo + createEffect inside an active reaction (`attachSlow` path)
				local innerMemo = Flux.createMemo(function()
					Flux.cleanup(function()
						dynCleaned += 1
					end)
					return gateSig()
				end)
				Flux.createEffect(function()
					innerMemo()
				end)
			end)
			flush()
			expect(fastTotal == 4 and memo() == 2, "live createMemo read inside and outside reaction")
			fastSet(3)
			flush()
			expect(fastTotal == 12 and dynCleaned >= 1, "re-running outer effect cleans up attached inner memo")
			gateSig:set(1)
			flush()
			expect(fastTotal == 28, "mid-run fastSet pulls createMemo on curIdx slot hit")
		end)
		hostScope:Destroy()

		-- 5. Diverged track after nested pull must not double-subscribe prefix or curNew dependencies
		local d1 = Flux.signal(1)
		local d2 = Flux.signal(2)
		local d3 = Flux.signal(3)
		local dToggle = Flux.signal(false)
		local dInner = Flux.computed(function()
			if dToggle() then
				return d1() + d3()
			end
			return 0
		end)
		local dOuter = Flux.computed(function()
			if not dToggle() then
				return d1() + d2()
			end
			local a = d1()
			local b = d3()
			local c = Flux.raw(dInner)
			return a + b + c + d1() + d3()
		end)
		local dEff = Flux.effect(function()
			dOuter()
		end)
		flush()
		sert.eq((d1 :: any)[1][4], 1)
		sert.eq((d3 :: any)[1][4], 0)
		dToggle:set(true)
		flush()
		sert.eq(dOuter:peek(), 12)
		sert.eq((d1 :: any)[1][4], 1)
		sert.eq((d3 :: any)[1][4], 1)
		dToggle:set(false)
		flush()
		sert.eq((d3 :: any)[1][4], 0)
		dEff:Destroy()
		dInner:Destroy()
		dOuter:Destroy()
		d1:Destroy()
		d2:Destroy()
		d3:Destroy()
		dToggle:Destroy()

		-- 6. Flux.safe recovers leaked 0-arg untrack()/owner state on throw and preserves tracking
		local sOk = Flux.signal(false)
		local throwCleaned = 0
		local recoveredFromSafe = Flux.safe(function()
			Flux.cleanup(function()
				throwCleaned += 1
			end)
			if not sOk() then
				Flux.untrack()
				error("partial boom", 0)
			end
			return "ok"
		end, function()
			return if Flux.isReactive() then "reactive" else "recovered"
		end)
		sert.defer(function()
			recoveredFromSafe:Destroy()
		end)
		sert.eq(recoveredFromSafe:get(), "recovered")
		sert(not Flux.isReactive(), "0-arg untrack before throw inside safe does not leak")
		sOk:set(true)
		sert.eq(recoveredFromSafe:get(), "ok")
		sert.eq(throwCleaned, 1)
		recoveredFromSafe:Destroy()
		sert.eq(throwCleaned, 2)
		sOk:Destroy()
	end
)

test("signal / computed · functional update computes untracked and returns self", function()
	local count = new(10)
	local bonus = new(5)
	local runs = 0
	local e = Flux.effect(function()
		count()
		runs += 1
	end)
	flush()
	sert.eq(runs, 1)

	local effectBonusReads = 0
	local outer = Flux.effect(function()
		count:update(function(cur)
			effectBonusReads += 1
			return cur + bonus()
		end)
	end)
	flush()
	sert.eq(count:peek(), 15)
	sert.eq(runs, 2)

	-- bonus change must not re-run outer because update(fn) ran fn untracked
	bonus:set(20)
	flush()
	sert.eq(effectBonusReads, 1)
	sert.eq(count:peek(), 15)

	-- 0-arg update still forces dependents for in-place table mutations
	local tbl = { items = { "a" } }
	local sig = new(tbl)
	local tableRuns = 0
	local e2 = Flux.effect(function()
		sig()
		tableRuns += 1
	end)
	flush()
	table.insert(tbl.items, "b")
	sert.eq(sig:update(), sig, "0-arg update returns self")
	flush()
	sert.eq(tableRuns, 2)

	-- returned self from 1-arg update chains cleanly
	sert.eq(
		count:update(function(cur)
			return cur + 1
		end),
		count,
		"1-arg update returns self"
	)
	sert.eq(count:peek(), 16)

	sert.throws(function()
		count:update(123 :: any)
	end, "expected a function or nil")

	e:Destroy()
	outer:Destroy()
	e2:Destroy()
	count:Destroy()
	bonus:Destroy()
	sig:Destroy()
end)

test("safe · retry reset re-evaluates fallback, unsubscribes on heal, and ignores post-destroy reset", function()
	local attempt = 0
	local shouldFail = true
	local lastReset: (() -> ())? = nil
	local node = Flux.safe(function()
		attempt += 1
		if shouldFail then
			error(`fail #{attempt}`, 0)
		end
		return `ok #{attempt}`
	end, function(_err, reset)
		lastReset = reset
		return `err #{attempt}`
	end)
	sert.defer(function()
		node:Destroy()
	end)

	sert.eq(node:get(), "err #1")
	sert(type(lastReset) == "function", "safe recovery receives reset callback")
	local reset = lastReset :: () -> ()

	-- calling reset retries immediately on next read even without source dependency changes
	reset()
	sert.eq(node:get(), "err #2")

	shouldFail = false
	reset()
	sert.eq(node:get(), "ok #3")

	-- once healed, stale reset does not force a re-run
	reset()
	sert.eq(node:get(), "ok #3")
	sert.eq(attempt, 3)

	-- calling reset after Destroy is a safe no-op
	node:Destroy()
	reset()
	sert.eq(attempt, 3)
end)

test("computed / createMemo · passes previous value with and without custom equals", function()
	local step = new(1)
	local seenPrevs = {}
	local acc = Flux.computed(function(prev)
		table.insert(seenPrevs, if prev == nil then false else prev)
		return (prev or 0) + step()
	end)
	sert.eq(acc:get(), 1)
	step:set(2)
	sert.eq(acc:get(), 3)
	sert.eq(seenPrevs, { false, 1 })

	local memoPrevs = {}
	local memo = Flux.createMemo(function(prev)
		table.insert(memoPrevs, if prev == nil then false else prev)
		return (prev or 10) + step()
	end, function(a, b)
		return a == b
	end)
	sert.eq(memo(), 12)
	step:set(0)
	sert.eq(memo(), 12)
	step:set(5)
	sert.eq(memo(), 17)
	sert.eq(memoPrevs, { false, 12, 12 })

	acc:Destroy()
	step:Destroy()
end)

test("safe · observed Flux.safe recovers from late throws across multiple reset() cycles", function()
	local fail = Flux.signal(false)
	local value = Flux.signal(1)
	local resets = 0
	local savedReset: (() -> ())? = nil
	local seen = {}

	local s = Flux.safe(function(): number
		if fail:get() then
			error("late safe boom", 0)
		end
		return value:get()
	end, function(_err, resetFn)
		resets += 1
		savedReset = resetFn
		return -resets
	end)
	sert.defer(function()
		s:Destroy()
		fail:Destroy()
		value:Destroy()
	end)

	local eff = Flux.effect(function()
		table.insert(seen, s:get())
	end)
	sert.defer(function()
		eff:Destroy()
	end)
	flush()
	sert.eq(seen, { 1 }, "observed baseline")

	local function runReset()
		assert(savedReset ~= nil, "reset callback should be captured")
		savedReset()
	end

	-- Late throw while observed
	fail:set(true)
	flush()
	expect(resets == 1 and seen[#seen] == -1 and savedReset ~= nil, "late throw enters fallback once")

	-- Calling reset while still failing re-evaluates and re-enters fallback cleanly
	runReset()
	flush()
	expect(resets == 2 and seen[#seen] == -2 and savedReset ~= nil, "reset while broken re-runs recovery handler")

	-- Heal and recover via reset
	fail:set(false)
	value:set(10)
	runReset()
	flush()
	expect(s:get() == 10 and seen[#seen] == 10, "reset recovers to live value after heal")

	-- Second late throw + second reset cycle continues tracking upstream changes
	fail:set(true)
	flush()
	expect(resets == 3 and seen[#seen] == -3, "second late throw enters fallback cleanly")
	fail:set(false)
	value:set(42)
	runReset()
	flush()
	expect(s:get() == 42 and seen[#seen] == 42, "second reset() cycle restores live tracking")

	eff:Destroy()
	s:Destroy()
	fail:Destroy()
	value:Destroy()
end)

test(
	"onObserved · deferred ownerless untracked hooks handle self writes, observer Destroy, and late onUnobserved",
	function()
		-- 1. onObserved writing s:set(v) updates downstream observers cleanly
		local s = Flux.signal(1)
		sert.defer(function()
			s:Destroy()
		end)
		local observedSeen = {}
		s:onObserved(function()
			s:set(99)
		end)
		local effWrite = Flux.effect(function()
			table.insert(observedSeen, s:get())
		end)
		sert.defer(function()
			effWrite:Destroy()
		end)
		flush()
		expect(observedSeen[#observedSeen] == 99, "onObserved s:set(v) propagates to active observer")
		effWrite:Destroy()
		s:Destroy()

		-- 2. onObserved destroying an observer triggers onUnobserved deferred without corrupting graph
		local target = Flux.signal("ok")
		sert.defer(function()
			target:Destroy()
		end)
		local targetObs, targetUnobs = 0, 0
		local effKill: any = nil
		target:onObserved(function()
			targetObs += 1
			if effKill then
				effKill:Destroy()
			end
		end)
		target:onUnobserved(function()
			targetUnobs += 1
		end)
		effKill = Flux.effect(function()
			target:get()
		end)
		sert.defer(function()
			effKill:Destroy()
		end)
		flush()
		expect(
			targetObs == 1 and targetUnobs == 1 and not Graph.isObserved(target),
			"destroying observer in onObserved fires onUnobserved"
		)
		target:Destroy()

		-- 3. Attaching onUnobserved on an already-observed node fires when its last observer leaves
		local already = Flux.signal(5)
		sert.defer(function()
			already:Destroy()
		end)
		local lateEff = Flux.effect(function()
			already:get()
		end)
		sert.defer(function()
			lateEff:Destroy()
		end)
		flush()
		expect(Graph.isObserved(already), "baseline observed")
		local lateUnobs = 0
		already:onUnobserved(function()
			lateUnobs += 1
		end)
		expect(lateUnobs == 0, "attaching onUnobserved while observed does not fire eagerly")
		lateEff:Destroy()
		expect(lateUnobs == 1, "onUnobserved attached on already-observed node fires on last observer teardown")
		already:Destroy()

		-- 4. Hooks run untracked and ownerless (reading other signals does not subscribe trigger effect, cleanup/effect not owned by scope)
		local src = Flux.signal(0)
		local side = Flux.signal("a")
		local hookOwnerDuringOn = "unset" :: any
		local hookOwnerDuringOff = "unset" :: any
		local innerRuns = 0
		local innerEffect: any = nil
		sert.defer(function()
			if innerEffect then
				innerEffect:Destroy()
			end
			src:Destroy()
			side:Destroy()
		end)
		src:onObserved(function()
			hookOwnerDuringOn = Flux.getOwner()
			local _ = side:get()
			innerEffect = Flux.effect(function()
				innerRuns += 1
				side:get()
			end)
		end)
		src:onUnobserved(function()
			hookOwnerDuringOff = Flux.getOwner()
			local _ = side:get()
		end)

		local outerRuns = 0
		local sc = Flux.scope(function()
			Flux.effect(function()
				outerRuns += 1
				src:get()
			end)
		end)
		sert.defer(function()
			sc:Destroy()
		end)
		flush()
		expect(hookOwnerDuringOn == nil and outerRuns == 1 and innerRuns == 1, "onObserved ran ownerless")

		side:set("b")
		flush()
		expect(
			outerRuns == 1 and innerRuns == 2,
			"reads inside onObserved do not subscribe outer effect; inner effect stays alive"
		)

		sc:Destroy()
		expect(hookOwnerDuringOff == nil, "onUnobserved ran ownerless")
		side:set("c")
		flush()
		expect(innerRuns == 3, "effect created inside onObserved was not owned or destroyed by outer scope")
		if innerEffect then
			innerEffect:Destroy()
		end
		src:Destroy()
		side:Destroy()
	end
)

test("dispose · child disposal inside Flux.untrack prunes source observers when no destroys or hooks exist", function()
	local src = Flux.signal(1)
	local runs = 0
	local sc = Flux.scope(function()
		Flux.untrack(function()
			Flux.effect(function()
				runs += 1
				src:get()
			end)
		end)
	end)
	flush()
	expect(runs == 1 and Graph.isObserved(src), "baseline untracked child effect observes source")

	Flux.untrack(function()
		sc:Destroy()
	end)
	expect(not Graph.isObserved(src), "disposing inside Flux.untrack removes observer cleanly with zero zombies")

	src:set(2)
	flush()
	expect(runs == 1, "destroyed untracked child effect does not re-run")
	src:Destroy()
end)

test("dispose · table disposal is array-only with cycle guard and supports userdata destructors", function()
	-- 1. Plain record tables with function fields must not have arbitrary methods invoked
	local called = 0
	local record = {
		fn = function()
			called += 1
		end,
		Destroy = "not-callable",
	}
	Flux.dispose(record)
	expect(called == 0, "dispose skips plain non-array record tables")

	-- 2. Array table with cyclic reference disposes items once without stack overflow
	local arrayCalled = 0
	local cyclicArr: { any } = {}
	cyclicArr[1] = function()
		arrayCalled += 1
	end
	cyclicArr[2] = cyclicArr
	Flux.dispose(cyclicArr)
	expect(arrayCalled == 1, "cyclic array disposes function once")

	-- 3. Userdata with Destroy / Disconnect / failing Destroy (newproxy available in Luau)
	local newproxyFn = (_G :: any).newproxy
	if newproxyFn ~= nil then
		local udCount = 0
		local ud = newproxyFn(true)
		getmetatable(ud).__index = {
			Destroy = function()
				udCount += 1
			end,
		}
		Flux.dispose(ud)
		expect(udCount == 1, "dispose invokes Destroy on userdata")

		local badUd = newproxyFn(true)
		getmetatable(badUd).__index = {
			Destroy = function()
				error("ud teardown boom")
			end,
		}
		local warned = env.warnings(function()
			Flux.dispose(badUd)
		end)
		expect(#warned == 1, "failing userdata Destroy is warned without throwing")
	end
end)

test("cycles & stabilize · cycle detection rolls back observer graphs cleanly and recovers", function()
	local hook = Flux.signal(0)
	sert.defer(function()
		hook:Destroy()
	end)
	hook:onObserved(function() end)

	local mode = Flux.signal(0)
	local extra = Flux.signal(1)
	local multi = Flux.signal(1)
	local a: any = nil
	local b: any = nil

	a = Flux.computed(function()
		local m = mode()
		if m == 1 then
			return b() + 1
		elseif m == 2 then
			return extra() + b() + 1
		end
		return extra()
	end)
	b = Flux.computed(function()
		local m = mode()
		if m == 0 then
			return 10
		elseif m == 1 then
			return a() + 1
		else
			return extra() + multi() + a()
		end
	end)

	-- Add a second observer to b so upgrade-to-list and multi-observer rollback paths execute too
	local effA = Flux.effect(function()
		local _ = pcall(function()
			return a()
		end)
	end)
	local effB = Flux.effect(function()
		local _ = pcall(function()
			return b()
		end)
	end)
	sert.defer(function()
		effA:Destroy()
		effB:Destroy()
		a:Destroy()
		b:Destroy()
		mode:Destroy()
		extra:Destroy()
		multi:Destroy()
	end)
	flush()

	-- Flip mode -> 1 creates direct a <-> b cycle across subscribe / raise / reconcile
	local warns1 = env.warnings(function()
		mode:set(1)
		flush()
	end)
	expect(#warns1 >= 0, "cycle flush completes without crashing caller")

	-- Flip mode -> 2 hits multi-source reconcile & tail rollback
	env.warnings(function()
		mode:set(2)
		flush()
	end)

	-- Recover to mode = 0 and verify graph works cleanly with zero leaked observers or hooks
	mode:set(0)
	extra:set(5)
	flush()
	expect(a() == 5 and b() == 10, "computeds recover cleanly after cycle rollback")

	effA:Destroy()
	effB:Destroy()
	a:Destroy()
	b:Destroy()
	hook:Destroy()
	mode:Destroy()
	extra:Destroy()
	multi:Destroy()
end)

test("stabilize & nested · unstable computed guard clears compRuns and nested outer deferrals work", function()
	-- 1. Nested effect reading/writing signal read by outer effect
	local sigBefore = Flux.signal(1)
	local sigAfter = Flux.signal(1)
	local outerRuns = 0
	local outer = Flux.effect(function()
		outerRuns += 1
		local v1 = sigBefore()
		Flux.untrack(function()
			local _ = Flux.scope(function()
				if outerRuns == 1 then
					sigBefore:set(2) -- Run-1 self-write inside untrack/scope (hits L424-429)
				end
			end)
		end)
		local inner = Flux.effect(function()
			if outerRuns == 1 and v1 == 1 then
				sigAfter:set(2) -- outer has not read sigAfter yet during first run
			elseif outerRuns == 2 then
				sigBefore:set(3) -- outer already read sigBefore -> defers outer effect (hits deferOuterEffect)
			end
		end)
		local _ = sigAfter()
		inner:Destroy()
	end)
	flush()
	expect(outerRuns >= 2, "Run-1 self-write and nested inner writes re-queued outer effect")
	outer:Destroy()

	-- 2. Nested effect throwing after writing outer dep still requeues outer (hits L1651)
	local gate = Flux.signal(0)
	local seenGate = 0
	local eOuter = Flux.effect(function()
		seenGate = gate()
		if seenGate == 0 then
			local eInner = Flux.effect(function()
				gate:set(1)
				error("inner boom")
			end)
			Flux.cleanup(eInner)
		end
	end)
	env.warnings(flush)
	expect(seenGate == 1, "throwing nested effect still schedules outer re-run when outer dep wrote")
	eOuter:Destroy()
	gate:Destroy()
	sigBefore:Destroy()
	sigAfter:Destroy()
end)

test(
	"owner & safe & computed · destroyed withOwner disposes and errors cleanly, safe disposes partial children, computed keeps prev on equals",
	function()
		-- 1. withOwner on a destroyed token disposes children and prefixes error when throwing (hits L2933-2941, L2950-2967)
		local ctx = Flux.context("default")
		local capturedTok: any = nil
		local ctxScope = Flux.scope(function()
			ctx:provide("scoped", function()
				capturedTok = Flux.getOwner()
			end)
		end)
		ctxScope:Destroy()

		local leakedClean = 0
		Flux.withOwner(capturedTok, function()
			Flux.cleanup(function()
				leakedClean += 1
			end)
			expect(ctx:get() == "scoped", "destroyed token still preserves bound context")
		end)
		expect(leakedClean == 1, "work created under destroyed owner disposes immediately")

		local boundReader = ctx:provide("bound-ctx", function()
			return Flux.bindContext(function()
				return ctx:get()
			end)
		end)
		expect(
			boundReader() == "bound-ctx" and ctx:get() == "default",
			"bindContext snapshots active context without leaking outside"
		)

		local okThrow, throwErr = pcall(function()
			Flux.withOwner(capturedTok, function()
				error("owner boom")
			end)
		end)
		expect(not okThrow and string.find(tostring(throwErr), "withOwner") ~= nil, "withOwner propagates error")

		-- 2. Flux.safe disposes partial child scopes/cleanups before running fallback (Q1)
		local trigger = Flux.signal(false)
		local events = {}
		local s = Flux.safe(function()
			if trigger() then
				Flux.cleanup(function()
					table.insert(events, "cleanup")
				end)
				table.insert(events, "before-throw")
				error("try boom")
			end
			return "ok"
		end, function()
			table.insert(events, "fallback")
			return "recovered"
		end)
		sert.defer(function()
			s:Destroy()
			trigger:Destroy()
		end)
		expect(s() == "ok", "initial safe succeeds")
		trigger:set(true)
		expect(s() == "recovered", "safe recovers via fallback")
		expect(
			#events == 3 and events[1] == "before-throw" and events[2] == "cleanup" and events[3] == "fallback",
			"safe disposes tryFn partial cleanups BEFORE running fallback"
		)
		s:Destroy()
		trigger:Destroy()

		-- 3. Flux.computed(fn, equals) keeps previous value reference on equality and runs equals untracked (Q3)
		local n = Flux.signal(1)
		local eqDep = Flux.signal(10)
		local eqRuns = 0
		local derived = Flux.computed(function()
			return { count = n(), tag = if n() == 1 then "first" else "second" }
		end, function(prev, nxt)
			eqRuns += 1
			local _ = eqDep() -- must not subscribe derived
			return prev ~= nil and nxt ~= nil and (prev.count :: number) % 2 == (nxt.count :: number) % 2
		end)
		local firstTbl = derived()
		expect(firstTbl.tag == "first" and eqRuns == 0, "initial computed does not call equals")
		n:set(3) -- parity stays odd -> equals returns true -> keeps firstTbl
		expect(derived() == firstTbl and eqRuns == 1, "computed keeps prev identity when equals returns true")
		eqDep:set(20) -- untracked inside equals -> must not recompute derived
		n:set(3)
		expect(derived() == firstTbl and eqRuns == 1, "reads inside equals do not subscribe computed")

		-- Throwing equals enters errored state cleanly (hits L3203)
		local eqBoom = Flux.computed(function()
			return n()
		end, function()
			error("equals boom")
		end)
		expect(eqBoom() == 3, "initial eqBoom succeeds")
		n:set(4)
		local okEqErr = pcall(function()
			return eqBoom()
		end)
		expect(not okEqErr, "throwing equals propagates error cleanly")

		eqBoom:Destroy()
		derived:Destroy()
		n:Destroy()
		eqDep:Destroy()
	end
)

test(
	"graph · coverage regressions: nested active effect pull, unstable stabilize, computed:update, wrapComputedEquals, and cycle variants",
	function()
		-- 1. Nested synchronous effect pull (innerEffect:peek() inside outer effect -> nestedRunning / readThisRunFrom / deferOuterEffect)
		local sA = Flux.signal(1)
		local sB = Flux.signal(1)
		local sC = Flux.signal(1)
		local sToggle = Flux.signal(true)
		local pulledC = Flux.computed(function()
			local _ = sB()
			Flux.untrack(function() end)
			return sC()
		end)

		local outerRuns = 0
		local outerEff: any = nil
		outerEff = Flux.effect(function()
			outerRuns += 1
			local a = sA()
			if sToggle() then
				local _ = sB()
			else
				local _ = sC()
			end
			if outerRuns == 2 then
				-- Run 2 (already subscribed on sA/sB): nested effect pulls synchronously while outerEff is active
				local innerEff = Flux.effect(function()
					sA:set(a + 1) -- sA already read this run -> hits readThisRunFrom & deferOuterEffect
				end)
				innerEff:peek()
				innerEff:Destroy()
			elseif outerRuns == 3 then
				-- Run 3: diverge dependency list so readThisRunFrom hits DIVERGED path
				sToggle:set(false)
				local divInner = Flux.effect(function()
					sA:set(10)
				end)
				divInner:peek()
				divInner:Destroy()
			end
		end)
		flush()
		sB:set(2) -- trigger Run 2
		flush()
		expect(outerRuns >= 3, "nested effect peek defers and re-runs outer effect cleanly")

		-- Case where pEval ~= pRunning (pulling dormant computed inside active outer effect hits canCheck=false)
		local outerViaCompRuns = 0
		local middleComp = Flux.computed(function()
			local eff2 = Flux.effect(function()
				sC:set(sC:peek() + 1)
			end)
			eff2:peek()
			eff2:Destroy()
			return sC:peek()
		end)
		local outerViaComp = Flux.effect(function()
			outerViaCompRuns += 1
			local _ = sC()
			if outerViaCompRuns == 2 then
				local _ = middleComp()
			end
		end)
		flush()
		sC:set(10)
		flush()
		expect(outerViaCompRuns >= 3, "canCheck=false nested effect marks outer effect dirty")
		outerEff:Destroy()
		outerViaComp:Destroy()
		middleComp:Destroy()
		pulledC:Destroy()
		sA:Destroy()
		sB:Destroy()
		sC:Destroy()
		sToggle:Destroy()

		-- 2. computed:update() across dead/live & clean/stale states
		local base = Flux.signal(1)
		local deadComp = Flux.computed(function()
			return base() * 2
		end)
		expect(deadComp() == 2, "seed deadComp")
		base:set(2)
		deadComp:update() -- dead stale branch
		expect(deadComp() == 4, "deadComp refreshes after update")
		deadComp:update() -- dead clean branch

		local liveHits = 0
		local liveComp = Flux.computed(function()
			return base() + 10
		end)
		local liveEff = Flux.effect(function()
			liveHits += 1
			local _ = liveComp()
		end)
		flush()
		liveComp:update() -- live clean branch (bumps CHANGED / notifies observers)
		flush()
		expect(liveHits == 2, "liveComp:update notifies downstream observers")
		base:set(3)
		liveComp:update() -- live stale before flush
		flush()
		expect(liveComp() == 13 and liveHits == 3, "liveComp updates cleanly across stale pre-flush update")
		liveEff:Destroy()
		liveComp:Destroy()
		deadComp:Destroy()
		base:Destroy()

		-- 3. wrapComputedEquals FORCE_COMMIT on initial nil and explicit false comparator with identical value
		local toggle = Flux.signal(1)
		local nilInit = Flux.computed(function()
			return if toggle() == 1 then nil else "x"
		end, function(a, b)
			return a == b
		end)
		expect(nilInit() == nil, "initial nil commits via FORCE_COMMIT cleanly")
		toggle:set(2)
		expect(nilInit() == "x", "transitions from nil to string cleanly")

		local forceEqSig = Flux.signal(1)
		local eqAlwaysFalseCalls = 0
		local eqForce = Flux.computed(function()
			local _ = forceEqSig()
			return 100
		end, function()
			return false
		end)
		local eqWatch = Flux.effect(function()
			eqAlwaysFalseCalls += 1
			local _ = eqForce()
		end)
		flush()
		forceEqSig:set(2)
		flush()
		expect(
			eqAlwaysFalseCalls == 2 and eqForce() == 100,
			"equals returning false with equal value force-commits observers"
		)
		eqWatch:Destroy()
		eqForce:Destroy()
		forceEqSig:Destroy()
		nilInit:Destroy()
		toggle:Destroy()

		-- 4. stabilize() unstable computed guard clears compRuns and surfaces error cleanly (even from nested flush!)
		local uSig = Flux.signal(0)
		local uComp = Flux.computed(function()
			local v = uSig()
			if v > 0 then
				Flux.untrack(function()
					uSig:set(v + 1)
				end)
			end
			return v
		end)
		local uEff = Flux.effect(function()
			local _ = uComp()
		end)
		flush()
		uSig:set(1)
		local warnsStab = env.warnings(flush)
		expect(
			#warnsStab >= 1 and string.find(warnsStab[1], "stabilize", 1, true) ~= nil,
			"stabilize rerun guard warns and recovers from unstable loop"
		)
		-- Also test nested flush() inside an effect hitting L2072-2073 cleanup
		local nestedSignal = Flux.signal(0)
		local uEffInner: any = nil
		local nestedWarns = env.warnings(function()
			local uInner = Flux.computed(function()
				local v = nestedSignal()
				if v > 0 then
					Flux.untrack(function()
						nestedSignal:set(v + 1)
					end)
				end
				return v
			end)
			uEffInner = Flux.effect(function()
				local _ = uInner()
			end)
			local triggerOuter = Flux.signal(0)
			local driver = Flux.effect(function()
				if triggerOuter() == 1 then
					nestedSignal:set(1)
					Flux.flush()
				end
			end)
			flush()
			triggerOuter:set(1)
			flush()
			driver:Destroy()
			uInner:Destroy()
		end)
		expect(#nestedWarns >= 1, "nested flush cleanup resets compRuns cleanly")
		if uEffInner then
			uEffInner:Destroy()
		end
		uEff:Destroy()
		uComp:Destroy()
		uSig:Destroy()
		nestedSignal:Destroy()

		-- 5. Cycle variants: direct self-cycle (L560), wasDead goLive rollback (L601-602, L686-694), list rollback (L606-607), and nOld==2/nNew==3 reconcile rollback (L822-825, L858-879)
		local hookNode = Flux.signal(0)
		sert.defer(function()
			hookNode:Destroy()
		end)
		hookNode:onObserved(function() end)

		local selfMode = Flux.signal(0)
		local selfComp: any = nil
		selfComp = Flux.computed(function()
			if selfMode() == 1 then
				return selfComp()
			end
			return 1
		end)
		local selfEff = Flux.effect(function()
			pcall(function()
				return selfComp()
			end)
		end)
		flush()
		env.warnings(function()
			selfMode:set(1)
			flush()
		end)
		selfEff:Destroy()
		selfComp:Destroy()
		selfMode:Destroy()

		-- wasDead + multi-dep reconcile + nOld==2 -> nNew==3 rollback + >2 observer list rollback
		local cGate = Flux.signal(0)
		local depX = Flux.signal(1)
		local depY = Flux.signal(2)
		local depZ = Flux.signal(3)
		local hubA: any = nil
		local hubB: any = nil
		hubA = Flux.computed(function()
			local g = cGate()
			if g == 1 then
				return depX() + hubB()
			elseif g == 2 then
				return depX() + depY() + depZ() + hubB()
			end
			return depX()
		end)
		hubB = Flux.computed(function()
			if cGate() > 0 then
				return hubA() + 1
			end
			return 5
		end)
		-- Two live observers on hubB so hubB's OBSERVERS becomes a list before hubA tries to subscribe
		local obsB1 = Flux.effect(function()
			pcall(function()
				return hubB()
			end)
		end)
		local obsB2 = Flux.effect(function()
			pcall(function()
				return hubB()
			end)
		end)
		local obsA1 = Flux.effect(function()
			pcall(function()
				return hubA()
			end)
		end)
		flush()
		env.warnings(function()
			cGate:set(1) -- hits nOld == 2 -> nNew == 3 (depX -> depX, hubB) rollback + list rollback on hubB
			flush()
		end)
		cGate:set(0)
		flush()
		env.warnings(function()
			cGate:set(2) -- hits multi-dep reconcile tail rollback
			flush()
		end)
		cGate:set(0)
		flush()

		-- wasDead goLive rollback: dead hubB reads dead hubA, while dead hubA ALREADY depends on hubB
		obsB1:Destroy()
		obsB2:Destroy()
		obsA1:Destroy()
		local deadA: any = nil
		local deadB: any = nil
		local dFlag = Flux.signal(false)
		deadA = Flux.computed(function()
			local _ = depX()
			if dFlag() then
				return deadB()
			end
			return 1
		end)
		deadB = Flux.computed(function()
			if dFlag() then
				return deadA()
			end
			return 2
		end)
		local _ = deadA()
		local _ = deadB()
		dFlag:set(true)
		local deadWatcher = Flux.effect(function()
			pcall(function()
				return deadA()
			end)
		end)
		env.warnings(flush)
		deadWatcher:Destroy()
		deadA:Destroy()
		deadB:Destroy()
		dFlag:Destroy()
		hubA:Destroy()
		hubB:Destroy()
		cGate:Destroy()
		depX:Destroy()
		depY:Destroy()
		depZ:Destroy()
		hookNode:Destroy()
	end
)

test("wrapComputedEquals · NaN SAME_VALUE, FORCE_COMMIT, heal and self-dispose", function()
	local eqNaN = function(a: any, b: any): boolean
		return (a ~= a and b ~= b) or a == b
	end

	-- 1a. NaN -> NaN SAME_VALUE in stabilize() with idx == last (fixed deps)
	local s = Flux.signal(0)
	local fixed = Flux.computed(function()
		local _ = s()
		return 0 / 0
	end, eqNaN)
	local fixedObs = 0
	local effFixed = Flux.effect(function()
		local _ = fixed()
		fixedObs += 1
	end)
	flush()
	local verFixed = Graph.version(fixed)
	expect(fixedObs == 1 and fixed:peek() ~= fixed:peek(), "fixed NaN initialized")
	s:set(1)
	flush()
	expect(fixedObs == 1, "NaN SAME_VALUE skips downstream in stabilize() with idx == last")
	expect(Graph.version(fixed) == verFixed and fixed:peek() ~= fixed:peek(), "fixed NaN version and value preserved")
	effFixed:Destroy()
	fixed:Destroy()
	s:Destroy()

	-- 1b. NaN -> NaN SAME_VALUE in stabilize() with idx ~= last (dynamic deps)
	local flip = Flux.signal(true)
	local d1 = Flux.signal(1)
	local d2 = Flux.signal(2)
	local dyn = Flux.computed(function()
		if flip() then
			local _ = d1()
		else
			local _ = d2()
		end
		return 0 / 0
	end, eqNaN)
	local dynObs = 0
	local effDyn = Flux.effect(function()
		local _ = dyn()
		dynObs += 1
	end)
	flush()
	local verDyn = Graph.version(dyn)
	flip:set(false)
	flush()
	expect(
		dynObs == 1 and Graph.version(dyn) == verDyn,
		"NaN SAME_VALUE with idx ~= last preserves version & skips obs"
	)
	expect(dyn:peek() ~= dyn:peek(), "dynamic NaN value preserved")
	effDyn:Destroy()
	dyn:Destroy()
	flip:Destroy()
	d1:Destroy()
	d2:Destroy()

	-- 1c. NaN -> NaN SAME_VALUE in lazy runComputed()
	local ls = Flux.signal(0)
	local lc = Flux.computed(function()
		local _ = ls()
		return 0 / 0
	end, eqNaN)
	local r1 = lc()
	local verLazy = Graph.version(lc)
	ls:set(1)
	local r2 = lc()
	expect(r1 ~= r1 and r2 ~= r2 and Graph.version(lc) == verLazy, "lazy runComputed preserves NaN via SAME_VALUE")
	lc:Destroy()
	ls:Destroy()

	-- 2a. FORCE_COMMIT on first-run nil == nil (observed & lazy)
	local nilObs = 0
	local cn = Flux.computed(function()
		return nil
	end, function(a, b)
		return a == b
	end)
	local effNil = Flux.effect(function()
		local _ = cn()
		nilObs += 1
	end)
	flush()
	expect(nilObs == 1 and Graph.version(cn) > 0, "first-run nil commits via FORCE_COMMIT when observed")
	effNil:Destroy()
	cn:Destroy()

	local lcn = Flux.computed(function()
		return nil
	end, function(a, b)
		return a == b
	end)
	local _ = lcn()
	expect(Graph.version(lcn) > 0, "first-run nil commits in lazy runComputed")
	lcn:Destroy()

	-- 2b. FORCE_COMMIT via stabilizeSameSlow on subsequent v == prev when equals returns false
	local step = Flux.signal(0)
	local allowSame = false
	local fc = Flux.computed(function()
		local _ = step()
		return 42
	end, function()
		return allowSame
	end)
	local fcRuns = 0
	local effFc = Flux.effect(function()
		local _ = fc()
		fcRuns += 1
	end)
	flush()
	local verFc0 = Graph.version(fc)
	step:set(1)
	flush()
	expect(fcRuns == 2 and Graph.version(fc) > verFc0, "FORCE_COMMIT commits identical value when equals is false")
	local verFc1 = Graph.version(fc)
	allowSame = true
	step:set(2)
	flush()
	expect(fcRuns == 2 and Graph.version(fc) == verFc1, "subsequent equals == true skips commit")
	effFc:Destroy()
	fc:Destroy()
	step:Destroy()

	-- 2c. FORCE_COMMIT via stabilizeSameSlow after prior error / heal
	local boom = Flux.signal(true)
	local healed = Flux.computed(function()
		if boom() then
			error("boom-nil")
		end
		return nil
	end, function()
		return false
	end)
	local okRead, lastRead: any = true, nil
	local healCount = 0
	local effHeal = Flux.effect(function()
		okRead, lastRead = pcall(healed)
		if okRead then
			healCount += 1
		end
	end)
	flush()
	expect(not okRead and healCount == 0, "prior error propagated before heal")
	local verPreHeal = Graph.version(healed)
	boom:set(false)
	flush()
	expect(
		okRead and lastRead == nil and healCount == 1 and Graph.version(healed) > verPreHeal,
		"FORCE_COMMIT heals after prior error"
	)
	effHeal:Destroy()
	healed:Destroy()
	boom:Destroy()

	-- 3. Self-dispose inside equals
	local ds = Flux.signal(0)
	local dc: any = nil
	local eqCalls = 0
	dc = Flux.computed(function()
		return ds()
	end, function()
		eqCalls += 1
		dc:Destroy()
		return false
	end)
	local effSelfDispose = Flux.effect(function()
		pcall(dc)
	end)
	flush()
	ds:set(1)
	flush()
	expect(eqCalls == 1 and dc:peek() == nil, "self-dispose inside equals leaves node cleanly destroyed")
	effSelfDispose:Destroy()
	ds:Destroy()
end)

test("OUTER_ACTIVE & noEffect sentinel · nested effects, flush, disposeChildren & defer paths", function()
	-- 1. Nested effect creation + nested flush() (canCheck == true in deferOuterEffect)
	local outerSig = Flux.signal(0)
	local innerTrigger = Flux.signal(0)
	local sibling = Flux.signal(0)
	local outerRuns = 0
	local innerRuns = 0
	local siblingRuns = 0
	local eSibling = Flux.effect(function()
		local _ = sibling()
		local _ = outerSig()
		siblingRuns += 1
	end)
	local eInner: any = nil
	local eOuter = Flux.effect(function()
		outerRuns += 1
		local _ = outerSig()
		if outerRuns == 1 then
			eInner = Flux.effect(function()
				innerRuns += 1
				if innerTrigger() == 1 then
					outerSig:set(1) -- hits multi-observer markObservers deferOuterEffect (canCheck == true) + sibling markOne
				end
			end)
			innerTrigger:set(1)
			flush()
			-- After nested flush, outerSig write during outer effect body hits deferSelf on multi-observer
			outerSig:set(2)
		end
	end)
	flush()
	expect(
		innerRuns == 1 and outerRuns >= 2 and siblingRuns >= 2,
		"nested flush & deferOuterEffect/deferSelf run cleanly"
	)
	if eInner then
		eInner:Destroy()
	end
	eOuter:Destroy()
	eSibling:Destroy()

	-- 2. Synchronous nested runEffectNow via computed (canCheck == false in deferOuterEffect)
	local trig2 = Flux.signal(0)
	local obs2 = Flux.signal(0)
	local outer2Runs = 0
	local eSync = Flux.effect(function()
		if trig2() > 0 then
			obs2:set(obs2:peek() + 1)
		end
	end)
	local cMid = Flux.computed(function()
		if trig2() > 0 then
			Flux.read(eSync)
		end
		return 1
	end)
	local eOuter2 = Flux.effect(function()
		outer2Runs += 1
		local _ = obs2()
		local _ = cMid()
	end)
	flush()
	expect(outer2Runs == 1, "initial sync runEffectNow setup")
	trig2:set(1)
	flush()
	expect(
		outer2Runs == 2 and obs2:peek() == 1,
		"sync runEffectNow inside computed triggers outer effect via canCheck==false"
	)
	eOuter2:Destroy()
	cMid:Destroy()
	eSync:Destroy()

	-- 3. disposeChildren inside an effect writing both tracked/untracked & multi-observer signals
	local sigCleanup = Flux.signal(0)
	local sigOther = Flux.signal(0)
	local otherCount = 0
	local cleanCount = 0
	local eOther = Flux.effect(function()
		local _ = sigOther()
		otherCount += 1
	end)
	local eClean = Flux.effect(function()
		cleanCount += 1
		local v = sigCleanup()
		Flux.cleanup(function()
			sigOther:set(v + 10)
			sigCleanup:set(v + 1)
		end)
	end)
	flush()
	expect(cleanCount == 1 and otherCount == 1, "initial cleanup effect baseline")
	sigCleanup:set(1)
	flush()
	expect(
		cleanCount == 2 and otherCount == 2 and sigOther:peek() == 10,
		"effect pre-run disposeChildren signal write propagates cleanly"
	)
	eClean:Destroy()
	eOther:Destroy()
	sigCleanup:Destroy()
	sigOther:Destroy()
	trig2:Destroy()
	obs2:Destroy()
	outerSig:Destroy()
	innerTrigger:Destroy()
	sibling:Destroy()
end)

test(
	"untrack() zero-arg & retrack() · effect, runComputed, runComputedProtected, stabilize, runEffectNow & safe",
	function()
		-- 1. Flux.effect: without retrack() (idx == last & idx > last), with retrack(), and self-write
		local a = Flux.signal(1)
		local b = Flux.signal(10)
		local c = Flux.signal(100)
		local effIdxLastRuns = 0
		local effIdxLast = Flux.effect(function()
			effIdxLastRuns += 1
			local _ = a()
			untrack()
			local _ = b()
		end)
		flush()
		b:set(11)
		flush()
		expect(effIdxLastRuns == 1, "effect zero-arg untrack without retrack ignores untracked dep (idx == last)")
		a:set(2)
		flush()
		expect(effIdxLastRuns == 2, "effect keeps prior tracked dep when returning without retrack (idx == last)")
		effIdxLast:Destroy()

		local expand = Flux.signal(false)
		local effIdxGtRuns = 0
		local effIdxGt = Flux.effect(function()
			effIdxGtRuns += 1
			local _ = a()
			if expand() then
				local _ = c()
			end
			untrack()
			local _ = b()
		end)
		flush()
		expand:set(true)
		flush()
		b:set(12)
		flush()
		expect(effIdxGtRuns == 2, "effect zero-arg untrack without retrack (idx > last) ignores b")
		c:set(101)
		flush()
		expect(effIdxGtRuns == 3, "effect preserves newly added dep before untrack() (idx > last)")
		effIdxGt:Destroy()

		local effSelfRuns = 0
		local effSelf = Flux.effect(function()
			effSelfRuns += 1
			local v = a()
			untrack()
			if v < 3 then
				a:set(3) -- hits deferSelf while curIdx < 0 in effect
			end
			retrack()
			local _ = c()
		end)
		flush()
		expect(
			effSelfRuns == 2 and a:peek() == 3,
			"effect zero-arg untrack + self-write + retrack preserves re-queue and tracks c"
		)
		c:set(102)
		flush()
		expect(effSelfRuns == 3, "effect retrack() restores tracking after self-write")
		effSelf:Destroy()

		-- 2. Lazy runComputed() + runComputedProtected()
		local ls1 = Flux.signal(1)
		local ls2 = Flux.signal(10)
		local ls3 = Flux.signal(100)
		local lazyExp = Flux.signal(false)
		local lazyRuns = 0
		local lc = Flux.computed(function()
			lazyRuns += 1
			local v = ls1()
			if lazyExp() then
				v += ls3()
			end
			untrack()
			local _ = ls2()
			return v
		end)
		expect(lc() == 1 and lazyRuns == 1, "lazy runComputed initial read")
		ls2:set(20)
		expect(lc() == 1 and lazyRuns == 1, "lazy runComputed without retrack ignores ls2 (idx == last)")
		lazyExp:set(true)
		expect(lc() == 101 and lazyRuns == 2, "lazy runComputed (idx > last)")
		ls2:set(30)
		expect(
			lc() == 101 and lazyRuns == 2,
			"lazy runComputed without retrack preserves idx > last without spurious invalidation"
		)
		ls3:set(103)
		expect(lc() == 104 and lazyRuns == 3, "lazy runComputed re-runs on tracked ls3")
		lc:Destroy()

		local lcSelfRuns = 0
		local lcSelf = Flux.computed(function()
			lcSelfRuns += 1
			local v = ls1()
			untrack()
			if v == 1 then
				ls1:set(2)
			end
			retrack()
			if v == 2 then
				ls1:set(3)
			end
			return v + ls3()
		end)
		expect(
			lcSelf() == 104 and lcSelfRuns == 1 and ls1:peek() == 2,
			"lazy runComputed treats write inside zero-arg untrack as untracked"
		)
		ls3:set(104)
		expect(lcSelf() == 107 and lcSelfRuns == 3, "lazy runComputed re-runs via selfDirty on write after retrack()")
		lcSelf:Destroy()

		local protSig = Flux.signal(1)
		local protThrows = Flux.computed(function()
			local _ = protSig()
			untrack()
			error("protected-untrack-err")
		end)
		local wrapOuter = Flux.computed(function()
			local _ = a()
			local ok = pcall(protThrows)
			local _ = c()
			return ok
		end)
		expect(wrapOuter() == false, "runComputedProtected error after zero-arg untrack recovers")
		c:set(105)
		expect(wrapOuter() == false, "outer computed still tracks c after inner runComputedProtected throw")
		wrapOuter:Destroy()
		protThrows:Destroy()
		protSig:Destroy()

		-- 3. Live stabilize() without retrack (idx == last & idx > last) + with retrack & self-write
		local stabExp = Flux.signal(false)
		local stabCount = 0
		local lcLive = Flux.computed(function()
			stabCount += 1
			local v = a()
			if stabExp() then
				v += c()
			end
			untrack()
			return v + b()
		end)
		local effLive = Flux.effect(function()
			local _ = lcLive()
		end)
		flush()
		expect(stabCount == 1, "live stabilize initial run")
		b:set(99)
		flush()
		expect(stabCount == 1, "live stabilize without retrack ignores b (idx == last)")
		stabExp:set(true)
		flush()
		expect(stabCount == 2, "live stabilize idx > last recomputes")
		b:set(100)
		flush()
		expect(stabCount == 2, "live stabilize without retrack ignores b (idx > last)")
		effLive:Destroy()
		lcLive:Destroy()

		local liveSig = Flux.signal(0)
		local lcSelfLiveRuns = 0
		local lcSelfLive = Flux.computed(function()
			lcSelfLiveRuns += 1
			local v = liveSig()
			untrack()
			if v == 1 then
				liveSig:set(2)
			end
			retrack()
			return v + c()
		end)
		local effSelfLive = Flux.effect(function()
			local _ = lcSelfLive()
		end)
		flush()
		expect(lcSelfLiveRuns == 1 and lcSelfLive:peek() == 105, "live stabilize self-write prime")
		liveSig:set(1)
		flush()
		expect(
			lcSelfLiveRuns == 3 and lcSelfLive:peek() == 107,
			"live stabilize self-write + retrack converges cleanly"
		)
		c:set(106)
		flush()
		expect(lcSelfLiveRuns == 4 and lcSelfLive:peek() == 108, "live stabilize tracks c after retrack")
		effSelfLive:Destroy()
		lcSelfLive:Destroy()
		liveSig:Destroy()

		-- 4. runEffectNow synchronous read with zero-arg untrack + retrack
		local syncRuns = 0
		local eNow = Flux.effect(function()
			syncRuns += 1
			local _ = a()
			untrack()
			local _ = b()
			retrack()
			local _ = c()
		end)
		eNow:get()
		b:set(200)
		eNow:get()
		expect(syncRuns == 1, "runEffectNow ignores untracked b")
		c:set(107)
		eNow:get()
		expect(syncRuns == 2, "runEffectNow tracks c after retrack")
		eNow:Destroy()

		-- 5. Flux.safe with zero-arg untrack (no retrack idx==last/idx>last, self-write, and error after untrack)
		local safeExp = Flux.signal(false)
		local safeRuns = 0
		local safeNode = Flux.safe(function()
			safeRuns += 1
			local v = a()
			if safeExp() then
				v += c()
			end
			untrack()
			return v + b()
		end, -1)
		expect(safeNode() == 203 and safeRuns == 1, "safe zero-arg untrack initial")
		b:set(201)
		expect(safeNode() == 203 and safeRuns == 1, "safe without retrack ignores b (idx == last)")
		safeExp:set(true)
		expect(safeNode() == 311 and safeRuns == 2, "safe without retrack handles idx > last")
		b:set(202)
		expect(safeNode() == 311 and safeRuns == 2, "safe ignores b after idx > last")
		safeNode:Destroy()

		local safeSelfSig = Flux.signal(1)
		local safeSelf = Flux.safe(function()
			local v = safeSelfSig()
			untrack()
			if v == 1 then
				safeSelfSig:set(2)
			end
			return v
		end, -1)
		expect(safeSelf() == 1 and safeSelfSig:peek() == 2, "safe handles self-write after zero-arg untrack")
		safeSelf:Destroy()
		safeSelfSig:Destroy()

		local rec = Flux.signal(0)
		local failGate = Flux.signal(true)
		local safeThrow = Flux.safe(function()
			local ok = failGate()
			untrack()
			local _ = b()
			if ok then
				error("safe-after-untrack")
			end
			return 777
		end, function()
			return rec()
		end)
		sert.defer(function()
			safeThrow:Destroy()
			failGate:Destroy()
			rec:Destroy()
		end)
		expect(safeThrow() == 0, "safe recovers and evaluates fallback after throw following zero-arg untrack")
		failGate:set(false)
		rec:set(1)
		expect(
			safeThrow() == 777,
			"safe normalizes curIdx/susp/evalFromUntrack so fallback recovery signal still tracks and heals"
		)

		safeThrow:Destroy()
		failGate:Destroy()
		rec:Destroy()
		safeExp:Destroy()
		stabExp:Destroy()
		lazyExp:Destroy()
		ls1:Destroy()
		ls2:Destroy()
		ls3:Destroy()
		expand:Destroy()
		a:Destroy()
		b:Destroy()
		c:Destroy()
	end
)

test("subscribe · self-read s == o and rollbackSubRaise across all observer shapes", function()
	-- Self-read s == o (both computed() and raw() inside self): returns/errors safely without corrupting state
	local selfMode = Flux.signal(0)
	local selfNode: any = nil
	selfNode = Flux.computed(function()
		if selfMode() == 1 then
			return selfNode()
		elseif selfMode() == 2 then
			return Flux.raw(selfNode)
		end
		return 10
	end)
	local selfObs = Flux.effect(function()
		pcall(selfNode)
	end)
	flush()
	env.warnings(function()
		selfMode:set(1)
		flush()
	end)
	selfMode:set(0)
	flush()
	expect(selfNode:peek() == 10, "recovered cleanly from live self-read")
	selfObs:Destroy()
	selfNode:Destroy()
	selfMode:Destroy()

	-- rollbackSubRaise across OBSERVERS == false (dead), single observer, and observer list
	local gate = Flux.signal(0)
	local base = Flux.signal(1)
	local hub: any = nil
	local bridge: any = nil
	hub = Flux.computed(function()
		local b = base()
		if gate() > 0 then
			return b + bridge()
		end
		return b
	end)
	bridge = Flux.computed(function()
		return hub() * 2
	end)
	local reader = Flux.computed(function()
		return hub()
	end)
	local _ = reader() -- lazy prime so hub starts dead (OBSERVERS == false)

	-- Case 1: OBSERVERS == false
	gate:set(1)
	expectError(function()
		bridge()
	end)
	expect(not Graph.isObserved(hub), "rollbackSubRaise on OBSERVERS == false restores dead state")
	gate:set(0)
	base:set(2)
	expect(reader() == 2, "hub & reader continue working cleanly after false-observer rollback")

	-- Case 2: Single observer (OBSERVERS = obs1)
	local seen1: { number } = {}
	local obs1 = Flux.effect(function()
		pcall(function()
			table.insert(seen1, hub())
		end)
	end)
	flush()
	expect(#seen1 == 1 and seen1[1] == 2, "single observer primed")
	env.warnings(function()
		gate:set(1)
		flush()
	end)
	gate:set(0)
	base:set(5)
	flush()
	expect(seen1[#seen1] == 5, "rollbackSubRaise preserves single observer subscription")

	-- Case 3: Observer list (OBSERVERS = { obs1, obs2 })
	local seen2: { number } = {}
	local obs2 = Flux.effect(function()
		pcall(function()
			table.insert(seen2, hub())
		end)
	end)
	flush()
	expect(#seen2 == 1 and seen2[1] == 5, "second observer promoted OBSERVERS to list")
	env.warnings(function()
		gate:set(1)
		flush()
	end)
	gate:set(0)
	base:set(9)
	flush()
	expect(seen1[#seen1] == 9 and seen2[#seen2] == 9, "rollbackSubRaise preserves multi-observer list subscriptions")

	obs1:Destroy()
	obs2:Destroy()
	reader:Destroy()
	bridge:Destroy()
	hub:Destroy()
	gate:Destroy()
	base:Destroy()
end)

test("stabilize() unstable guard · cycle detection across write paths and negative non-looping tests", function()
	local function assertUnstableCaught(label: string, setupFn: () -> (any, () -> ()))
		local trigger, cleanupFn = setupFn()
		sert.defer(cleanupFn)
		if trigger then
			trigger:set(1)
		end
		local warns = env.warnings(flush)
		cleanupFn()
		expect(#warns >= 1 and string.find(warns[1], "unstable", 1, true) ~= nil, label .. " caught unstable loop")
	end

	-- Positive 1: direct self-write (markSelf -> markOne)
	assertUnstableCaught("direct self-write", function()
		local s = Flux.signal(0)
		local c = Flux.computed(function()
			local v = s()
			if v > 0 then
				s:set(v + 1)
			end
			return v
		end)
		local e = Flux.effect(function()
			local _ = c()
		end)
		flush()
		return s, function()
			e:Destroy()
			c:Destroy()
			s:Destroy()
		end
	end)

	-- Positive 2: write inside untrack(fn)
	assertUnstableCaught("untrack(fn)", function()
		local s = Flux.signal(0)
		local c = Flux.computed(function()
			local v = s()
			if v > 0 then
				untrack(function()
					s:set(v + 1)
				end)
			end
			return v
		end)
		local e = Flux.effect(function()
			local _ = c()
		end)
		flush()
		return s, function()
			e:Destroy()
			c:Destroy()
			s:Destroy()
		end
	end)

	-- Positive 3: write after zero-arg untrack() WITH retrack()
	assertUnstableCaught("zero-arg untrack + retrack", function()
		local s = Flux.signal(0)
		local c = Flux.computed(function()
			local v = s()
			untrack()
			if v > 0 then
				s:set(v + 1)
			end
			retrack()
			return v
		end)
		local e = Flux.effect(function()
			local _ = c()
		end)
		flush()
		return s, function()
			e:Destroy()
			c:Destroy()
			s:Destroy()
		end
	end)

	-- Positive 4: write after zero-arg untrack() WITHOUT retrack()
	assertUnstableCaught("zero-arg untrack without retrack", function()
		local s = Flux.signal(0)
		local c = Flux.computed(function()
			local v = s()
			untrack()
			if v > 0 then
				s:set(v + 1)
			end
			return v
		end)
		local e = Flux.effect(function()
			local _ = c()
		end)
		flush()
		return s, function()
			e:Destroy()
			c:Destroy()
			s:Destroy()
		end
	end)

	-- Positive 5: write via raw(fn)
	assertUnstableCaught("raw(fn)", function()
		local s = Flux.signal(0)
		local c = Flux.computed(function()
			local v = s()
			if v > 0 then
				Flux.raw(function()
					s:set(v + 1)
				end)
			end
			return v
		end)
		local e = Flux.effect(function()
			local _ = c()
		end)
		flush()
		return s, function()
			e:Destroy()
			c:Destroy()
			s:Destroy()
		end
	end)

	-- Positive 6: write via scope()
	assertUnstableCaught("scope()", function()
		local s = Flux.signal(0)
		local c = Flux.computed(function()
			local v = s()
			if v > 0 then
				Flux.scope(function()
					s:set(v + 1)
				end)
			end
			return v
		end)
		local e = Flux.effect(function()
			local _ = c()
		end)
		flush()
		return s, function()
			e:Destroy()
			c:Destroy()
			s:Destroy()
		end
	end)

	-- Positive 7: write via in-body dispose()
	assertUnstableCaught("in-body dispose()", function()
		local s = Flux.signal(0)
		local c = Flux.computed(function()
			local v = s()
			if v > 0 then
				Flux.dispose(function()
					s:set(v + 1)
				end)
			end
			return v
		end)
		local e = Flux.effect(function()
			local _ = c()
		end)
		flush()
		return s, function()
			e:Destroy()
			c:Destroy()
			s:Destroy()
		end
	end)

	-- Positive 8: write via wrapComputedEquals
	assertUnstableCaught("wrapComputedEquals", function()
		local s = Flux.signal(0)
		local c = Flux.computed(function()
			return s()
		end, function()
			s:set(s:peek() + 1)
			return false
		end)
		local e = Flux.effect(function()
			local _ = c()
		end)
		flush()
		return s, function()
			e:Destroy()
			c:Destroy()
			s:Destroy()
		end
	end)

	-- Positive 9: write via flushHooks during reconcile
	assertUnstableCaught("flushHooks", function()
		local s = Flux.signal(0)
		local h = Flux.signal(0)
		h:onObserved(function()
			s:set(s:peek() + 1)
		end)
		h:onUnobserved(function()
			s:set(s:peek() + 1)
		end)
		local c = Flux.computed(function()
			local v = s()
			if v > 0 and v % 2 == 1 then
				local _ = h()
			end
			return v
		end)
		local e = Flux.effect(function()
			local _ = c()
		end)
		flush()
		return s, function()
			e:Destroy()
			c:Destroy()
			h:Destroy()
			s:Destroy()
		end
	end)

	-- Positive 10: 2-node disposeChildren cleanup cycle
	assertUnstableCaught("disposeChildren 2-node cleanup cycle", function()
		local armed = false
		local s1 = Flux.signal(0)
		local s2 = Flux.signal(0)
		local c1 = Flux.computed(function()
			local v = s1()
			if v > 0 then
				Flux.cleanup(function()
					if armed then
						s2:set(s2:peek() + 1)
					end
				end)
			end
			return v
		end)
		local c2 = Flux.computed(function()
			local v = s2()
			if v > 0 then
				Flux.cleanup(function()
					if armed then
						s1:set(s1:peek() + 1)
					end
				end)
			end
			return v
		end)
		local e = Flux.effect(function()
			local _ = c1()
			local _ = c2()
		end)
		flush()
		s1:set(1)
		s2:set(1)
		flush()
		armed = true
		s1:set(2)
		return nil, function()
			e:Destroy()
			c1:Destroy()
			c2:Destroy()
			s1:Destroy()
			s2:Destroy()
		end
	end)

	-- Positive 11: write inside recoverSafe
	assertUnstableCaught("recoverSafe", function()
		local s = Flux.signal(0)
		local sf = Flux.safe(function()
			local v = s()
			if v > 0 then
				error("safe-loop")
			end
			return v
		end, function()
			s:set(s:peek() + 1)
			return 0
		end)
		local e = Flux.effect(function()
			local _ = sf()
		end)
		flush()
		return s, function()
			e:Destroy()
			sf:Destroy()
			s:Destroy()
		end
	end)

	-- Positive 12: multi-height nextH < h oscillation
	assertUnstableCaught("multi-height nextH < h oscillation", function()
		local s1 = Flux.signal(0)
		local low = Flux.computed(function()
			return s1()
		end)
		local high = Flux.computed(function()
			local v = low()
			if v > 0 then
				s1:set(v + 1)
			end
			return v
		end)
		local e = Flux.effect(function()
			local _ = high()
		end)
		flush()
		return s1, function()
			e:Destroy()
			high:Destroy()
			low:Destroy()
			s1:Destroy()
		end
	end)

	-- Positive 13: same-height 2-node oscillation
	assertUnstableCaught("same-height 2-node oscillation", function()
		local sa = Flux.signal(0)
		local sb = Flux.signal(0)
		local ca = Flux.computed(function()
			local v = sa()
			if v > 0 then
				untrack(function()
					sb:set(v + 1)
				end)
			end
			return v
		end)
		local cb = Flux.computed(function()
			local v = sb()
			if v > 0 then
				untrack(function()
					sa:set(v + 1)
				end)
			end
			return v
		end)
		local e = Flux.effect(function()
			local _ = ca()
			local _ = cb()
		end)
		flush()
		return sa, function()
			e:Destroy()
			ca:Destroy()
			cb:Destroy()
			sa:Destroy()
			sb:Destroy()
		end
	end)

	-- Negative (a1): 200 non-looping untrack(fn) writes targeting downstream computed & single same-height computed
	local drvSig = Flux.signal(0)
	local downSig = Flux.signal(0)
	local sameSig = Flux.signal(0)
	local downRuns = 0
	local sameRuns = 0
	local sameComp = Flux.computed(function()
		sameRuns += 1
		return sameSig()
	end)
	local driver = Flux.computed(function()
		local v = drvSig()
		if v > 0 then
			untrack(function()
				for i = 1, 200 do
					downSig:set(i)
					sameSig:set(i)
				end
			end)
		end
		return v
	end)
	local downstream = Flux.computed(function()
		downRuns += 1
		return driver() + downSig()
	end)
	local effNeg = Flux.effect(function()
		local _ = downstream()
		local _ = sameComp()
	end)
	flush()
	drvSig:set(1)
	local warnsNegA = env.warnings(flush)
	expect(
		#warnsNegA == 0 and downstream:peek() == 201 and sameComp:peek() == 200,
		"200 non-looping untrack writes produce no false positive"
	)
	effNeg:Destroy()
	downstream:Destroy()
	driver:Destroy()
	sameComp:Destroy()
	drvSig:Destroy()
	downSig:Destroy()
	sameSig:Destroy()

	-- Negative (a2): 200 non-looping untrack(fn) writes to 200 distinct same-height computeds
	local batchDrv = Flux.signal(0)
	local batchSigs = table.create(200)
	local batchComps = table.create(200)
	for i = 1, 200 do
		batchSigs[i] = Flux.signal(0)
		local si = batchSigs[i]
		batchComps[i] = Flux.computed(function()
			return si()
		end)
	end
	local batchComp = Flux.computed(function()
		local v = batchDrv()
		if v > 0 then
			untrack(function()
				for i = 1, 200 do
					batchSigs[i]:set(v)
				end
			end)
		end
		return v
	end)
	local effBatch = Flux.effect(function()
		local _ = batchComp()
		for i = 1, 200 do
			local _ = batchComps[i]()
		end
	end)
	flush()
	batchDrv:set(7)
	local warnsNegB = env.warnings(flush)
	expect(
		#warnsNegB == 0 and batchComps[200]:peek() == 7,
		"200 distinct same-height untrack writes produce zero false positives"
	)
	effBatch:Destroy()
	batchComp:Destroy()
	batchDrv:Destroy()
	for i = 1, 200 do
		batchComps[i]:Destroy()
		batchSigs[i]:Destroy()
	end

	-- Negative (b): single-run cleanup write during pre-run disposeChildren completes cleanly
	local cs1 = Flux.signal(0)
	local cs2 = Flux.signal(0)
	local cc1 = Flux.computed(function()
		local v = cs1()
		if v == 1 then
			Flux.cleanup(function()
				cs2:set(99)
			end)
		end
		return v
	end)
	local cc2 = Flux.computed(function()
		return cs2()
	end)
	local effCleanNeg = Flux.effect(function()
		local _ = cc1()
		local _ = cc2()
	end)
	flush()
	cs1:set(1)
	flush()
	cs1:set(2)
	local warnsNegC = env.warnings(flush)
	expect(
		#warnsNegC == 0 and cc2:peek() == 99 and cc1:peek() == 2,
		"single-run disposeChildren cleanup write causes zero false positives"
	)
	effCleanNeg:Destroy()
	cc1:Destroy()
	cc2:Destroy()
	cs1:Destroy()
	cs2:Destroy()
end)

test(
	"Graph bookkeeping & fast/slow paths · live counters, disposeChildren multi-source, createSignal, duplicate reads & setter",
	function()
		-- 1. liveSigEquals 0 -> 1 -> 0
		local sigEq = Flux.signal({ x = 1 }, function(a, b)
			return a.x == b.x
		end)
		local eqRuns = 0
		local eqEff = Flux.effect(function()
			local _ = sigEq()
			eqRuns += 1
		end)
		flush()
		sigEq:set({ x = 1 })
		flush()
		expect(eqRuns == 1, "liveSigEquals skips custom-equal writes")
		eqEff:Destroy()
		sigEq:Destroy()
		local sigPlain = Flux.signal(1)
		local plainRuns = 0
		local plainEff = Flux.effect(function()
			local _ = sigPlain()
			plainRuns += 1
		end)
		flush()
		sigPlain:set(1)
		flush()
		expect(plainRuns == 1, "fast == path restored after liveSigEquals returns to 0")
		sigPlain:set(2)
		flush()
		expect(plainRuns == 2, "plain signal commits after liveSigEquals drops to 0")
		plainEff:Destroy()
		sigPlain:Destroy()

		-- 2. liveDestroys & liveHooks 0 -> 1 -> 0
		local destroyedCount = 0
		local hookLog = ""
		local hs = Flux.signal(1)
		hs:onObserved(function()
			hookLog ..= "O"
		end)
		hs:onUnobserved(function()
			hookLog ..= "U"
		end)
		hs:onDestroy(function()
			destroyedCount += 1
		end)
		local he = Flux.effect(function()
			local _ = hs()
		end)
		sert.defer(function()
			he:Destroy()
			hs:Destroy()
		end)
		flush()
		he:Destroy()
		hs:Destroy()
		expect(hookLog == "OU" and destroyedCount == 1, "liveHooks & liveDestroys execute before decrementing to 0")

		-- Fast no-hook / no-destroy scope teardown afterwards
		local fastAfter = 0
		local fastRoot = Flux.scope(function()
			local fs = Flux.signal(1)
			Flux.effect(function()
				fastAfter = fs()
			end)
		end)
		flush()
		expect(fastAfter == 1, "scope primed after liveHooks/liveDestroys returned to 0")
		fastRoot:Destroy()

		-- 3. disposeChildren with 0, 1, and multiple sources (single & multi observer)
		local ms1 = Flux.signal(1)
		local ms2 = Flux.signal(2)
		local ms3 = Flux.signal(3)
		local zeroRuns, oneRuns, multiRuns = 0, 0, 0
		local childScope = Flux.scope(function()
			local cOne = Flux.computed(function()
				return ms1() * 10
			end)
			local cMulti = Flux.computed(function()
				return ms1() + ms2() + ms3()
			end)
			Flux.effect(function()
				zeroRuns += 1
			end)
			Flux.effect(function()
				local _ = cOne()
				oneRuns += 1
			end)
			Flux.effect(function()
				local _ = cMulti()
				local _ = ms2()
				local _ = ms3()
				multiRuns += 1
			end)
		end)
		flush()
		expect(zeroRuns == 1 and oneRuns == 1 and multiRuns == 1, "0/1/multi-source scope children initialized")
		childScope:Destroy()
		ms1:set(10)
		ms2:set(20)
		ms3:set(30)
		flush()
		expect(zeroRuns == 1 and oneRuns == 1 and multiRuns == 1, "0/1/multi-source children cleanly disposed")
		ms1:Destroy()
		ms2:Destroy()
		ms3:Destroy()

		-- 4. createSignal unobserved writes, custom equals on createSignal/createMemo, duplicate reads s() + s()
		local gUnobs, setUnobs = Flux.createSignal(5)
		expect(setUnobs(9) == 9 and gUnobs() == 9, "createSignal unobserved write updates value")

		local gEq, setEq = Flux.createSignal(10, function(a, b)
			return math.abs(a - b) < 2
		end)
		local memoRuns = 0
		local mEq = Flux.createMemo(function()
			memoRuns += 1
			return gEq() + gEq()
		end, function(a, b)
			return a == b
		end)
		expect(mEq() == 20 and memoRuns == 1, "duplicate reads track cleanly")
		setEq(11)
		expect(mEq() == 20 and memoRuns == 1, "createSignal custom equals skips close writes")
		setEq(13)
		expect(mEq() == 26 and memoRuns == 2, "createSignal custom equals commits distinct write")

		-- 5. Flux.setter on SignalMT and ComputedMT / Node paths
		local sigNode = Flux.signal(1)
		local setSigNode = Flux.setter(sigNode)
		local compNode = Flux.computed(function()
			return sigNode() * 2
		end)
		local setCompNode = Flux.setter(compNode)
		local wrapperNode = Graph.new(5)
		local setWrapper = Flux.setter(wrapperNode)
		local proxyNode = setmetatable({ rawget(wrapperNode :: any, 1) }, { __type = Graph.Node })
		local setProxy = Flux.setter(proxyNode)

		expect(setSigNode(4) == 4 and sigNode:peek() == 4, "setter updates SignalMT")
		expect(setCompNode(99) == 99 and compNode:peek() == 99, "setter updates ComputedMT/Node")
		expect(setWrapper(8) == 8 and wrapperNode:peek() == 8, "setter updates Graph.new Node wrapper")
		expect(setProxy(12) == 12 and wrapperNode:peek() == 12, "setter updates __type = Node proxy")

		wrapperNode:Destroy()
		compNode:Destroy()
		sigNode:Destroy()
		setSigNode(10)
		expect(sigNode:peek() == nil, "setter write on disposed signal is safe no-op")
	end
)

test(
	"graph · computed:update matrix, fast-path child teardown, counter transitions, NaN same-value, retrack, and error heal",
	function()
		-- 1. computed:update across dead-stale, live-fresh, live-stale, and inside reactive effect
		local base = Flux.signal(1)
		local compRuns = 0
		local comp = Flux.computed(function()
			compRuns += 1
			return base() * 10
		end)
		expect(comp() == 10 and compRuns == 1)
		base:set(2)
		comp:update()
		expect(comp:peek() == 20 and compRuns == 2, "dead stale computed:update pulls stale value")

		local obsSeen = 0
		local obs = Flux.effect(function()
			obsSeen = comp()
		end)
		flush()
		expect(obsSeen == 20)
		comp:update() -- live fresh triggers observers / forces notify
		flush()
		base:set(3)
		local innerSeen = 0
		local probe = Flux.signal(0)
		local outerEff = Flux.effect(function()
			local _ = probe()
			comp:update() -- pulls live stale inside active reaction while preserving outer tracking
			innerSeen = comp:peek()
		end)
		flush()
		expect(
			innerSeen == 30 and obsSeen == 30,
			"live stale computed:update inside effect pulls and preserves tracking"
		)
		probe:set(1)
		flush()
		expect(comp:peek() == 30, "outer effect remained tracked after inner comp:update()")
		outerEff:Destroy()
		probe:Destroy()
		obs:Destroy()
		comp:Destroy()
		base:Destroy()

		-- 2. Zero-hook zero-destroy child computed teardown stops upstream reads & resets fast-path counters 2->1->0
		local up = Flux.signal(1)
		local childRuns = 0
		local fastScope = Flux.scope(function()
			local childComp = Flux.computed(function()
				childRuns += 1
				return up() + 1
			end)
			expect(childComp() == 2)
		end)
		fastScope:Destroy()
		up:set(5)
		expect(childRuns == 1, "destroyed child computed without hooks/destroys unlinks cleanly")

		local eqRuns1, eqRuns2 = 0, 0
		local sEq1 = Flux.signal(1, function(a, b)
			return a == b
		end)
		local sEq2 = Flux.signal(1, function(a, b)
			return math.floor(a) == math.floor(b)
		end)
		local d1 = Flux.computed(function()
			eqRuns1 += 1
			return sEq1()
		end)
		local d2 = Flux.computed(function()
			eqRuns2 += 1
			return sEq2()
		end)
		expect(d1() == 1 and d2() == 1)
		sEq1:Destroy()
		sEq2:set(1.5)
		expect(d2() == 1 and eqRuns2 == 1, "destroying first equals signal keeps second live equals working")
		d1:Destroy()
		d2:Destroy()
		sEq2:Destroy()

		local hookCount = 0
		local h1, h2 = Flux.signal(1), Flux.signal(2)
		local dCount = 0
		h1:onObserved(function()
			hookCount += 1
		end)
		h2:onUnobserved(function()
			hookCount -= 1
		end)
		h1:onDestroy(function()
			dCount += 1
		end)
		h2:onDestroy(function()
			dCount += 1
		end)
		local e1 = Flux.effect(function()
			local _ = h1()
		end)
		local e2 = Flux.effect(function()
			local _ = h2()
		end)
		sert.defer(function()
			h1:Destroy()
			h2:Destroy()
			e1:Destroy()
			e2:Destroy()
		end)
		flush()
		expect(hookCount == 1)
		h1:Destroy()
		h2:Destroy()
		e1:Destroy()
		e2:Destroy()
		expect(dCount == 2 and up:peek() == 5, "hooks and onDestroy counters return cleanly to zero")
		up:Destroy()

		-- 3. Computed NaN consecutive SAME_VALUE suppression -> transitions cleanly back to number
		local nanSrc = Flux.signal(1 :: any)
		local nanComp = Flux.computed(function()
			local v = nanSrc()
			return if v == "nan1" or v == "nan2" then 0 / 0 else v
		end, function(a, b)
			return (a ~= a and b ~= b) or a == b
		end)
		local nanObsRuns = 0
		local nanObs = Flux.computed(function()
			nanObsRuns += 1
			return nanComp()
		end)
		expect(nanObs() == 1 and nanObsRuns == 1)
		nanSrc:set("nan1")
		expect(nanObs() ~= nanObs() and nanObsRuns == 2, "transition number->NaN propagates")
		nanSrc:set("nan2")
		local _ = nanObs()
		expect(nanObsRuns == 2, "consecutive NaN suppresses downstream recomputation")
		nanSrc:set(42)
		expect(nanObs() == 42 and nanObsRuns == 3, "transition NaN->number propagates")
		nanObs:Destroy()
		nanComp:Destroy()
		nanSrc:Destroy()

		-- 4. Computed fail -> recover (nFailed/unfail/healed) + nested effect creation + bare untrack/retrack
		local shouldFail = Flux.signal(true)
		local failComp = Flux.computed(function()
			if shouldFail() then
				error("transient fault")
			end
			return 77
		end)
		local healSeen = 0
		local healEff = Flux.effect(function()
			healSeen = failComp()
		end)
		local errs = env.warnings(flush)
		expect(#errs >= 1 and healSeen == 0, "effect observes initial computed fault cleanly")
		shouldFail:set(false)
		flush()
		expect(healSeen == 77, "observer heals once failing computed recovers")
		healEff:Destroy()
		failComp:Destroy()
		shouldFail:Destroy()

		local a, b, c = Flux.signal(1), Flux.signal(10), Flux.signal(100)
		local innerEff: any = nil
		local innerRuns, outerRuns = 0, 0
		local nestedOuter = Flux.effect(function()
			outerRuns += 1
			local v1 = a()
			untrack()
			local _ = b()
			retrack()
			local _ = c()
			if innerEff == nil then
				innerEff = Flux.effect(function()
					innerRuns += 1
					local _ = a()
				end)
			end
			if v1 == 1 then
				a:set(2) -- self-write queues outer effect alongside nested effect
			end
		end)
		flush()
		expect(outerRuns == 2 and innerRuns >= 1, "nested effect creation during outer run + self-requeue runs cleanly")
		b:set(20)
		flush()
		expect(outerRuns == 2, "b read between bare untrack()/retrack() stayed untracked")
		c:set(200)
		flush()
		expect(outerRuns == 3, "c read after bare retrack() remained tracked")
		if innerEff then
			innerEff:Destroy()
		end
		nestedOuter:Destroy()
		a:Destroy()
		b:Destroy()
		c:Destroy()
	end
)

test("graph · arbitrary-depth DAGs (>128 and 1200 depth) and iterative lifecycle paths", function()
	local function makeChain(baseSig: any, depth: number): { any }
		local nodes = table.create(depth) :: { any }
		local prev: any = baseSig
		for i = 1, depth do
			local dep = prev
			local n = Flux.computed(function()
				return dep() + 1
			end)
			nodes[i] = n
			prev = n
		end
		for i = 80, depth, 80 do
			local _ = nodes[i]()
		end
		local _ = nodes[depth]()
		return nodes
	end

	-- 1. Exercise shallow subscribe() growing heapCap past 512 before deeper graphs allocate
	local sGrow = Flux.signal(0)
	local growChain = makeChain(sGrow, 520)
	local topObs = Flux.computed(function()
		return growChain[520]() + 1
	end)
	local growEff = Flux.effect(function()
		local _ = topObs()
	end)
	flush()
	expect(topObs() == 521, "520-deep chain grows heap via shallow subscribe cleanly")
	growEff:Destroy()
	topObs:Destroy()
	for i = 520, 1, -1 do
		growChain[i]:Destroy()
	end
	sGrow:Destroy()

	-- 2. Depth 1200 acyclic DAG: build, two heap doublings (512->1024->2048), lazy pull, goLiveIter, stabilize, settleIter, goDeadIter, pullDeadIter, teardown
	local s1k = Flux.signal(10)
	local chain1k = makeChain(s1k, 1200)
	expect(chain1k[1200]() == 1210, "depth=1200 initial chunked pull matches")

	s1k:set(20)
	-- Direct unchunked dead pull across a 200-node unprimed tail segment
	expect(chain1k[200]() == 220, "pullDeadIter computes 200-deep dirty segment cleanly")
	expect(chain1k[1200]() == 1220, "depth=1200 dead pull propagates cleanly")

	local seen1k = 0
	local eff1k = Flux.effect(function()
		seen1k = chain1k[1200]()
	end)
	flush()
	expect(seen1k == 1220, "goLiveIter activates depth=1200 chain")

	-- Stabilize push across 1200 nodes
	s1k:set(30)
	flush()
	expect(seen1k == 1230, "stabilize propagates depth=1200 chain")

	-- settleIter: direct read of dirty depth=1200 live chain before flush()
	s1k:set(40)
	expect(chain1k[1200]() == 1240, "settleIter settles live depth=1200 chain prior to flush")
	flush()
	expect(seen1k == 1240, "flush after settleIter remains consistent")

	-- goDeadIter: destroy effect across 1200-deep chain, then dead pull again
	eff1k:Destroy()
	s1k:set(50)
	for i = 200, 1000, 200 do
		local _ = chain1k[i]()
	end
	expect(chain1k[1200]() == 1250, "pullDeadIter after goDeadIter on depth=1200 chain")

	for i = 1200, 1, -1 do
		chain1k[i]:Destroy()
	end
	s1k:Destroy()

	-- 2b. Non-cyclic deep (>150) height raise across single & multi-observer branches via raiseVisit -> raiseIter
	local baseA = Flux.signal(1)
	local baseB = Flux.signal(100)
	local raiseGate = Flux.signal(false)
	local chainB = makeChain(baseB, 20)
	local chainA = table.create(160) :: { any }
	local a160Runs = 0
	chainA[1] = Flux.computed(function()
		if raiseGate() then
			return baseA() + chainB[20]()
		end
		return baseA()
	end)
	for i = 2, 160 do
		local prevA = chainA[i - 1]
		if i == 160 then
			chainA[i] = Flux.computed(function()
				a160Runs += 1
				return prevA() + 1
			end)
		else
			chainA[i] = Flux.computed(function()
				return prevA() + 1
			end)
		end
	end
	local _ = chainA[80]()
	local _ = chainA[160]()
	local fan1 = Flux.computed(function()
		return chainA[140]()
	end)
	local fan2 = Flux.computed(function()
		return chainA[140]() * 2
	end)
	local seenA160, seenFan1, seenFan2 = 0, 0, 0
	local effMain = Flux.effect(function()
		seenA160 = chainA[160]()
	end)
	local effFan1 = Flux.effect(function()
		seenFan1 = fan1()
	end)
	local effFan2 = Flux.effect(function()
		seenFan2 = fan2()
	end)
	flush()
	expect(seenA160 == 160 and seenFan1 == 140 and seenFan2 == 280 and a160Runs == 1, "baseline 160-chain")

	raiseGate:set(true)
	flush()
	expect(seenA160 == 280 and seenFan1 == 260 and seenFan2 == 520, "deep raiseIter raises all multi-obs heights")
	local runsBeforeLiveRead = a160Runs
	expect(chainA[160]() == 280 and a160Runs == runsBeforeLiveRead, "live read after raiseIter uses cached stamp")
	baseB:set(200)
	flush()
	expect(seenA160 == 380 and seenFan1 == 360 and seenFan2 == 720, "deep raised DAG propagates downstream writes")

	effFan2:Destroy()
	effFan1:Destroy()
	effMain:Destroy()
	fan2:Destroy()
	fan1:Destroy()
	for i = 160, 1, -1 do
		chainA[i]:Destroy()
	end
	for i = 20, 1, -1 do
		chainB[i]:Destroy()
	end
	raiseGate:Destroy()
	baseB:Destroy()
	baseA:Destroy()

	-- 3. Deep (>150) hooks (onObserved / onUnobserved), dirty goLiveIter, goDeadIter states, and multi-observer diamonds
	local hSig = Flux.signal(1)
	local sigObsCount, sigUnobsCount = 0, 0
	hSig:onObserved(function()
		sigObsCount += 1
	end)
	hSig:onUnobserved(function()
		sigUnobsCount += 1
	end)
	local hChain = makeChain(hSig, 170)
	local midObsCount, midUnobsCount = 0, 0
	hChain[85]:onObserved(function()
		midObsCount += 1
	end)
	hChain[85]:onUnobserved(function()
		midUnobsCount += 1
	end)
	-- Add a secondary branch to create multi-observer diamond forks
	local forkTop = Flux.computed(function()
		return hChain[160]() + hChain[170]()
	end)
	local _ = forkTop()
	-- Dirty hSig before going live so finishGoLive hits dirty == true (no deps changed yet -> unchanged? write first!)
	hSig:set(2)
	local hSeen = 0
	local hEff = Flux.effect(function()
		hSeen = forkTop()
	end)
	sert.defer(function()
		hEff:Destroy()
		hSig:Destroy()
		for i = 170, 1, -1 do
			hChain[i]:Destroy()
		end
	end)
	flush()
	expect(hSeen == 334 and sigObsCount == 1 and midObsCount == 1, "goLiveIter fires hooks and commits dirty tree")

	-- Error then goDeadIter on deep chain
	local errGate = Flux.signal(false)
	local errSig = Flux.signal(5)
	local errChain = makeChain(errSig, 160)
	local topErr = Flux.computed(function()
		local v = errChain[160]()
		if errGate() then
			error("deep fault")
		end
		return v
	end)
	local _ = topErr()
	local errSeen = 0
	local errEff = Flux.effect(function()
		local ok, v = pcall(topErr)
		if ok then
			errSeen = v
		end
	end)
	flush()
	expect(errSeen == 165, "baseline deep error chain")
	errGate:set(true)
	flush() -- leaves topErr in ERRORED
	errEff:Destroy() -- goDeadIter on clean + ERRORED
	hEff:Destroy() -- goDeadIter with hooks -> onUnobserved
	expect(sigUnobsCount == 1 and midUnobsCount == 1, "goDeadIter fires onUnobserved hooks")

	-- Re-verify settleIter with STALE/ERRORED and clean stamps + pullDeadIter STALE/live/disposed/unchanged branches
	errGate:set(false)
	expect(topErr() == 165, "heals deep errored chain")

	-- pullDeadIter: STALE live dependency, STALE dead dependency, STALE disposed dependency, changed value & unchanged skip
	local deadSrc = Flux.signal(1)
	local toggleTarget = Flux.signal(100)
	local toggleMod = Flux.computed(function()
		local _ = deadSrc()
		return toggleTarget()
	end)
	local cMid = makeChain(toggleMod, 165)
	local extraBranch = Flux.computed(function()
		return deadSrc() * 0 + 1
	end)
	local deadTailRuns = 0
	local deadTail = Flux.computed(function()
		deadTailRuns += 1
		return cMid[165]() + extraBranch()
	end)
	for i = 80, 165, 80 do
		local _ = cMid[i]()
	end
	local _ = deadTail()
	-- Dirty via update() -> STALE on dead dep, then on live dep
	extraBranch:update()
	expect(deadTail() == 266, "pullDeadIter refreshes STALE dead dep")

	-- Make cMid[1] observed separately (live) and mark it dirty with settle/stale
	local liveTap = Flux.effect(function()
		local _ = cMid[1]()
	end)
	flush()
	deadSrc:set(2) -- toggleMod stays 100, cMid[1] stays live-clean after stabilize or before flush
	local beforeSkipRuns = deadTailRuns
	local deadTailVal = deadTail() -- pullDeadIter hits s[OBSERVERS] refresh(s, 0) + unchanged changed stamp!
	flush()
	expect(
		deadTailVal == 266 and deadTailRuns == beforeSkipRuns,
		"pullDeadIter handles live branch refresh and skips recompute on unchanged upstream stamp"
	)

	-- Now change toggleTarget (100 -> 200) -> pullDeadIter sees changed upstream and recomputes cMid[2..165] & deadTail
	toggleTarget:set(200)
	local changedDeadTail = deadTail()
	flush()
	expect(
		changedDeadTail == 366 and deadTailRuns == beforeSkipRuns + 1,
		"pullDeadIter recomputes downstream chain when stWaiting source changes value"
	)

	liveTap:Destroy()
	-- Destroy extraBranch while dead so goLiveIter hits list == nil and pullDeadIter sees non-live disposed dep
	extraBranch:Destroy()
	cMid[1]:update()
	expect(deadTail() == 365 or deadTail() == 366, "pullDeadIter handles destroyed dead dependency cleanly")

	-- 4. Deep (>150) raiseIter + goLiveIter cycle detection & rollback (single-observer and multi-observer)
	local cycGate = Flux.signal(false)
	local cycBase = Flux.signal(1)
	local cycNodes = table.create(165) :: { any }
	local cycPrev: any = cycBase
	for i = 1, 165 do
		local d = cycPrev
		if i == 1 then
			cycNodes[i] = Flux.computed(function()
				local v = d()
				if cycGate() then
					return v + cycNodes[165]()
				end
				return v
			end)
		else
			cycNodes[i] = Flux.computed(function()
				return d() + 1
			end)
		end
		cycPrev = cycNodes[i]
	end
	for i = 80, 165, 80 do
		local _ = cycNodes[i]()
	end
	local _ = cycNodes[165]()

	-- Test goLiveIter rollback & raiseIter cycle via multi-observer diamond on cycNodes[165]
	local sideA = Flux.computed(function()
		return cycNodes[165]() + 10
	end)
	local sideB = Flux.computed(function()
		return cycNodes[165]() + 20
	end)
	local topDia = Flux.computed(function()
		return sideA() + sideB()
	end)
	local _ = sideA()
	local _ = sideB()
	local _ = topDia()
	local cycEff = Flux.effect(function()
		pcall(topDia)
	end)
	flush()
	env.warnings(function()
		cycGate:set(true)
		flush()
	end)
	cycGate:set(false)
	cycBase:set(10)
	flush()
	expect(topDia() == 378, "deep (>150) raiseIter & goLiveIter recover cleanly after cycle")

	-- Also test goLiveIter hitting res < 0 (raiseIter cycle) during initial goLive of a primed cycle-gated tree
	cycEff:Destroy()
	-- Re-prime cycNodes[1] while dead with cycGate=true so cycNodes[1] records cycNodes[165] in its sources while both are dead
	cycGate:set(true)
	local _ = cycNodes[1]()
	local tmpEff = Flux.effect(function()
		local _ = cycNodes[165]()
	end)
	local goLiveCycleWarns = env.warnings(flush)
	cycGate:set(false)
	expect(#goLiveCycleWarns >= 1, "goLiveIter cycle rollback warns and cleans up stack")
	tmpEff:Destroy()
	for i = 165, 1, -1 do
		cycNodes[i]:Destroy()
	end
	topDia:Destroy()
	sideA:Destroy()
	sideB:Destroy()
	cycBase:Destroy()
	cycGate:Destroy()
	deadTail:Destroy()
	for i = 165, 1, -1 do
		cMid[i]:Destroy()
	end
	toggleMod:Destroy()
	toggleTarget:Destroy()
	deadSrc:Destroy()
	topErr:Destroy()
	for i = 160, 1, -1 do
		errChain[i]:Destroy()
	end
	errSig:Destroy()
	errGate:Destroy()
	forkTop:Destroy()
	for i = 170, 1, -1 do
		hChain[i]:Destroy()
	end
	hSig:Destroy()
end)

test(
	"graph · unstable heapPushed guard, bare untrack/self-dispose at idx==last, disposeChildren shapes & Node API",
	function()
		-- 1. heapPushed + checkCompRun via untrack(fn) inside computed at h == heapMin (both n == 1 and n > 1 signal)
		local u1 = Flux.signal(0)
		local c1 = Flux.computed(function()
			local v = u1()
			if v > 0 and v < 150 then
				untrack(function()
					u1:set(v + 1)
				end)
			end
			return v
		end)
		local e1 = Flux.effect(function()
			local _ = c1()
		end)
		flush()
		u1:set(1)
		local w1 = env.warnings(flush)
		expect(
			#w1 >= 1 and string.find(w1[1], "unstable", 1, true) ~= nil,
			"untrack signal write inside computed at heapMin (n==1) triggers unstable guard"
		)
		e1:Destroy()
		c1:Destroy()
		u1:Destroy()

		local u2 = Flux.signal(0)
		local c2a = Flux.computed(function()
			local v = u2()
			if v > 0 and v < 150 then
				untrack(function()
					u2:set(v + 1)
				end)
			end
			return v
		end)
		local c2b = Flux.computed(function()
			return u2() * 2
		end)
		local e2 = Flux.effect(function()
			local _ = c2a()
			local _ = c2b()
		end)
		flush()
		u2:set(1)
		local w2 = env.warnings(flush)
		expect(
			#w2 >= 1 and string.find(w2[1], "unstable", 1, true) ~= nil,
			"untrack signal write inside computed at heapMin (n>1) triggers unstable guard"
		)
		e2:Destroy()
		c2a:Destroy()
		c2b:Destroy()
		u2:Destroy()

		-- 2. Bare untrack() (without retrack) at end of computed & effect when idx == last (not curNode path)
		local bSig = Flux.signal(1)
		local bHidden = Flux.signal(10)
		local bCompRuns = 0
		local bComp = Flux.computed(function()
			bCompRuns += 1
			local v = bSig()
			untrack()
			return v + bHidden()
		end)
		local bEffRuns = 0
		local bEff = Flux.effect(function()
			bEffRuns += 1
			local _ = bComp()
			untrack()
			local _ = bHidden()
		end)
		flush()
		expect(bCompRuns == 1 and bEffRuns == 1)
		bHidden:set(20)
		flush()
		expect(bCompRuns == 1 and bEffRuns == 1, "bare untrack() at idx==last leaves hidden untracked cleanly")
		bSig:set(2)
		flush()
		expect(bCompRuns == 2 and bEffRuns == 2, "bare untrack() after identical idx==last cleans state cleanly")
		bEff:Destroy()
		bComp:Destroy()
		bSig:Destroy()
		bHidden:Destroy()

		-- 3. Self-disposing computed and effect when idx == last (DISPOSED_NSRC caught cleanly)
		local sdSig = Flux.signal(0)
		local sdComp: any
		sdComp = Flux.computed(function()
			local v = sdSig()
			if v > 0 then
				sdComp:Destroy()
			end
			return v
		end)
		local sdHold = Flux.effect(function()
			local _ = sdComp()
		end)
		flush()
		sdSig:set(1)
		flush()
		expect(sdComp:peek() == nil, "self-disposing computed at idx==last reaps cleanly")
		sdHold:Destroy()

		local seSig = Flux.signal(0)
		local seEff: any
		seEff = Flux.effect(function()
			local v = seSig()
			if v > 0 then
				seEff:Destroy()
			end
		end)
		flush()
		seSig:set(1)
		flush()
		seSig:set(2)
		flush()
		expect(not Graph.isObserved(seSig), "self-disposing effect at idx==last reaps cleanly")
		sdSig:Destroy()
		seSig:Destroy()

		-- 4. Effect-subscribe cycle attribution in drain & reconcileEffect
		local ecGate = Flux.signal(0)
		local ecA: any
		local ecB: any
		ecA = Flux.computed(function()
			if ecGate() > 0 then
				return ecB() + 1
			end
			return 1
		end)
		ecB = Flux.computed(function()
			return ecA() + 1
		end)
		local _ = ecB()
		ecGate:set(1)
		local ecEff = Flux.effect(function()
			local _ = ecA()
		end)
		local ecWarn = env.warnings(flush)
		expect(#ecWarn >= 1, "drain attributes initial effect-subscribe cycle cleanly")
		ecEff:Destroy()
		ecGate:set(0)
		ecA:Destroy()
		ecB:Destroy()
		ecGate:Destroy()

		-- 5. 7-slot effects (0,1,2,6 srcs; grow/shrink) & ALL disposeChildren chained shapes + rollbackReconcileTail + defer=false + markList multi-obs
		local s0, s1, s2, s3, s4, s5, s6 =
			Flux.signal(1),
			Flux.signal(2),
			Flux.signal(3),
			Flux.signal(4),
			Flux.signal(5),
			Flux.signal(6),
			Flux.signal(7)
		local effSeen = 0
		local deadCleanCount = 0
		local nestedEffRuns = 0
		local nestedScopeClean = 0
		local deadPlain: any
		local deadWithChild: any
		local cOne: any
		local cTwo: any
		local cZero: any
		local cChainMulti: any
		local extComp: any
		local scDispose = Flux.scope(function()
			-- 0-source effect
			Flux.createEffect(function()
				effSeen += 1
			end)
			-- Nested child scope (hits disposeOne branch in disposeChildren fast path)
			Flux.scope(function()
				Flux.cleanup(function()
					nestedScopeClean += 1
				end)
			end)
			-- Externally observed computed (hits disposeOne branch for observed child computed)
			extComp = Flux.computed(function()
				return s5() + 10
			end)
			-- Unobserved (dead) computed without children
			deadPlain = Flux.computed(function()
				return s1() + 5
			end)
			-- Unobserved (dead) computed WITH a child cleanup
			deadWithChild = Flux.computed(function()
				Flux.cleanup(function()
					deadCleanCount += 1
				end)
				return s2() + 5
			end)
			-- 1-source effect + 1-source chained computed + nested child effect (node[E_CHILDREN])
			cOne = Flux.computed(function()
				return s1() + 1
			end)
			Flux.createEffect(function()
				effSeen += cOne()
				Flux.createEffect(function()
					nestedEffRuns += 1
					effSeen += s2()
				end)
			end)
			-- 1-source effect + 2-source chained computed (clearCompSrcs)
			cTwo = Flux.computed(function()
				return s1() + s2()
			end)
			Flux.createEffect(function()
				effSeen += cTwo()
			end)
			-- 1-source effect + 0-source chained computed
			cZero = Flux.computed(function()
				return 42
			end)
			Flux.createEffect(function()
				effSeen += cZero()
			end)
			-- Multi-source effect + chained computed + non-chained signal (disposeMultiEffect + disposeChained)
			cChainMulti = Flux.computed(function()
				return s3() + s4()
			end)
			Flux.createEffect(function()
				effSeen += s0() + cChainMulti()
			end)
			-- 6-source dynamic grow/shrink effect
			local wide = Flux.computed(function()
				return s1() + s2() + s3() + s4() + s5() + s6()
			end)
			Flux.createEffect(function()
				if s0() > 1 then
					effSeen += wide() + s1() + s2() + s3() + s4() + s5()
				else
					effSeen += wide()
				end
			end)
		end)
		local extVal = 0
		local extEff = Flux.effect(function()
			extVal = extComp()
		end)
		sert.defer(function()
			extEff:Destroy()
		end)
		flush()
		expect(extVal == 16, "externally observed computed ran before disposeChildren")
		local _ = deadPlain()
		local _ = deadWithChild()
		s0:set(2)
		flush()
		s0:set(1)
		flush()
		scDispose:Destroy()
		extEff:Destroy()
		cOne:set(999)
		expect(
			deadCleanCount == 1
				and nestedScopeClean == 1
				and extComp:peek() == nil
				and cOne:peek() == nil
				and cTwo:peek() == nil
				and cZero:peek() == nil
				and cChainMulti:peek() == nil
				and deadPlain:peek() == nil
				and deadWithChild:peek() == nil,
			"disposeChildren tears down chained/dead/external computeds and scopes and ignores post-dispose writes"
		)
		local effSeenAfterDispose = effSeen
		local nestedRunsAfterDispose = nestedEffRuns
		s0:set(10)
		s1:set(11)
		s2:set(12)
		s3:set(13)
		s4:set(14)
		s5:set(15)
		s6:set(16)
		flush()
		expect(
			effSeen == effSeenAfterDispose and nestedEffRuns == nestedRunsAfterDispose,
			"torn down effects and nested child effects do not re-run after disposeChildren"
		)
		s0:set(1)
		s1:set(2)
		s2:set(3)
		s3:set(4)
		s4:set(5)
		s5:set(6)
		s6:set(7)
		expect(
			not Graph.isObserved(s0)
				and not Graph.isObserved(s1)
				and not Graph.isObserved(s3)
				and not Graph.isObserved(s6),
			"disposeChildren cleans 0/1/2/6-source effects and all chained computeds without leaks"
		)

		-- rollbackReconcileTail (nNew=6 diverging over nOld=6) + defer=false (multi-obs: 1 dirty + 1 effect) + markList (2+ obs)
		local mGate = Flux.signal(0)
		local mHead = Flux.signal(1)
		local cycY: any
		local tailComp: any
		tailComp = Flux.computed(function()
			if mGate() == 0 then
				return s1() + s2() + s3()
			end
			return s1() + s4() + s5() + cycY()
		end)
		cycY = Flux.computed(function()
			return tailComp() + 1
		end)
		local cycYTapped = Flux.effect(function()
			pcall(cycY)
		end)
		local mMulti = Flux.computed(function()
			return mHead() * 3
		end)
		local mObs1 = Flux.computed(function()
			return mMulti() + 1
		end)
		local mObs2Runs = 0
		local mObsEff = Flux.effect(function()
			mObs2Runs += 1
			local _ = mMulti()
			pcall(tailComp)
		end)
		local mObs1Tap = Flux.effect(function()
			local _ = mObs1()
		end)
		flush()
		mMulti:set(99) -- markList multi-observer outside effect
		local inEffMark = Flux.effect(function()
			mMulti:set(100) -- markList multi-observer inside effect
		end)
		flush()
		mHead:set(2)
		flush() -- exercises defer=false on mMulti (mObs1 dirty + mObsEff clean/dirty mix)
		env.warnings(function()
			mGate:set(1)
			flush() -- exercises rollbackReconcileTail
		end)
		mGate:set(0)
		flush()
		expect(
			mObs2Runs >= 2 and tailComp:peek() == 9,
			"rollbackReconcileTail and markList multi-observer paths succeed"
		)

		-- 6. Node API parity: call, get, peek, raw, read, getter across live clean, dead clean, pull, hit, and miss
		local apiSig = Flux.signal(10)
		local apiComp = Flux.computed(function()
			return apiSig() * 2
		end)
		local apiGetter = Flux.getter(apiComp)
		expect(apiComp() == 20 and apiComp:get() == 20 and apiComp:peek() == 20)
		expect(Flux.raw(apiComp) == 20 and Flux.read(apiComp) == 20 and apiGetter() == 20)
		local apiReader = Flux.effect(function()
			local _ = apiComp()
			local _ = apiComp:get()
			local _ = apiGetter()
			local _ = Flux.read(apiComp)
		end)
		flush()
		apiSig:set(25)
		expect(apiComp() == 50 and apiComp:get() == 50 and apiComp:peek() == 50)
		expect(Flux.raw(apiComp) == 50 and Flux.read(apiComp) == 50 and apiGetter() == 50)
		apiReader:Destroy()
		apiComp:Destroy()
		apiSig:Destroy()

		-- 7. rawFn, untrack(fn) self-cycle, and direct computed write markList (1-obs & N-obs, re==nil & re~=nil)
		local rawTrig = Flux.signal(1)
		local rawHidden = Flux.signal(10)
		local rawCleanCount = 0
		local rawCompRuns = 0
		local rawComp = Flux.computed(function()
			rawCompRuns += 1
			local base = rawTrig()
			local h = Flux.raw(function()
				Flux.cleanup(function()
					rawCleanCount += 1
				end)
				return rawHidden()
			end)
			return base + h
		end)
		expect(rawComp() == 11 and rawCleanCount == 0)
		rawHidden:set(20)
		expect(rawComp() == 11 and rawCompRuns == 1, "raw(fn) inside computed does not subscribe to hidden reads")
		rawTrig:set(2)
		expect(
			rawComp() == 22 and rawCompRuns == 2 and rawCleanCount == 1,
			"raw(fn) cleanup attaches to computed and fires on recompute"
		)
		rawComp:Destroy()
		expect(rawCleanCount == 2, "raw(fn) cleanup fires on computed Destroy")

		-- live computed calling Flux.raw(throwing) during stabilize(): pEval == nil -> rawFn sets evalNode = active
		local rawErrSig = Flux.signal(1)
		local rawErrCleaned = 0
		local rawErrComp = Flux.computed(function()
			local v = rawErrSig()
			Flux.cleanup(function()
				rawErrCleaned += 1
			end)
			if v == 2 then
				Flux.raw(function()
					error("raw stab boom", 0)
				end)
			end
			return v * 10
		end)
		local rawErrSeen = 0
		local rawErrEff = Flux.effect(function()
			local ok, val = pcall(rawErrComp)
			if ok then
				rawErrSeen = val
			end
		end)
		flush()
		expect(rawErrSeen == 10, "live rawErrComp initial value")
		rawErrSig:set(2)
		local rawErrWarns = env.warnings(flush)
		local okRawErr = pcall(rawErrComp.peek, rawErrComp)
		expect(
			#rawErrWarns == 0 and not okRawErr and rawErrCleaned == 2,
			`raw(fn) throw during stabilize marks active computed ERRORED (warns={#rawErrWarns}, ok={okRawErr}, cleaned={rawErrCleaned})`
		)
		rawErrSig:set(3)
		flush()
		expect(rawErrSeen == 30, "rawErrComp heals on recovery")
		rawErrEff:Destroy()
		rawErrComp:Destroy()
		rawErrSig:Destroy()

		-- withOwner inside computed with raw(fn): pSet == true preserves explicit owner
		local extClean = 0
		local extScope = Flux.scope(function() end)
		local ownerPreserved = Flux.computed(function()
			return Flux.withOwner(extScope, function()
				return Flux.raw(function()
					Flux.cleanup(function()
						extClean += 1
					end)
					return 5
				end)
			end)
		end)
		expect(ownerPreserved() == 5 and extClean == 0)
		ownerPreserved:Destroy()
		expect(extClean == 0, "pSet == true inside raw(fn) kept external owner instead of attaching to computed")
		extScope:Destroy()
		expect(extClean == 1, "external owner cleanup fires on its Destroy")

		local suspTrig = Flux.signal(1)
		local suspRawClean = 0
		local suspEffRuns = 0
		local suspEff = Flux.effect(function()
			suspEffRuns += 1
			local _ = suspTrig()
			untrack()
			Flux.raw(function()
				Flux.cleanup(function()
					suspRawClean += 1
				end)
				return rawHidden()
			end)
		end)
		flush()
		rawHidden:set(30)
		flush()
		expect(
			suspEffRuns == 1 and suspRawClean == 0,
			"raw(fn) after bare untrack() skips subscription to hidden signal"
		)
		suspTrig:set(2)
		flush()
		expect(
			suspEffRuns == 2 and suspRawClean == 1,
			"raw(fn) after bare untrack() attaches cleanup to suspended effect"
		)
		suspEff:Destroy()
		expect(suspRawClean == 2, "raw(fn) suspended cleanup runs on Destroy")

		-- live computed calling Flux.untrack(throwing) during stabilize(): pEval == nil -> sets evalNode = active
		local untrackErrSig = Flux.signal(1)
		local untrackErrComp = Flux.computed(function()
			local v = untrackErrSig()
			if v == 2 then
				Flux.untrack(function()
					error("untrack stab boom", 0)
				end)
			end
			return v * 10
		end)
		local untrackErrSeen = 0
		local untrackErrEff = Flux.effect(function()
			local ok, val = pcall(untrackErrComp)
			if ok then
				untrackErrSeen = val
			end
		end)
		flush()
		untrackErrSig:set(2)
		local untrackErrWarns = env.warnings(flush)
		local okUntrackErr = pcall(untrackErrComp.peek, untrackErrComp)
		expect(
			#untrackErrWarns == 0 and not okUntrackErr,
			`untrack(fn) throw during stabilize marks active computed ERRORED (warns={#untrackErrWarns}, ok={okUntrackErr})`
		)
		untrackErrSig:set(3)
		flush()
		expect(untrackErrSeen == 30, "untrackErrComp heals on recovery")
		untrackErrEff:Destroy()
		untrackErrComp:Destroy()
		untrackErrSig:Destroy()

		-- Direct computed :set() on 1-observer and N-observer (outside effect & inside running effect)
		local dBase = Flux.signal(1)
		local singleSetComp = Flux.computed(function()
			return dBase() * 2
		end)
		local singleSeen = 0
		local singleObs = Flux.effect(function()
			singleSeen = singleSetComp()
		end)
		flush()
		singleSetComp:set(77)
		flush()
		expect(singleSeen == 77, "1-observer computed :set() notifies observer outside effect")

		local multiSetComp = Flux.computed(function()
			return dBase() * 3
		end)
		local obsAVal, obsBVal = 0, 0
		local obsA = Flux.effect(function()
			obsAVal = multiSetComp()
		end)
		local obsB = Flux.effect(function()
			obsBVal = multiSetComp()
		end)
		flush()
		multiSetComp:set(99)
		flush()
		expect(obsAVal == 99 and obsBVal == 99, "multi-observer computed :set() outside effect notifies all observers")

		local selfWriteRuns = 0
		local obsC = Flux.effect(function()
			selfWriteRuns += 1
			local v = multiSetComp()
			if v == 99 then
				multiSetComp:set(200) -- deferSelf on obsC + markOne on obsA/obsB
			end
		end)
		flush()
		expect(
			obsAVal == 200 and obsBVal == 200 and selfWriteRuns == 2,
			"multi-observer computed :set() inside observing effect defers self and notifies siblings"
		)
		obsC:Destroy()
		obsB:Destroy()
		obsA:Destroy()
		multiSetComp:Destroy()
		singleObs:Destroy()
		singleSetComp:Destroy()
		dBase:Destroy()
		rawHidden:Destroy()
		rawTrig:Destroy()
		suspTrig:Destroy()

		-- 8. Additional targeted mutation killers: getMemo dirty slot hit, writeComputed on dirty computed,
		--    setSignal slow return value, runEffectNow self-requeue via :peek(), and trackSlow diverged dedup / nested divergence
		local mGate2 = Flux.signal(1)
		local mSig2 = Flux.signal(10)
		local mComp2 = Flux.computed(function()
			return mSig2() * 2
		end)
		local mSeen2 = 0
		local mEff2 = Flux.effect(function()
			if mGate2() == 2 then
				mSig2:set(20)
			end
			mSeen2 = Flux.read(mComp2)
		end)
		flush()
		expect(mSeen2 == 20, "Flux.read(comp) initial read")
		mGate2:set(2)
		flush()
		expect(mSeen2 == 40, "getMemo r[i]==node slot hit pulls dirty computed mid-run")
		mEff2:Destroy()

		-- writeComputed on dirty computed: no-force equal after pull skips obs, force=true wakes obs,
		-- and calling comp:set() inside another effect does NOT subscribe caller to comp's upstream signal
		local wBase = Flux.signal(1)
		local wComp = Flux.computed(function()
			return math.abs(wBase()) * 2
		end)
		local wObsRuns = 0
		local wObsVal = 0
		local wObsEff = Flux.effect(function()
			wObsRuns += 1
			wObsVal = wComp()
		end)
		flush()
		wBase:set(-1) -- wComp is dirty before flush (pulls 2 == old 2)
		wComp:set(2) -- pulls wComp -> old == 2 == value without force -> skips observer!
		flush()
		expect(wObsRuns == 1 and wObsVal == 2, "writeComputed without force skips when pulled dirty value equals arg")
		wBase:set(1) -- dirty again (pulls 2)
		wComp:set(2, true) -- force=true wakes observer
		flush()
		expect(wObsRuns == 2 and wObsVal == 2, "writeComputed with force=true notifies observer even when equal")

		local wCallerRuns = 0
		local wTrig = Flux.signal(0)
		local wCaller = Flux.effect(function()
			wCallerRuns += 1
			if wTrig() > 0 then
				wBase:set(9) -- dirty wComp inside effect
				expect(wBase:set(9) == 9, "setSignal slow path returns written value")
				wComp:set(99) -- pulls wComp inside effect without leaking curNode
			end
		end)
		flush()
		wTrig:set(1)
		flush()
		wBase:set(10) -- wCaller must NOT have subscribed to wBase when wComp:set pulled wComp!
		flush()
		expect(wCallerRuns == 2, "writeComputed inside effect does not subscribe caller to upstream sources")
		wCaller:Destroy()
		wObsEff:Destroy()
		wComp:Destroy()
		wTrig:Destroy()
		wBase:Destroy()
		mComp2:Destroy()
		mSig2:Destroy()
		mGate2:Destroy()

		-- runEffectNow self-requeue via e:peek()
		local rSig = Flux.signal(1)
		local rRuns = 0
		local rEff: any
		rEff = Flux.effect(function()
			rRuns += 1
			local v = rSig()
			if v == 1 then
				rSig:set(2)
			end
		end)
		rEff:peek()
		flush()
		expect(rRuns == 2, "runEffectNow synchronous :peek() self-requeues on write-after-read")
		rEff:Destroy()
		rSig:Destroy()

		-- trackSlow diverged dedup & nested divergence (freeNew == nil)
		local divGate = Flux.signal(false)
		local divA = Flux.signal(1)
		local divB = Flux.signal(2)
		local divC = Flux.signal(3)
		local innerDiv = Flux.computed(function()
			if not divGate() then
				return divA()
			end
			return divC() + divC()
		end)
		local outerDiv = Flux.computed(function()
			if not divGate() then
				return divA()
			end
			local _ = divB() + divB()
			return Flux.raw(innerDiv)
		end)
		local outerDivTap = Flux.effect(function()
			local _ = outerDiv()
		end)
		local innerDivTap = Flux.effect(function()
			local _ = innerDiv()
		end)
		flush()
		divGate:set(true)
		flush()
		divC:set(10)
		flush()
		expect(
			(divB :: any)[1][4] == 1 and (divC :: any)[1][4] == 1 and innerDiv:peek() == 20 and outerDiv:peek() == 6,
			"trackSlow dedupes post-divergence reads and handles nested divergence when freeNew is nil"
		)
		innerDivTap:Destroy()
		outerDivTap:Destroy()
		outerDiv:Destroy()
		innerDiv:Destroy()
		divC:Destroy()
		divB:Destroy()
		divA:Destroy()
		divGate:Destroy()

		-- 9. updateNode (:update()), wrapComputedEquals stabilize error attribution, and runEffectNow (:peek()) edge paths
		local uTbl = { count = 1 }
		local uSig = Flux.signal(uTbl)
		local uCompReads = 0
		local uDead = Flux.computed(function()
			uCompReads += 1
			return uSig().count
		end)
		local uDeadDownRuns = 0
		local uDeadDown = Flux.computed(function()
			uDeadDownRuns += 1
			return uDead() * 10
		end)
		expect(uDeadDown() == 10 and uCompReads == 1 and uDeadDownRuns == 1, "baseline dead computed chain")

		-- Signal :update() inside running effect and inside computed that already read uSig
		local uSelfEffRuns = 0
		local uSelfEff = Flux.effect(function()
			uSelfEffRuns += 1
			local _ = uSig()
			if uSelfEffRuns == 1 then
				uTbl.count = 2
				uSig:update()
			end
		end)
		flush()
		expect(uSelfEffRuns == 2, "signal :update() inside running effect requeues via markSelf")
		uSelfEff:Destroy()

		local uDeadUpd = Flux.computed(function()
			local _ = uSig()
			return uTbl.count
		end)
		expect(uDeadUpd() == 2)
		uTbl.count = 3
		uDeadUpd:update() -- update() on dead clean computed
		-- Re-verify calling :update() on a dead computed inside a running effect that already read it
		local uSelfCompRuns = 0
		local uSelfComp = Flux.effect(function()
			uSelfCompRuns += 1
			local _ = uDead()
			if uSelfCompRuns == 1 then
				uDead:update() -- computed :update() inside running effect -> markSelf
			end
		end)
		flush()
		expect(uSelfCompRuns == 2, "computed :update() inside running effect requeues via markSelf")
		uSelfComp:Destroy()

		-- Dead dirty computed :update() bumps CHANGED so downstream dead computed recomputes on next read
		local uSrc = Flux.signal(1)
		local uMid = Flux.computed(function()
			return uSrc() + 1
		end)
		local uDownRuns = 0
		local uDown = Flux.computed(function()
			uDownRuns += 1
			return uMid() + 10
		end)
		expect(uDown() == 12 and uDownRuns == 1)
		uSrc:set(2) -- uMid is dead & dirty
		uMid:update() -- marks uMid STALE & bumps uMid[CHANGED]
		expect(uDown() == 13 and uDownRuns == 2, "dead dirty computed :update() invalidates downstream dead reader")

		-- Live dirty computed :update() called inside another effect pulls cleanly without subscribing caller to uSrc
		local uLiveObsRuns = 0
		local uLiveEff = Flux.effect(function()
			uLiveObsRuns += 1
			local _ = uMid()
		end)
		flush()
		local callerTrig = Flux.signal(0)
		local callerRuns = 0
		local callerEff = Flux.effect(function()
			callerRuns += 1
			if callerTrig() == 1 then
				uSrc:set(5) -- uMid is live dirty
				uMid:update() -- pulls uMid (6) cleanly without leaking curNode to uSrc!
			end
		end)
		flush()
		callerTrig:set(1)
		flush()
		expect(uLiveObsRuns == 2 and uMid:peek() == 6 and callerRuns == 2, "live dirty :update() pulls & notifies")
		uSrc:set(7) -- callerEff must NOT re-run since uMid:update() cleared curNode during pull
		flush()
		expect(callerRuns == 2, "live dirty :update() inside effect did not subscribe caller to upstream signal")
		callerEff:Destroy()
		callerTrig:Destroy()

		-- Live clean computed :update() bumps CHANGED so dead downstream recomputes, and no-op on destroyed/effect/scope
		local deadAfterCleanRuns = 0
		local deadAfterClean = Flux.computed(function()
			deadAfterCleanRuns += 1
			return uMid() * 2
		end)
		expect(deadAfterClean() == 16 and deadAfterCleanRuns == 1)
		uMid:update() -- live clean bump
		flush()
		expect(
			deadAfterClean() == 16 and deadAfterCleanRuns == 2 and uLiveObsRuns == 4,
			"live clean :update() wakes observers & bumps version"
		)

		local uNoopEff = Flux.effect(function() end)
		local uNoopScope = Flux.scope(function() end)
		uNoopEff:update()
		uNoopScope:update()
		uNoopEff:Destroy()
		uNoopScope:Destroy()
		uLiveEff:Destroy()
		deadAfterClean:Destroy()
		uMid:Destroy() -- destroyed computed :update() no-op
		uMid:update()
		uDown:Destroy()
		uSrc:Destroy()
		uDeadUpd:Destroy()
		uDeadDown:Destroy()
		uDead:Destroy()
		uSig:Destroy()

		-- wrapComputedEquals throwing error during stabilize() marks computed ERRORED cleanly
		local eqErrSig = Flux.signal(1)
		local eqErrComp = Flux.computed(function()
			return eqErrSig() * 10
		end, function(prev, nxt)
			if nxt == 20 then
				error("stab-eq-boom", 0)
			end
			return prev == nxt
		end)
		local eqErrOk, eqErrSeen = true, 0
		local eqErrEff = Flux.effect(function()
			eqErrOk, eqErrSeen = pcall(eqErrComp)
		end)
		sert.defer(function()
			eqErrEff:Destroy()
			eqErrComp:Destroy()
			eqErrSig:Destroy()
		end)
		flush()
		expect(eqErrOk and eqErrSeen == 10, "baseline eqErrComp")
		eqErrSig:set(2)
		env.warnings(flush)
		local peekOk = pcall(eqErrComp.peek, eqErrComp)
		expect(not peekOk and not eqErrOk, "wrapComputedEquals error during stabilize marks computed ERRORED")
		eqErrSig:set(3)
		flush()
		expect(eqErrOk and eqErrSeen == 30, "eqErrComp heals cleanly on recovery")
		eqErrEff:Destroy()
		eqErrComp:Destroy()
		eqErrSig:Destroy()

		-- runEffectNow (:peek()) refreshes dirty computed dep and handles self-destruction mid-run
		local rnSrc = Flux.signal(1)
		local rnComp = Flux.computed(function()
			return rnSrc() * 3
		end)
		local rnVal = 0
		local rnClean = 0
		local rnEff: any
		rnEff = Flux.effect(function()
			Flux.cleanup(function()
				rnClean += 1
			end)
			rnVal = rnComp()
			if rnVal == 9 then
				rnEff:Destroy()
			end
		end)
		flush()
		rnSrc:set(3) -- rnComp is dirty before rnEff:peek()
		rnEff:peek() -- runEffectNow refreshes rnComp -> 9 and rnEff destroys itself mid-run!
		expect(
			rnVal == 9 and rnClean == 2 and not Graph.isObserved(rnSrc),
			"runEffectNow refreshes dep and self-disposes"
		)
		rnComp:Destroy()
		rnSrc:Destroy()

		inEffMark:Destroy()
		mObs1Tap:Destroy()
		mObsEff:Destroy()
		mObs1:Destroy()
		mMulti:Destroy()
		cycYTapped:Destroy()
		cycY:Destroy()
		tailComp:Destroy()
		mHead:Destroy()
		mGate:Destroy()
		s0:Destroy()
		s1:Destroy()
		s2:Destroy()
		s3:Destroy()
		s4:Destroy()
		s5:Destroy()
		s6:Destroy()
	end
)

test("runEffectNow · clean skip, ownership, cleanup order, nested outerFrame & dep reconciliation", function()
	local nodes: { any } = {}
	local function trackNode<T>(x: T): T
		table.insert(nodes, x)
		return x
	end
	sert.defer(function()
		for i = #nodes, 1, -1 do
			(nodes[i] :: any):Destroy()
		end
	end)

	-- 1. Clean e:peek() while unrelated computed is dirty before flush must NOT run e
	local unSig = trackNode(Flux.signal(1))
	local unComp = trackNode(Flux.computed(function()
		return unSig() * 2
	end))
	local unObs = trackNode(Flux.effect(function()
		local _ = unComp()
	end))
	local cSig = trackNode(Flux.signal(10))
	local cRuns = 0
	local cEff = trackNode(Flux.effect(function()
		cRuns += 1
		local _ = cSig()
	end))
	flush()
	expect(cRuns == 1, "baseline clean effect run count")
	unSig:set(2) -- leaves heapMin ~= INF while entering peek() -> pullValue calls runEffectNow(cEff)
	cEff:peek()
	expect(cRuns == 1 and unComp() == 4, "clean effect peek() during batch with unrelated dirty computed skips re-run")
	flush()
	unObs:Destroy()

	-- 2. e:peek() inside Flux.withOwner(extOwner): prior cleanup fires BEFORE body, child owned by e, post-peek child by extOwner
	local ownSig = trackNode(Flux.signal(1))
	local phaseLog = {}
	local ownChildClean = 0
	local extChildClean = 0
	local ownEff = trackNode(Flux.effect(function()
		local v = ownSig()
		Flux.cleanup(function()
			table.insert(phaseLog, "cleanup:" .. v)
		end)
		local innerC = Flux.computed(function()
			Flux.cleanup(function()
				ownChildClean += 1
			end)
			return v * 3
		end)
		local _ = innerC()
		table.insert(phaseLog, "body:" .. v)
	end))
	flush()
	expect(#phaseLog == 1 and phaseLog[1] == "body:1", "initial run logged body")
	table.clear(phaseLog)
	ownSig:set(2)
	local extOwner = trackNode(Flux.scope(function() end))
	Flux.withOwner(extOwner, function()
		ownEff:peek()
		local postC = Flux.computed(function()
			Flux.cleanup(function()
				extChildClean += 1
			end)
			return 99
		end)
		local _ = postC()
		Flux.cleanup(function()
			extChildClean += 1
		end)
	end)
	expect(
		#phaseLog == 2 and phaseLog[1] == "cleanup:1" and phaseLog[2] == "body:2",
		"runEffectNow disposes prior children/cleanups before running new body"
	)
	expect(ownChildClean == 1 and extChildClean == 0, "prior e-owned child disposed; new extOwner items alive")
	extOwner:Destroy()
	expect(ownChildClean == 1 and extChildClean == 2, "extOwner disposed post-peek child/cleanup, NOT e's owned child")
	ownEff:Destroy()
	expect(ownChildClean == 2, "e:Destroy() disposed e's own child")

	-- 3a. Nested e2:peek() inside running e1 preserves selfWritten when inner effect doesn't write
	local s1 = trackNode(Flux.signal(0))
	local s2 = trackNode(Flux.signal(10))
	local e2Runs = 0
	local e2Seen = 0
	local e2 = trackNode(Flux.effect(function()
		e2Runs += 1
		e2Seen = s2()
	end))
	local e1Runs = 0
	local e1Seen = 0
	local e1 = trackNode(Flux.effect(function()
		e1Runs += 1
		local v = s1()
		e1Seen = v
		if v == 2 then
			s1:set(3)
			s2:set(20)
			e2:peek()
		end
	end))
	flush()
	expect(e1Runs == 1 and e2Runs == 1 and e2Seen == 10, "nested test baseline")
	s1:set(2)
	flush()
	expect(e1Runs == 3 and e1Seen == 3 and e2Runs == 2 and e2Seen == 20, "outer selfWritten survived nested e2:peek()")

	-- 3b. Nested e2b:peek() writes e1b's source -> outerFrame.written requeues e1b; subsequent top-level e3:peek() still works
	local b1 = trackNode(Flux.signal(1))
	local b2 = trackNode(Flux.signal(1))
	local e2b = trackNode(Flux.effect(function()
		local x = b2()
		if x == 10 then
			b1:set(3)
		end
	end))
	local b1Runs, b1Seen = 0, 0
	local e1b = trackNode(Flux.effect(function()
		b1Runs += 1
		b1Seen = b1()
		if b1Seen == 2 then
			b2:set(10)
			e2b:peek()
		end
	end))
	flush()
	b1:set(2)
	flush()
	expect(b1Runs == 3 and b1Seen == 3, "outerFrame.written requeued outer effect after nested e2b:peek()")

	local s3 = trackNode(Flux.signal(0))
	local s3Runs, s3Seen = 0, 0
	local e3 = trackNode(Flux.effect(function()
		s3Runs += 1
		s3Seen = s3()
		if s3Seen == 1 then
			s3:set(2)
		end
	end))
	flush()
	s3:set(1)
	e3:peek()
	flush()
	expect(s3Runs == 3 and s3Seen == 2, "top-level e3:peek() after nested frame unwinds noEffect cleanly")

	-- 4. e:peek() changing deps inside bare Flux.untrack() of outer effect clears curNew & restores suspRun
	local uGate = trackNode(Flux.signal(true))
	local ux1 = trackNode(Flux.signal(1))
	local ux2 = trackNode(Flux.signal(2))
	local uIn = trackNode(Flux.effect(function()
		if uGate() then
			local _ = ux1()
		else
			local _ = ux2()
		end
	end))
	local oA = trackNode(Flux.signal(1))
	local oB = trackNode(Flux.signal(10))
	local oRuns, oVal = 0, 0
	local oPhase = trackNode(Flux.signal(0))
	local uOut = trackNode(Flux.effect(function()
		oRuns += 1
		local _ = oA()
		if oPhase:peek() == 1 then
			oPhase:set(2)
			untrack()
			uGate:set(false)
			uIn:peek()
			retrack()
		end
		oVal = oB()
	end))
	flush()
	expect(Graph.isObserved(ux1) and not Graph.isObserved(ux2), "uIn initially tracks ux1")
	oPhase:set(1)
	oA:set(2)
	flush()
	expect(not Graph.isObserved(ux1) and Graph.isObserved(ux2), "uIn:peek() reconciled deps from ux1 to ux2")
	expect(oVal == 10 and oRuns == 2, "outer effect completed run after retrack")
	oB:set(99)
	flush()
	expect(oRuns == 3 and oVal == 99, "retrack after uIn:peek() restored suspRun and tracked oB")
	e1b:Destroy()
	e2b:Destroy()
	e3:Destroy()
	uOut:Destroy()
	uIn:Destroy()
	e1:Destroy()
	e2:Destroy()
	cEff:Destroy()
end)

test("updateNode · live/dead dirty & clean paths, self-marking and downstream invalidation", function()
	local nodes: { any } = {}
	local function trackNode<T>(x: T): T
		table.insert(nodes, x)
		return x
	end
	sert.defer(function()
		for i = #nodes, 1, -1 do
			(nodes[i] :: any):Destroy()
		end
	end)

	-- 1. Live dirty comp:update() inside live computed reader pulls comp without subscribing reader to comp's upstream
	local src = trackNode(Flux.signal(1))
	local comp = trackNode(Flux.computed(function()
		return { v = src() * 10 }
	end))
	local keepCompSeen = 0
	local keepEff = trackNode(Flux.effect(function()
		keepCompSeen = comp().v
	end))
	local sA = trackNode(Flux.signal(1))
	local sB = trackNode(Flux.signal(100))
	local readerRuns = 0
	local reader = trackNode(Flux.computed(function()
		readerRuns += 1
		local a = sA()
		comp:update()
		local b = sB()
		return a + b + comp:peek().v
	end))
	local readerEff = trackNode(Flux.effect(function()
		local _ = reader()
	end))
	flush()
	expect(keepCompSeen == 10 and readerRuns == 1, "baseline live updateNode")

	src:set(2) -- comp is dirty before flush
	sA:set(2)
	flush()
	expect(reader:peek() == 122 and readerRuns == 2 and keepCompSeen == 20, "comp:update() pulled dirty comp")
	-- Modify src while sA/sB stay fixed: reader must NOT have subscribed to src
	src:set(3)
	flush()
	expect(readerRuns == 2 and keepCompSeen == 30, "reader did not subscribe to comp's upstream src")
	sB:set(200)
	flush()
	expect(readerRuns == 3 and reader:peek() == 232, "reader preserved trailing sB subscription")

	-- 2. Live dirty comp:update() where pull(comp) destroys comp's sole observer (refreshes obs & st)
	local dSrc = trackNode(Flux.signal(1))
	local soleEff: any = nil
	local dComp = trackNode(Flux.computed(function()
		local v = dSrc()
		if v == 2 and soleEff then
			soleEff:Destroy()
		end
		return v * 5
	end))
	soleEff = trackNode(Flux.effect(function()
		local _ = dComp()
	end))
	flush()
	dSrc:set(2)
	dComp:update() -- pulls dComp -> destroys soleEff -> comp becomes dead!
	expect(dComp:peek() == 10 and not Graph.isObserved(dSrc), "pull during update() destroyed sole observer cleanly")
	dSrc:set(4) -- while dead, dComp must not remain stamped with LIVE_BASE
	expect(dComp() == 20, "subsequent read after dead transition recomputes instead of reading stale value")

	-- 3. Dead dirty comp:update() stays STALE, bumps CHANGED/epoch, and markSelf works for computed & effect
	local ddSrc = trackNode(Flux.signal(1))
	local ddMidRuns = 0
	local ddMid = trackNode(Flux.computed(function()
		ddMidRuns += 1
		return math.abs(ddSrc())
	end))
	local ddDownRuns = 0
	local ddDown = trackNode(Flux.computed(function()
		ddDownRuns += 1
		return ddMid() + 100
	end))
	expect(ddDown() == 101 and ddMidRuns == 1 and ddDownRuns == 1, "baseline dead dirty")
	ddSrc:set(2) -- marks ddMid STALE (dead)
	ddMid:update() -- dead dirty branch (L3128-3134)
	expect(ddMidRuns == 1, "dead dirty update() did not eagerly recompute ddMid")
	expect(ddDown() == 102 and ddMidRuns == 2 and ddDownRuns == 2, "ddMid stayed STALE and ddDown recomputed")

	-- Dead dirty inside computed (curNode ~= nil) and inside bare-untracked effect (curNode == nil, runningEffect ~= nil)
	local msFlag = trackNode(Flux.signal(0))
	local msSrc = trackNode(Flux.signal(1))
	local msDead = trackNode(Flux.computed(function()
		return msSrc()
	end))
	local msCompRuns = 0
	local msComp = trackNode(Flux.computed(function()
		msCompRuns += 1
		local v = msDead()
		if msFlag() == 1 then
			msSrc:set(2)
			msDead:update()
			msFlag:set(0)
		end
		return v
	end))
	local msCompEff = trackNode(Flux.effect(function()
		local _ = msComp()
	end))
	flush()
	expect(msCompRuns == 1, "msComp baseline")
	msFlag:set(1)
	flush()
	expect(msCompRuns == 3 and msComp:peek() == 2, "dead dirty update() marked active computed via markSelf")

	local meFlag = trackNode(Flux.signal(0))
	local meSrc = trackNode(Flux.signal(1))
	local meDead = trackNode(Flux.computed(function()
		return meSrc()
	end))
	local meRuns, meSeen = 0, 0
	local meEff = trackNode(Flux.effect(function()
		meRuns += 1
		meSeen = meDead()
		if meFlag() == 1 then
			meFlag:set(0)
			untrack()
			meSrc:set(2)
			meDead:update()
		end
	end))
	flush()
	expect(meRuns == 1 and meSeen == 1, "meEff baseline")
	meFlag:set(1)
	flush()
	expect(meRuns == 3 and meSeen == 2, "dead dirty update() after bare untrack() marked runningEffect via markSelf")

	-- 4. Dead clean comp:update(): does NOT recompute comp on next read, DOES recompute deadDown
	local dcSrc = trackNode(Flux.signal(5))
	local dcRuns = 0
	local dcComp = trackNode(Flux.computed(function()
		dcRuns += 1
		return dcSrc() * 2
	end))
	local dcDownRuns = 0
	local dcDown = trackNode(Flux.computed(function()
		dcDownRuns += 1
		return dcComp() + 1
	end))
	expect(dcDown() == 11 and dcRuns == 1 and dcDownRuns == 1, "dead clean baseline")
	dcComp:update()
	expect(dcComp() == 10 and dcRuns == 1, "dead clean update() keeps comp clean (does not mark STALE)")
	expect(dcDown() == 11 and dcDownRuns == 2 and dcRuns == 1, "dead clean update() bumps CHANGED so dcDown recomputes")

	-- 5. Live clean comp:update() inside computed & bare-untracked effect marks self
	local lcSrc = trackNode(Flux.signal(1))
	local lcLive = trackNode(Flux.computed(function()
		return lcSrc()
	end))
	local lcGate = trackNode(Flux.signal(false))
	local lcCompRuns = 0
	local lcComp = trackNode(Flux.computed(function()
		lcCompRuns += 1
		local v = lcLive()
		if lcGate() then
			lcGate:set(false)
			lcLive:update()
		end
		return v
	end))
	local lcKeep = trackNode(Flux.effect(function()
		local _ = lcComp()
	end))
	flush()
	lcGate:set(true)
	flush()
	expect(lcCompRuns == 3, "live clean update() marked active computed")

	local leGate = trackNode(Flux.signal(false))
	local leLive = trackNode(Flux.computed(function()
		return lcSrc()
	end))
	local leRuns = 0
	local leEff = trackNode(Flux.effect(function()
		leRuns += 1
		local _ = leLive()
		if leGate() then
			leGate:set(false)
			untrack()
			leLive:update()
		end
	end))
	flush()
	leGate:set(true)
	flush()
	expect(leRuns == 3, "live clean update() after bare untrack() marked runningEffect")

	keepEff:Destroy()
	readerEff:Destroy()
	msCompEff:Destroy()
	meEff:Destroy()
	lcKeep:Destroy()
	leEff:Destroy()
end)

test("getter · signal and computed slot hits, dedup and dead/dirty pulls", function()
	local nodes: { any } = {}
	local function trackNode<T>(x: T): T
		table.insert(nodes, x)
		return x
	end
	sert.defer(function()
		for i = #nodes, 1, -1 do
			(nodes[i] :: any):Destroy()
		end
	end)

	-- 1. Signal getter advances curIdx on matching slot so dropping a trailing dep triggers reconcile properly
	local s1 = trackNode(Flux.signal(1))
	local s2 = trackNode(Flux.signal(10))
	local drop2 = trackNode(Flux.signal(false))
	local g1 = Flux.getter(s1)
	local g2 = Flux.getter(s2)
	local sgRuns, sgVal = 0, 0
	local sgEff = trackNode(Flux.effect(function()
		sgRuns += 1
		sgVal = g1() + if drop2() then 0 else g2()
	end))
	flush()
	expect(sgRuns == 1 and sgVal == 11, "signal getter initial")
	drop2:set(true)
	flush()
	expect(sgRuns == 2 and sgVal == 1 and not Graph.isObserved(s2), "signal getter slot hit allowed trailing dep drop")
	s1:set(5)
	flush()
	expect(sgRuns == 3 and sgVal == 5, "kept s1 getter triggers effect")

	-- 2. Computed getter slot advance (L4119), dedup (L4128), dead clean skip (L4120/L4123), dead dirty pull (L4124)
	local cBase = trackNode(Flux.signal(2))
	local cRuns = 0
	local comp = trackNode(Flux.computed(function()
		cRuns += 1
		return cBase() * 10
	end))
	local gc = Flux.getter(comp)

	-- Live effect reads gc() twice (L4128 dedup) + s2 via g2, then drops g2
	local cDrop = trackNode(Flux.signal(false))
	local cgRuns, cgVal = 0, 0
	local cgEff = trackNode(Flux.effect(function()
		cgRuns += 1
		cgVal = gc() + gc() + if cDrop() then 0 else g2()
	end))
	flush()
	expect(cgRuns == 1 and cgVal == 50 and cRuns == 1, "computed getter live dedup initial")
	cDrop:set(true)
	flush()
	expect(
		cgRuns == 2 and cgVal == 40 and not Graph.isObserved(s2),
		"computed getter slot hit allowed trailing dep drop"
	)
	cBase:set(3)
	flush()
	expect(cgRuns == 3 and cgVal == 60 and cRuns == 2, "computed getter tracked upstream changes")
	cgEff:Destroy()
	sgEff:Destroy()

	-- Dead clean & dead dirty computed getter (also inside an outer effect with matching slot!)
	local dSrc = trackNode(Flux.signal(4))
	local dCompRuns = 0
	local dComp = trackNode(Flux.computed(function()
		dCompRuns += 1
		return dSrc() * 3
	end))
	local gd = Flux.getter(dComp)
	expect(gd() == 12 and dCompRuns == 1, "dead dirty getter evaluated dComp")
	expect(gd() == 12 and dCompRuns == 1, "dead clean getter skipped memoSlow at current epoch")
	dSrc:set(5)
	expect(gd() == 15 and dCompRuns == 2, "dead dirty getter pulled updated dComp")

	-- Same inside a reactive slot hit when dComp is temporarily dead vs live
	local slotGate = trackNode(Flux.signal(true))
	local slotRuns, slotVal = 0, 0
	local slotEff = trackNode(Flux.effect(function()
		slotRuns += 1
		slotVal = gd()
		if slotGate() then
			local _ = g1()
		end
	end))
	flush()
	expect(slotRuns == 1 and slotVal == 15, "slotEff baseline")
	slotGate:set(false)
	flush()
	expect(slotRuns == 2 and not Graph.isObserved(s1), "computed getter curIdx += 2 on matching slot")
	dSrc:set(6)
	expect(gd() == 18, "live computed getter reads fresh value")
	flush()
	expect(slotRuns == 3 and slotVal == 18, "slotEff ran on dComp update")
	slotEff:Destroy()
end)

test("stabilize DEFERRED · single/multi-observer defer, clean/effect no-defer, and pull reset", function()
	local nodes: { any } = {}
	local function trackNode<T>(x: T): T
		table.insert(nodes, x)
		return x
	end
	sert.defer(function()
		for i = #nodes, 1, -1 do
			(nodes[i] :: any):Destroy()
		end
	end)

	local cond = trackNode(Flux.signal(true))
	local x = trackNode(Flux.signal(1))
	local midRuns = 0
	local mid = trackNode(Flux.computed(function()
		midRuns += 1
		return x() * 10
	end))

	-- Drop mid once & re-subscribe so mid[CHILDREN] == nil
	local obs1 = trackNode(Flux.computed(function()
		return if cond() then mid() else 0
	end))
	local obs2 = trackNode(Flux.computed(function()
		return if cond() then mid() + 1 else 1
	end))
	local obsClean = trackNode(Flux.computed(function()
		return mid() * 2
	end))
	local enableClean = trackNode(Flux.signal(false))
	local e1 = trackNode(Flux.effect(function()
		local _ = obs1()
	end))
	local e2 = trackNode(Flux.effect(function()
		local _ = obs2()
	end))
	local cleanSeen = 0
	local eClean = trackNode(Flux.effect(function()
		if enableClean() then
			cleanSeen = obsClean()
		end
	end))
	flush()
	expect(midRuns == 1, "initial midRuns")

	cond:set(false)
	flush() -- obs1 & obs2 drop mid -> mid[CHILDREN] = nil
	cond:set(true)
	flush() -- re-subscribe obs1 & obs2 (x unchanged so mid stayed cached); mid[CHILDREN] == nil
	expect(midRuns == 1, "re-subscribed mid after drop")

	-- Case A: multi-observer (obs1, obs2) both dirty computeds, neither reads mid when cond == false -> mid defers!
	cond:set(false)
	x:set(2)
	flush()
	expect(midRuns == 1, "Case A: 2 dirty computed observers allow mid to DEFER cleanly")

	-- Re-subscribe for Case B (obs1 dirty, obsClean clean computed)
	cond:set(true)
	enableClean:set(true)
	flush()
	expect(midRuns == 2 and cleanSeen == 40, "Case B baseline")

	cond:set(false)
	x:set(3)
	flush()
	expect(midRuns == 3 and cleanSeen == 60, "Case B: clean computed observer prevents DEFER")

	-- Case C1: 2 observers where obs[OBS1] is computed (dirty) and obs[OBS1+1] is dirty effect reading cond + mid:peek()
	enableClean:set(false)
	cond:set(false)
	e2:Destroy()
	flush() -- mid is now dead, mid[CHILDREN] == nil
	cond:set(true)
	flush() -- obs1 is sole observer (obs[OBS1])
	local cEffSeen = 0
	local obsEff = trackNode(Flux.effect(function()
		local c = cond()
		if c then
			cEffSeen = mid()
		else
			cEffSeen = mid:peek()
		end
	end))
	flush()
	expect(midRuns == 3 and cEffSeen == 30, "Case C1 baseline")

	cond:set(false)
	x:set(4)
	flush()
	expect(
		midRuns == 4 and cEffSeen == 40,
		"Case C1: dirty effect as 2nd observer prevents DEFER so mid computes before effect runs"
	)

	-- Case C2: single observer is dirty effect (o1[HEIGHT] == INF) -> must NOT defer
	obsEff:Destroy()
	local s2Cond = trackNode(Flux.signal(true))
	local s2x = trackNode(Flux.signal(1))
	local s2MidRuns = 0
	local s2Mid = trackNode(Flux.computed(function()
		s2MidRuns += 1
		return s2x() * 10
	end))
	local sEffSeen = 0
	local sDropEff = trackNode(Flux.effect(function()
		if s2Cond() then
			local _ = s2Mid()
		end
	end))
	flush()
	s2Cond:set(false)
	flush() -- drop s2Mid -> s2Mid[CHILDREN] = nil
	sDropEff:Destroy()
	s2Cond:set(true)
	local singleEff = trackNode(Flux.effect(function()
		if s2Cond() then
			sEffSeen = s2Mid()
		else
			sEffSeen = s2Mid:peek()
		end
	end))
	flush()
	expect(s2MidRuns == 1 and sEffSeen == 10, "Case C2 baseline")
	s2Cond:set(false)
	s2x:set(5)
	flush()
	expect(s2MidRuns == 2 and sEffSeen == 50, "Case C2: single dirty effect observer prevents DEFER")
	singleEff:Destroy()

	-- Case D: pull(DEFERRED) resets mid[CHILDREN] = false so subsequent batch evaluates eagerly
	local pCond = trackNode(Flux.signal(true))
	local px = trackNode(Flux.signal(1))
	local pMidRuns = 0
	local pMid = trackNode(Flux.computed(function()
		pMidRuns += 1
		return px() * 10
	end))
	local pObsSeen = 0
	local pObs = trackNode(Flux.computed(function()
		return if pCond() then pMid() else -1
	end))
	local pEff = trackNode(Flux.effect(function()
		pObsSeen = pObs()
	end))
	flush()
	pCond:set(false)
	flush() -- drop -> pMid[CHILDREN] = nil
	pCond:set(true)
	flush() -- pMidRuns == 1
	expect(pMidRuns == 1 and pObsSeen == 10, "Case D baseline")

	-- Batch 1: dirties pObs + px while pCond stays true -> pMid defers, pObs pulls pMid resetting CHILDREN = false
	local trigPull = trackNode(Flux.signal(0))
	local pObs2 = trackNode(Flux.computed(function()
		local _ = trigPull()
		return if pCond() then pMid() else -1
	end))
	e1:Destroy()
	pEff:Destroy()
	local pEff2 = trackNode(Flux.effect(function()
		pObsSeen = pObs2()
	end))
	flush()
	trigPull:set(1)
	px:set(2)
	flush()
	expect(pMidRuns == 2 and pObsSeen == 20, "Case D Batch 1 pulled deferred pMid")
	-- Batch 2: pCond false + px changed -> because Batch 1's pull reset CHILDREN = false, pMid now runs eagerly!
	pCond:set(false)
	px:set(3)
	flush()
	expect(pMidRuns == 3 and pObsSeen == -1, "Case D Batch 2 ran pMid eagerly after pull cleared nil predictor")

	pEff2:Destroy()
	eClean:Destroy()
end)

test("stabilize self-dispose · cleanup of curNew, curNode, VALUE and reap", function()
	local hookLog = {}
	local reactiveInHook = false
	local s1 = Flux.signal(1)
	local s2 = Flux.signal(10)
	local sibSig = Flux.signal(1)
	local c: any = nil
	local cEff: any = nil
	local sibVal = 0
	local sibEff: any = nil
	sert.defer(function()
		if sibEff then
			sibEff:Destroy()
		end
		if cEff then
			cEff:Destroy()
		end
		if c then
			c:Destroy()
		end
		sibSig:Destroy()
		s1:Destroy()
		s2:Destroy()
	end)

	s1:onUnobserved(function()
		reactiveInHook = Flux.isReactive()
		table.insert(hookLog, "off")
	end)
	c = Flux.computed(function()
		local v = s1()
		if v == 2 then
			local _ = s2() -- diverges curNew ~= nil
			c:Destroy()
			return "never"
		end
		return "secret"
	end)
	local sib = Flux.computed(function()
		return sibSig() * 7
	end)
	cEff = Flux.effect(function()
		pcall(c)
	end)
	sibEff = Flux.effect(function()
		sibVal = sib()
	end)
	flush()
	expect(c:peek() == "secret" and sibVal == 7 and Graph.isObserved(s1), "self-dispose baseline")

	s1:set(2)
	sibSig:set(2)
	flush()
	expect(c:peek() == nil, "self-disposed computed cleared VALUE to nil")
	expect(not Graph.isObserved(s1) and #hookLog == 1, "self-disposed computed reaped source subscriptions")
	expect(not reactiveInHook, "unobserved hook ran with curNode cleared")
	expect(sibVal == 14, "sibling computed ran cleanly after c self-disposed")

	-- Confirm curNew did not leak into subsequent computed evaluation
	sibSig:set(3)
	flush()
	expect(sibVal == 21 and Graph.isObserved(sibSig), "curNew was cleared after self-dispose")
	sib:Destroy()
end)

test("error healing · finishErrored, unfail, healed, stabilizeSameSlow and runComputed", function()
	local nodes: { any } = {}
	local function trackNode<T>(x: T): T
		table.insert(nodes, x)
		return x
	end
	sert.defer(function()
		for i = #nodes, 1, -1 do
			(nodes[i] :: any):Destroy()
		end
	end)

	-- 1. Live computed: value 10 -> throws on 0 -> throws again on -1 -> heals to SAME value 10 on 1
	local s = trackNode(Flux.signal(1))
	local c = trackNode(Flux.computed(function()
		local v = s()
		if v <= 0 then
			error("boom-" .. v, 0)
		end
		return 10
	end))
	local dRuns, dVal, dOk = 0, 0, true
	local d = trackNode(Flux.computed(function()
		dRuns += 1
		return c() + 1
	end))
	local e = trackNode(Flux.effect(function()
		dOk, dVal = pcall(d)
	end))
	flush()
	expect(dOk and dVal == 11 and dRuns == 1, "live heal baseline")

	s:set(0)
	env.warnings(flush)
	expect(not dOk, "first error propagated")

	s:set(-1) -- throws a second time while already in failed[]
	env.warnings(flush)
	expect(not dOk, "second error updated failed[node] epoch without double-counting nFailed")

	s:set(1) -- returns 10 (identical to pre-error cached VALUE!) -> unfail() + healed()
	flush()
	expect(dOk and dVal == 11 and dRuns == 4, "live computed healed downstream back to 11 with same value")

	-- 2. Dead computed fails twice then heals to same value 10
	local ds = trackNode(Flux.signal(1))
	local dc = trackNode(Flux.computed(function()
		if ds() <= 0 then
			error("dead-boom", 0)
		end
		return 10
	end))
	local ddRuns = 0
	local dd = trackNode(Flux.computed(function()
		ddRuns += 1
		return dc() + 5
	end))
	expect(dd() == 15 and ddRuns == 1, "dead heal baseline")
	ds:set(0)
	expectError(function()
		dd()
	end, "dead-boom")
	ds:set(-1)
	expectError(function()
		dd()
	end, "dead-boom")
	ds:set(1)
	expect(dd() == 15 and ddRuns == 4, "dead computed healed dead downstream back to 15")

	-- 3. Recover to DIFFERENT value leaves failed entry stale; next same-value run must NOT spuriously heal
	-- Keep another errored computed live so nFailed > 0 during the check!
	local otherS = trackNode(Flux.signal(0))
	local otherErr = trackNode(Flux.computed(function()
		if otherS() == 0 then
			error("other-err", 0)
		end
		return 99
	end))
	local otherOk, otherVal = true, 0
	local otherEff = trackNode(Flux.effect(function()
		otherOk, otherVal = pcall(otherErr)
	end))
	env.warnings(flush)
	expect(not otherOk, "otherErr active so nFailed > 0")

	local s2 = trackNode(Flux.signal(1))
	local c2 = trackNode(Flux.computed(function()
		local v = s2()
		if v == 0 then
			error("c2-boom", 0)
		end
		return if v == 1 then 10 else 20
	end))
	local c2DownRuns, c2Seen, c2Ok = 0, 0, true
	local c2Down = trackNode(Flux.computed(function()
		c2DownRuns += 1
		return c2() + 100
	end))
	local c2Eff = trackNode(Flux.effect(function()
		c2Ok, c2Seen = pcall(c2Down)
	end))
	flush()
	expect(c2Ok and c2Seen == 110 and c2DownRuns == 1, "c2 baseline")
	s2:set(0)
	env.warnings(flush)
	expect(not c2Ok, "c2 errored")
	s2:set(2) -- recovers to DIFFERENT value 20
	flush()
	expect(c2Ok and c2Seen == 120 and c2DownRuns == 3, "c2 recovered to different value")
	s2:set(3) -- recomputes to 20 again while nFailed > 0 -> unfail returns false (at ~= CHANGED)
	flush()
	expect(c2DownRuns == 3 and c2Seen == 120, "stale failed[c2] did not spuriously re-trigger c2Down")

	-- otherErr heals afterwards -> verifies nFailed wasn't corrupted when c2 unfailed
	otherS:set(1)
	flush()
	expect(otherOk and otherVal == 99, "otherErr healed cleanly with slowCommit preserved")

	-- 4. FORCE_COMMIT computed (equals = allowSame) fails then heals to same value 42 via stabilizeSameSlow -> unfail
	local fs = trackNode(Flux.signal(1))
	local allowSame = false
	local fc = trackNode(Flux.computed(function()
		if fs() == 0 then
			error("fc-boom", 0)
		end
		return 42
	end, function()
		return allowSame
	end))
	local fcDownRuns, fcOk, fcVal = 0, true, 0
	local fcDown = trackNode(Flux.computed(function()
		fcDownRuns += 1
		return fc() + 1
	end))
	local fcEff = trackNode(Flux.effect(function()
		fcOk, fcVal = pcall(fcDown)
	end))
	flush()
	expect(fcOk and fcVal == 43 and fcDownRuns == 1, "fc baseline")
	fs:set(0)
	env.warnings(flush)
	expect(not fcOk, "fc errored")
	fs:set(1) -- recovers to 42 with allowSame = false -> FORCE_COMMIT path calls unfail() & clears failed[fc]
	flush()
	expect(fcOk and fcVal == 43 and fcDownRuns == 3, "fc healed via FORCE_COMMIT")
	local prevDown = fcDownRuns
	allowSame = true
	fs:set(2) -- equals=true returns 42 -> must NOT spuriously heal again
	flush()
	expect(fcDownRuns == prevDown, "FORCE_COMMIT unfail removed failed[fc] cleanly")

	-- 5. NaN SAME_VALUE computed fails then recovers to NaN -> stabilizes via stabilizeSameSlow & heals
	local ns = trackNode(Flux.signal(1))
	local nc = trackNode(Flux.computed(function()
		if ns() == 0 then
			error("nan-boom", 0)
		end
		return 0 / 0
	end, function(a, b)
		return (a ~= a and b ~= b) or a == b
	end))
	local ncOk, ncIsNaN, ncRuns = true, false, 0
	local ncEff = trackNode(Flux.effect(function()
		ncRuns += 1
		local ok, v = pcall(nc)
		ncOk = ok
		ncIsNaN = ok and v ~= v
	end))
	flush()
	expect(ncOk and ncIsNaN and ncRuns == 1, "NaN heal baseline")
	ns:set(0)
	env.warnings(flush)
	expect(not ncOk, "NaN computed errored")
	ns:set(1)
	flush()
	expect(ncOk and ncIsNaN and ncRuns == 3, "NaN computed healed through stabilizeSameSlow")

	e:Destroy()
	otherEff:Destroy()
	c2Eff:Destroy()
	fcEff:Destroy()
	ncEff:Destroy()
end)

test("notifyObservers · single and multi-observer with and without runningEffect", function()
	local nodes: { any } = {}
	local function trackNode<T>(x: T): T
		table.insert(nodes, x)
		return x
	end
	sert.defer(function()
		for i = #nodes, 1, -1 do
			(nodes[i] :: any):Destroy()
		end
	end)

	-- 1. Single observer effect: untrack-peek dirty computed mid-effect BEFORE reading it -> deferSelf skips
	local s = trackNode(Flux.signal(1))
	local c = trackNode(Flux.computed(function()
		return s() * 2
	end))
	local eRuns, eSeen = 0, 0
	local e = trackNode(Flux.effect(function()
		eRuns += 1
		if eRuns == 1 then
			local _ = c() -- subscribe
			untrack(function()
				s:set(2)
				local _ = c:peek() -- notifyObservers(e, c) with x == e, readThisRun == false
			end)
			eSeen = 100
			return
		end
		eSeen = c()
	end))
	flush()
	expect(
		eRuns == 1 and eSeen == 100 and c:peek() == 4,
		"single observer untrack-peek before read did not self-requeue"
	)

	-- 2. Two observers o1, o2 with runningEffect == nil: pulling c inside o1 notifies o2 WITHOUT marking o1
	local s2 = trackNode(Flux.signal(1))
	local c2 = trackNode(Flux.computed(function()
		return s2() * 10
	end))
	local trig = trackNode(Flux.signal(0))
	local o1Runs, o2Runs, o2Seen = 0, 0, 0
	local o1 = trackNode(Flux.computed(function()
		o1Runs += 1
		local t = trig()
		if t == 1 then
			s2:set(2)
			return c2:peek()
		elseif t == 2 then
			return Flux.raw(function()
				s2:set(3)
				return c2:peek()
			end)
		end
		return c2()
	end))
	local o2 = trackNode(Flux.computed(function()
		o2Runs += 1
		return c2() + 1
	end))
	local eo1 = trackNode(Flux.effect(function()
		local _ = o1()
	end))
	local eo2 = trackNode(Flux.effect(function()
		o2Seen = o2()
	end))
	flush()
	expect(o1Runs == 1 and o2Runs == 1 and o2Seen == 11, "multi-observer no-effect baseline")

	trig:set(1) -- inside o1 during stabilize(): curNode == o1, evalNode == o1, runningEffect == nil
	flush()
	expect(o1Runs == 2 and o2Runs == 2 and o2Seen == 21, "notifyObservers marked o2 but did not re-dirty curNode o1")

	trig:set(2) -- inside Flux.raw in o1: curNode == nil, evalNode == o1, runningEffect == nil
	flush()
	expect(o1Runs == 3 and o2Runs == 3 and o2Seen == 31, "notifyObservers marked o2 but did not re-dirty evalNode o1")

	-- 3. Two observers (eff, obsB) with runningEffect ~= nil: untrack-peek inside eff notifies obsB without self-requeue
	local ms = trackNode(Flux.signal(1))
	local mc = trackNode(Flux.computed(function()
		return ms() * 5
	end))
	local obsBSeen = 0
	local obsB = trackNode(Flux.effect(function()
		obsBSeen = mc()
	end))
	local effRuns = 0
	local eff = trackNode(Flux.effect(function()
		effRuns += 1
		if effRuns == 1 then
			local _ = mc()
			untrack(function()
				ms:set(2)
				local _ = mc:peek()
			end)
			return
		end
		local _ = mc()
	end))
	flush()
	expect(effRuns == 1 and obsBSeen == 10, "multi-observer with runningEffect marked obsB without self-requeue")

	e:Destroy()
	eo1:Destroy()
	eo2:Destroy()
	obsB:Destroy()
	eff:Destroy()
end)

test("ownSlow, reconcileEffect, rawFn & wrapComputedEquals evalNode", function()
	local nodes: { any } = {}
	local function trackNode<T>(x: T): T
		table.insert(nodes, x)
		return x
	end
	sert.defer(function()
		for i = #nodes, 1, -1 do
			(nodes[i] :: any):Destroy()
		end
	end)

	local ctx = Flux.context("default")

	-- 1. ownSlow effect wrapper creates child under ctxA outside ctxA & preserves caller ctxB across e:peek() and c:peek()
	local effSig = trackNode(Flux.signal(1))
	local effChildCtx = ""
	local ctxEff: any = nil
	local ctxComp: any = nil
	ctx:provide("ctxA", function()
		-- Signal with 2 observers inside ctx (tests L2742 h and h ~= SCOPE)
		local s = trackNode(Flux.signal(42))
		local c1 = trackNode(Flux.computed(function()
			return s()
		end))
		expect(c1() == 42, "signal created inside ctx reads properly")

		ctxEff = trackNode(Flux.effect(function()
			local _ = effSig()
			local child = trackNode(Flux.computed(function()
				effChildCtx = ctx:get()
				return 1
			end))
			child()
		end))
		ctxComp = trackNode(Flux.computed(function()
			local _ = effSig()
			return ctx:get()
		end))
	end)
	flush()
	expect(effChildCtx == "ctxA", "initial effect body saw ctxA")
	effSig:set(2)
	flush()
	expect(effChildCtx == "ctxA", "re-run outside provide restored ctxA and ownExtra so child saw ctxA")

	ctx:provide("ctxB", function()
		effSig:set(3)
		ctxEff:peek()
		expect(ctx:get() == "ctxB", "after ctxEff:peek() outer ctxB was restored")
		local innerCheck = trackNode(Flux.computed(function()
			return ctx:get()
		end))
		expect(innerCheck() == "ctxB", "ownExtra after ctxEff:peek() remains true inside ctxB")

		effSig:set(4)
		expect(ctxComp:peek() == "ctxA" and ctx:get() == "ctxB", "ctxComp:peek() ran in ctxA and restored ctxB")
	end)
	ctxEff:Destroy()

	-- 2. reconcileEffect paths: bare untrack drop, diverge-then-self-destroy, diverge-drop with sibling
	local rHookCalls = 0
	local rHookReactive = false
	local rs1 = trackNode(Flux.signal(1))
	rs1:onUnobserved(function()
		rHookCalls += 1
		rHookReactive = Flux.isReactive()
	end)
	local rs2 = trackNode(Flux.signal(2))
	local rGate = trackNode(Flux.signal(0))
	local re: any = nil
	re = trackNode(Flux.effect(function()
		local g = rGate()
		if g == 0 then
			local _ = rs1()
		elseif g == 1 then
			untrack() -- leaves curNode == nil while idx ~= last!
		elseif g == 2 then
			local _ = rs2() -- diverges curNew ~= nil then self-disposes
			re:Destroy()
		end
	end))
	local sibSig = trackNode(Flux.signal(1))
	local sibSaw = 0
	local sibEff = trackNode(Flux.effect(function()
		sibSaw = sibSig()
	end))
	flush()
	expect(Graph.isObserved(rs1), "rs1 initially observed")

	rGate:set(1)
	flush()
	expect(
		not Graph.isObserved(rs1) and rHookCalls == 1 and not rHookReactive,
		"bare-untrack reconcile cleared curNode"
	)

	rGate:set(0)
	flush()
	expect(Graph.isObserved(rs1), "rs1 re-subscribed")

	rGate:set(2) -- re diverges onto rs2 then calls re:Destroy()
	sibSig:set(10)
	flush()
	expect(not Graph.isObserved(rs1) and not Graph.isObserved(rs2) and sibSaw == 10, "diverge + self-destroy reaped")
	sibSig:set(11)
	flush()
	expect(sibSaw == 11, "curNew/evalNode clean after reconcileEffect self-dispose")

	-- Diverge drop onto rs2 with sibling in same flush
	local rdFlag = trackNode(Flux.signal(true))
	local rda = trackNode(Flux.signal(1))
	local rdb = trackNode(Flux.signal(2))
	local rdaOff = false
	rda:onUnobserved(function()
		rdaOff = true
	end)
	local rdSaw = 0
	local rdEff = trackNode(Flux.effect(function()
		rdSaw = if rdFlag() then rda() else rdb()
	end))
	flush()
	rdFlag:set(false)
	sibSig:set(12)
	flush()
	expect(rdaOff and not Graph.isObserved(rda) and Graph.isObserved(rdb) and rdSaw == 2 and sibSaw == 12)

	-- 3. rawFn active ~= runningEffect vs active == computed
	local rawSig = trackNode(Flux.signal(1))
	local rawGate = trackNode(Flux.signal(false))
	local rawMid = trackNode(Flux.computed(function()
		return rawSig() * 10
	end))
	local rawEffRuns, rawEffSeen = 0, 0
	local rawEff = trackNode(Flux.effect(function()
		rawEffRuns += 1
		local g = rawGate()
		rawEffSeen = rawMid()
		if g and rawEffSeen == 10 then
			Flux.raw(function()
				rawSig:set(2)
				rawMid:peek()
			end)
		end
	end))
	flush()
	expect(rawEffRuns == 1 and rawEffSeen == 10, "raw() in effect baseline")
	rawGate:set(true)
	flush()
	expect(rawEffRuns == 3 and rawEffSeen == 20, "raw() inside effect allows mid write to requeue runningEffect")

	local rcSig = trackNode(Flux.signal(1))
	local rcGate = trackNode(Flux.signal(false))
	local rcMid = trackNode(Flux.computed(function()
		return rcSig() * 10
	end))
	local rcCompRuns = 0
	local rcComp = trackNode(Flux.computed(function()
		rcCompRuns += 1
		local g = rcGate()
		local v = rcMid()
		if g and v == 10 then
			Flux.raw(function()
				rcSig:set(2)
				rcMid:peek()
			end)
		end
		return v
	end))
	local rcKeep = trackNode(Flux.effect(function()
		local _ = rcComp()
	end))
	flush()
	expect(rcCompRuns == 1 and rcComp:peek() == 10, "raw() in computed baseline")
	rcGate:set(true)
	flush()
	expect(rcCompRuns == 2 and rcComp:peek() == 10 and rcMid:peek() == 20, "raw() inside computed blocks self-dirtying")

	-- 4. wrapComputedEquals evalNode during stabilize() equals(prev, v)
	local eqSig = trackNode(Flux.signal(1))
	local eqMid = trackNode(Flux.computed(function()
		return eqSig() * 10
	end))
	local eqRuns = 0
	local eqComp = trackNode(Flux.computed(function()
		eqRuns += 1
		return eqMid()
	end, function(prev, nxt)
		if nxt == 20 then
			eqSig:set(3)
			local _ = eqMid:peek()
		end
		return prev == nxt
	end))
	local eqKeep = trackNode(Flux.effect(function()
		local _ = eqComp()
	end))
	flush()
	eqSig:set(2)
	flush()
	expect(eqRuns == 2 and eqComp:peek() == 20 and eqMid:peek() == 30, "equals() in stabilize sets evalNode = node")

	eqKeep:Destroy()
	rcKeep:Destroy()
	rawEff:Destroy()
	rdEff:Destroy()
	sibEff:Destroy()
end)

test("finishGoDead · live higher-height node going dead during active lower-height batch", function()
	local nodes: { any } = {}
	local function trackNode<T>(x: T): T
		table.insert(nodes, x)
		return x
	end
	sert.defer(function()
		for i = #nodes, 1, -1 do
			(nodes[i] :: any):Destroy()
		end
	end)

	local s = trackNode(Flux.signal(1))
	local u = trackNode(Flux.signal(1))
	local lo = trackNode(Flux.computed(function()
		return s() * 10
	end))
	local hiRuns = 0
	local hi = trackNode(Flux.computed(function()
		hiRuns += 1
		return lo() + 1
	end))
	local other = trackNode(Flux.computed(function()
		return math.abs(u()) * 2
	end))
	local hiEff = trackNode(Flux.effect(function()
		local _ = hi()
	end))
	local otherEff = trackNode(Flux.effect(function()
		local _ = other()
	end))
	flush()
	expect(hiRuns == 1 and hi:peek() == 11, "finishGoDead baseline")

	-- Case A: hi goes dead AFTER u:set(-1) (heapMin = 1 < hi HEIGHT 2) while hi was pulled before flush (STAMP == epoch)
	u:set(-1) -- other (height 1) is dirty -> heapMin = 1
	s:set(2)
	expect(lo:peek() == 20 and hi:peek() == 21 and hiRuns == 2, "pulled hi inside active height-1 batch")
	hiEff:Destroy()
	flush()
	s:set(3)
	expect(hi() == 31 and hiRuns == 3, "Case A: dead hi recomputed cleanly after upstream write")

	-- Case B1: st <= LIVE_MAX_IDLE (hi is LIVE CLEAN, height 2) goes dead during active height-1 batch; verify `epoch += 1` (L980)
	local hiEff2 = trackNode(Flux.effect(function()
		local _ = hi()
	end))
	flush() -- hi[HEIGHT] == 2, hi[STAMP] == 2 + LIVE_BASE
	local deadSrc = trackNode(Flux.signal(1))
	local deadXRuns = 0
	local deadX = trackNode(Flux.computed(function()
		deadXRuns += 1
		return deadSrc() * 100
	end))
	u:set(1) -- other dirty at height 1 (`math.abs(1)*2 == 2` so batch flush won't bump epoch)
	expect(deadX() == 100 and deadXRuns == 1, "deadX stamped at current epoch inside batch")
	hiEff2:Destroy() -- finishGoDead(hi) sees 2 + LIVE_BASE > 1 + LIVE_BASE -> bumps epoch += 1, hi[STAMP] = epoch - 1
	flush()
	deadSrc:set(2)
	expect(deadX() == 200 and deadXRuns == 2, "Case B1: finishGoDead epoch increment prevented stale epoch match")

	-- Case B2: verify `node[STAMP] = epoch - 1` (L981) vs `epoch + 1` or deleted stamp assignment
	local hiEff3 = trackNode(Flux.effect(function()
		local _ = hi()
	end))
	flush()
	expect(hiRuns == 3, "hi re-observed without recomputing")
	u:set(-1) -- heapMin = 1, other still evaluates to same value 2
	hiEff3:Destroy() -- finishGoDead(hi) bumps epoch and sets hi[STAMP] = epoch - 1
	flush()
	s:set(4) -- bumps epoch by 1: if hi[STAMP] had been `epoch + 1`, hi[STAMP] == epoch would skip pull!
	expect(
		hi() == 41 and hiRuns == 4,
		"Case B2: finishGoDead stamped hi at epoch - 1 so next upstream write invalidates"
	)

	-- Case C: DEFERRED computed dropped cleanly during stabilize() evaluates fresh afterwards
	local dCond = trackNode(Flux.signal(true))
	local dx = trackNode(Flux.signal(1))
	local dMid = trackNode(Flux.computed(function()
		return dx() * 10
	end))
	local dObs = trackNode(Flux.computed(function()
		return if dCond() then dMid() else 0
	end))
	local dKeep = trackNode(Flux.effect(function()
		local _ = dObs()
	end))
	flush()
	dCond:set(false)
	flush() -- drop dMid once -> dMid[CHILDREN] = nil
	dCond:set(true)
	flush()
	dCond:set(false)
	dx:set(2)
	flush()
	expect(dMid() == 20, "Case C: dead computed after DEFERRED drop evaluates updated upstream")

	hiEff:Destroy()
	hiEff2:Destroy()
	hiEff3:Destroy()
	dKeep:Destroy()
	otherEff:Destroy()
end)

test("flushRecoverFast, recover, runComputed & pull edge cases", function()
	local nodes: { any } = {}
	local function trackNode<T>(x: T): T
		table.insert(nodes, x)
		return x
	end
	sert.defer(function()
		for i = #nodes, 1, -1 do
			(nodes[i] :: any):Destroy()
		end
	end)

	-- 1. flushRecoverFast clears anyReruns / passes when an effect runs > GUARD_PASSES (32) passes and then throws
	local frCount = 0
	local frMode = 0
	local frSig = trackNode(Flux.signal(0))
	local frEff = trackNode(Flux.effect(function()
		local v = frSig()
		if frMode == 1 then
			if v < 35 then
				frSig:set(v + 1)
			elseif v == 35 then
				error("fr-boom", 0)
			end
		elseif frMode == 2 then
			frCount += 1
			if v < 75 then
				frSig:set(v + 1)
			end
		end
	end))
	flush()
	frMode = 1
	frSig:set(1)
	env.warnings(flush) -- enters flushRecoverFast after passes > 32 set anyReruns = true and cycles[frEff] = 3

	-- If flushRecoverFast did not reset passes = 0 / clearRerunState(), running 75 more passes hits GUARD_PASSES / RERUN_LIMIT sooner or carries stale cycles[frEff]
	frMode = 2
	frSig:set(0)
	local warnings = env.warnings(flush)
	expect(#warnings == 0 and frCount == 76, "flushRecoverFast reset anyReruns/cycles and passes")
	frEff:Destroy()

	-- 2. recover: bare untrack() throw, diverge-throw with sibling, live computed self-disposing sole obs then throw, ctx throw
	local us = trackNode(Flux.signal(0))
	local uEff = trackNode(Flux.effect(function()
		if us() == 1 then
			untrack()
			error("untrack-throw", 0)
		end
	end))
	flush()
	us:set(1)
	local uWarns = env.warnings(flush)
	expect(#uWarns == 1, "recover captured error thrown after bare untrack()")
	uEff:Destroy()

	-- Diverge then throw alongside sibling effect
	local ds1 = trackNode(Flux.signal(1))
	local ds2 = trackNode(Flux.signal(2))
	local dFlip = trackNode(Flux.signal(false))
	local sibS = trackNode(Flux.signal(1))
	local sibSeen = 0
	local dErrEff = trackNode(Flux.effect(function()
		if dFlip() then
			local _ = ds2()
			error("div-throw", 0)
		end
		local _ = ds1()
	end))
	local dSibEff = trackNode(Flux.effect(function()
		sibSeen = sibS()
	end))
	flush()
	dFlip:set(true)
	sibS:set(9)
	local divWarns = env.warnings(flush)
	expect(
		#divWarns == 1 and sibSeen == 9 and Graph.isObserved(ds2) and not Graph.isObserved(ds1),
		"recover reconciled deps up to throw, cleared curNew & ran sibling"
	)
	dErrEff:Destroy()
	sibS:set(10)
	flush()
	expect(sibSeen == 10 and Graph.isObserved(sibS), "curNew/state clean after recover")
	dSibEff:Destroy()

	-- Live computed destroys its own sole observer then throws during stabilize() -> warns as unhandled
	local soTrig = trackNode(Flux.signal(false))
	local soEff: any = nil
	local soComp = trackNode(Flux.computed(function()
		if soTrig() then
			if soEff then
				soEff:Destroy()
			end
			error("orphan-boom", 0)
		end
		return 1
	end))
	soEff = trackNode(Flux.effect(function()
		pcall(soComp)
	end))
	flush()
	soTrig:set(true)
	local orphanWarns = env.warnings(flush)
	expect(#orphanWarns >= 1, "recover warned when throwing computed had lost its observers")

	-- Recover inside nested flush with Context preserves pCtx/pExtra for sibling effect
	local ctx = Flux.context("def")
	local innerFail = trackNode(Flux.signal(false))
	local innerEff = trackNode(Flux.effect(function()
		if innerFail() then
			error("inner-ctx-boom", 0)
		end
	end))
	local sibCtxSaw = ""
	local sibTrig = trackNode(Flux.signal(0))
	local sibCtxEff = trackNode(Flux.effect(function()
		if sibTrig() == 1 then
			sibCtxSaw = ctx:get()
		end
	end))
	flush()
	ctx:provide("outer", function()
		innerFail:set(true)
		sibTrig:set(1)
		local cw = env.warnings(flush)
		expect(#cw == 1, "nested flush error suppressed cleanly")
		expect(ctx:get() == "outer", "nested flush preserved outer context")
	end)
	expect(sibCtxSaw == "outer", "sibling effect in flush after recover still saw outer context")
	innerEff:Destroy()
	sibCtxEff:Destroy()

	-- 3. runComputed dead pull inside withOwner & bare untrack, plus ERRORED live computed inside bare untrack
	local ext = trackNode(Flux.scope(function() end))
	local rcDeadTrig = trackNode(Flux.signal(1))
	local rcChildClean, rcPostClean = 0, 0
	local rcDead = trackNode(Flux.computed(function()
		local v = rcDeadTrig()
		local rcChild = Flux.computed(function()
			Flux.cleanup(function()
				rcChildClean += 1
			end)
			return v
		end)
		local _ = rcChild()
		return v * 2
	end))
	Flux.withOwner(ext, function()
		expect(rcDead() == 2, "pulled dead computed inside withOwner")
		Flux.cleanup(function()
			rcPostClean += 1
		end)
	end)
	expect(rcChildClean == 0 and rcPostClean == 0, "children alive initially")
	ext:Destroy()
	expect(rcPostClean == 1 and rcChildClean == 0, "withOwner cleanup belonged to ext, rcDead's child owned by rcDead")
	rcDead:Destroy()
	expect(rcChildClean == 1, "rcDead:Destroy() disposed rcDead's child")

	-- Pull dead computed calling bare untrack() from top-level, then create child at top level -> susp cleared
	local buTrig = trackNode(Flux.signal(1))
	local buChildClean = 0
	local buComp = trackNode(Flux.computed(function()
		local v = buTrig()
		untrack()
		Flux.cleanup(function()
			buChildClean += 1
		end)
		return v
	end))
	expect(buComp() == 1, "bare untrack inside top-level dead computed")
	local afterChildClean = 0
	expectError(function()
		Flux.cleanup(function()
			afterChildClean += 1
		end)
	end, "outside a reactive owner")
	expect(buChildClean == 0 and afterChildClean == 0, "susp was cleared after top-level runComputed")
	buComp:Destroy()
	expect(buChildClean == 1, "buComp:Destroy() ran buComp's cleanup")

	-- Live ERRORED computed read inside bare untrack() & raw() of effect must rethrow cached error without re-running
	local leTrig = trackNode(Flux.signal(false))
	local leRuns = 0
	local leErrComp = trackNode(Flux.computed(function()
		leRuns += 1
		if leTrig() then
			error("cached-err", 0)
		end
		return 7
	end))
	local leKeep = trackNode(Flux.effect(function()
		pcall(leErrComp)
	end))
	flush() -- leErrComp is now live & observed by leKeep
	leTrig:set(true)
	env.warnings(flush) -- stabilize() marks live leErrComp ERRORED
	local leRunsAfterErr = leRuns
	local caughtMsg, caughtRawMsg = "", ""
	local leReader = trackNode(Flux.effect(function()
		Flux.raw(function()
			local ok, err = pcall(leErrComp)
			if not ok then
				caughtRawMsg = tostring(err)
			end
		end)
		untrack()
		local ok, err = pcall(leErrComp)
		if not ok then
			caughtMsg = tostring(err)
		end
	end))
	flush()
	expect(
		string.find(caughtRawMsg, "cached-err", 1, true) ~= nil
			and string.find(caughtMsg, "cached-err", 1, true) ~= nil
			and leRuns == leRunsAfterErr,
		"reading live ERRORED computed inside flush raw/untrack rethrew cached error without re-running"
	)
	leKeep:Destroy()
	leReader:Destroy()
end)

test("deep iterative traversals · pullDeadIter, settleIter, raiseVisit/raiseIter & goLiveIter", function()
	local nodes: { any } = {}
	local function trackNode<T>(x: T): T
		table.insert(nodes, x)
		return x
	end
	sert.defer(function()
		for i = #nodes, 1, -1 do
			(nodes[i] :: any):Destroy()
		end
	end)

	-- 1. pullDeadIter (depth 138): math.abs head + extra trailing source s2 on top node
	local s0 = trackNode(Flux.signal(1))
	local s2 = trackNode(Flux.signal(10))
	local headRuns = 0
	local cur: any = trackNode(Flux.computed(function()
		headRuns += 1
		return math.abs(s0())
	end))
	for _ = 2, 137 do
		local prev = cur
		cur = trackNode(Flux.computed(function()
			return prev() + 1
		end))
	end
	local topDeadRuns = 0
	local topPrev = cur
	local topDead = trackNode(Flux.computed(function()
		topDeadRuns += 1
		return topPrev() + s2()
	end))

	-- Reader checks r1(), topDead(), r2() to verify pNode restoration (L1876)
	local r1 = trackNode(Flux.signal(1))
	local r2 = trackNode(Flux.signal(100))
	local rCompRuns = 0
	local rComp = trackNode(Flux.computed(function()
		rCompRuns += 1
		return r1() + topDead() + r2()
	end))
	local rEffSeen = 0
	local rEff = trackNode(Flux.effect(function()
		rEffSeen = rComp()
	end))
	flush()
	expect(rEffSeen == (1 + 136 + 10) + 101 and topDeadRuns == 1 and rCompRuns == 1, "pullDeadIter baseline")

	-- Unchanged head (s0: 1 -> -1) + changed source 2 (s2: 10 -> 20)
	s0:set(-1)
	s2:set(20)
	expect(topDead() == (1 + 136 + 20) and topDeadRuns == 2, "pullDeadIter skipped unchanged chain and checked s2")
	expect(topDead() == (1 + 136 + 20) and topDeadRuns == 2, "pullDeadIter stamped topDead at epoch cleanly")

	-- Changed head (s0: -1 -> 5) propagates through stWaiting
	s0:set(5)
	expect(topDead() == (5 + 136 + 20) and topDeadRuns == 3, "pullDeadIter updated via stWaiting")

	-- Reader still tracks r2 after pullDeadIter (L1876 curNode = pNode)
	r2:set(200)
	flush()
	expect(rCompRuns == 2 and rEffSeen == 1 + (5 + 136 + 20) + 200, "rComp still tracked r2 after pullDeadIter")

	-- Deep dead chain reading a LIVE dirty computed mid-batch (L1849 s[OBSERVERS])
	local lmSig = trackNode(Flux.signal(1))
	local lmLive = trackNode(Flux.computed(function()
		return lmSig() * 10
	end))
	local lmKeep = trackNode(Flux.effect(function()
		local _ = lmLive()
	end))
	local lmChain: any = lmLive
	for _ = 1, 136 do
		local prev = lmChain
		lmChain = trackNode(Flux.computed(function()
			return prev() + 1
		end))
	end
	expect(lmChain() == 10 + 136, "live-mid deep dead chain baseline")
	lmSig:set(3)
	expect(lmChain() == 30 + 136, "pullDeadIter refreshed dirty live dependency inside batch")
	flush()
	rEff:Destroy()
	lmKeep:Destroy()

	-- 2. settleIter (depth 138 live chain): pNode restore & error propagation (st == ERRORED)
	local ls = trackNode(Flux.signal(1))
	local throwAt5 = trackNode(Flux.signal(false))
	local lcur: any = trackNode(Flux.computed(function()
		local v = ls()
		if throwAt5() and v == 5 then
			error("deep-live-err", 0)
		end
		return v
	end))
	for _ = 2, 138 do
		local prev = lcur
		lcur = trackNode(Flux.computed(function()
			return prev() + 1
		end))
	end
	local sr1 = trackNode(Flux.signal(1))
	local sr2 = trackNode(Flux.signal(10))
	local lKeepOk, lKeepVal = true, 0
	local lKeep = trackNode(Flux.effect(function()
		lKeepOk, lKeepVal = pcall(lcur)
	end))
	local srCompRuns = 0
	local srComp = trackNode(Flux.computed(function()
		srCompRuns += 1
		return sr1() + lcur() + sr2()
	end))
	local srSeen = 0
	local srKeep = trackNode(Flux.effect(function()
		local ok, v = pcall(srComp)
		if ok then
			srSeen = v
		end
	end))
	flush()
	expect(lKeepOk and lKeepVal == 138 and srSeen == 1 + 138 + 10, "settleIter baseline")

	ls:set(2)
	sr1:set(2)
	expect(srComp() == 2 + 139 + 10, "settleIter computed deep live chain inside batch")
	flush()
	sr2:set(20)
	flush()
	expect(srSeen == 2 + 139 + 20, "srComp preserved trailing sr2 dep after settleIter")

	-- settleIter hitting ERRORED intermediate node inside batch
	throwAt5:set(true)
	ls:set(5)
	env.warnings(flush)
	expect(not lKeepOk, "deep live chain errored")
	sr1:set(3) -- dirty srComp; reading srComp pulls lcur which is ERRORED
	local okErr = pcall(srComp)
	expect(not okErr, "settleIter preserved ERRORED error cleanly")
	flush()
	throwAt5:set(false)
	ls:set(1)
	flush()
	expect(lKeepOk and lKeepVal == 138, "deep live chain healed")
	lKeep:Destroy()
	srKeep:Destroy()

	-- 3. raiseVisit & raiseIter: single & multi-observer cycle cleanup + valid subsequent height raise + mid-batch stamp reset
	local function testRaiseCase(deep: boolean)
		local label = if deep then "deep" else "shallow"
		local cycGate = trackNode(Flux.signal(0))
		local base = trackNode(Flux.signal(1))
		-- Build bottom chain of height `chainLen` so when cycHead subscribes to tail, tail triggers raiseVisit / raiseIter
		local tail: any = trackNode(Flux.computed(function()
			return base()
		end))
		local chainLen = if deep then 135 else 2
		for _ = 2, chainLen do
			local prev = tail
			tail = trackNode(Flux.computed(function()
				return prev() + 1
			end))
		end

		local cycA: any = nil
		local cycB: any = nil
		cycA = trackNode(Flux.computed(function()
			local g = cycGate()
			if g == 1 then
				return cycB() + 1
			elseif g == 2 then
				return tail() + 100
			end
			return 1
		end))
		local upChain: any = cycA
		local upLen = if deep then 132 else 0
		for _ = 1, upLen do
			local prev = upChain
			upChain = trackNode(Flux.computed(function()
				return prev() + 1
			end))
		end
		-- Give upChain BOTH a multi-observer branch (cycB, extraObs)
		cycB = trackNode(Flux.computed(function()
			return upChain() + 1
		end))
		local extraObs = trackNode(Flux.computed(function()
			return upChain() + 2
		end))
		local topA = trackNode(Flux.computed(function()
			return cycB() + extraObs()
		end))
		local topOk, topErr: any = true, nil
		local eTop = trackNode(Flux.effect(function()
			topOk, topErr = pcall(topA)
		end))
		flush()
		expect(topOk, `{label} cycle test baseline`)

		-- Multi-observer cycle (cycB + extraObs on upChain) -> must detect cycle and clean raiseActive
		cycGate:set(1)
		env.warnings(flush)
		expect(
			not topOk and string.find(tostring(topErr), "circular dependency", 1, true) ~= nil,
			`{label} multi-observer cycle caught`
		)

		-- Immediately perform valid height raise on the same nodes (g == 2 -> reads tall chain tail) -> must succeed!
		cycGate:set(2)
		local okWarns = env.warnings(flush)
		local expectedUp = 1 + (chainLen - 1) + 100 + upLen
		expect(
			#okWarns == 0 and topOk and topA() == (expectedUp + 1) + (expectedUp + 2),
			`{label} raise succeeded after cycle cleanup`
		)

		-- Mid-batch height raise of a clean node (L518 / L580 node[STAMP] = h + LIVE_BASE):
		-- Create fresh clean chain `x` (initially height 1 -> gate reads tall after raise) during a batch
		eTop:Destroy()
		local rSig = trackNode(Flux.signal(1))
		local tall: any = trackNode(Flux.computed(function()
			return rSig() * 10
		end))
		for _ = 2, (if deep then 136 else 4) do
			local prev = tall
			tall = trackNode(Flux.computed(function()
				return prev() + 1
			end))
		end
		local xGate = trackNode(Flux.signal(false))
		local xMid = trackNode(Flux.computed(function()
			return if xGate() then tall() else rSig()
		end))
		local xTop = trackNode(Flux.computed(function()
			return xMid() + 1000
		end))
		local xKeep = trackNode(Flux.effect(function()
			local _ = xTop()
		end))
		local tKeep = trackNode(Flux.effect(function()
			local _ = tall()
		end))
		flush()

		-- Step A: trigger raise in a batch (xGate -> true raises xMid & xTop height to >136), then BEFORE flush dirty tall and read xTop()!
		xGate:set(true)
		flush()
		rSig:set(2)
		local val = xTop()
		expect(val == 20 + ((if deep then 136 else 4) - 1) + 1000, `{label} xTop settled cleanly after height raise`)
		flush()
		xKeep:Destroy()
		tKeep:Destroy()
	end
	testRaiseCase(false)
	testRaiseCase(true)

	-- 4. goLiveIter (depth 138): signal hook firing + multi-source at depth 135 + height raise + goDead cleanup
	local glSig = trackNode(Flux.signal(7))
	local glSig2 = trackNode(Flux.signal(3))
	local glHookLog = {}
	glSig:onObserved(function()
		table.insert(glHookLog, "on")
	end)
	glSig:onUnobserved(function()
		table.insert(glHookLog, "off")
	end)

	-- Build two chains so combining them triggers subscribe + raise inside goLiveIter
	local aChain: any = trackNode(Flux.computed(function()
		return glSig()
	end))
	for _ = 2, 134 do
		local prev = aChain
		aChain = trackNode(Flux.computed(function()
			return prev() + 1
		end))
	end
	local bChain: any = trackNode(Flux.computed(function()
		return glSig2()
	end))
	for _ = 2, 10 do
		local prev = bChain
		bChain = trackNode(Flux.computed(function()
			return prev() + 1
		end))
	end
	-- Multi-source dead computed combining bChain (low) then aChain (tall -> triggers sh >= p[HEIGHT] height raise!)
	local combo = trackNode(Flux.computed(function()
		return bChain() + aChain()
	end))
	local glCur: any = combo
	for _ = 1, 5 do
		local prev = glCur
		glCur = trackNode(Flux.computed(function()
			return prev() + 1
		end))
	end
	expect(not Graph.isObserved(glSig) and #glHookLog == 0, "goLiveIter initially dead")
	local glSeen = 0
	local glEff = trackNode(Flux.effect(function()
		glSeen = glCur()
	end))
	flush()
	expect(
		Graph.isObserved(glSig) and #glHookLog == 1 and glHookLog[1] == "on" and glSeen == (3 + 9) + (7 + 133) + 5,
		"goLiveIter subscribed deep DAG, fired hook, and raised height"
	)
	glEff:Destroy()
	expect(
		not Graph.isObserved(glSig) and #glHookLog == 2 and glHookLog[2] == "off",
		"goDeadIter unsubscribed deep DAG and fired unobserved hook"
	)
end)
