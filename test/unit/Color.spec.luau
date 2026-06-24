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

local rtest = sert.rtest
local expect = sert
local Color = Flux.Color

local approx = sert.approx

local function rgbApprox(a, b, eps)
	return approx(a.R, b.R, eps) and approx(a.G, b.G, eps) and approx(a.B, b.B, eps)
end

rtest("color · Oklab fromRGB/toRGB round-trips per channel", function()
	local cases = {
		Color3.new(0, 0, 0), -- black
		Color3.new(1, 1, 1), -- white
		Color3.new(0.5, 0.5, 0.5), -- mid grey
		Color3.new(1, 0, 0), -- saturated red
		Color3.new(0, 1, 0), -- saturated green
		Color3.new(0, 0, 1), -- saturated blue
		Color3.new(0.2, 0.6, 0.9), -- arbitrary
	}
	for _, c in cases do
		local lab = Color.Oklab.fromRGB(c)
		-- pass clamped=false so the inverse is exact: toRGB gamut-clips by default, which
		-- intentionally nudges saturated colours off the exact round-trip (the chroma-reduction
		-- clip is covered by the "gamut clip keeps colours in range" test below).
		local back = Color.Oklab.toRGB(lab, false)
		expect(approx(back.R, c.R, 1e-4), `R round-trip for {c}: got {back.R} expected {c.R}`)
		expect(approx(back.G, c.G, 1e-4), `G round-trip for {c}: got {back.G} expected {c.G}`)
		expect(approx(back.B, c.B, 1e-4), `B round-trip for {c}: got {back.B} expected {c.B}`)
	end
end)

rtest("color · Oklab fromLinear/toLinear round-trips per channel", function()
	local cases = {
		Color3.new(0, 0, 0),
		Color3.new(1, 1, 1),
		Color3.new(0.25, 0.5, 0.75),
		Color3.new(0.8, 0.1, 0.3),
	}
	for _, c in cases do
		local lab = Color.Oklab.fromLinear(c)
		-- pass clamped=false so the inverse is exact, not clamped to [0,1]
		local back = Color.Oklab.toLinear(lab, false)
		expect(approx(back.R, c.R, 1e-4), `linear R round-trip for {c}: got {back.R}`)
		expect(approx(back.G, c.G, 1e-4), `linear G round-trip for {c}: got {back.G}`)
		expect(approx(back.B, c.B, 1e-4), `linear B round-trip for {c}: got {back.B}`)
	end
end)

rtest("color · Oklab known values for linear black and white", function()
	-- Pure linear white maps to Oklab L=1, a=0, b=0; pure black to all zeros.
	local white = Color.Oklab.fromLinear(Color3.new(1, 1, 1))
	expect(approx(white.X, 1, 1e-4), `white L should be 1, got {white.X}`)
	expect(approx(white.Y, 0, 1e-4), `white a should be 0, got {white.Y}`)
	expect(approx(white.Z, 0, 1e-4), `white b should be 0, got {white.Z}`)

	local black = Color.Oklab.fromLinear(Color3.new(0, 0, 0))
	expect(approx(black.X, 0, 1e-6), `black L should be 0, got {black.X}`)
	expect(approx(black.Y, 0, 1e-6), `black a should be 0, got {black.Y}`)
	expect(approx(black.Z, 0, 1e-6), `black b should be 0, got {black.Z}`)
end)

rtest("color · sRGB fromLinear/toLinear round-trip and endpoints", function()
	-- toLinear is the inverse of fromLinear (sRGB gamma curve).
	local cases = {
		Color3.new(0, 0, 0),
		Color3.new(1, 1, 1),
		Color3.new(0.001, 0.5, 0.95), -- spans the linear segment (<0.0031308 path) and the power segment
		Color3.new(0.2, 0.4, 0.8),
	}
	for _, c in cases do
		local round = Color.sRGB.toLinear(Color.sRGB.fromLinear(c))
		expect(rgbApprox(round, c, 1e-5), `sRGB toLinear∘fromLinear round-trip for {c}: got {round}`)

		local round2 = Color.sRGB.fromLinear(Color.sRGB.toLinear(c))
		expect(rgbApprox(round2, c, 1e-5), `sRGB fromLinear∘toLinear round-trip for {c}: got {round2}`)
	end

	-- Endpoints are fixed points of both directions.
	expect(rgbApprox(Color.sRGB.fromLinear(Color3.new(0, 0, 0)), Color3.new(0, 0, 0), 1e-7), "fromLinear black")
	expect(rgbApprox(Color.sRGB.fromLinear(Color3.new(1, 1, 1)), Color3.new(1, 1, 1), 1e-7), "fromLinear white")
	expect(rgbApprox(Color.sRGB.toLinear(Color3.new(0, 0, 0)), Color3.new(0, 0, 0), 1e-7), "toLinear black")
	expect(rgbApprox(Color.sRGB.toLinear(Color3.new(1, 1, 1)), Color3.new(1, 1, 1), 1e-7), "toLinear white")
end)

rtest("color · sRGB fromLinear matches a known mid-grey value", function()
	-- Linear 0.5 encodes to sRGB ~0.7353569830 (standard sRGB OETF).
	local encoded = Color.sRGB.fromLinear(Color3.new(0.5, 0.5, 0.5))
	expect(approx(encoded.R, 0.7353569830, 1e-6), `sRGB encode of 0.5 should be ~0.73536, got {encoded.R}`)
	-- And the inverse decodes back.
	local decoded = Color.sRGB.toLinear(Color3.new(0.7353569830, 0.7353569830, 0.7353569830))
	expect(approx(decoded.R, 0.5, 1e-6), `sRGB decode should be ~0.5, got {decoded.R}`)
end)

rtest("color · Oklab HCL round-trips and matches a known hue", function()
	-- toHCL∘fromHCL is identity (within atan2 wrap) for in-range HCL triples. Hue is in degrees.
	local hcls = {
		Vector3.new(0, 0.0, 0.5), -- achromatic
		Vector3.new(90, 0.1, 0.6),
		Vector3.new(180, 0.2, 0.4),
		Vector3.new(270, 0.15, 0.7),
	}
	for _, hcl in hcls do
		local lab = Color.Oklab.fromHCL(hcl)
		local back = Color.Oklab.toHCL(lab)
		-- chroma and lightness must round-trip regardless of hue wrap
		expect(approx(back.Y, hcl.Y, 1e-5), `HCL chroma round-trip for {hcl}: got {back.Y}`)
		expect(approx(back.Z, hcl.Z, 1e-5), `HCL lightness round-trip for {hcl}: got {back.Z}`)
		if hcl.Y > 1e-6 then
			-- hue (X of HCL, degrees) round-trips when chroma is non-zero
			local dh = math.abs(back.X - hcl.X)
			dh = math.min(dh, math.abs(dh - 360)) -- allow wrap at 360°
			expect(dh < 1e-3, `HCL hue round-trip for {hcl}: got {back.X}`)
		end
	end

	-- fromHCL maps lightness to L (X) and zero chroma to zero a/b.
	local lab = Color.Oklab.fromHCL(Vector3.new(108, 0, 0.42))
	-- Vector3 components are 32-bit floats, so 0.42 round-trips with ~1e-7 error.
	expect(approx(lab.X, 0.42, 1e-6), `fromHCL L should be lightness, got {lab.X}`)
	expect(approx(lab.Y, 0, 1e-9), `fromHCL a should be 0 at zero chroma, got {lab.Y}`)
	expect(approx(lab.Z, 0, 1e-9), `fromHCL b should be 0 at zero chroma, got {lab.Z}`)
end)

rtest("color · lighten/darken adjust Oklab L and invert each other", function()
	local c = Color3.new(0.4, 0.55, 0.7)
	local lab = Color.Oklab.fromRGB(c)
	expect(approx(Color.Oklab.lighten(lab, 0.1).X, lab.X + 0.1, 1e-6), "lighten adds to L")
	-- darken(a) ≡ lighten(-a)
	local d = Color.Oklab.darken(lab, 0.1)
	local l = Color.Oklab.lighten(lab, -0.1)
	expect(approx(d.X, l.X, 1e-9) and approx(d.Y, l.Y, 1e-9) and approx(d.Z, l.Z, 1e-9), "darken ≡ lighten(-a)")
	-- L clamps to [0, 1]
	expect(Color.Oklab.lighten(Color.Oklab.fromRGB(Color3.new(1, 1, 1)), 0.5).X <= 1, "L clamps at 1")
	-- Color3 wrapper: lighten then darken by the same amount round-trips closely
	local back = Color.darken(Color.lighten(c, 0.1), 0.1)
	expect(rgbApprox(back, c, 1e-3), `lighten∘darken ≈ identity, got {back}`)
end)

rtest("color · saturate/desaturate adjust chroma and invert each other", function()
	local c = Color3.new(0.6, 0.3, 0.4)
	local lab = Color.Oklab.fromRGB(c)
	local chroma = math.sqrt(lab.Y ^ 2 + lab.Z ^ 2)
	local sat = Color.Oklab.saturate(lab, 0.05)
	expect(approx(math.sqrt(sat.Y ^ 2 + sat.Z ^ 2), chroma + 0.05, 1e-6), "saturate adds to chroma")
	-- desaturate(a) ≡ saturate(-a)
	local de = Color.Oklab.desaturate(lab, 0.05)
	local sn = Color.Oklab.saturate(lab, -0.05)
	expect(approx(de.Y, sn.Y, 1e-9) and approx(de.Z, sn.Z, 1e-9), "desaturate ≡ saturate(-a)")
	-- hue direction (a:b ratio) preserved by saturate
	expect(approx(sat.Y * lab.Z, sat.Z * lab.Y, 1e-9), "saturate preserves hue direction")
	-- a gray has no hue to saturate
	local gray = Color.Oklab.fromRGB(Color3.new(0.5, 0.5, 0.5))
	local stillGray = Color.Oklab.saturate(gray, 0.1)
	expect(approx(stillGray.Y, 0, 1e-6) and approx(stillGray.Z, 0, 1e-6), "cannot saturate a gray")
end)

rtest("color · rotateHue rotates around the wheel", function()
	local lab = Color.Oklab.fromRGB(Color3.new(0.8, 0.2, 0.2))
	-- 360° is a full turn back to the start
	local full = Color.Oklab.rotateHue(lab, 360)
	expect(approx(full.Y, lab.Y, 1e-5) and approx(full.Z, lab.Z, 1e-5), "rotateHue 360° ≈ identity")
	-- chroma and lightness preserved; hue advances by exactly 90°
	local rot = Color.Oklab.rotateHue(lab, 90)
	expect(approx(rot.X, lab.X, 1e-9), "rotateHue preserves L")
	expect(
		approx(math.sqrt(rot.Y ^ 2 + rot.Z ^ 2), math.sqrt(lab.Y ^ 2 + lab.Z ^ 2), 1e-6),
		"rotateHue preserves chroma"
	)
	local dh = (Color.Oklab.toHCL(rot).X - Color.Oklab.toHCL(lab).X) % 360
	expect(approx(dh, 90, 1e-3), `hue advances 90°, got {dh}`)
end)

rtest("color · grayscale removes chroma and preserves L", function()
	local lab = Color.Oklab.fromRGB(Color3.new(0.2, 0.7, 0.5))
	local gray = Color.Oklab.grayscale(lab)
	expect(approx(gray.Y, 0, 1e-9) and approx(gray.Z, 0, 1e-9), "grayscale zeroes chroma")
	expect(approx(gray.X, lab.X, 1e-9), "grayscale preserves L")
	-- Color3 result is neutral (R≈G≈B)
	local c = Color.grayscale(Color3.new(0.2, 0.7, 0.5))
	expect(approx(c.R, c.G, 1e-3) and approx(c.G, c.B, 1e-3), `grayscale Color3 is neutral, got {c}`)
end)

rtest("color · mix matches the engine's lab-lerp path", function()
	local a = Color3.new(0.9, 0.1, 0.1)
	local b = Color3.new(0.1, 0.1, 0.9)
	-- endpoints
	expect(rgbApprox(Color.mix(a, b, 0), a, 1e-4), "mix t=0 is a")
	expect(rgbApprox(Color.mix(a, b, 1), b, 1e-4), "mix t=1 is b")
	-- midpoint is the straight Oklab lerp, the same path the motion engine takes
	local expected = Color.Oklab.toRGB(Color.Oklab.fromRGB(a):Lerp(Color.Oklab.fromRGB(b), 0.5))
	expect(rgbApprox(Color.mix(a, b, 0.5), expected, 1e-6), "mix midpoint is the lab midpoint")
end)

rtest("color · fromTemperature spans warm to cool, normalised", function()
	local warm = Color.fromTemperature(2000)
	local cool = Color.fromTemperature(12000)
	-- warm light is red-dominant, cool light is blue-dominant
	expect(warm.R > warm.B, `2000K is warm (R>B), got {warm}`)
	expect(cool.B > cool.R, `12000K is cool (B>R), got {cool}`)
	-- max-channel normalised: the brightest channel is ~1
	expect(approx(math.max(warm.R, warm.G, warm.B), 1, 1e-6), "warm normalised to max 1")
	expect(approx(math.max(cool.R, cool.G, cool.B), 1, 1e-6), "cool normalised to max 1")
	-- input clamps: below 1000K equals 1000K
	expect(rgbApprox(Color.fromTemperature(500), Color.fromTemperature(1000), 1e-9), "temperature clamps low")
end)

rtest("color · luminance and contrast follow WCAG", function()
	expect(approx(Color.luminance(Color3.new(1, 1, 1)), 1, 1e-6), "white luminance is 1")
	expect(approx(Color.luminance(Color3.new(0, 0, 0)), 0, 1e-6), "black luminance is 0")
	-- 21:1 for black on white, symmetric, 1:1 for equal colours
	expect(approx(Color.contrast(Color3.new(1, 1, 1), Color3.new(0, 0, 0)), 21, 1e-4), "white/black contrast is 21")
	expect(approx(Color.contrast(Color3.new(0, 0, 0), Color3.new(1, 1, 1)), 21, 1e-4), "contrast is symmetric")
	local c = Color3.new(0.3, 0.6, 0.9)
	expect(approx(Color.contrast(c, c), 1, 1e-9), "contrast with self is 1")
end)

rtest("color · readable picks the more legible text colour", function()
	local white = Color3.new(1, 1, 1)
	local black = Color3.new(0, 0, 0)
	expect(Color.readable(white) == black, "black text on white")
	expect(Color.readable(black) == white, "white text on black")
	-- custom candidates: pick whichever contrasts better against a light bg
	local navy = Color3.new(0.05, 0.05, 0.3)
	expect(Color.readable(Color3.new(0.95, 0.95, 0.8), navy, white) == navy, "picks the higher-contrast candidate")
end)

rtest("color · gamut clip keeps colours in range and preserves hue", function()
	-- Saturating a primary pushes it out of gamut; the result must stay valid.
	local pushed = Color.saturate(Color3.new(1, 0, 0), 0.3)
	expect(pushed.R >= 0 and pushed.R <= 1, `clip R in range, got {pushed.R}`)
	expect(pushed.G >= 0 and pushed.G <= 1, `clip G in range, got {pushed.G}`)
	expect(pushed.B >= 0 and pushed.B <= 1, `clip B in range, got {pushed.B}`)
	-- The clipped colour keeps (approximately) the original hue, unlike a per-channel clamp.
	local outOfGamut = Vector3.new(0.7, 0.3, 0.1) -- high-chroma lab, outside sRGB
	local clipped = Color.Oklab.toRGB(outOfGamut, true)
	local hueIn = Color.Oklab.toHCL(outOfGamut).X
	local hueOut = Color.Oklab.toHCL(Color.Oklab.fromRGB(clipped)).X
	local dh = math.abs(hueIn - hueOut)
	dh = math.min(dh, 360 - dh)
	expect(dh < 2, `gamut clip preserves hue within 2°, got {dh}`)
end)

return {}
