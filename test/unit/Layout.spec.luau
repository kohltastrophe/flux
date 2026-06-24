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

rtest("layout · grid, aspectRatio, sizeConstraint, flex", function()
	local g, ar, sc, fx
	local s = Flux.scope(function()
		g = Flux.grid({ cell = Vector2.new(80, 80), gap = 4, fill = "y" })
		ar = Flux.aspectRatio(1.6, "scale", "height")
		sc = Flux.sizeConstraint(Vector2.new(100, 50), Vector2.new(400, 300))
		fx = Flux.flex("grow")
	end)

	expect(g:IsA("UIGridLayout"), "grid returns a UIGridLayout")
	expect(g.CellSize == UDim2.fromOffset(80, 80), "cell Vector2 → offset UDim2")
	expect(g.CellPadding == UDim2.fromOffset(4, 4), "gap number → offset UDim2")
	expect(g.FillDirection == Enum.FillDirection.Vertical, "fill y → Vertical")

	expect(approx(ar.AspectRatio, 1.6), "ratio set")
	expect(ar.AspectType == Enum.AspectType.ScaleWithParentSize, "aspectType friendly string")
	expect(ar.DominantAxis == Enum.DominantAxis.Height, "dominantAxis friendly string")

	expect(sc.MinSize == Vector2.new(100, 50) and sc.MaxSize == Vector2.new(400, 300), "size min/max set")

	expect(fx.FlexMode == Enum.UIFlexMode.Grow, "flex friendly string → enum")

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
