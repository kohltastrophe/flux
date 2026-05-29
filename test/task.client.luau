--!strict
--!optimize 2
--[[
	Flux — Comprehensive Unit Test Suite
	====================================

	Flux is a reactive framework (Values / Computeds / Effects / Stores /
	Async / mapping / declarative instances), so these tests exercise the
	*reactive graph*, not the HyperLogLog placeholder that previously lived
	in this file.

	NOTES ON DETERMINISM
	--------------------
	* Effects and property/attribute bindings are DEFERRED. In a live game
	  they flush on RunService.Heartbeat; here we flush synchronously with
	  `Flux.Graph.flush()` after every state change we want observed. Reading
	  a Value or Computed does NOT need a flush (reads are pull-based).
	* The Async tests genuinely yield (task.wait); the harness tolerates
	  yielding test bodies.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flux = require(ReplicatedStorage:WaitForChild("Flux")) :: any
-- `unwrap`/`destroy` live on the Store submodule, not on the Flux root.
local Store = require((ReplicatedStorage:WaitForChild("Flux") :: any):WaitForChild("Store")) :: any

local flush = Flux.Graph.flush

-- ──────────────────────────────────────────────────────────────────────────
-- Test helpers
-- ──────────────────────────────────────────────────────────────────────────

local function expectError(fn: () -> (), fragment: string?)
	local ok, err = pcall(fn)
	assert(not ok, "expected the call to error, but it succeeded")
	if fragment then
		assert(
			string.find(tostring(err), fragment, 1, true) ~= nil,
			`expected error containing "{fragment}", got: {tostring(err)}`
		)
	end
end

local function approx(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

-- ──────────────────────────────────────────────────────────────────────────
-- Tests
-- ──────────────────────────────────────────────────────────────────────────

local tests = {

	-- ===== VALUES ===========================================================

	["01 Value · read and write"] = function()
		local v = Flux(10)
		assert(v:get() == 10, ":get() returns the value")
		assert(v() == 10, "calling with no args reads (shorthand for :get)")

		v:set(20)
		assert(v() == 20, ":set() writes")

		v(30)
		assert(v:get() == 30, "calling with an arg writes (shorthand for :set)")
	end,

	["02 Value · isNode detection"] = function()
		assert(Flux.isNode(Flux(1)) == true, "value node is a node")
		assert(Flux.isNode(Flux(function()
			return 1
		end)) == true, "computed is a node")
		assert(Flux.isNode(5) == false, "number is not a node")
		assert(Flux.isNode("x") == false, "string is not a node")
		assert(Flux.isNode({}) == false, "plain table is not a node")
		assert(Flux.isNode(nil) == false, "nil is not a node")
	end,

	["03 Value · operator overloading"] = function()
		local x = Flux(6)

		assert(x + 4 == 10, "__add")
		assert(x - 1 == 5, "__sub")
		assert(x * 2 == 12, "__mul")
		assert(x / 2 == 3, "__div")
		assert(x // 4 == 1, "__idiv")
		assert(x % 4 == 2, "__mod")
		assert(x ^ 2 == 36, "__pow")
		assert(-x == -6, "__unm")
		assert((x .. "!") == "6!", "__concat")
		assert(tostring(x) == "6", "__tostring")

		-- node-to-node operands
		local y = Flux(5)
		assert(x + y == 11, "node + node")
		assert((x > y) == true, "node > node")

		-- node-to-node ONLY operands
		assert((x < y) == false, "__lt")
		assert((x > y) == true, "__lt (swapped)")
		assert((y <= x) == true, "__le")
	end,

	["04 Value · equals option short-circuits propagation"] = function()
		-- An `equals` that always reports "equal" means writes never propagate.
		local v = Flux(10, {
			equals = function()
				return true
			end,
		})
		local runs = 0
		local c = Flux(function()
			runs += 1
			return v()
		end)

		assert(c() == 10 and runs == 1, "computed evaluates once")

		v(999)
		assert(v:get() == 10, "value unchanged because equals reported equal")
		assert(c() == 10 and runs == 1, "no recompute since nothing changed")

		-- force bypasses the equality check
		v:set(20, true)
		assert(v:get() == 20, "force write updates the value")
		assert(c() == 20 and runs == 2, "force write propagates to observers")
	end,

	-- ===== COMPUTEDS ========================================================

	["05 Computed · lazy evaluation"] = function()
		local ran = false
		local c = Flux(function()
			ran = true
			return 42
		end)
		assert(ran == false, "computed body does not run until first read")
		assert(c() == 42, "reading evaluates and returns the result")
		assert(ran :: any == true, "body ran on read")
	end,

	["06 Computed · memoization and invalidation"] = function()
		local src = Flux(2)
		local count = 0
		local c = Flux(function()
			count += 1
			return src * 10
		end)

		assert(c() == 20 and count == 1, "first read computes")
		assert(c() == 20 and count == 1, "second read is cached")

		src(3)
		assert(c() == 30 and count == 2, "recomputes after dependency change")
		assert(c() == 30 and count == 2, "cached again after recompute")
	end,

	["07 Computed · dynamic dependency tracking"] = function()
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

		assert(c() == 1 and runs == 1, "initial: tracks useA and a")

		b(200)
		assert(c() == 1 and runs == 1, "changing untracked b does not invalidate")

		useA(false)
		assert(c() == 200 and runs == 2, "switching branches re-tracks dependencies")

		a(5)
		assert(c() == 200 and runs == 2, "a is no longer tracked")

		b(300)
		assert(c() == 300 and runs == 3, "b is now tracked")
	end,

	["08 Computed · chaining"] = function()
		local n = Flux(2)
		local doubled = Flux(function()
			return n * 2
		end)
		local quad = Flux(function()
			return doubled * 2
		end)

		assert(quad() == 8, "2 -> 4 -> 8")
		n(3)
		assert(doubled() == 6, "intermediate updated")
		assert(quad() == 12, "downstream updated")
	end,

	["09 Computed · raw vs read tracking"] = function()
		-- raw() reads WITHOUT registering a dependency
		local v = Flux(5)
		local rawRuns = 0
		local cRaw = Flux(function()
			rawRuns += 1
			return Flux.raw(v) + 100
		end)
		assert(cRaw() == 105 and rawRuns == 1)
		v(6)
		assert(cRaw() == 105 and rawRuns == 1, "raw read created no dependency")

		-- read() reads WITH dependency tracking
		local v2 = Flux(5)
		local readRuns = 0
		local cRead = Flux(function()
			readRuns += 1
			return Flux.read(v2) + 100
		end)
		assert(cRead() == 105 and readRuns == 1)
		v2(6)
		assert(cRead() == 106 and readRuns == 2, "read created a dependency")

		-- both pass through non-node values unchanged
		assert(Flux.raw(7) == 7, "raw passes through plain values")
		assert(Flux.read(7) == 7, "read passes through plain values")
	end,

	-- ===== EFFECTS ==========================================================

	["10 Effect · runs on flush and re-runs on change"] = function()
		local v = Flux(0)
		local runs, last = 0, nil
		Flux(function()
			runs += 1
			last = v()
		end, true)

		assert(runs == 0, "effect is deferred, not run on creation")
		flush()
		assert(runs == 1 and last == 0, "effect runs on flush")

		v(7)
		flush()
		assert(runs == 2 and last == 7, "effect re-runs after dependency change")
	end,

	["11 Effect · batches multiple writes per flush"] = function()
		local v = Flux(0)
		local runs, last = 0, nil
		Flux(function()
			runs += 1
			last = v()
		end, true)
		flush()
		assert(runs == 1 and last == 0)

		v(1)
		v(2)
		v(3)
		flush()
		assert(runs == 2, "three writes in one frame -> one effect run")
		assert(last == 3, "effect observes the final value only")
	end,

	["12 Effect · onCleanup runs before each re-run"] = function()
		local trigger = Flux(0)
		local effectRuns, cleanups = 0, 0
		Flux(function()
			effectRuns += 1
			local _ = trigger()
			Flux.onCleanup(function()
				cleanups += 1
			end)
		end, true)

		flush()
		assert(effectRuns == 1 and cleanups == 0, "no cleanup before first re-run")

		trigger(1)
		flush()
		assert(effectRuns == 2 and cleanups == 1, "cleanup fires before the re-run")

		trigger(2)
		flush()
		assert(effectRuns == 3 and cleanups == 2, "cleanup fires again")
	end,

	["13 Effect · onCleanup errors outside a reactive context"] = function()
		expectError(function()
			Flux.onCleanup(function() end)
		end, "reactive")
	end,

	["14 Node · onDestroy and Destroy"] = function()
		local destroyed = false
		local n = Flux(1)
		n:onDestroy(function()
			destroyed = true
		end)
		n:Destroy()
		assert(destroyed, "onDestroy callback fired on Destroy")
	end,

	["15 Effect · stops re-running after Destroy"] = function()
		local v = Flux(0)
		local runs = 0
		local e = Flux(function()
			runs += 1
			local _ = v()
		end, true)
		flush()
		assert(runs == 1)

		e:Destroy()
		v(5)
		flush()
		assert(runs == 1, "destroyed effect is unsubscribed and never re-runs")
	end,

	-- ===== GRAPH SEMANTICS ==================================================

	["16 Graph · diamond is glitch-free (single recompute)"] = function()
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

		assert(d() == 5 and dRuns == 1, "1 -> b=2,c=3 -> d=5")

		a(5)
		assert(d() == 13, "5 -> b=6,c=7 -> d=13")
		assert(dRuns == 2, "d recomputes exactly once despite two changed parents")
		assert(d() == 13 and dRuns == 2, "still cached")
	end,

	["17 Graph · cycle is detected, not hung; graph stays usable"] = function()
		-- Self-referential computed. Detection is internal (it warns); the read
		-- returns a fallback rather than infinite-looping. A traceback warning
		-- printed during this test is EXPECTED.
		print("  (heads up: the next 'Cyclic read' warning is expected)")
		local cyclic
		cyclic = Flux(function()
			return (cyclic :: any)() + 1
		end)

		-- Must return (not hang). Outcome value is a fallback; we don't assert it.
		pcall(function()
			return (cyclic :: any)()
		end)

		-- The rest of the graph must still work after a cyclic node exists.
		local healthy = Flux(7)
		local derived = Flux(function()
			return healthy * 2
		end)
		assert(derived() == 14, "graph remains functional after a cyclic node")
		healthy(8)
		assert(derived() == 16, "and continues to react")
	end,

	-- ===== SCOPES ===========================================================

	["18 Scope · tracks and destroys created nodes"] = function()
		local s = Flux.scope()
		local v = s(5)
		assert(Flux.isNode(v) and v() == 5, "scope() creates a tracked Value")

		local destroyed = false
		v:onDestroy(function()
			destroyed = true
		end)

		s:Destroy()
		assert(destroyed, "scope:Destroy() destroys tracked nodes")
	end,

	["19 Scope · destroyed scope stops scoped effects"] = function()
		local s = Flux.scope()
		local src = Flux(0)
		local runs = 0
		s(function()
			runs += 1
			local _ = src()
		end, true)
		flush()
		assert(runs == 1)

		s:Destroy()
		src(1)
		flush()
		assert(runs == 1, "scoped effect no longer fires after scope destroyed")
	end,

	-- ===== STORES ===========================================================

	["20 Store · deep reactivity per key"] = function()
		local state = Flux.store({
			player = { health = 100, name = "Guest" },
			settings = { volume = 0.5 },
		})

		local healthRuns, volumeRuns = 0, 0
		Flux(function()
			healthRuns += 1
			local _ = state.player.health
		end, true)
		Flux(function()
			volumeRuns += 1
			local _ = state.settings.volume
		end, true)

		flush()
		assert(healthRuns == 1 and volumeRuns == 1, "both effects run once initially")

		state.player.health = 90
		flush()
		assert(state.player.health == 90, "deep write persisted")
		assert(healthRuns == 2, "health observer re-ran")
		assert(volumeRuns == 1, "unrelated branch observer did NOT re-run")
	end,

	["21 Store · structural (length) tracking"] = function()
		local s = Flux.store({ items = { "a", "b" } })
		local lenRuns, lastLen = 0, 0
		Flux(function()
			lenRuns += 1
			lastLen = #s.items
		end, true)

		flush()
		assert(lenRuns == 1 and lastLen == 2, "tracks length initially")

		-- Mutate via __newindex (definitely intercepted) to grow the array.
		s.items[#s.items + 1] = "c"
		flush()
		assert(lenRuns == 2 and lastLen == 3, "length observer re-runs on structural change")
	end,

	["22 Store · unwrap returns the raw table"] = function()
		local s = Flux.store({ a = 1, nested = { b = 2 } })
		local raw = Store.unwrap(s)

		assert(type(raw) == "table", "unwrap returns a table")
		assert(getmetatable(raw) == nil, "raw table has no proxy metatable")
		assert(raw.a == 1, "values are intact")
		assert(getmetatable(raw.nested :: any) == nil, "nested raw table is also un-proxied")
	end,

	-- ===== WRAP =============================================================

	["23 Wrap · replaces primitives with nodes"] = function()
		local t = { hp = 100, mp = 50, alive = true }
		Flux.wrap(t)

		assert(Flux.isNode(t.hp), "hp became a node")
		assert(Flux.isNode(t.mp), "mp became a node")
		assert(Flux.isNode(t.alive), "alive became a node")
		assert((t.hp :: any)() == 100, "node holds the original value");

		(t.hp :: any)(90)
		assert((t.hp :: any)() == 90, "wrapped node is writable")
	end,

	["24 Wrap · recurses and preserves existing nodes"] = function()
		local existing = Flux(7)
		local t = {
			name = "x",
			keep = existing,
			stats = { atk = 5 },
		}
		Flux.wrap(t)

		assert(Flux.isNode(t.name), "top-level primitive wrapped")
		assert(t.keep == existing, "pre-existing node left untouched")
		assert(type(t.stats) == "table" and not Flux.isNode(t.stats), "nested table traversed, not replaced")
		assert(Flux.isNode((t.stats :: any).atk), "nested primitive wrapped")
	end,

	["25 Wrap · scoped wrap is cleaned up"] = function()
		local s = Flux.scope()
		local t = { a = 1, b = 2 }
		s:wrap(t)
		assert(Flux.isNode(t.a), "scoped wrap creates nodes")

		local nodeA = t.a
		s:Destroy()
		-- After destruction the node is torn down; calling it should error.
		expectError(function()
			return (nodeA :: any)()
		end)
	end,

	-- ===== MAPPING (For) ====================================================

	["26 forValue · updates in place, caches by value"] = function()
		-- DOCS / TYPE say (indexNode, value); the IMPLEMENTATION passes
		-- (value, indexNode). This test pins the real runtime behavior.
		local a, b = { id = "a" }, { id = "b" }
		local list = Flux({ a, b })
		local calls = 0

		local mapped = Flux.forValue(list, function(indexNode, value)
			calls += 1
			assert(Flux.isNode(indexNode), "forValue first arg is a reactive index")
			return { value = value, indexNode = indexNode }
		end)

		local r1 = mapped()
		assert(calls == 2, "mapped once per value")

		-- Result table is keyed by position; entries carry the value + index node.
		assert(r1[1].value == a and r1[2].value == b, "values mapped to positions")
		assert(r1[1].indexNode() == 1 and r1[2].indexNode() == 2, "index nodes track position")

		-- Reorder: cached by identity, so no remap; index nodes update in place.
		list({ b, a })
		local r2 = mapped()
		assert(calls == 2, "reorder reuses cached results (no remap)")
		assert(r2[1].value == b and r2[2].value == a, "result follows new order")
		assert(r1[1].indexNode() == 2, "value a's index node moved to 2")
		assert(r2[2] == r1[1], "same cached object follows the value across positions")
	end,

	["27 forIndex · updates in place, caches by position"] = function()
		local list = Flux({ 10, 20, 30 })
		local calls = 0
		local mapped = Flux.forIndex(list, function(index, itemNode)
			calls += 1
			assert(Flux.isNode(itemNode), "forIndex second arg is a reactive node")
			return {
				read = function()
					return (itemNode :: any)()
				end,
			}
		end)

		local r1 = mapped()
		assert(calls == 3, "one map call per slot")
		assert(r1[1].read() == 10 and r1[2].read() == 20 and r1[3].read() == 30)

		-- Change a value -> node updates in place, no new map call.
		list({ 10, 99, 30 })
		local r2 = mapped()
		assert(calls == 3, "value change does not remap")
		assert(r2[2].read() == 99, "underlying item node updated")
		assert(r2[1] == r1[1], "unchanged slot's cached result reused")

		-- Shrink -> removed slots cleaned out of the result.
		list({ 10 })
		local r3 = mapped()
		assert(calls == 3, "shrinking does not remap")
		assert(r3[1].read() == 10 and r3[2] == nil and r3[3] == nil, "removed slots cleared")
	end,

	-- ===== ASYNC ============================================================

	["28 Async · loading lifecycle and resolution"] = function()
		local res = Flux.async(function()
			task.wait(0.05)
			return 42
		end, 0)

		assert(res.data() == 0, "starts with the initial value")
		assert(res.loading() == false, "not loading before the effect flushes")

		flush()
		assert(res.loading() == true, "loading becomes true once the fetch starts")

		task.wait(0.15)
		assert(res.loading() == false, "loading clears after resolution")
		assert(res.data() == 42, "data holds the resolved value")
		assert(res.error() == nil, "no error on success")

		res:Destroy()
	end,

	["29 Async · captures errors"] = function()
		local res = Flux.async(function()
			task.wait(0.03)
			error("boom")
		end)

		flush()
		task.wait(0.12)

		assert(res.loading() == false, "loading cleared after failure")
		assert(res.data() == nil, "data stays nil on failure")
		assert(res.error() ~= nil, "error node populated")
		assert(string.find(tostring(res.error()), "boom", 1, true) ~= nil, "error message captured")

		res:Destroy()
	end,

	["30 Async · latest request wins (race handling)"] = function()
		local input = Flux(1)
		local res = Flux.async(function()
			local v = input() -- read BEFORE yielding so it is tracked
			task.wait(if v == 1 then 0.20 else 0.05)
			return v
		end)

		flush() -- starts the slow fetch for v = 1
		task.wait(0.02)
		input(2) -- change dependency
		flush() -- starts the fast fetch for v = 2

		task.wait(0.40) -- let both fetches finish
		assert(res.data() == 2, `the newer result should win, got {tostring(res.data())}`)

		res:Destroy()
	end,

	-- ===== DECLARATIVE INSTANCES ===========================================

	["31 new · static properties"] = function()
		local s = Flux.scope()
		local frame: Frame = s:new "Frame" {
			Name = "TestFrame",
			Size = UDim2.fromOffset(100, 50),
			BackgroundTransparency = 0.25,
		}

		assert(frame:IsA("Frame"), "created the requested class")
		assert(frame.Name == "TestFrame", "string property assigned")
		assert(frame.Size == UDim2.fromOffset(100, 50), "UDim2 property assigned")
		assert(approx(frame.BackgroundTransparency, 0.25), "number property assigned")

		s:Destroy()
	end,

	["32 new · reactive property binding (direct node)"] = function()
		local s = Flux.scope()
		local text = Flux("hello")
		local label = s:new "TextLabel" { Text = text }

		flush()
		assert(label.Text == "hello", "bound to initial node value after flush")

		text("world")
		flush()
		assert(label.Text == "world", "property tracks the node")

		s:Destroy()
	end,

	["33 new · inline function binding (implicit memo)"] = function()
		local s = Flux.scope()
		local count = Flux(1)
		local label = s:new "TextLabel" {
			Text = function()
				return "Count: " .. count
			end,
		}

		flush()
		assert(label.Text == "Count: 1", "implicit memo evaluated")

		count(2)
		flush()
		assert(label.Text == "Count: 2", "implicit memo reacts to its dependency")

		s:Destroy()
	end,

	["34 new · numeric children are parented"] = function()
		local s = Flux.scope()
		local parent = s:new "Frame" {
			Name = "Parent",
			s:new "TextLabel" { Name = "ChildA" },
			s:new "TextLabel" { Name = "ChildB" },
		}

		assert(parent:FindFirstChild("ChildA") ~= nil, "first child parented")
		assert(parent:FindFirstChild("ChildB") ~= nil, "second child parented")

		s:Destroy()
	end,

	["35 new · __REF (callback and node forms)"] = function()
		local s = Flux.scope()

		local captured
		s:new "Frame" {
			__REF = function(inst)
				captured = inst
			end,
		}
		assert(captured ~= nil and captured:IsA("Frame"), "__REF callback received the instance")

		local refNode = Flux(nil)
		s:new "Frame" { __REF = refNode }
		assert(refNode() ~= nil and (refNode() :: any):IsA("Frame"), "__REF node set to the instance")

		s:Destroy()
	end,

	["36 new · __ATTR (static and reactive)"] = function()
		local s = Flux.scope()

		local f = s:new "Frame" { __ATTR = { Level = 7, Tag = "boss" } }
		assert(f:GetAttribute("Level") == 7, "static numeric attribute set")
		assert(f:GetAttribute("Tag") == "boss", "static string attribute set")

		local lvl = Flux(1)
		local f2 = s:new "Frame" { __ATTR = { Level = lvl } }
		flush()
		assert(f2:GetAttribute("Level") == 1, "reactive attribute initial value")
		lvl(2)
		flush()
		assert(f2:GetAttribute("Level") == 2, "reactive attribute updates")

		s:Destroy()
	end,

	["37 new · defaults applied and toggleable via Flux.Flags"] = function()
		-- Default for ImageButton sets AutoButtonColor = false (Roblox default is true).
		local s = Flux.scope()
		local btn = s:new "ImageButton" {}
		assert(btn.AutoButtonColor == false, "class defaults applied when Flags.defaults is true")
		s:Destroy()

		-- Disable defaults; capture results, restore the flag BEFORE asserting so a
		-- failed assertion can't leak global state into other tests.
		local oldFlag = Flux.Flags.defaults
		Flux.Flags.defaults = false
		local s2 = Flux.scope()
		local btn2 = s2:new "ImageButton" {}
		local autoColorWithoutDefaults = btn2.AutoButtonColor
		s2:Destroy()
		Flux.Flags.defaults = oldFlag

		assert(autoColorWithoutDefaults == true, "no defaults applied when Flags.defaults is false")
	end,

	["38 edit · applies props and reactive bindings to an existing instance"] = function()
		local s = Flux.scope()
		local existing = Instance.new("Frame")
		local color = Flux(Color3.new(1, 0, 0))

		s:edit(existing) {
			Name = "Edited",
			BackgroundColor3 = color,
		}

		flush()
		assert(existing.Name == "Edited", "static prop applied to existing instance")
		assert(existing.BackgroundColor3 == Color3.new(1, 0, 0), "reactive bind initial value")

		color(Color3.new(0, 1, 0))
		flush()
		assert(existing.BackgroundColor3 == Color3.new(0, 1, 0), "reactive bind updates")

		existing:Destroy()
		s:Destroy()
	end,

	-- ===== LISTEN ===========================================================

	["39 listen · receives updates until disconnected"] = function()
		local v = Flux(1)
		local received = {}
		local disconnect: () -> () = Flux.listen(v, function(val)
			table.insert(received, val)
		end)
		assert(type(disconnect) == "function", "listen returns a disconnect function")

		v(2)
		flush()
		v(3)
		flush()
		assert(received[#received] == 3, "listener observed the latest value")

		disconnect()
		v(4)
		flush()
		assert(table.find(received, 4) == nil, "listener stops firing after disconnect")
	end,

	-- ===== SUGAR / EQUIVALENCE =============================================

	["40 API · :set/:get parity with call sugar"] = function()
		local a = Flux(1)
		local b = Flux(1)

		a:set(50)
		b(50)
		assert(a:get() == b(), "set()/() and get()/() are interchangeable")

		-- isNode holds for scoped and computed nodes too
		local s = Flux.scope()
		assert(Flux.isNode(s(0)), "scoped value is a node")
		assert(
			Flux.isNode(Flux(function()
				return a + b
			end)),
			"computed is a node"
		)
		s:Destroy()
	end,
}

-- ──────────────────────────────────────────────────────────────────────────
-- Runner
-- ──────────────────────────────────────────────────────────────────────────

local testsList = {}
for name, f in tests :: any do
	table.insert(testsList :: any, { name, f })
end

table.sort(testsList, function(a: any, b: any)
	return a[1] < b[1]
end)

local passed, failed = 0, 0
for i, v in testsList do
	local name, f = table.unpack(v)
	local ok, err = pcall(f :: any)
	if ok then
		passed += 1
		testsList[i] = { true, `✅ {name}` } :: any
	else
		failed += 1
		testsList[i] = { false, `❌ {name}: {err}` } :: any
	end
end

print("Test Results:")
for _, v in testsList do
	if v[1] then
		print(v[2])
	else
		warn(v[2])
	end
end

print(`\nSummary: {passed} passed, {failed} failed, {#testsList} total`)

if failed > 0 then
	error(`{failed} test(s) failed`)
end

return "All tests passed."
