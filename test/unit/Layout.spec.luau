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

test("layout · sert.roblox.Layout geometry, visibility, clipping and settle on Flux layout tree", function()
	local RobloxLayout = sert.roblox.Layout
	local width = Flux(180)
	local gap = Flux(8)
	local screen, panel, rowA, rowB, listConstraint, padConstraint
	local s = Flux.scope(function()
		rowA = Flux.new("Frame")({
			Name = "RowA",
			LayoutOrder = 1,
			Position = UDim2.fromOffset(0, 0),
			Size = function()
				return UDim2.fromOffset(width(), 32)
			end,
		})
		rowB = Flux.new("Frame")({
			Name = "RowB",
			LayoutOrder = 2,
			Position = UDim2.fromOffset(0, 40),
			Size = UDim2.fromOffset(260, 32),
		})
		listConstraint = Flux.list({ direction = "y", gap = gap })
		padConstraint = Flux.padding(12)
		panel = Flux.new("Frame")({
			Name = "Panel",
			ClipsDescendants = true,
			Position = UDim2.fromOffset(20, 30),
			Size = UDim2.fromOffset(200, 120),
			padConstraint,
			listConstraint,
			rowA,
			rowB,
		})
		screen = Flux.new("ScreenGui")({
			Enabled = true,
			panel,
		})
	end)
	flush()

	local settled = RobloxLayout.settle(panel, {
		maxFrames = 10,
		stable = 2,
		step = function()
			env.frame(1 / 60)
		end,
	})
	expect(settled, "Flux layout tree settles within frame budget")
	expect.eq(RobloxLayout.visible(panel), true, "panel is visible under enabled ScreenGui")
	expect.eq(RobloxLayout.visible(rowA), true, "rowA is visible inside panel")

	local rA = RobloxLayout.geometry.rect(rowA)
	expect.eq(rA.width, 180, "rowA initial width matches reactive signal")
	expect.eq(rA.height, 32, "rowA height matches UDim2")
	expect.eq(
		RobloxLayout.geometry.sameRect(rA, { x = 32, y = 42, width = 180, height = 32 }),
		true,
		"sameRect matches"
	)

	width(140)
	gap(16)
	flush()
	expect.eq(RobloxLayout.geometry.rect(rowA).width, 140, "rowA width updates reactively")
	expect.eq(listConstraint.Padding, UDim.new(0, 16), "list gap updates reactively")
	expect.eq(RobloxLayout.geometry.rect(rowB).y, 42 + 32 + 16, "rowB Y position reflects updated list gap")

	local low, high = RobloxLayout.clippedBounds(rowB)
	expect.eq(low.X, 32, "clippedBounds low.X starts at padded child left edge")
	expect.eq(high.X - low.X, 188, "ClipsDescendants clamps wider child width to panel right edge")

	screen.Enabled = false
	expect.eq(RobloxLayout.visible(rowA), false, "disabling ancestor ScreenGui hides descendant")

	s:Destroy()
	screen:Destroy()
end)

sert.laws.ui("layout · vstack and hstack with padding, flex, sizeConstraint and aspectRatio", {
	noTextOverflow = not env.IS_ROBLOX,
	mount = function(_uiEnv, parent, viewport)
		local hostParent, cleanHost = env.mountUi(parent, viewport)
		local cardW = math.min(viewport.X - 24, 480)
		local cardH = math.min(viewport.Y - 24, 320)
		local root: Frame
		local scope = Flux.scope(function()
			root = Flux.new("Frame")({
				Name = "Card",
				Parent = hostParent,
				Position = UDim2.fromOffset(12, 12),
				Size = UDim2.fromOffset(cardW, cardH),
				Flux.padding(12),
				Flux.sizeConstraint({ min = Vector2.new(200, 160), max = Vector2.new(600, 480) }),
				Flux.list({ direction = "y", gap = 8 }),
				Flux.new("Frame")({
					Name = "Header",
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 32),
					Flux.list({ direction = "x", gap = 8, align = "center" }),
					Flux.new("Frame")({
						Name = "Icon",
						LayoutOrder = 1,
						Size = UDim2.fromOffset(28, 28),
						Flux.aspectRatio(1, "fit", "height"),
					}),
					Flux.new("TextLabel")({
						Name = "Title",
						LayoutOrder = 2,
						Size = UDim2.fromOffset(120, 24),
						Text = "Inventory",
						TextSize = 14,
						TextScaled = true,
					}),
					Flux.new("Frame")({
						Name = "Spacer",
						LayoutOrder = 3,
						Size = UDim2.fromOffset(16, 8),
						Flux.flex("fill"),
					}),
					Flux.new("TextLabel")({
						Name = "Badge",
						LayoutOrder = 4,
						Size = UDim2.fromOffset(48, 22),
						Text = "PRO",
						TextSize = 12,
						TextScaled = true,
					}),
				}),
				Flux.new("Frame")({
					Name = "BodyRow1",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 36),
					Flux.padding({ x = 8, y = 4 }),
					Flux.new("TextLabel")({
						Name = "Label1",
						Size = UDim2.fromScale(1, 1),
						Text = "Primary slot configured",
						TextSize = 14,
						TextScaled = true,
					}),
				}),
				Flux.new("Frame")({
					Name = "BodyRow2",
					LayoutOrder = 3,
					Size = UDim2.new(1, 0, 0, 36),
					Flux.padding({ x = 8, y = 4 }),
					Flux.new("TextLabel")({
						Name = "Label2",
						Size = UDim2.fromScale(1, 1),
						Text = "Secondary slot ready",
						TextSize = 14,
						TextScaled = true,
					}),
				}),
			})
		end)
		flush()
		sert.defer(function()
			scope:Destroy()
			root:Destroy()
			cleanHost()
			flush()
		end)
		return root
	end,
	check = function(_uiEnv, root, vp)
		local RobloxLayout = sert.roblox.Layout
		RobloxLayout.audit(root, { viewport = vp.size, fitsParent = true, noTextOverflow = not env.IS_ROBLOX })
		local header = root:FindFirstChild("Header") :: Frame
		local row1 = root:FindFirstChild("BodyRow1") :: Frame
		local row2 = root:FindFirstChild("BodyRow2") :: Frame
		local icon = header:FindFirstChild("Icon") :: Frame
		local title = header:FindFirstChild("Title") :: TextLabel
		local spacer = header:FindFirstChild("Spacer") :: Frame
		local badge = header:FindFirstChild("Badge") :: TextLabel

		RobloxLayout.aligned({ header, row1, row2 }, "Left")
		RobloxLayout.spacing({ header, row1, row2 }, "Y", 8)
		RobloxLayout.aligned({ icon, title, spacer, badge }, "CenterY")
		RobloxLayout.spacing({ icon, title, spacer, badge }, "X", 8)
		RobloxLayout.aspectRatio(icon, 1)
		RobloxLayout.within(icon, header)
		RobloxLayout.nonZero(title)
	end,
})

local lastGridState: {
	gapSig: any,
	cellSig: any,
	gridInst: UIGridLayout,
} = nil :: any

sert.laws.ui("layout · grid and scrolling frame with AutomaticCanvasSize and reactive gap", {
	noTextOverflow = not env.IS_ROBLOX,
	mount = function(_uiEnv, parent, viewport)
		local hostParent, cleanHost = env.mountUi(parent, viewport)
		local gapSig = Flux.signal(6)
		local cellSig = Flux.signal(Vector2.new(72, 44))
		local scroll: ScrollingFrame
		local gridInst: UIGridLayout
		local scope = Flux.scope(function()
			gridInst = Flux.grid({ cell = cellSig, gap = gapSig, fill = "x" })
			local cells: { any } = {
				Name = "GridScroll",
				Parent = hostParent,
				Position = UDim2.fromOffset(10, 10),
				Size = UDim2.fromOffset(math.min(viewport.X - 20, 420), math.min(viewport.Y - 20, 260)),
				CanvasSize = UDim2.fromScale(0, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ClipsDescendants = true,
				Flux.padding(8),
				gridInst,
			}
			for i = 1, 8 do
				table.insert(
					cells,
					Flux.new("Frame")({
						Name = `Cell_{i}`,
						LayoutOrder = i,
						Flux.new("TextLabel")({
							Name = "Caption",
							Size = UDim2.fromScale(1, 1),
							Text = `Item {i}`,
							TextSize = 12,
							TextScaled = true,
						}),
					})
				)
			end
			scroll = Flux.new("ScrollingFrame")(cells)
		end)
		flush()
		lastGridState = {
			gapSig = gapSig,
			cellSig = cellSig,
			gridInst = gridInst,
		}
		sert.defer(function()
			scope:Destroy()
			scroll:Destroy()
			cleanHost()
			flush()
		end)
		return scroll
	end,
	check = function(_uiEnv, root, vp)
		local RobloxLayout = sert.roblox.Layout
		local checkText = not env.IS_ROBLOX
		RobloxLayout.audit(root, { viewport = vp.size, fitsParent = true, noTextOverflow = checkText })
		local gridInst = lastGridState.gridInst
		expect(gridInst.AbsoluteContentSize.Y > 0, "UIGridLayout computes non-zero AbsoluteContentSize.Y")
		if not env.IS_ROBLOX or root.AbsoluteCanvasSize.Y > 0 then
			expect(
				root.AbsoluteCanvasSize.Y >= gridInst.AbsoluteContentSize.Y + 16 - 0.5,
				"AutomaticCanvasSize.Y expands to fit UIGridLayout content plus padding"
			)
		end

		local gapSig = lastGridState.gapSig
		local cellSig = lastGridState.cellSig
		gapSig:set(10)
		cellSig:set(Vector2.new(80, 52))
		flush()
		RobloxLayout.audit(root, { viewport = vp.size, fitsParent = true, noTextOverflow = checkText })
	end,
})

test("layout · AutomaticSize, UIScale, TextBounds and RobloxLayout.audit checks", function()
	local RobloxLayout = sert.roblox.Layout
	local screen, rootFrame, badge, autoBox, scaledPanel, scaledChild
	local labelText = Flux.signal("Ready")
	local scaleFactor = Flux.signal(1)
	local s = Flux.scope(function()
		badge = Flux.new("TextLabel")({
			Name = "Badge",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(120, 24),
			Text = labelText,
			TextSize = 14,
			TextWrapped = true,
		})
		autoBox = Flux.new("Frame")({
			Name = "AutoBox",
			Position = UDim2.fromOffset(16, 16),
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Flux.padding(8),
			Flux.list({ direction = "y", gap = 6 }),
			badge,
			Flux.new("Frame")({
				Name = "Swatch",
				LayoutOrder = 2,
				Size = UDim2.fromOffset(120, 20),
			}),
		})
		scaledChild = Flux.new("Frame")({
			Name = "ScaledChild",
			Size = UDim2.fromScale(0.5, 0.4),
		})
		scaledPanel = Flux.new("Frame")({
			Name = "ScaledPanel",
			Position = UDim2.fromOffset(200, 16),
			Size = UDim2.fromOffset(160, 100),
			Flux.new("UIScale")({
				Scale = scaleFactor,
			}),
			scaledChild,
		})
		rootFrame = Flux.new("Frame")({
			Name = "RootSurface",
			Size = UDim2.fromOffset(800, 600),
			autoBox,
			scaledPanel,
		})
		screen = Flux.new("ScreenGui")({
			Name = "AutoSizeGui",
			rootFrame,
		})
	end)
	flush()

	-- AutoBox has padding 8 on each side (16 total) + children (width 120, heights 24 + 6 + 20 = 50) -> 136 x 66
	sert.near(autoBox.AbsoluteSize.X, 136, 1, "AutomaticSize.XY computes width from children + padding")
	sert.near(autoBox.AbsoluteSize.Y, 66, 1, "AutomaticSize.XY computes height from UIListLayout + padding")
	local hasTextMetrics = not env.IS_ROBLOX or badge.TextBounds.X > 0
	if hasTextMetrics then
		expect.eq(badge.TextFits, true, "short text fits inside 120x24 TextLabel")
		expect(badge.TextBounds.X > 0 and badge.TextBounds.Y > 0, "TextBounds are non-zero for non-empty text")
		RobloxLayout.noTextOverflow(autoBox)
	end

	RobloxLayout.noOverlap(autoBox)
	RobloxLayout.fitsParent(badge)
	RobloxLayout.fitsViewport(autoBox, { viewport = Vector2.new(800, 600) })
	RobloxLayout.audit(rootFrame, {
		viewport = Vector2.new(800, 600),
		fitsParent = true,
		noTextOverflow = hasTextMetrics,
	})

	scaleFactor:set(0.5)
	flush()
	sert.near(scaledPanel.AbsoluteSize.X, 80, 1, "UIScale scales container AbsoluteSize.X")
	sert.near(scaledPanel.AbsoluteSize.Y, 50, 1, "UIScale scales container AbsoluteSize.Y")
	sert.near(scaledChild.AbsoluteSize.X, 40, 1, "UIScale propagates to descendant AbsoluteSize.X")
	sert.near(scaledChild.AbsoluteSize.Y, 20, 1, "UIScale propagates to descendant AbsoluteSize.Y")

	s:Destroy()
	screen:Destroy()
	flush()
end)

local ctest = if env.IS_ROBLOX and game:GetService("Players").LocalPlayer ~= nil then sert.rtest else sert.skip
ctest("layout · sert.roblox.Layout.settle, geometry and Flicker.around verify non-flickering list layout", function()
	local RobloxLayout = sert.roblox.Layout
	local Flicker = sert.roblox.Flicker
	local gap = Flux(8)
	local gui, container, first, second, third
	local s = Flux.scope(function()
		first = Flux.new("Frame")({
			Name = "First",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(120, 28),
		})
		second = Flux.new("Frame")({
			Name = "Second",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(120, 28),
			Flux.flex("fill"),
		})
		third = Flux.new("Frame")({
			Name = "Third",
			LayoutOrder = 3,
			Size = UDim2.fromOffset(120, 28),
		})
		container = Flux.new("Frame")({
			Name = "Container",
			Position = UDim2.fromOffset(24, 24),
			Size = UDim2.fromOffset(200, 180),
			Flux.padding(10),
			Flux.list({ direction = "y", gap = gap, align = "center" }),
			third,
			first,
			second,
		})
		local player = game:GetService("Players").LocalPlayer
		gui = Flux.new("ScreenGui")({
			Parent = if player then player:WaitForChild("PlayerGui") else workspace,
			DisplayOrder = 1000,
			container,
		})
	end)
	flush()

	expect(RobloxLayout.settle(container), "Studio UIListLayout + UIPadding settles")
	expect.eq(RobloxLayout.visible(first), true, "first item is visible")
	expect.eq(RobloxLayout.visible(second), true, "second item is visible")
	expect.eq(RobloxLayout.visible(third), true, "third item is visible")

	local r1 = RobloxLayout.geometry.rect(first)
	local r2 = RobloxLayout.geometry.rect(second)
	local r3 = RobloxLayout.geometry.rect(third)
	expect(r1.y < r2.y and r2.y < r3.y and r1.width == 120, "children lay out in LayoutOrder vertically")

	local report = Flicker.around(function()
		return second
	end, function()
		gap(14)
		flush()
	end, { motion = 12, stable = 2 })
	Flicker.expect(report)

	s:Destroy()
	gui:Destroy()
end)

return {}
