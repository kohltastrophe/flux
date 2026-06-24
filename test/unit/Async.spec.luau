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
local new = Flux.Graph.new
local flush = Flux.flush
local Async = Flux.async

test("async · source change re-triggers; the fetcher's own reads are untracked", function()
	-- dependencies arrive only through the SOURCE; nothing the (untracked) fetcher
	-- reads becomes a dependency, avoiding the "which reads happened pre-yield?" trap
	local src = new(1)
	local other = new(10)
	local fetchRuns = 0
	local fetchThread
	local a = Async(src, function(v)
		fetchRuns += 1
		fetchThread = coroutine.running()
		coroutine.yield()
		return v + other:get() -- read inside the fetcher: must NOT be a dependency
	end)
	flush()
	expect(fetchRuns == 1 and a.loading:get() == true, "fetch starts on flush")
	coroutine.resume(fetchThread)
	expect(a.loading:get() == false and a.data:get() == 11, "fetch resolves (1 + 10)")
	other:set(20)
	flush()
	expect(fetchRuns == 1, "a read inside the fetcher is not a dependency")
	src:set(2)
	flush()
	expect(fetchRuns == 2, "source change re-triggers the fetch")
	coroutine.resume(fetchThread)
	expect(a.data:get() == 22, "refetch resolves with the new source value (2 + 20)")
end)

test("async · fetcher erroring synchronously sets error; source change recovers", function()
	local gate = new(1)
	local fetchRuns = 0
	local a = Async(gate, function(g)
		fetchRuns += 1
		if g == 1 then
			error("sync fetch failure")
		end
		return g * 10
	end)
	flush()
	expect(
		fetchRuns == 1 and a.error:get() ~= nil and a.loading:get() == false and a.data:get() == nil,
		"error node set, loading false, data nil"
	)
	gate:set(2)
	flush()
	expect(
		fetchRuns == 2 and a.data:get() == 20 and a.error:get() == nil and a.loading:get() == false,
		"source change re-triggers, recovers"
	)
end)

test("async · mutate sets data without fetching and drops in-flight fetch", function()
	local source = new(1)
	local fetchRuns = 0
	local fetchThread
	local a = Async(source, function(v)
		fetchRuns += 1
		fetchThread = coroutine.running()
		coroutine.yield()
		return v * 10
	end)
	flush()
	expect(fetchRuns == 1 and a.loading:get() == true, "initial fetch in flight")
	a:mutate(999)
	expect(a.data:get() == 999, "mutate writes data immediately")
	expect(a.loading:get() == false, "mutate clears loading")
	expect(fetchRuns == 1, "mutate does not trigger a fetch")
	coroutine.resume(fetchThread) -- resolve the stale in-flight fetch
	expect(a.data:get() == 999, "stale in-flight fetch is dropped, mutate value kept")
end)

test("async · refetch re-runs with the current source value, no source write", function()
	local source = new(5)
	local fetchRuns = 0
	local seen = {}
	local a = Async(source, function(v)
		fetchRuns += 1
		seen[fetchRuns] = v
		return v * 2
	end)
	flush()
	expect(fetchRuns == 1 and a.data:get() == 10, "initial fetch")
	a:refetch()
	expect(fetchRuns == 2 and seen[2] == 5, "refetch re-runs with current source value")
	expect(a.data:get() == 10 and a.loading:get() == false, "synchronous refetch resolves")
end)

test("async · refetch picks up a source set without an intervening flush", function()
	local source = new(1)
	local seen = {}
	local fetchRuns = 0
	local a = Async(source, function(v)
		fetchRuns += 1
		seen[fetchRuns] = v
		return v
	end)
	flush()
	source:set(7) -- write source but do NOT flush the effect
	a:refetch() -- refetch must read the *current* source value (7), not the flushed one
	expect(seen[fetchRuns] == 7, "refetch reads the live source value")
end)

test("async · refetch with a function source re-evaluates the selector", function()
	local base = new(3)
	local fetchRuns = 0
	local seen = {}
	local a = Async(function()
		return base:get() * 2
	end, function(v)
		fetchRuns += 1
		seen[fetchRuns] = v
		return v
	end)
	flush()
	base:set(10) -- no flush
	a:refetch()
	expect(seen[fetchRuns] == 20, "function source is re-evaluated on refetch")
end)

test("async · refetch/mutate after Destroy are safe no-ops", function()
	local fetches = 0
	local source = new(1)
	local a = Async(source, function(v)
		fetches += 1
		return v
	end)
	flush()
	expect(fetches == 1, "initial fetch ran once")
	a:Destroy()
	expect((pcall(function()
		a:refetch()
	end)) == true, "refetch after destroy does not error")
	expect((pcall(function()
		a:mutate(5)
	end)) == true, "mutate after destroy does not error")
	flush()
	-- true no-ops, not just non-throwing: the post-Destroy guard returns before
	-- re-running the fetcher, so the count stays put
	expect(fetches == 1, "no fetch ran after Destroy")
end)

test("async · Destroy while a fetch is in flight is a safe no-op (no crash)", function()
	-- destroy() must bump the race guard, else the suspended fetcher resumes, passes
	-- the `currentId == _fetchId` check, and writes to now-nil state nodes (crash)
	local resumeThread
	local a = Async(function()
		resumeThread = coroutine.running()
		coroutine.yield() -- in-flight: resolves only after Destroy
		return 7
	end, nil)
	flush() -- effect runs, spawns the fetcher, which yields
	a:Destroy()
	local ok = coroutine.resume(resumeThread)
	expect(ok == true, "in-flight fetcher resolving after Destroy does not error")
end)

test("async · refetch does not become a dependency of an enclosing effect", function()
	local source = new(1)
	local a = Async(source, function(v)
		return v
	end)
	flush()
	local outerRuns = 0
	local e = new(function()
		outerRuns += 1
		a:refetch() -- must not capture `source` as a dep of `e`
	end, true)
	flush()
	expect(outerRuns == 1, "enclosing effect ran once")
	source:set(2)
	flush()
	-- e re-runs ONLY if it captured source; refetch's raw() read must prevent that
	expect(outerRuns == 1, "refetch's untracked read did not subscribe the outer effect")
	e:Destroy()
end)

test("async · latest in-flight wins; stale resolution discarded (headless)", function()
	-- hold two in-flight fetches at once (each parks on yield) and choose the resume
	-- order. Resuming the OLDER one LAST must not clobber the newer: runFetcher's
	-- `currentId == self._fetchId` guard drops the stale write.
	local src = new(1)
	local threads = {} -- threads[inputValue] = parked coroutine
	local fetchRuns = 0
	local a = Async(src, function(v)
		fetchRuns += 1
		threads[v] = coroutine.running()
		coroutine.yield()
		return v * 100
	end)

	flush() -- starts the fetch for v = 1, which parks on yield
	expect(fetchRuns == 1 and threads[1] ~= nil, "first fetch (v=1) is in flight and parked")
	expect(a.loading:get() == true, "loading is true during the pending window")
	expect(a.data:get() == nil, "no data resolved yet")

	src:set(2)
	flush() -- starts the fetch for v = 2 while v = 1 is still parked
	expect(fetchRuns == 2 and threads[2] ~= nil, "second fetch (v=2) is now also in flight")
	expect(a.loading:get() == true, "still loading with the newer fetch pending")

	-- Resume the NEWER fetch first: it wins the race and resolves.
	coroutine.resume(threads[2])
	expect(a.data:get() == 200, "newer fetch (v=2) resolves and wins")
	expect(a.loading:get() == false, "loading clears once the latest fetch resolves")

	-- Now resume the OLDER, stale fetch LAST. Its result (100) must be discarded.
	coroutine.resume(threads[1])
	expect(a.data:get() == 200, "stale older fetch (v=1) does NOT clobber the newer result")
	expect(a.loading:get() == false, "stale resolution does not re-toggle loading")
	expect(a.error:get() == nil, "stale resolution leaves error untouched")
end)

test("async · loading false→true→false across the pending window (headless)", function()
	local fetchThread
	local a = Async(function()
		fetchThread = coroutine.running()
		coroutine.yield()
		return 42
	end, 0)

	expect(a.data:get() == 0, "starts with the initial value before any flush")
	expect(a.loading:get() == false, "loading is false before the effect flushes")

	flush() -- starts the (one-shot) fetch, which parks on yield
	expect(a.loading:get() == true, "loading flips true once the fetch is in flight")
	expect(a.data:get() == 0, "data still the initial value while pending")

	coroutine.resume(fetchThread) -- resolve
	expect(a.loading:get() == false, "loading flips back false after resolution")
	expect(a.data:get() == 42, "data holds the resolved value")
	expect(a.error:get() == nil, "no error on success")
end)

test("async · a prior error is cleared when the fetch re-triggers (headless)", function()
	-- the first run errors synchronously; a source change clears the error at
	-- trigger time (error:set(nil)), and the successful re-run leaves it nil
	local gate = new(1)
	local a = Async(gate, function(g)
		if g == 1 then
			error("first boom")
		end
		return g * 10
	end)

	flush()
	expect(a.error:get() ~= nil, "first run's synchronous error is captured")
	expect(string.find(tostring(a.error:get()), "first boom", 1, true) ~= nil, "error message captured")
	expect(a.loading:get() == false and a.data:get() == nil, "loading cleared, no data on failure")

	gate:set(2) -- re-trigger
	flush()
	expect(a.error:get() == nil, "prior error is cleared on re-trigger")
	expect(a.data:get() == 20, "successful re-run resolves")
	expect(a.loading:get() == false, "loading cleared after the successful re-run")
end)

test("async · state: unresolved → pending → ready → refreshing → ready (headless)", function()
	-- the resolved flag (not data presence) drives state, so an initialValue reads as
	-- unresolved/pending until the first real fetch completes, then ready/refreshing after
	local fetchThread
	local a = Async(function()
		fetchThread = coroutine.running()
		coroutine.yield()
		return 42
	end, 0)
	expect(a.data:get() == 0, "data starts at the initial value")
	expect(a.state:get() == "unresolved", "unresolved before the first flush, despite an initial value")
	flush()
	expect(a.state:get() == "pending", "pending while the first fetch is in flight (no resolved value yet)")
	coroutine.resume(fetchThread)
	expect(a.state:get() == "ready" and a.data:get() == 42, "ready once the fetch resolves")
	a:refetch()
	expect(a.state:get() == "refreshing", "refreshing while a refetch runs over an already-resolved value")
	coroutine.resume(fetchThread)
	expect(a.state:get() == "ready", "back to ready after the refetch resolves")
end)

test("async · state is ready when a fetch resolves to nil", function()
	-- resolved is tracked by a flag, so a legitimately nil result is ready, not unresolved
	local a = Async(function()
		return nil
	end, "init")
	flush() -- synchronous fetcher resolves during the spawn
	expect(a.state:get() == "ready", "a nil resolution still counts as resolved")
	expect(a.data:get() == nil, "data holds the nil result")
end)

test("async · retry after a never-resolved error is pending, not refreshing (headless)", function()
	-- the first fetch errors before ever resolving, so a refetch shows pending
	-- (no prior value) rather than refreshing
	local fetchThread, first = nil, true
	local a = Async(function()
		fetchThread = coroutine.running()
		coroutine.yield()
		if first then
			first = false
			error("boom")
		end
		return 7
	end, nil)
	flush()
	expect(a.state:get() == "pending", "first fetch is pending")
	coroutine.resume(fetchThread)
	expect(a.state:get() == "errored", "errored after the failure")
	a:refetch()
	expect(a.state:get() == "pending", "retry is pending since nothing ever resolved")
	coroutine.resume(fetchThread)
	expect(a.state:get() == "ready" and a.data:get() == 7, "ready after the successful retry")
end)

test("async · a falsy source gates the fetch until it turns truthy", function()
	-- nil/false source = "not ready": the fetcher is skipped and state stays unresolved
	local gate = new(nil :: any)
	local runs = 0
	local a = Async(gate, function(g)
		runs += 1
		return g * 100
	end, "init")
	flush()
	expect(runs == 0, "fetcher not called while the source is nil")
	expect(a.state:get() == "unresolved" and a.loading:get() == false, "unresolved and not loading while gated")
	gate:set(3)
	flush()
	expect(runs == 1 and a.data:get() == 300, "fetches once the source turns truthy")
	expect(a.state:get() == "ready", "ready after the gated fetch resolves")
	gate:set(false)
	flush()
	expect(runs == 1, "a falsy source again does not refetch")
	expect(a.state:get() == "ready", "the latest value is retained while re-gated")
end)

test("async · mutate marks the resource ready and drops the in-flight fetch (headless)", function()
	-- an optimistic value counts as resolved (state → ready) and the race guard bump
	-- discards the parked fetch when it resumes
	local fetchThread
	local a = Async(function()
		fetchThread = coroutine.running()
		coroutine.yield()
		return 1
	end, nil)
	flush()
	expect(a.state:get() == "pending", "pending before any value resolves")
	a:mutate(99)
	expect(a.state:get() == "ready" and a.data:get() == 99, "mutate resolves the resource to ready")
	coroutine.resume(fetchThread)
	expect(a.state:get() == "ready" and a.data:get() == 99, "the dropped fetch leaves the mutated value")
end)

test("async · fetcher receives the previous value and the refetching payload (headless)", function()
	local seen, fetchThread = {}, nil
	local a = Async(function(_input, previous, refetching)
		seen[#seen + 1] = { value = previous, refetching = refetching }
		fetchThread = coroutine.running()
		coroutine.yield()
		return (previous or 0) + 1
	end, 10)
	flush()
	coroutine.resume(fetchThread)
	expect(a.data:get() == 11, "first run sees previous == initial value (10 + 1)")
	expect(seen[1].refetching == false, "a source/initial run reports refetching = false")
	a:refetch("manual")
	coroutine.resume(fetchThread)
	expect(a.data:get() == 12, "refetch sees the previous resolved value (11 + 1)")
	expect(seen[2].refetching == "manual", "the refetch payload is forwarded as the refetching arg")
end)

rtest("async · loading lifecycle with real yields", function()
	local res = Flux.async(function()
		task.wait(0.03)
		return 42
	end, 0)
	expect(res.data() == 0, "starts with the initial value")
	expect(res.loading() == false, "not loading before the effect flushes")
	flush()
	expect(res.loading() == true, "loading becomes true once the fetch starts")
	task.wait(0.08)
	expect(res.loading() == false, "loading clears after resolution")
	expect(res.data() == 42, "data holds the resolved value")
	expect(res.error() == nil, "no error on success")
	res:Destroy()
end)

rtest("async · captures errors across yields", function()
	local res = Flux.async(function()
		task.wait(0.02)
		error("boom")
	end)
	flush()
	task.wait(0.06)
	expect(res.loading() == false, "loading cleared after failure")
	expect(res.data() == nil, "data stays nil on failure")
	expect(res.error() ~= nil, "error node populated")
	expect(string.find(tostring(res.error()), "boom", 1, true) ~= nil, "error message captured")
	res:Destroy()
end)

rtest("async · latest request wins (race handling)", function()
	local input = Flux(1)
	local res = Flux.async(input, function(v)
		task.wait(if v == 1 then 0.08 else 0.03)
		return v
	end)
	flush() -- starts the slow fetch for v = 1
	task.wait(0.02)
	input(2) -- change the source
	flush() -- starts the fast fetch for v = 2
	task.wait(0.12) -- let both fetches finish (slow one resolves ~0.08s in, then is discarded)
	expect(res.data() == 2, `the newer result should win, got {tostring(res.data())}`)
	res:Destroy()
end)

rtest("async · refetch with a real yielding fetcher resolves fresh", function()
	local source = Flux(1)
	local a = Flux.async(source, function(v)
		task.wait(0.02)
		return v * 100
	end)
	flush()
	task.wait(0.05)
	expect(a.data() == 100, "initial fetch resolved")
	source(4)
	a:refetch() -- before the effect's own flush; reads live value 4
	task.wait(0.05)
	expect(a.data() == 400, "refetch resolved with the live source value")
	a:Destroy()
end)

test("gate · gating the source off drops an in-flight fetch", function()
	local gate = new(1)
	local fetchThread
	local a = Async(gate, function(v)
		fetchThread = coroutine.running()
		coroutine.yield() -- park the fetch in flight
		return v * 100
	end, "init")
	flush() -- spawns the fetch, which parks at the yield
	expect(a.loading() == true, "loading while the fetch is in flight")

	gate(false) -- gate off while the fetch is still parked
	flush()
	coroutine.resume(fetchThread) -- the now-stale fetch resolves

	expect(a.data() == "init", "the stale in-flight result is discarded")
	expect(a.state() == "unresolved", "the gated-off node reads as unresolved")
	a:Destroy()
end)

test("gate · gating off after an error clears the error", function()
	local gate = new(1)
	local a = Async(gate, function()
		error("boom")
	end, "x")
	flush() -- the synchronous fetcher throws
	expect(a.state() == "errored", "errored after the fetcher throws")

	gate(false)
	flush()
	expect(a.error() == nil, "error cleared when gated off")
	expect(a.state() == "unresolved", "gated-off node reads as unresolved, not errored")
	a:Destroy()
end)

test("refetch · honors the source gate", function()
	local gate = new(false) -- gated off
	local runs = 0
	local a = Async(gate, function(v)
		runs += 1
		return v
	end, "init")
	flush()
	expect(runs == 0, "the fetcher does not run while gated")
	a:refetch()
	expect(runs == 0, "refetch does not bypass the gate")
	a:Destroy()
end)

return {}
