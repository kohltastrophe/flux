--!nonstrict
local env = if game ~= nil
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Flux, sert = env.Flux, env.sert

local test = sert.test
local expect = sert
local flush = Flux.flush
local Color3 = env.Color3
local ColorSequence = env.ColorSequence
local NumberSequence = env.NumberSequence
local Enum = env.Enum
local UDim = env.UDim
local UDim2 = env.UDim2
local Vector2 = env.Vector2

test("layout · padding (number, table, struct node)", function()
	local insets = Flux({ top = 10, bottom = 0, left = 5, right = 5 })
	local all, sided, bound
	local s = Flux.scope(function()
		all = Flux.padding(8)
		sided = Flux.padding({ x = 16, top = 4 })
		bound = Flux.padding(insets)
	end)

	expect(all:IsA("UIPadding"), "padding returns a UIPadding")
	expect(all.PaddingTop == UDim.new(0, 8), "number → offset top")
	expect(
		all.PaddingLeft == UDim.new(0, 8) and all.PaddingRight == UDim.new(0, 8) and all.PaddingBottom == UDim.new(0, 8),
		"all four sides set"
	)

	expect(sided.PaddingLeft == UDim.new(0, 16) and sided.PaddingRight == UDim.new(0, 16), "x → left/right")
	expect(sided.PaddingTop == UDim.new(0, 4), "top override")
	expect(sided.PaddingBottom == UDim.new(0, 0), "unset side stays default")

	flush()
	expect(bound.PaddingTop == UDim.new(0, 10), "struct node bound reactively")
	insets({ top = 20, bottom = 0, left = 5, right = 5 })
	flush()
	expect(bound.PaddingTop == UDim.new(0, 20), "struct node update tracked")

	s:Destroy()
end)

test("layout · list maps friendly strings, gap & sets SortOrder explicitly", function()
	local l, l2
	local s = Flux.scope(function()
		l = Flux.list({ gap = 12, direction = "x", align = "center" })
		-- justify is the main axis (horizontal here); raw enums go through the
		-- axis-pinned horizontalAlign/verticalAlign.
		l2 = Flux.list({ direction = "x", justify = "end", verticalAlign = Enum.VerticalAlignment.Top })
	end)

	expect(l:IsA("UIListLayout"), "list returns a UIListLayout")
	expect(l.Padding == UDim.new(0, 12), "gap → Padding offset")
	expect(l.FillDirection == Enum.FillDirection.Horizontal, "direction x → Horizontal")
	expect(l.VerticalAlignment == Enum.VerticalAlignment.Center, "align → cross-axis (vertical) center")
	expect(l.SortOrder == Enum.SortOrder.LayoutOrder, "SortOrder is LayoutOrder")

	expect(l2.HorizontalAlignment == Enum.HorizontalAlignment.Right, "justify → main-axis (horizontal) end")
	expect(l2.VerticalAlignment == Enum.VerticalAlignment.Top, "verticalAlign accepts a raw Enum")

	-- Set by the helper itself, not the per-class defaults: an engine-default UIListLayout sorts by Name.
	local wereDefaultsOn = Flux.Flags.defaults
	Flux.Flags.defaults = false
	local bare, grid
	local s2 = Flux.scope(function()
		bare = Flux.list({ direction = "y" })
		grid = Flux.grid({ cell = 32 })
	end)
	Flux.Flags.defaults = wereDefaultsOn
	expect(bare.SortOrder == Enum.SortOrder.LayoutOrder, "a list orders by LayoutOrder with the defaults off")
	expect(grid.SortOrder == Enum.SortOrder.LayoutOrder, "and so does a grid")
	s2:Destroy()

	s:Destroy()
end)

test("layout · grid and aspectRatio", function()
	local g, ar
	local s = Flux.scope(function()
		g = Flux.grid({ cell = Vector2.new(80, 80), gap = 4, fill = "y", maxCells = 3 })
		ar = Flux.aspectRatio(1.6, "scale", "height")
	end)

	expect(g:IsA("UIGridLayout"), "grid returns a UIGridLayout")
	expect(g.CellSize == UDim2.fromOffset(80, 80), "cell Vector2 → offset UDim2")
	expect(g.CellPadding == UDim2.fromOffset(4, 4), "gap number → offset UDim2")
	expect(g.FillDirection == Enum.FillDirection.Vertical, "fill y → Vertical")
	expect(g.FillDirectionMaxCells == 3, "maxCells set")

	sert.near(ar.AspectRatio, 1.6, nil, "ratio set")
	expect(ar.AspectType == Enum.AspectType.ScaleWithParentSize, "aspectType friendly string")
	expect(ar.DominantAxis == Enum.DominantAxis.Height, "dominantAxis friendly string")

	s:Destroy()
end)

test("layout · corner and stroke", function()
	local radius = Flux(4)
	local c, defaulted, st, inner
	local s = Flux.scope(function()
		c = Flux.corner(radius)
		defaulted = Flux.corner()
		st = Flux.stroke({ thickness = 2, color = Color3.new(1, 0, 0), mode = "border", joins = "miter" })
		inner = Flux.stroke({ mode = "border", position = "inner", offset = -1 })
	end)
	flush()
	expect(c:IsA("UICorner"), "corner returns a UICorner")
	expect(c.CornerRadius == UDim.new(0, 4), "reactive radius bound")
	radius(12)
	flush()
	expect(c.CornerRadius == UDim.new(0, 12), "reactive radius tracks")
	expect(defaulted.CornerRadius == UDim.new(0, 8), "corner() keeps the engine default")

	expect(st:IsA("UIStroke"), "stroke returns a UIStroke")
	expect(st.Thickness == 2 and st.Color == Color3.new(1, 0, 0), "stroke props set")
	expect(st.ApplyStrokeMode == Enum.ApplyStrokeMode.Border, "stroke mode friendly string")
	expect(st.LineJoinMode == Enum.LineJoinMode.Miter, "stroke joins friendly string")
	expect(st.BorderStrokePosition == Enum.BorderStrokePosition.Outer, "position left at the engine default")
	expect(inner.BorderStrokePosition == Enum.BorderStrokePosition.Inner, "stroke position friendly string")
	expect(inner.BorderOffset == UDim.new(0, -1), "stroke offset in pixels")

	local sides
	local s2 = Flux.scope(function()
		sides = Flux.corner({ top = radius, bottomLeft = 2 })
	end)
	flush()
	expect(
		sides.TopLeftRadius == UDim.new(0, 12) and sides.TopRightRadius == UDim.new(0, 12),
		"a side names two corners"
	)
	expect(sides.BottomLeftRadius == UDim.new(0, 2), "a corner on its own")
	expect(sides.BottomRightRadius == UDim.new(0, 8), "an unnamed corner keeps the engine default")
	radius(6)
	flush()
	expect(sides.TopLeftRadius == UDim.new(0, 6), "per-corner radii track")
	s2:Destroy()
	s:Destroy()
end)

test("layout · flex defaults to fill and accepts reactive modes", function()
	local mode = Flux("shrink")
	local fill, reactive
	local s = Flux.scope(function()
		fill = Flux.flex()
		reactive = Flux.flex(mode)
	end)
	flush()
	expect(fill.FlexMode == Enum.UIFlexMode.Fill, "flex() → Fill")
	expect(reactive.FlexMode == Enum.UIFlexMode.Shrink, "reactive mode bound")
	mode("grow")
	flush()
	expect(reactive.FlexMode == Enum.UIFlexMode.Grow, "reactive mode tracks")
	mode:set(nil) -- `mode(nil)` would be a read, not a write
	flush()
	expect(reactive.FlexMode == Enum.UIFlexMode.Fill, "a reactive nil reads as fill, like flex()")
	mode(Enum.UIFlexMode.Shrink)
	flush()
	expect(reactive.FlexMode == Enum.UIFlexMode.Shrink, "a reactive raw enum passes through")
	env.warnings(function() -- an unknown mode warns (once per session)
		mode("bogus")
		flush()
	end)
	expect(reactive.FlexMode == Enum.UIFlexMode.None, "a reactive unknown value writes the engine default")
	mode("grow")
	flush()
	expect(reactive.FlexMode == Enum.UIFlexMode.Grow, "and recovers once the value is valid")
	s:Destroy()
end)

test("layout · list flex distribution strings and lineAlign", function()
	local l
	local s = Flux.scope(function()
		l = Flux.list({ direction = "x", justify = "evenly", align = "stretch", wraps = true, lineAlign = "center" })
	end)
	expect(l.HorizontalFlex == Enum.UIFlexAlignment.SpaceEvenly, "justify evenly → main-axis flex")
	expect(l.VerticalFlex == Enum.UIFlexAlignment.Fill, "align stretch → cross-axis flex")
	expect(l.ItemLineAlignment == Enum.ItemLineAlignment.Center, "lineAlign → ItemLineAlignment")
	expect(l.Wraps == true, "wraps set")
	s:Destroy()
end)

test("layout · fully reactive list: direction re-routes align/justify", function()
	local dir = Flux("x")
	local l
	local s = Flux.scope(function()
		l = Flux.list({ direction = dir, align = "center", justify = "between" })
	end)
	flush()
	expect(l.FillDirection == Enum.FillDirection.Horizontal, "reactive direction bound")
	expect(l.HorizontalFlex == Enum.UIFlexAlignment.SpaceBetween, "justify → main-axis flex (horizontal)")
	expect(l.VerticalAlignment == Enum.VerticalAlignment.Center, "align → cross axis (vertical)")

	dir("y")
	flush()
	expect(l.FillDirection == Enum.FillDirection.Vertical, "direction tracked")
	expect(l.VerticalFlex == Enum.UIFlexAlignment.SpaceBetween, "justify follows the main-axis flip")
	expect(l.HorizontalAlignment == Enum.HorizontalAlignment.Center, "align follows the cross-axis flip")
	expect(l.HorizontalFlex == Enum.UIFlexAlignment.None, "stale main-axis flex cleared")
	expect(l.VerticalAlignment == Enum.VerticalAlignment.Top, "stale cross alignment resets to engine default")
	s:Destroy()
end)

test("layout · reactive enum props (aspectType, grid fill)", function()
	local at = Flux("fit")
	local fill = Flux("x")
	local ar, g
	local s = Flux.scope(function()
		ar = Flux.aspectRatio(1, at)
		g = Flux.grid({ fill = fill })
	end)
	flush()
	expect(ar.AspectType == Enum.AspectType.FitWithinMaxSize, "reactive aspectType bound")
	expect(g.FillDirection == Enum.FillDirection.Horizontal, "reactive grid fill bound")
	at("scale")
	fill("y")
	flush()
	expect(ar.AspectType == Enum.AspectType.ScaleWithParentSize, "reactive aspectType tracks")
	expect(g.FillDirection == Enum.FillDirection.Vertical, "reactive grid fill tracks")
	s:Destroy()
end)

test("layout · a reactive pinned override that yields nil falls through to routing", function()
	local pin = Flux.signal(nil)
	local l
	local s = Flux.scope(function()
		l = Flux.list({ direction = "x", horizontalAlign = pin, justify = "end" })
	end)
	flush()
	expect(l.HorizontalAlignment == Enum.HorizontalAlignment.Right, "nil override routes justify to the main axis")
	pin("center")
	flush()
	expect(l.HorizontalAlignment == Enum.HorizontalAlignment.Center, "a value pins the axis")
	pin:set(nil, true)
	flush()
	expect(l.HorizontalAlignment == Enum.HorizontalAlignment.Right, "back to nil routes again")
	s:Destroy()
end)

test("layout · padding follows a source that changes shape or starts empty", function()
	local compact = Flux(true)
	local late = Flux.signal(nil)
	local pad, lazy
	local s = Flux.scope(function()
		pad = Flux.padding(function()
			return if compact() then { top = 8 } else 4
		end)
		lazy = Flux.padding(late)
	end)
	flush()
	expect(pad.PaddingTop == UDim.new(0, 8) and pad.PaddingLeft == UDim.new(0, 0), "struct shape")
	compact(false)
	flush()
	expect(pad.PaddingTop == UDim.new(0, 4) and pad.PaddingLeft == UDim.new(0, 4), "length shape after the flip")
	compact(true)
	flush()
	expect(pad.PaddingTop == UDim.new(0, 8) and pad.PaddingLeft == UDim.new(0, 0), "struct shape again")
	expect(lazy.PaddingTop == UDim.new(0, 0), "a nil source reads as no padding")
	late(6)
	flush()
	expect(lazy.PaddingTop == UDim.new(0, 6), "the source filling in later binds")
	s:Destroy()
end)

test("layout · a gap function binds reactively", function()
	local inset = Flux(10)
	local l
	local s = Flux.scope(function()
		l = Flux.list({
			gap = function()
				return inset() // 2
			end,
		})
	end)
	flush()
	expect(l.Padding == UDim.new(0, 5), "gap fn → Padding")
	inset(30)
	flush()
	expect(l.Padding == UDim.new(0, 15), "gap fn tracks its deps")
	s:Destroy()
end)

test("layout · UDim lengths pass through untouched (scale preserved)", function()
	local pad, l
	local s = Flux.scope(function()
		pad = Flux.padding(UDim.new(0.5, 4))
		l = Flux.list({ gap = UDim.new(0.1, 0) })
	end)
	expect(pad.PaddingTop == UDim.new(0.5, 4), "padding UDim as-is")
	expect(l.Padding == UDim.new(0.1, 0), "gap UDim as-is")
	s:Destroy()
end)

test("layout · unknown friendly strings warn and leave engine defaults", function()
	local l, fx, ar, s
	local direction = env.fresh("diagonal")
	local warned = env.warnings(function()
		s = Flux.scope(function()
			l = Flux.list({ direction = direction })
			fx = Flux.flex("bogus")
			ar = Flux.aspectRatio(2, "cover", "depth")
		end)
	end)
	-- Each unknown string warns once per session (and a Studio --repeat reruns the session's suite): a fresh one warns.
	expect.eq(warned[1], `[Flux] unknown direction "{direction}"; falling back to default`)
	expect(l.FillDirection == Enum.FillDirection.Vertical, "bad direction → engine default (Vertical)")
	expect(fx.FlexMode == Enum.UIFlexMode.None, "bad flex mode → engine default (None)")
	expect(ar.AspectType == Enum.AspectType.FitWithinMaxSize, "bad aspectType → engine default")
	expect(ar.DominantAxis == Enum.DominantAxis.Width, "bad dominantAxis → engine default")
	s:Destroy()
end)

test("layout · an instance built inside a scope is destroyed with the scope", function()
	-- The shared constructor now registers an owner onDestroy (like Flux.new), so a layout
	-- instance built in a scope is torn down with it, not only via its parent's cascade.
	-- (Destroying fires deferred, so assert the synchronous signal: a destroyed instance's
	-- Parent is locked and re-parenting it errors.)
	local pad
	local s = Flux.scope(function()
		pad = Flux.padding(8)
	end)
	expect(pad:IsA("UIPadding"), "instance created inside the scope")
	s:Destroy()
	expect(not pcall(function()
		pad.Parent = env.Instance.new("Folder")
	end), "Parent locked (destroyed) on scope teardown")
end)

test("layout · gradient converts colors and transparencies", function()
	local stops = Flux({ Color3.new(1, 0, 0), Color3.new(0, 0, 1) })
	local solid, ramp, passthrough
	local s = Flux.scope(function()
		solid = Flux.gradient({ color = Color3.new(1, 0, 0), transparency = 0.5, rotation = 90 })
		ramp = Flux.gradient({
			color = stops,
			transparency = { 0, 0.5, 1 },
			offset = Vector2.new(0.1, 0),
			enabled = false,
		})
		passthrough = Flux.gradient({ color = ColorSequence.new(Color3.new(0, 1, 0)) })
	end)
	flush()

	expect(solid:IsA("UIGradient"), "gradient returns a UIGradient")
	expect(solid.Color == ColorSequence.new(Color3.new(1, 0, 0)), "a Color3 becomes a solid sequence")
	expect(solid.Transparency == NumberSequence.new(0.5) and solid.Rotation == 90, "number transparency and rotation")

	local colors = ramp.Color.Keypoints
	expect(#colors == 2 and colors[2].Time == 1 and colors[2].Value == Color3.new(0, 0, 1), "color stops spread evenly")
	local alphas = ramp.Transparency.Keypoints
	expect(#alphas == 3 and alphas[2].Time == 0.5 and alphas[3].Value == 1, "number stops spread evenly")
	expect(ramp.Offset == Vector2.new(0.1, 0) and ramp.Enabled == false, "offset and enabled map through")
	expect(passthrough.Color == ColorSequence.new(Color3.new(0, 1, 0)), "a ColorSequence passes through")

	stops({ Color3.new(0, 1, 0), Color3.new(1, 1, 1), Color3.new(0, 0, 0) })
	flush()
	expect(#ramp.Color.Keypoints == 3, "a reactive stop array re-spreads")
	s:Destroy()
end)

test("layout · sizeConstraint and textSizeConstraint", function()
	local maxWidth = Flux(256)
	local capped, boxed, free, text
	local s = Flux.scope(function()
		capped = Flux.sizeConstraint({ maxWidth = maxWidth })
		boxed = Flux.sizeConstraint({ min = Vector2.new(10, 20), max = Vector2.new(300, 200), minHeight = 40 })
		free = Flux.sizeConstraint()
		text = Flux.textSizeConstraint({ max = 24 })
	end)
	flush()

	expect(capped.MaxSize == Vector2.new(256, math.huge), "a width cap leaves the height unconstrained")
	expect(capped.MinSize == Vector2.zero, "and the minimum untouched")
	expect(boxed.MinSize == Vector2.new(10, 40), "a per-axis minimum wins over the vector component")
	expect(boxed.MaxSize == Vector2.new(300, 200), "a whole max vector applies")
	expect(free.MaxSize == Vector2.new(math.huge, math.huge), "sizeConstraint() keeps the engine defaults")
	expect(text:IsA("UITextSizeConstraint") and text.MaxTextSize == 24 and text.MinTextSize == 1, "text size capped")

	maxWidth(512)
	flush()
	expect(capped.MaxSize.X == 512, "a reactive width cap tracks")
	s:Destroy()
end)

test("layout · reactive padding supports x and y axis shorthands", function()
	local insets = Flux.signal({ x = 12, y = 8 } :: any)
	local pad
	local s = Flux.scope(function()
		pad = Flux.padding(insets)
	end)
	flush()
	expect(
		pad.PaddingLeft == UDim.new(0, 12)
			and pad.PaddingRight == UDim.new(0, 12)
			and pad.PaddingTop == UDim.new(0, 8)
			and pad.PaddingBottom == UDim.new(0, 8),
		"reactive padding table resolves x and y shorthands"
	)
	insets({ x = 20, top = 4, y = 10 })
	flush()
	expect(
		pad.PaddingLeft == UDim.new(0, 20) and pad.PaddingTop == UDim.new(0, 4) and pad.PaddingBottom == UDim.new(0, 10),
		"explicit side overrides axis shorthand on reactive update"
	)
	s:Destroy()
end)

return {}
