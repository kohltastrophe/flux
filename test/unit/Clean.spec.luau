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
local Clean = Flux.clean

test("clean · one failing cleanup doesn't abort the rest (expected warn)", function()
	local ran = false
	Clean({
		function()
			error("cleanup failure (expected warn)")
		end,
		function()
			ran = true
		end,
	})
	expect(ran, "clean isolates failures")
end)

test("clean · table with Destroy method is destroyed", function()
	local called = false
	local obj = {
		Destroy = function(_self)
			called = true
		end,
	}
	Clean(obj)
	expect(called, "cleanTable calls obj:Destroy()")
end)

test("clean · table with lowercase destroy method is destroyed", function()
	local called = false
	local obj = {
		destroy = function(_self)
			called = true
		end,
	}
	Clean(obj)
	expect(called, "cleanTable calls obj:destroy()")
end)

test("clean · Destroy takes precedence over destroy", function()
	local upper, lower = false, false
	local obj = {
		Destroy = function(_self)
			upper = true
		end,
		destroy = function(_self)
			lower = true
		end,
	}
	Clean(obj)
	expect(upper, "Destroy branch runs")
	expect(not lower, "destroy branch is not also invoked when Destroy exists")
end)

test("clean · Flux Node is destroyed via its Destroy method", function()
	local node = new(7)
	local destroyed = false
	node:onDestroy(function()
		destroyed = true
	end)
	Clean(node)
	expect(destroyed, "Clean(node) routes through cleanTable to Node.Destroy, firing onDestroy")
	-- metatable kept (isNode stays true), inner table stripped so the GC can reclaim it
	expect(Flux.isNode(node), "destroyed node keeps its metatable (isNode stays true)")
	expect(next(node._) == nil, "destroyed node's inner table was stripped")
end)

test("clean · nested array cleans every leaf function", function()
	local a, b = false, false
	Clean({
		{
			function()
				a = true
			end,
		},
		function()
			b = true
		end,
	})
	expect(a, "nested inner-array function ran")
	expect(b, "top-level function ran")
end)

test("clean · cleaning a function twice does not error", function()
	local count = 0
	local fn = function()
		count += 1
	end
	Clean(fn)
	Clean(fn)
	expect(count == 2, "function invoked on each clean, no error on second")
end)

test("clean · cleaning a node twice does not error", function()
	local node = new(1)
	local destroyed = 0
	node:onDestroy(function()
		destroyed += 1
	end)
	Clean(node)
	-- Second clean of an already-destroyed node must be a silent no-op (scope teardown relies on this)
	Clean(node)
	expect(destroyed == 1, "onDestroy fired exactly once; second clean is a no-op, not a re-destroy or error")
end)

test("clean · cleaning nil is a silent no-op", function()
	Clean(nil)
	expect(true, "Clean(nil) did not error")
end)

test("clean · cleaning an unsupported primitive is a silent no-op", function()
	Clean(42)
	Clean("hello")
	Clean(true)
	expect(true, "Clean of number/string/boolean did not error")
end)

rtest("clean · disconnects a live RBXScriptConnection and tolerates double clean", function()
	local bindable = Instance.new("BindableEvent")
	local conn = bindable.Event:Connect(function() end)
	expect(conn.Connected, "connection is live before Clean")
	Clean(conn)
	expect(conn.Connected == false, "Clean disconnects the connection")
	-- Already-disconnected: Clean guards on obj.Connected, so this must not error
	Clean(conn)
	expect(conn.Connected == false, "second Clean on a dead connection is a no-op")
	bindable:Destroy()
end)

rtest("clean · cancels a suspended thread so it never resumes", function()
	local resumed = false
	local co = task.delay(0.03, function()
		resumed = true
	end)
	expect(coroutine.status(co) == "suspended", "thread parked before Clean")
	Clean(co)
	-- well past the 0.03s delay: it would have fired by now had it not been cancelled
	task.wait(0.07)
	expect(resumed == false, "cancelled thread never resumed")
	-- Cleaning an already-dead/non-suspended thread must not error (status guard)
	Clean(co)
	expect(true, "second Clean on cancelled thread is a no-op")
end)

test("clean · table with a Disconnect/disconnect method is disconnected", function()
	-- Parity with Graph's cleanupFactory: a connection-shaped table is torn down by Clean too.
	local upper, lower = false, false
	Clean({
		Disconnect = function()
			upper = true
		end,
	})
	Clean({
		disconnect = function()
			lower = true
		end,
	})
	expect(upper and lower, "both Disconnect and disconnect methods were called")
end)

return {}
