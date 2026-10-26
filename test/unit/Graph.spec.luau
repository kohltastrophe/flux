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
local rtest = sert.rtest
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
	s:onObserved(function()
		table.insert(log, "on")
	end)
	s:onUnobserved(function()
		table.insert(log, "off")
	end)
	local c = Flux.computed(function()
		return s() + 1
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
	flush()
	expect(table.concat(log, ",") == "on", "observed once, though two effects depend on it")
	scope:Destroy()
	expect(table.concat(log, ",") == "on,off", "unobserved once")
	s(1)
	expect(c() == 2, "still readable")
end)

test("onObserved · a computed's hooks follow the effects that read it", function()
	local log = {}
	local s = Flux.signal(0)
	local gate = Flux.signal(true)
	local c = Flux.computed(function()
		return s() * 2
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
	flush()
	gate(false)
	flush()
	gate(true)
	flush()
	expect(table.concat(log, ",") == "on,off,on", "follows the branch: " .. table.concat(log, ","))
	scope:Destroy()
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
	expect(c().name == "b", "a reader pulling gets the new object")
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
end)

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
	expect(s:get() == nil, "nil fallback")
end)

test("safe · a recovery fn that throws re-raises its own error unchanged", function()
	local ok, caught = pcall(function()
		return Flux.safe(function(): string
			error("inner")
		end, function(): string
			error("handler boom", 0)
		end):get()
	end)
	expect(not ok and caught == "handler boom", `the handler's message, not a wrapped copy (got {caught})`)

	local errObj = { code = 500 }
	local okTable, caughtTable = pcall(function()
		return Flux.safe(function(): string
			error("inner")
		end, function(): string
			error(errObj)
		end):get()
	end)
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
			sert.eq(cleanups, runs - 1, "every earlier run's cleanup ran before the next run")
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
end, { runs = 100, exhaustive = { size = 2 } })

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

return {}
