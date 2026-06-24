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

test("responsive · scaleFor min mode fits the tighter axis", function()
	expect(approx(Responsive.scaleFor(1920, 1080), 1), "at reference → 1.0")
	expect(approx(Responsive.scaleFor(960, 540), 0.5), "half reference → 0.5")
	expect(approx(Responsive.scaleFor(800, 600), 800 / 1920), "min picks the tighter (width) axis")
	expect(approx(Responsive.scaleFor(3840, 2160), 2), "above reference scales up unclamped")
end)

test("responsive · scaleFor honors mode", function()
	expect(approx(Responsive.scaleFor(960, 1080, { mode = "width" }), 0.5), "width mode tracks X")
	expect(approx(Responsive.scaleFor(1920, 540, { mode = "height" }), 0.5), "height mode tracks Y")
	expect(approx(Responsive.scaleFor(800, 1080, { mode = "max" }), 1), "max picks the looser axis")
	expect(approx(Responsive.scaleFor(960, 540, { mode = "diagonal" }), 0.5), "diagonal ratio")
end)

test("responsive · scaleFor clamps", function()
	expect(approx(Responsive.scaleFor(384, 216, { min = 0.5 }), 0.5), "min clamp floors the factor")
	expect(approx(Responsive.scaleFor(3840, 2160, { max = 1.5 }), 1.5), "max clamp caps the factor")
end)

test("responsive · scaleFor unknown mode falls back to min (expected warn)", function()
	expect(approx(Responsive.scaleFor(960, 540, { mode = "wat" :: any }), 0.5), "bad mode → min")
end)

test("responsive · breakpointFor thresholds", function()
	expect(Responsive.breakpointFor(599) == "phone", "< 600 → phone")
	expect(Responsive.breakpointFor(600) == "tablet", "600 boundary → tablet")
	expect(Responsive.breakpointFor(1023) == "tablet", "< 1024 → tablet")
	expect(Responsive.breakpointFor(1024) == "desktop", "1024 boundary → desktop")
	expect(
		Responsive.breakpointFor(700, { breakpoints = { phone = 800, tablet = 1600 } }) == "phone",
		"custom thresholds"
	)
end)

test("responsive · default node values", function()
	expect(approx(Flux.scale:get(), 1), "default scale at reference is 1.0")
	expect(Flux.breakpoint:get() == "desktop", "default breakpoint is desktop")
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
	expect(Flux.breakpoint:get() == "tablet", "800 wide → tablet")
	Flux.viewport:set({ X = 500, Y = 900 } :: any)
	expect(Flux.breakpoint:get() == "phone", "500 wide → phone")
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
