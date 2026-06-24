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

test("safe · returns tryFn result when it succeeds", function()
	local dep = new(2)
	local s = Flux.safe(function()
		return dep:get() * 10
	end, -1)
	expect(s:get() == 20, "passes through success value")
end)

test("safe · returns plain fallback on throw", function()
	local s = Flux.safe(function(): number
		error("boom")
	end, 99)
	expect(s:get() == 99, "fallback value on error")
end)

test("safe · function fallback receives the error", function()
	local seen: any = nil
	local s = Flux.safe(function(): string
		error("kaboom")
	end, function(err)
		seen = err
		return "recovered"
	end)
	expect(s:get() == "recovered", "fallback fn result")
	expect(string.find(tostring(seen), "kaboom", 1, true) ~= nil, "fallback fn got the error")
end)

test("safe · self-heals: re-evaluates and recovers when a dep changes", function()
	local dep = new(0)
	local runs = 0
	local s = Flux.safe(function(): number
		runs += 1
		local v = dep:get()
		if v == 0 then
			error("not ready")
		end
		return v * 2
	end, -1)
	expect(s:get() == -1 and runs == 1, "errors -> fallback, deps captured")
	dep:set(5)
	expect(s:get() == 10 and runs == 2, "recovers on dep change")
	dep:set(0)
	expect(s:get() == -1 and runs == 3, "errors again -> fallback again")
end)

test("safe · does not double-run tryFn per evaluation", function()
	local dep = new(1)
	local runs = 0
	local s = Flux.safe(function()
		runs += 1
		return dep:get()
	end, 0)
	s:get()
	s:get()
	expect(runs == 1, "single eval, cached read")
	dep:set(2)
	s:get()
	expect(runs == 2, "exactly one re-run per dep change")
end)

test("safe · nil fallback is valid and stays clean (no retry storm)", function()
	local runs = 0
	local s = Flux.safe(function(): number?
		runs += 1
		error("always")
	end, nil)
	expect(s:get() == nil and runs == 1, "nil fallback")
	s:get()
	s:get()
	expect(runs == 1, "no re-run without a dep change (does not park DIRTY)")
end)

test("safe · cleanup inside tryFn runs before each re-eval", function()
	local dep = new(1)
	local cleanups = 0
	local s = Flux.safe(function()
		Flux.cleanup(function()
			cleanups += 1
		end)
		return dep:get()
	end, 0)
	expect(s:get() == 1 and cleanups == 0, "first eval")
	dep:set(2)
	expect(s:get() == 2 and cleanups == 1, "cleanup ran before re-eval")
end)

test("safe · equals short-circuits propagation", function()
	local dep = new(1)
	local downstreamRuns = 0
	local s = Flux.safe(
		function()
			return dep:get() % 2
		end,
		-1,
		function(a, b)
			return a == b
		end
	)
	local d = new(function()
		downstreamRuns += 1
		return s:get()
	end)
	expect(d:get() == 1 and downstreamRuns == 1, "init")
	dep:set(3)
	expect(d:get() == 1 and downstreamRuns == 1, "equal value short-circuits")
	dep:set(2)
	expect(d:get() == 0 and downstreamRuns == 2, "changed value propagates")
end)

test("safe · structured (table) error reaches the recovery fn intact", function()
	local errObj = { code = 500, detail = "kaboom" }
	local seen: any = nil
	local s = Flux.safe(function(): string
		error(errObj)
	end, function(err)
		seen = err
		return "recovered"
	end)
	expect(s:get() == "recovered", "recovered value")
	expect(seen == errObj, "recovery fn got the exact table (identity preserved, not stringified)")
	expect(type(seen) == "table" and seen.code == 500, "table fields intact")
end)

test("catch · returns fn result on success, handler result on throw", function()
	local okPath = Flux.catch(function()
		return 42
	end, function()
		return -1
	end)
	expect(okPath == 42, "success path")
	local errPath = Flux.catch(function(): number
		error("nope")
	end, function(err)
		expect(string.find(tostring(err), "nope", 1, true) ~= nil, "handler got error")
		return -1
	end)
	expect(errPath == -1, "handler path")
end)

test("catch · does not subscribe the surrounding computation to its reads", function()
	local dep = new(1)
	local outerRuns = 0
	local outer = new(function()
		outerRuns += 1
		return Flux.catch(function()
			return dep:get()
		end, function()
			return 0
		end)
	end)
	expect(outer:get() == 1 and outerRuns == 1, "init")
	dep:set(2)
	expect(outer:get() == 1 and outerRuns == 1, "catch read is untracked")
end)

test("catch · reads after the guarded block stay tracked", function()
	local a = new(1)
	local b = new(10)
	local outerRuns = 0
	local outer = new(function()
		outerRuns += 1
		local guarded = Flux.catch(function()
			return a:get()
		end, function()
			return 0
		end)
		return guarded + b:get()
	end)
	expect(outer:get() == 11 and outerRuns == 1, "init")
	b:set(20)
	expect(outer:get() == 21 and outerRuns == 2, "post-catch read re-tracked")
	a:set(5)
	expect(outer:get() == 21 and outerRuns == 2, "guarded read stays untracked")
end)

test("catch · handler that itself throws propagates", function()
	expectError(function()
		Flux.catch(function()
			error("inner")
		end, function()
			error("handler boom")
		end)
	end, "handler boom")
end)

test("catch · structured (table) error reaches the handler intact", function()
	local errObj = { code = 404 }
	local seen: any = nil
	local result = Flux.catch(function(): number
		error(errObj)
	end, function(err)
		seen = err
		return -1
	end)
	expect(result == -1, "handler path")
	expect(seen == errObj, "handler got the exact table (identity preserved, not stringified)")
end)

test("catch · re-raises a thrown table error unchanged", function()
	local errObj = { code = 500 }
	local ok, caught = pcall(function()
		Flux.catch(function()
			error("inner")
		end, function()
			error(errObj)
		end)
	end)
	expect(ok == false, "handler error propagated")
	expect(caught == errObj, "re-raised the exact table via error(_, 0), not a stringified copy")
end)

test("scope · a safe node created in a scope is destroyed with it", function()
	local node
	local destroyed = false
	local s = Flux.scope(function()
		node = Flux.safe(function()
			return 1
		end, 0)
		node:onDestroy(function()
			destroyed = true
		end)
	end)
	expect(node:get() == 1, "safe works")
	s:Destroy()
	expect(destroyed, "scope destroyed the safe node (its onDestroy fired)")
end)

return {}
