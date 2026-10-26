--!nonstrict
local env = if game ~= nil
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Flux, sert, IS_ROBLOX = env.Flux, env.sert, env.IS_ROBLOX

local test = sert.test
local expect = sert
local Responsive = Flux.Responsive
local Vector2 = env.Vector2

-- Derivation math is tested through the factories with a private viewport source,
-- the same seam container queries use: a Vector2 node stands in for a surface.
test("responsive · scaleOf fits the tighter axis by default, honors mode and clamps", function()
	local bogus = env.fresh("wat")
	local cases = {
		{ Vector2.new(1920, 1080), {}, 1 },
		{ Vector2.new(960, 540), {}, 0.5 },
		{ Vector2.new(800, 600), {}, 800 / 1920 }, -- the tighter (width) axis
		{ Vector2.new(3840, 2160), {}, 2 }, -- above the reference, unclamped
		{ Vector2.new(960, 1080), { mode = "width" }, 0.5 },
		{ Vector2.new(1920, 540), { mode = "height" }, 0.5 },
		{ Vector2.new(800, 1080), { mode = "max" }, 1 }, -- the looser axis
		{ Vector2.new(384, 216), { min = 0.5 }, 0.5 },
		{ Vector2.new(3840, 2160), { max = 1.5 }, 1.5 },
		{ Vector2.new(960, 540), { mode = bogus }, 0.5 },
	}
	local warned = env.warnings(function()
		for _, case in cases do
			local options = table.clone(case[2]) :: any
			options.viewport = Flux(case[1])
			local s = Responsive.scaleOf(options)
			sert.near(s:get(), case[3], nil, `{case[1].X}x{case[1].Y} with {next(case[2])}: got {s:get()}`)
			s:Destroy()
		end
	end)
	expect.eq(warned[1], `[Flux] unknown scale mode "{bogus}"; falling back to "min"`, "the unknown mode warns")
end)

test("responsive · breakpointOf thresholds", function()
	local vp = Flux(Vector2.new(599, 1080))
	local b = Responsive.breakpointOf({ viewport = vp })
	expect(b:get() == "phone", "< 600 → phone")
	vp(Vector2.new(600, 1080))
	expect(b:get() == "tablet", "600 boundary → tablet")
	vp(Vector2.new(1023, 1080))
	expect(b:get() == "tablet", "< 1024 → tablet")
	vp(Vector2.new(1024, 1080))
	expect(b:get() == "desktop", "1024 boundary → desktop")
	b:Destroy()

	local custom = Responsive.breakpointOf({
		viewport = Flux(Vector2.new(700, 0)),
		breakpoints = { phone = 800, tablet = 1600 },
	})
	expect(custom:get() == "phone", "custom thresholds")
	custom:Destroy()
end)

test("responsive · scale & breakpoint nodes start at the reference and react to viewport writes", function()
	sert.near(Flux.Responsive.scale:get(), 1, nil, "default scale at reference is 1.0")
	expect(Responsive.breakpoint:get() == "desktop", "default breakpoint is desktop")
	-- The viewport node is the write seam.
	Flux.Responsive.viewport:set(Vector2.new(800, 600))
	sert.near(Flux.Responsive.scale:get(), 800 / 1920, nil, "scale recomputes from viewport (pull-based)")
	expect(Responsive.breakpoint:get() == "tablet", "800 wide → tablet")
	Flux.Responsive.viewport:set(Vector2.new(500, 900))
	expect(Responsive.breakpoint:get() == "phone", "500 wide → phone")
end)

test("responsive · scaleOf / breakpointOf escape hatches use merged config", function()
	Flux.Responsive.viewport:set(Vector2.new(1280, 720))
	local s = Responsive.scaleOf({ mode = "width" })
	sert.near(s:get(), 1280 / 1920, nil, "scaleOf overrides mode")
	local b = Responsive.breakpointOf({ breakpoints = { phone = 400, tablet = 800 } })
	expect(b:get() == "desktop", "breakpointOf overrides thresholds (1280 ≥ 800)")
	s:Destroy()
	b:Destroy()
end)

test("responsive · scaleOf/breakpointOf take a reference and a function viewport source", function()
	-- e.g. a plugin dock: Flux(dock, "AbsoluteSize"); here a plain node stands in for the surface size.
	local container = Flux(Vector2.new(400, 300))
	local s = Responsive.scaleOf({ viewport = container, reference = Vector2.new(800, 600) })
	local fn = Responsive.breakpointOf({
		viewport = function()
			return Vector2.new(container().X / 2, 0)
		end,
	})
	sert.near(s:get(), 0.5, nil, "scale derives against the given reference")
	expect(fn:get() == "phone", "a function source works too")
	container(Vector2.new(1600, 1200))
	sert.near(s:get(), 2, nil, "and both track the source")
	expect(fn:get() == "tablet", "and both track the source (function)")
	s:Destroy()
	fn:Destroy()
end)

test("responsive · platform and display size resolve to known classes", function()
	local platform = Responsive.platform:get()
	expect(
		platform == "pc" or platform == "mobile" or platform == "console" or platform == "vr",
		"platform is a known device class"
	)
	local display = Responsive.displaySize:get()
	expect(display == "Small" or display == "Medium" or display == "Large", "displaySize is a known size")
	if not IS_ROBLOX then
		expect(platform == "pc", "headless defaults to pc")
		expect(display == "Medium", "headless displays are Medium")
	end
end)

test("responsive · input and accessibility nodes hold known values", function()
	local mode = Responsive.input:get()
	expect(mode == "keyboard" or mode == "touch" or mode == "gamepad", "input is a known mode")
	local size = Responsive.textSize:get()
	expect(size == "Medium" or size == "Large" or size == "Larger" or size == "Largest", "textSize is a known size")
	expect(type(Responsive.reducedMotion:get()) == "boolean", "reducedMotion is a boolean")
	local transparency = Responsive.preferredTransparency:get()
	expect(
		type(transparency) == "number" and transparency >= 0 and transparency <= 1,
		"preferredTransparency is within [0, 1]"
	)
	if not IS_ROBLOX then
		expect(mode == "keyboard", "headless input matches the pc platform")
		expect(
			size == "Medium" and Responsive.reducedMotion:get() == false and transparency == 1,
			"headless preferences are the engine defaults"
		)
	end
end)

test("responsive · input modes map every gamepad slot, and sensors leave the mode alone", function()
	local inputFor = (if IS_ROBLOX
		then require((game :: any).ReplicatedStorage.Flux.Responsive) :: any
		else require("../../src/Responsive") :: any)._inputFor
	expect(inputFor("Gamepad1") == "gamepad" and inputFor("Gamepad8") == "gamepad", "every gamepad slot")
	expect(inputFor("Accelerometer") == nil and inputFor("Focus") == nil, "sensors and focus leave the mode alone")
end)

-- Headless only: the sert.env engine's services are writable, so a spec can play the player changing a setting.
local engineTest = if env.engine ~= nil then test else sert.skip
engineTest("responsive · the live nodes follow the engine's services", function()
	local services = env.Compat.services
	local Enum = env.Enum
	local GuiService, UserInputService = services.GuiService, services.UserInputService
	GuiService.PreferredTextSize = Enum.PreferredTextSize.Larger
	GuiService.ReducedMotionEnabled = true
	GuiService.PreferredTransparency = 0.5
	UserInputService.PreferredInput = Enum.PreferredInput.Gamepad
	UserInputService.KeyboardEnabled = false
	env.settle()
	local seen = {
		Responsive.textSize:get(),
		Responsive.reducedMotion:get(),
		Responsive.preferredTransparency:get(),
		Responsive.input:get(),
		Responsive.platform:get(),
	}
	GuiService.PreferredTextSize = Enum.PreferredTextSize.Medium
	GuiService.ReducedMotionEnabled = false
	GuiService.PreferredTransparency = 1
	UserInputService.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
	UserInputService.KeyboardEnabled = true
	env.settle()
	expect.eq(seen[1], "Larger", "textSize follows PreferredTextSize")
	expect.eq(seen[2], true, "reducedMotion follows ReducedMotionEnabled")
	expect.eq(seen[3], 0.5, "preferredTransparency follows PreferredTransparency")
	expect.eq(seen[4], "gamepad", "input follows PreferredInput")
	expect.eq(seen[5], "mobile", "platform re-derives without a keyboard")
	expect.eq(Responsive.platform:get(), "pc", "and back")
end)

return {}
