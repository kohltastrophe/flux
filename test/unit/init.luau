--!nonstrict
local IS_ROBLOX = game ~= nil
local env = if IS_ROBLOX
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("./lib/env") :: any

local Flux = env.Flux
local sert = env.sert

local defaultSnapshot: { [string]: { [string]: any } } = {}
for class, map in Flux.Defaults do
	defaultSnapshot[class] = table.clone(map)
end

local hooks = {
	afterEach = function()
		local leak = env.idle(Flux)
		Flux.Flags.defaults = true
		table.clear(Flux.Defaults)
		for class, map in defaultSnapshot do
			Flux.Defaults[class] = table.clone(map)
		end
		Flux.Responsive.viewport:set(env.Vector2.new(1920, 1080))
		env.reset()
		assert(not leak, leak)
	end,
}
sert.setup(hooks)

if IS_ROBLOX then
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
	sert.loaded(require("./unit/Graph.spec"))
	sert.loaded(require("./unit/Store.spec"))
	sert.loaded(require("./unit/Conditional.spec"))
	sert.loaded(require("./unit/Async.spec"))
	sert.loaded(require("./unit/Clock.spec"))
	sert.loaded(require("./unit/Edit.spec"))
	sert.loaded(require("./unit/Bind.spec"))
	sert.loaded(require("./unit/Motion.spec"))
	sert.loaded(require("./unit/Responsive.spec"))
	sert.loaded(require("./unit/Layout.spec"))
	sert.loaded(require("./unit/Interact.spec"))
	sert.loaded(require("./unit/Sync.spec"))
	sert.loaded(require("./unit/Init.spec"))
end

return hooks
