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

local ctest = if IS_ROBLOX and game:GetService("Players").LocalPlayer ~= nil then sert.rtest else sert.skip

test("interact · exclusive activate swaps the active member", function()
	local group = Flux.exclusive()
	local a = Flux(false)
	local b = Flux(false)

	group:activate(a)
	expect(a:get() == true, "activate sets the member true")

	group:activate(b)
	expect(b:get() == true, "new member activates")
	expect(a:get() == false, "previous member deactivates")

	group:activate(b)
	expect(b:get() == true, "re-activating the active member keeps it true")
end)

test("interact · exclusive deactivate releases only its own slot", function()
	local group = Flux.exclusive()
	local a = Flux(false)
	local b = Flux(true)

	group:activate(a)
	group:deactivate(b)
	expect(b:get() == false, "deactivating a non-active member still sets it false")
	expect(a:get() == true, "the active member is untouched")

	group:deactivate(a)
	expect(a:get() == false, "deactivating the active member sets it false")

	a(true) -- external write; the group released `a` above
	group:activate(b)
	expect(a:get() == true, "a released member is not deactivated by later activations")
end)

test("interact · exclusive toggle flips through the group", function()
	local group = Flux.exclusive()
	local a = Flux(false)
	local b = Flux(false)

	group:toggle(a)
	expect(a:get() == true, "toggle activates an inactive member")
	group:toggle(b)
	expect(a:get() == false and b:get() == true, "toggle routes through activate, swapping members")
	group:toggle(b)
	expect(b:get() == false, "toggle deactivates an active member")
end)

test("interact · exclusive clear deactivates whichever member is active", function()
	local group = Flux.exclusive()
	local a = Flux(false)
	group:clear() -- an empty group is a no-op
	group:activate(a)
	group:clear()
	expect(a:get() == false, "clear deactivates the active member")
end)

test("interact · exclusive rejects non-node members", function()
	local group = Flux.exclusive()
	expect(not pcall(function()
		group:activate(true)
	end), "a plain value errors")
	expect(not pcall(function()
		group:toggle(function() end)
	end), "a function errors")
end)

test("interact · pointIn tests inclusive absolute bounds", function()
	-- Pure field reads: a plain table stands in for the GuiObject headless.
	local object = { AbsolutePosition = { X = 100, Y = 50 }, AbsoluteSize = { X = 200, Y = 100 } } :: any
	expect(Flux.pointIn(100, 50, object) == true, "top-left corner is inside")
	expect(Flux.pointIn(300, 150, object) == true, "bottom-right corner is inside")
	expect(Flux.pointIn(200, 100, object) == true, "interior point is inside")
	expect(Flux.pointIn(99, 100, object) == false, "left of bounds")
	expect(Flux.pointIn(301, 100, object) == false, "right of bounds")
	expect(Flux.pointIn(200, 49, object) == false, "above bounds")
	expect(Flux.pointIn(200, 151, object) == false, "below bounds")
end)

rtest("interact · sunk yields false outside a player gui", function()
	-- No BasePlayerGui ancestor (a bare tree, a SurfaceGui in workspace, a plugin
	-- dock): nothing can claim the point, so the walk is skipped entirely.
	local orphan = Flux.new("Frame")({ Size = UDim2.fromOffset(100, 100) })
	expect(Flux.sunk(0, 0, orphan) == false, "an object outside a player gui is never sunk")
	orphan:Destroy()
end)

ctest("interact · sunk detects an input-claiming gui above the object", function()
	local player = game:GetService("Players").LocalPlayer
	local gui = Flux.new("ScreenGui")({ Parent = player:WaitForChild("PlayerGui") })
	local position = UDim2.fromOffset(500, 300)
	local under = Flux.new("Frame")({ Parent = gui, Position = position, Size = UDim2.fromOffset(100, 100) })
	local over = Flux.new("Frame")({
		Parent = gui,
		Position = position,
		Size = UDim2.fromOffset(100, 100),
		Active = true,
		ZIndex = 2,
	})

	local corner = under.AbsolutePosition
	local x, y = corner.X + 10, corner.Y + 10
	expect(Flux.sunk(x, y, under) == true, "an Active frame above sinks the point")

	over.Active = false
	expect(Flux.sunk(x, y, under) == false, "an inactive frame above does not sink")
	expect(Flux.sunk(x, y, over) == false, "the topmost gui itself is never sunk")

	gui:Destroy()
end)

return {}
