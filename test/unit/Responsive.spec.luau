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
local flush = Flux.flush
local Responsive = Flux.Responsive

local approx = sert.approx

-- Derivation math is tested through the factories with a private viewport source,
-- the same seam container queries use: a plain {X,Y} node stands in for a surface.
test("responsive · scaleOf min mode fits the tighter axis", function()
	local vp = Flux({ X = 1920, Y = 1080 } :: any)
	local s = Responsive.scaleOf({ viewport = vp })
	expect(approx(s:get(), 1), "at reference → 1.0")
	vp({ X = 960, Y = 540 } :: any)
	expect(approx(s:get(), 0.5), "half reference → 0.5")
	vp({ X = 800, Y = 600 } :: any)
	expect(approx(s:get(), 800 / 1920), "min picks the tighter (width) axis")
	vp({ X = 3840, Y = 2160 } :: any)
	expect(approx(s:get(), 2), "above reference scales up unclamped")
	s:Destroy()
end)

test("responsive · scaleOf honors mode", function()
	local w = Responsive.scaleOf({ viewport = Flux({ X = 960, Y = 1080 } :: any), mode = "width" })
	expect(approx(w:get(), 0.5), "width mode tracks X")
	local h = Responsive.scaleOf({ viewport = Flux({ X = 1920, Y = 540 } :: any), mode = "height" })
	expect(approx(h:get(), 0.5), "height mode tracks Y")
	local m = Responsive.scaleOf({ viewport = Flux({ X = 800, Y = 1080 } :: any), mode = "max" })
	expect(approx(m:get(), 1), "max picks the looser axis")
	w:Destroy()
	h:Destroy()
	m:Destroy()
end)

test("responsive · scaleOf clamps", function()
	local floored = Responsive.scaleOf({ viewport = Flux({ X = 384, Y = 216 } :: any), min = 0.5 })
	expect(approx(floored:get(), 0.5), "min clamp floors the factor")
	local capped = Responsive.scaleOf({ viewport = Flux({ X = 3840, Y = 2160 } :: any), max = 1.5 })
	expect(approx(capped:get(), 1.5), "max clamp caps the factor")
	floored:Destroy()
	capped:Destroy()
end)

test("responsive · scaleOf unknown mode falls back to min (expected warn)", function()
	local s = Responsive.scaleOf({ viewport = Flux({ X = 960, Y = 540 } :: any), mode = "wat" :: any })
	expect(approx(s:get(), 0.5), "bad mode → min")
	s:Destroy()
end)

test("responsive · breakpointOf thresholds", function()
	local vp = Flux({ X = 599, Y = 1080 } :: any)
	local b = Responsive.breakpointOf({ viewport = vp })
	expect(b:get() == "phone", "< 600 → phone")
	vp({ X = 600, Y = 1080 } :: any)
	expect(b:get() == "tablet", "600 boundary → tablet")
	vp({ X = 1023, Y = 1080 } :: any)
	expect(b:get() == "tablet", "< 1024 → tablet")
	vp({ X = 1024, Y = 1080 } :: any)
	expect(b:get() == "desktop", "1024 boundary → desktop")
	b:Destroy()

	local custom = Responsive.breakpointOf({
		viewport = Flux({ X = 700, Y = 0 } :: any),
		breakpoints = { phone = 800, tablet = 1600 },
	})
	expect(custom:get() == "phone", "custom thresholds")
	custom:Destroy()
end)

test("responsive · default node values", function()
	expect(approx(Flux.scale:get(), 1), "default scale at reference is 1.0")
	expect(Responsive.breakpoint:get() == "desktop", "default breakpoint is desktop")
	if not IS_ROBLOX then
		local insets = Flux.safeArea:get()
		expect(
			insets.top == 0 and insets.bottom == 0 and insets.left == 0 and insets.right == 0,
			"default safeArea is zero (headless)"
		)
	end
end)

test("responsive · scale & breakpoint nodes react to viewport writes", function()
	-- The viewport node is the write seam; a plain {X,Y} table drives the math.
	Flux.viewport:set({ X = 800, Y = 600 } :: any)
	expect(approx(Flux.scale:get(), 800 / 1920), "scale recomputes from viewport (pull-based)")
	expect(Responsive.breakpoint:get() == "tablet", "800 wide → tablet")
	Flux.viewport:set({ X = 500, Y = 900 } :: any)
	expect(Responsive.breakpoint:get() == "phone", "500 wide → phone")
end)

test("responsive · scaleOf / breakpointOf escape hatches use merged config", function()
	Flux.viewport:set({ X = 1280, Y = 720 } :: any)
	local s = Responsive.scaleOf({ mode = "width" })
	expect(approx(s:get(), 1280 / 1920), "scaleOf overrides mode")
	local b = Responsive.breakpointOf({ breakpoints = { phone = 400, tablet = 800 } })
	expect(b:get() == "desktop", "breakpointOf overrides thresholds (1280 ≥ 800)")
	s:Destroy()
	b:Destroy()
end)

test("responsive · scaleOf/breakpointOf accept a custom viewport source (container queries)", function()
	-- e.g. a plugin dock: Flux(dock, "AbsoluteSize"); here a plain node stands in for the surface size.
	local container = Flux({ X = 400, Y = 300 } :: any)
	local s = Responsive.scaleOf({ viewport = container, reference = { X = 800, Y = 600 } :: any })
	local b = Responsive.breakpointOf({ viewport = container, breakpoints = { phone = 500, tablet = 700 } })

	expect(approx(s:get(), 0.5), "scale derives from the container, not the global viewport")
	expect(b:get() == "phone", "breakpoint derives from the container width")

	container({ X = 800, Y = 600 } :: any)
	expect(approx(s:get(), 1), "scale tracks container resizes")
	expect(b:get() == "desktop", "breakpoint tracks container resizes")

	local fn = Responsive.breakpointOf({
		viewport = function()
			return { X = container().X / 2, Y = 0 } :: any
		end,
	})
	expect(fn:get() == "phone", "a function source works too")

	s:Destroy()
	b:Destroy()
	fn:Destroy()
end)

rtest("responsive · scale node drives a real UIScale from viewport", function()
	local uiScale
	local s = Flux.scope(function()
		Flux.viewport:set(Vector2.new(960, 540))
		uiScale = Flux.new("UIScale")({ Scale = Flux.scale })
	end)
	flush()
	expect(approx(uiScale.Scale, 0.5), "UIScale tracks scale node (960x540 → 0.5)")
	Flux.viewport:set(Vector2.new(1920, 1080))
	flush()
	expect(approx(uiScale.Scale, 1), "UIScale updates on viewport change")
	s:Destroy()
end)

rtest("responsive · safeArea exposes numeric inset struct", function()
	local insets = Flux.safeArea:get()
	expect(
		type(insets.top) == "number"
			and type(insets.bottom) == "number"
			and type(insets.left) == "number"
			and type(insets.right) == "number",
		"safeArea has numeric insets from GuiService"
	)
end)

return {}
