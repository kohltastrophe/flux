--!nonstrict
--[[
	Unit-suite aggregator. `spec.luau` requires this for both runtimes; it owns
	the shared teardown and then requires every `*.spec.luau` sibling, each of
	which registers its tests with `sert` as a side effect of being required.

	Headless (vanilla luau CLI) resolves siblings by string path; Roblox resolves
	them as child ModuleScripts. `Init.spec` is required LAST in both runtimes so
	the trailing `heartbeat ·` test still sees init.luau's Heartbeat hookup alive.

	NOTE ON HEADLESS PATHS: this is a directory module required as `./unit` by
	spec.luau, and Luau resolves a required directory's init.luau relative paths
	from the directory's PARENT (test/), not from test/unit/. So the requires
	below are written relative to test/ (`../src`, `./sert`, `./unit/*.spec`),
	whereas the leaf `*.spec.luau` files (being ordinary file modules) use
	their own directory (`../../src`, `../sert`).
]]

local IS_ROBLOX = game ~= nil

local Flux
local sert
if IS_ROBLOX then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	Flux = require(ReplicatedStorage:WaitForChild("Flux")) :: any
	sert = require(ReplicatedStorage:WaitForChild("sert")) :: any
else
	Flux = require("../src") :: any
	sert = require("./sert") :: any
end

-- Establish the clean baseline BEFORE each test: headless, strict defaults ON
-- (dev/unoptimized), so without this the very first test in a run sees strict enabled.
sert.beforeEach(function()
	Flux.strict(false)
end)

-- afterEach resets the leak-prone globals a test might flip (strict, Flags.defaults,
-- the responsive viewport singleton) so a throwing test can't leak them into the
-- tests after it, and registration order across suites stays irrelevant.
sert.afterEach(function()
	Flux.strict(false)
	Flux.Flags.defaults = true
	Flux.viewport:set((if IS_ROBLOX then Vector2.new(1920, 1080) else { X = 1920, Y = 1080 }) :: any)
end)

if IS_ROBLOX then
	-- Require every sibling suite, deferring Init.spec to the very end.
	local initSpec: ModuleScript? = nil
	for _, child in script:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		elseif child.Name == "Init.spec" then
			initSpec = child :: ModuleScript
		else
			require(child)
		end
	end
	if initSpec then
		require(initSpec)
	end
else
	require("./unit/Graph.spec")
	require("./unit/Clean.spec")
	require("./unit/Store.spec")
	require("./unit/Wrap.spec")
	require("./unit/For.spec")
	require("./unit/Selector.spec")
	require("./unit/Conditional.spec")
	require("./unit/Safe.spec")
	require("./unit/Context.spec")
	require("./unit/Async.spec")
	require("./unit/Find.spec")
	require("./unit/Edit.spec")
	require("./unit/Bind.spec")
	require("./unit/Motion.spec")
	require("./unit/Color.spec")
	require("./unit/Responsive.spec")
	require("./unit/Layout.spec")
	require("./unit/Init.spec")
end

return {}
