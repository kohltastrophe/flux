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
local flush = Flux.flush

local approx = sert.approx

rtest("layout · padding (number, table, struct node)", function()
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

rtest("layout · list maps friendly strings, gap & inherits SortOrder default", function()
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
	expect(l.SortOrder == Enum.SortOrder.LayoutOrder, "inherits UIListLayout default SortOrder")

	expect(l2.HorizontalAlignment == Enum.HorizontalAlignment.Right, "justify → main-axis (horizontal) end")
	expect(l2.VerticalAlignment == Enum.VerticalAlignment.Top, "verticalAlign accepts a raw Enum")

	s:Destroy()
end)

rtest("layout · grid, aspectRatio, flex", function()
	local g, ar, fx
	local s = Flux.scope(function()
		g = Flux.grid({ cell = Vector2.new(80, 80), gap = 4, fill = "y", maxCells = 3 })
		ar = Flux.aspectRatio(1.6, "scale", "height")
		fx = Flux.flex("grow")
	end)

	expect(g:IsA("UIGridLayout"), "grid returns a UIGridLayout")
	expect(g.CellSize == UDim2.fromOffset(80, 80), "cell Vector2 → offset UDim2")
	expect(g.CellPadding == UDim2.fromOffset(4, 4), "gap number → offset UDim2")
	expect(g.FillDirection == Enum.FillDirection.Vertical, "fill y → Vertical")
	expect(g.FillDirectionMaxCells == 3, "maxCells set")

	expect(approx(ar.AspectRatio, 1.6), "ratio set")
	expect(ar.AspectType == Enum.AspectType.ScaleWithParentSize, "aspectType friendly string")
	expect(ar.DominantAxis == Enum.DominantAxis.Height, "dominantAxis friendly string")

	expect(fx.FlexMode == Enum.UIFlexMode.Grow, "flex friendly string → enum")

	s:Destroy()
end)

rtest("layout · corner and stroke", function()
	local radius = Flux(4)
	local c, defaulted, st
	local s = Flux.scope(function()
		c = Flux.corner(radius)
		defaulted = Flux.corner()
		st = Flux.stroke({ thickness = 2, color = Color3.new(1, 0, 0), mode = "border", joins = "miter" })
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
	s:Destroy()
end)

rtest("layout · flex defaults to fill and accepts reactive modes", function()
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
	s:Destroy()
end)

rtest("layout · list flex distribution strings and lineAlign", function()
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

rtest("layout · fully reactive list: direction re-routes align/justify", function()
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

rtest("layout · reactive enum props (aspectType, grid fill)", function()
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

rtest("layout · a reactive enum prop writes the engine default for an unknown value", function()
	local mode = Flux("bogus")
	local fx
	local s = Flux.scope(function()
		fx = Flux.flex(mode)
	end)
	flush()
	expect(fx.FlexMode == Enum.UIFlexMode.None, "reactive bad flex mode → engine default, like the static path")
	mode("grow")
	flush()
	expect(fx.FlexMode == Enum.UIFlexMode.Grow, "recovers once the value is valid")
	s:Destroy()
end)

rtest("layout · a reactive pinned override that yields nil falls through to routing", function()
	local pin = Flux.Graph.signal(nil)
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

rtest("layout · padding follows a source that changes shape or starts empty", function()
	local compact = Flux(true)
	local late = Flux.Graph.signal(nil)
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

rtest("layout · reactive args bind and clean up on Destroy", function()
	local gap = Flux(8)
	local l
	local s = Flux.scope(function()
		l = Flux.list({ gap = gap })
	end)
	flush()
	expect(l.Padding == UDim.new(0, 8), "reactive gap bound")
	gap(16)
	flush()
	expect(l.Padding == UDim.new(0, 16), "reactive gap tracks node")
	l:Destroy()
	gap(32)
	flush()
	expect(true, "writing the node after Destroy does not error")
	s:Destroy()
end)

rtest("layout · function props bind reactively (length fn, struct fn, gap fn)", function()
	local inset = Flux(10)
	local pad, structPad, l
	local s = Flux.scope(function()
		pad = Flux.padding(function()
			return inset() * 2
		end)
		structPad = Flux.padding(function()
			return { top = inset() }
		end)
		l = Flux.list({
			gap = function()
				return inset() // 2
			end,
		})
	end)
	flush()
	expect(pad.PaddingTop == UDim.new(0, 20) and pad.PaddingBottom == UDim.new(0, 20), "length fn → all sides")
	expect(structPad.PaddingTop == UDim.new(0, 10), "struct fn → named side")
	expect(structPad.PaddingBottom == UDim.new(0, 0), "struct fn missing side defaults to 0")
	expect(l.Padding == UDim.new(0, 5), "gap fn → Padding")

	inset(30)
	flush()
	expect(pad.PaddingTop == UDim.new(0, 60), "length fn tracks its deps")
	expect(structPad.PaddingTop == UDim.new(0, 30), "struct fn tracks its deps")
	expect(l.Padding == UDim.new(0, 15), "gap fn tracks its deps")

	s:Destroy()
end)

rtest("layout · a single-length node drives all four padding sides", function()
	local len = Flux(8)
	local pad
	local s = Flux.scope(function()
		pad = Flux.padding(len)
	end)
	flush()
	expect(pad.PaddingTop == UDim.new(0, 8) and pad.PaddingLeft == UDim.new(0, 8), "node length → all sides")
	len(24)
	flush()
	expect(pad.PaddingBottom == UDim.new(0, 24) and pad.PaddingRight == UDim.new(0, 24), "node length tracks")
	s:Destroy()
end)

rtest("layout · UDim lengths pass through untouched (scale preserved)", function()
	local pad, l
	local s = Flux.scope(function()
		pad = Flux.padding(UDim.new(0.5, 4))
		l = Flux.list({ gap = UDim.new(0.1, 0) })
	end)
	expect(pad.PaddingTop == UDim.new(0.5, 4), "padding UDim as-is")
	expect(l.Padding == UDim.new(0.1, 0), "gap UDim as-is")
	s:Destroy()
end)

rtest("layout · unknown friendly strings warn and leave engine defaults (expected warn)", function()
	local l, fx, ar
	local s = Flux.scope(function()
		l = Flux.list({ direction = "diagonal" })
		fx = Flux.flex("bogus")
		ar = Flux.aspectRatio(2, "cover", "depth")
	end)
	expect(l.FillDirection == Enum.FillDirection.Vertical, "bad direction → engine default (Vertical)")
	expect(fx.FlexMode == Enum.UIFlexMode.None, "bad flex mode → engine default (None)")
	expect(ar.AspectType == Enum.AspectType.FitWithinMaxSize, "bad aspectType → engine default")
	expect(ar.DominantAxis == Enum.DominantAxis.Width, "bad dominantAxis → engine default")
	s:Destroy()
end)

rtest("layout · an instance built inside a scope is destroyed with the scope", function()
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
		pad.Parent = workspace
	end), "Parent locked (destroyed) on scope teardown")
end)

return {}
