--!nonstrict
local env = if game ~= nil
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Flux, sert = env.Flux, env.sert

local test = sert.test
local expect = sert
local new = Flux
local flush = Flux.flush
local Async = Flux.async
local untrackFn = Flux.untrack

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
	a:Destroy()
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
	expect(fetchRuns == 1 and a.loading:get() == false and a.data:get() == nil, "loading false and data nil on failure")
	expect(string.find(tostring(a.error:get()), "sync fetch failure", 1, true) ~= nil, "the error is captured")
	gate:set(2)
	flush()
	expect(
		fetchRuns == 2 and a.data:get() == 20 and a.error:get() == nil and a.loading:get() == false,
		"source change re-triggers, recovers"
	)
	a:Destroy()
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
	expect(fetchRuns == 1 and a.state:get() == "pending", "initial fetch in flight")
	a:mutate(999)
	expect(a.data:get() == 999 and a.state:get() == "ready", "mutate writes data immediately and resolves")
	expect(a.loading:get() == false, "mutate clears loading")
	expect(fetchRuns == 1, "mutate does not trigger a fetch")
	coroutine.resume(fetchThread) -- resolve the stale in-flight fetch
	expect(a.data:get() == 999 and a.state:get() == "ready", "stale in-flight fetch is dropped, mutate value kept")
	a:Destroy()
end)

test("async · refetch re-runs with the live source value, a node's or a function's, flushed or not", function()
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
	source:set(7) -- write source but do NOT flush the effect
	a:refetch()
	expect(seen[fetchRuns] == 7, "refetch reads the live source value, not the flushed one")
	a:Destroy()

	local fromFn = Async(function()
		return source:get() * 2
	end, function(v)
		table.insert(seen, v)
		return v
	end)
	flush()
	source:set(10) -- no flush
	fromFn:refetch()
	expect(seen[#seen] == 20, "a function source is re-evaluated on refetch")
	fromFn:Destroy()
end)

test("async · refetch, mutate and an in-flight fetch after Destroy are safe no-ops", function()
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

	-- destroy() must bump the race guard, else the suspended fetcher resumes, passes
	-- the `currentId == _fetchId` check, and writes to now-nil state nodes (crash)
	local resumeThread
	local parked = Async(function()
		resumeThread = coroutine.running()
		coroutine.yield() -- in-flight: resolves only after Destroy
		return 7
	end, nil)
	flush() -- effect runs, spawns the fetcher, which yields
	parked:Destroy()
	local ok = coroutine.resume(resumeThread)
	expect(ok == true, "an in-flight fetcher resolving after Destroy does not error")
end)

test("async · refetch leaves its caller's tracking alone: an effect, a scope body, untrack(fn)", function()
	local source = new(1)
	local a = Async(source, function(v)
		return v
	end)
	flush()
	local outerRuns = 0
	local e = Flux.effect(function()
		outerRuns += 1
		a:refetch() -- must not capture `source` as a dep of `e`
	end)
	flush()
	expect(outerRuns == 1, "enclosing effect ran once")
	source:set(2)
	flush()
	-- e re-runs ONLY if it captured source; refetch's raw() read must prevent that
	expect(outerRuns == 1, "refetch's untracked read did not subscribe the outer effect")
	e:Destroy()

	local seen
	local root = Flux.scope(function()
		a:refetch()
		seen = Flux.isReactive()
	end)
	expect(seen == false, "refetch() did not switch tracking on in a scope body")
	root:Destroy()

	local dep = new(1)
	local runs = 0
	local inner = Flux.effect(function()
		runs += 1
		untrackFn(function()
			a:refetch()
			dep:get()
		end)
	end)
	flush()
	dep:set(2)
	flush()
	expect(runs == 1, "the read after refetch() inside untrack(fn) did not subscribe")
	inner:Destroy()
	a:Destroy()
end)

test("async · latest in-flight wins; stale resolution discarded", function()
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
	a:Destroy()
end)

test("async · state and loading: unresolved → pending → ready → refreshing → ready", function()
	-- the resolved flag (not data presence) drives state, so an initialValue reads as
	-- unresolved/pending until the first real fetch completes, then ready/refreshing after
	local fetchThread
	local result = 42
	local a = Async(function()
		fetchThread = coroutine.running()
		coroutine.yield()
		return result
	end, 0)
	expect(a.data:get() == 0, "data starts at the initial value")
	expect(a.state:get() == "unresolved", "unresolved before the first flush, despite an initial value")
	expect(a.loading:get() == false, "not loading before the effect flushes")
	flush()
	expect(a.state:get() == "pending", "pending while the first fetch is in flight (no resolved value yet)")
	expect(a.loading:get() == true and a.data:get() == 0, "loading, data still the initial value")
	coroutine.resume(fetchThread)
	expect(a.state:get() == "ready" and a.data:get() == 42, "ready once the fetch resolves")
	expect(a.loading:get() == false and a.error:get() == nil, "loading cleared, no error")
	a:refetch()
	expect(a.state:get() == "refreshing", "refreshing while a refetch runs over an already-resolved value")
	coroutine.resume(fetchThread)
	expect(a.state:get() == "ready", "back to ready after the refetch resolves")
	result = nil
	a:refetch()
	coroutine.resume(fetchThread)
	expect(a.state:get() == "ready" and a.data:get() == nil, "a nil result is ready too, not unresolved")
	a:Destroy()
end)

test("async · retry after a never-resolved error is pending, not refreshing", function()
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
	a:Destroy()
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
	a:refetch()
	expect(runs == 0, "refetch does not bypass the gate")
	expect(a.state:get() == "unresolved" and a.loading:get() == false, "unresolved and not loading while gated")
	gate:set(3)
	flush()
	expect(runs == 1 and a.data:get() == 300, "fetches once the source turns truthy")
	expect(a.state:get() == "ready", "ready after the gated fetch resolves")
	gate:set(false)
	flush()
	expect(runs == 1, "a falsy source again does not refetch")
	expect(a.state:get() == "ready", "the latest value is retained while re-gated")
	a:Destroy()
end)

test("async · fetcher receives the previous value and the refetching payload", function()
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
	a:Destroy()
end)

test("async · fetchers yielding on the scheduler resolve and fail", function()
	-- Fetchers yield a frame (Flux.Clock.wait: virtual headless), not a set time, and both run at once; env.frames
	-- steps frames until the results are in.
	local wait = Flux.Clock.wait
	local res = Flux.async(function()
		wait()
		return 42
	end, 0)
	local failing = Flux.async(function()
		wait()
		error("boom")
	end)
	flush()
	expect(res.loading() == true, "loading once the fetch starts")
	expect(
		env.frames(function()
			return not res.loading() and failing.error() ~= nil
		end),
		"every fetch settles after a real yield"
	)
	expect(res.data() == 42 and res.error() == nil, "resolves")
	expect(string.find(tostring(failing.error()), "boom", 1, true) ~= nil, "an error across a yield is captured")
	expect(failing.loading() == false and failing.data() == nil, "loading cleared, no data")
	res:Destroy()
	failing:Destroy()
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

return {}
