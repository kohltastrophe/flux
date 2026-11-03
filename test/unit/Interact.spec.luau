--!nonstrict
local env = if game ~= nil
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Flux, sert, IS_ROBLOX = env.Flux, env.sert, env.IS_ROBLOX

local Enum = env.Enum
local Vector2 = env.Vector2

local SINK_NONE = Enum.InputSink.None
local SINK_ACTIVATE = Enum.InputSink.Activate
local SINK_ALL = Enum.InputSink.All

local test = sert.test
local expect = sert
local InteractModule = if IS_ROBLOX
	then require((game :: any).ReplicatedStorage.Flux.Interact) :: any
	else require("../../src/Interact") :: any

local ctest = if IS_ROBLOX and game:GetService("Players").LocalPlayer ~= nil then sert.rtest else sert.skip

test("interact · pointIn tests inclusive absolute bounds", function()
	local object = { AbsolutePosition = Vector2.new(100, 50), AbsoluteSize = Vector2.new(200, 100) } :: any
	expect(Flux.Interact.pointIn(100, 50, object) == true, "top-left corner is inside")
	expect(Flux.Interact.pointIn(300, 150, object) == true, "bottom-right corner is inside")
	expect(Flux.Interact.pointIn(200, 100, object) == true, "interior point is inside")
	expect(Flux.Interact.pointIn(99, 100, object) == false, "left of bounds")
	expect(Flux.Interact.pointIn(301, 100, object) == false, "right of bounds")
	expect(Flux.Interact.pointIn(200, 49, object) == false, "above bounds")
	expect(Flux.Interact.pointIn(200, 151, object) == false, "below bounds")
end)

local function claimers(x: number, y: number, object: GuiObject): string
	local player = game:GetService("Players").LocalPlayer
	local names = {}
	for _, gui in player.PlayerGui:GetGuiObjectsAtPosition(x, y) do
		if gui == object then
			break
		elseif gui.Active or gui.InputSink.Value ~= 0 then
			table.insert(names, gui:GetFullName())
		end
	end
	return table.concat(names, ", ")
end

local function render()
	local run = game:GetService("RunService")
	run.RenderStepped:Wait()
	run.Heartbeat:Wait()
end

ctest("interact · sunk detects an input-claiming gui above the object", function()
	local player = game:GetService("Players").LocalPlayer
	local gui = Flux.new("ScreenGui")({
		DisplayOrder = 1000,
		ScreenInsets = Enum.ScreenInsets.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local position = UDim2.new(0.5, -50, 0.5, -50)
	local under = Flux.new("Frame")({ Parent = gui, Position = position, Size = UDim2.fromOffset(100, 100) })
	local over = Flux.new("Frame")({
		Parent = gui,
		Position = position,
		Size = UDim2.fromOffset(100, 100),
		InputSink = SINK_ALL,
		ZIndex = 2,
	})

	render()
	local corner = under.AbsolutePosition
	local x, y = corner.X + 10, corner.Y + 10
	expect(
		Flux.Interact.sunk(x, y, under) == true,
		`an All sink above sinks the point (at {x}, {y}; claimed by {claimers(x, y, under)})`
	)

	over.InputSink = SINK_NONE
	expect(
		Flux.Interact.sunk(x, y, under) == false,
		`an None sink above does not sink (claimed by {claimers(x, y, under)})`
	)
	expect(Flux.Interact.sunk(x, y, over) == false, "the topmost gui itself is never sunk")

	local button = Instance.new("TextButton")
	button.Parent = gui
	button.Position = position
	button.Size = under.Size
	button.ZIndex = 3
	render()
	expect.eq(Flux.Interact.sunk(x, y, under), true, "a native button (Activate by default) claims the press")
	button.InputSink = Enum.InputSink.None
	button.Active = false
	expect.eq(
		Flux.Interact.sunk(x, y, under),
		false,
		"a decorative native button with None permits the underlying control"
	)
	button.InputSink = Enum.InputSink.All
	expect.eq(Flux.Interact.sunk(x, y, under), true, "the native All button claims the point")

	gui:Destroy()
end)

ctest("interact · covered ignores the object's own buttons and hears only what is on top of it", function()
	local player = game:GetService("Players").LocalPlayer
	local gui = Flux.new("ScreenGui")({
		DisplayOrder = 1000,
		ScreenInsets = Enum.ScreenInsets.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local position = UDim2.new(0.5, -50, 0.5, -50)
	local list = Flux.new("Frame")({ Parent = gui, Position = position, Size = UDim2.fromOffset(100, 100) })
	Flux.new("TextButton")({ Parent = list, Size = UDim2.fromScale(1, 1), Text = "" })
	render()
	local corner = list.AbsolutePosition
	local x, y = corner.X + 10, corner.Y + 10
	expect(
		Flux.Interact.sunk(x, y, list) == true,
		`its own row sinks the point for sunk (at {x}, {y}; claimed by {claimers(x, y, list)})`
	)
	expect(Flux.Interact.covered(x, y, list) == false, `but doesn't cover it (claimed by {claimers(x, y, list)})`)

	local panel = Flux.new("Frame")({
		Parent = gui,
		Position = position,
		Size = UDim2.fromOffset(100, 100),
		InputSink = SINK_ALL,
		ZIndex = 5,
	})
	render()
	expect(Flux.Interact.covered(x, y, list) == true, "a panel on top covers it")
	panel.InputSink = SINK_NONE
	expect(Flux.Interact.covered(x, y, list) == false, "unless the panel doesn't claim input")

	gui:Destroy()
end)

local virtualInput
if IS_ROBLOX and game:GetService("Players").LocalPlayer ~= nil then
	local ok, result = pcall(function()
		return game:GetService("UserInputService"):CreateVirtualInput()
	end)
	if ok and result ~= nil then
		local gui = Instance.new("ScreenGui")
		gui.Name = "VirtualInputCalibration"
		gui.DisplayOrder = 1000000
		gui.ScreenInsets = Enum.ScreenInsets.None
		gui.Parent = game:GetService("Players").LocalPlayer.PlayerGui
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(160, 100)
		button.Position = UDim2.new(0.5, -80, 0.5, -50)
		button.InputSink = Enum.InputSink.Activate
		button.Parent = gui
		local began, entered, activated = 0, 0, 0
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				began += 1
			end
		end)
		button.MouseEnter:Connect(function()
			entered += 1
		end)
		button.Activated:Connect(function()
			activated += 1
		end)
		local delivered = pcall(function()
			task.wait(0.1)
			local at = button.AbsolutePosition + Vector2.new(32, 32) + game:GetService("GuiService"):GetGuiInset()
			result:SendMousePosition(at)
			result:SendMouseButton(at, Enum.UserInputType.MouseButton1, true)
			task.wait(0.05)
			result:SendMouseButton(at, Enum.UserInputType.MouseButton1, false)
			task.wait(0.05)
		end)
		gui:Destroy()
		if delivered and began > 0 and entered > 0 and activated > 0 then
			virtualInput = result
		else
			print(
				`[InputSink-native] SKIPPED: uncovered virtual-input calibration not delivered (began={began}, entered={entered}, activated={activated})`
			)
		end
	else
		print("[InputSink-native] SKIPPED: public virtual input unavailable")
	end
end
local pointerTest = if virtualInput ~= nil then ctest else sert.skip
pointerTest("interact · native InputSink None Activate All and release outside bounds", function()
	local playerGui = game:GetService("Players").LocalPlayer.PlayerGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "InputSinkRegression"
	gui.DisplayOrder = 1000000
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.Parent = playerGui
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(160, 100)
	button.Position = UDim2.new(0.5, -80, 0.5, -50)
	button.InputSink = Enum.InputSink.Activate
	button.Parent = gui
	local cover = Instance.new("Frame")
	cover.Size = button.Size
	cover.Position = button.Position
	cover.ZIndex = 2
	cover.Parent = gui
	local hovering, pressing
	local scope = Flux.scope(function()
		hovering = Flux.Interact.hover(button)
		pressing = Flux.Interact.press(button)
	end)
	local began, entered, activated = 0, 0, 0
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			began += 1
		end
	end)
	button.MouseEnter:Connect(function()
		entered += 1
	end)
	button.Activated:Connect(function()
		activated += 1
	end)
	local ok, failure = pcall(function()
		task.wait(0.1)
		local at = button.AbsolutePosition + Vector2.new(32, 32) + game:GetService("GuiService"):GetGuiInset()
		for _, sink in { Enum.InputSink.All, Enum.InputSink.Activate } do
			cover.InputSink = sink
			virtualInput:SendMousePosition(at)
			task.wait(0.1)
			Flux.flush()
			expect.eq(hovering:peek(), false, `{sink.Name} cover suppresses Flux hover`)
			virtualInput:SendMouseButton(at, Enum.UserInputType.MouseButton1, true)
			task.wait(0.05)
			Flux.flush()
			expect.eq(pressing:peek(), false, `{sink.Name} cover suppresses Flux press`)
			virtualInput:SendMouseButton(at, Enum.UserInputType.MouseButton1, false)
			task.wait(0.05)
		end
		cover.InputSink = Enum.InputSink.None
		virtualInput:SendMousePosition(at + Vector2.new(180, 0))
		task.wait(0.05)
		virtualInput:SendMousePosition(at)
		task.wait(0.1)
		Flux.flush()
		expect.eq(hovering:peek(), true, "None decoration permits hover")
		virtualInput:SendMouseButton(at, Enum.UserInputType.MouseButton1, true)
		task.wait(0.05)
		Flux.flush()
		expect.eq(pressing:peek(), true, "None decoration permits a press")
		local outside = at + Vector2.new(180, 0)
		virtualInput:SendMousePosition(outside)
		task.wait(0.05)
		virtualInput:SendMouseButton(outside, Enum.UserInputType.MouseButton1, false)
		task.wait(0.05)
		Flux.flush()
		expect.eq(pressing:peek(), false, "release outside the button settles the press")
	end)
	scope:Destroy()
	gui:Destroy()
	if not ok then
		error(failure, 0)
	end
end)

local function fakeSignal()
	local sig = sert.doubles.Signal.new()
	function sig:listeners()
		return self:connections()
	end
	return sig
end

local function fakeGui(cover)
	local gui = {
		InputBegan = fakeSignal(),
		InputChanged = fakeSignal(),
		InputEnded = fakeSignal(),
		Destroying = fakeSignal(),
		Focused = fakeSignal(),
		FocusLost = fakeSignal(),
	}
	local root = {}
	function root:GetGuiObjectsAtPosition()
		return { cover, gui }
	end
	function gui:FindFirstAncestorWhichIsA()
		return if cover then root else nil
	end
	function gui:IsFocused()
		return false
	end
	return gui
end

local function fakeCover()
	return {
		InputSink = SINK_ALL,
		IsA = function()
			return false
		end,
	}
end

test("interact · InputSink controls claiming, descendants and decorative buttons", function()
	expect.eq(Flux.Interact.sunk(0, 0, fakeGui()), false, "an object outside a player gui is never sunk")
	local over = fakeCover()
	local under = fakeGui(over)
	over.InputSink = SINK_NONE
	expect.eq(Flux.Interact.sunk(10, 10, under), false, "explicit None does not claim")
	over.InputSink = SINK_ACTIVATE
	expect.eq(Flux.Interact.sunk(10, 10, under), true, "Activate claims the press without a boolean Active flag")
	over.IsDescendantOf = function(_, object)
		return object == under
	end
	expect.eq(Flux.Interact.covered(10, 10, under), false, "the container permits its descendant control")
	over.InputSink = SINK_ALL
	over.IsDescendantOf = function()
		return false
	end
	expect.eq(Flux.Interact.covered(10, 10, under), true, "an unrelated All sink covers the container")
	over.InputSink = SINK_NONE
	over.IsA = function(_, class)
		return class == "GuiButton"
	end
	expect.eq(Flux.Interact.sunk(10, 10, under), false, "a decorative button explicitly permits input")
	over.IsA = function()
		return false
	end
	over.Active = true
	expect.eq(Flux.Interact.sunk(10, 10, under), true, "an Active gui claims with InputSink None")
	expect.eq(Flux.Interact.covered(10, 10, under), true, "and covers a container it isn't inside")
end)

local function fakeServices()
	local selectionChanged = fakeSignal()
	local menuChanged = fakeSignal()
	local guiService = { MenuIsOpen = false }
	function guiService:GetPropertyChangedSignal(property)
		return if property == "MenuIsOpen" then menuChanged else selectionChanged
	end
	local userInputService = { InputBegan = fakeSignal(), InputEnded = fakeSignal(), focusedTextBox = nil }
	function userInputService:GetFocusedTextBox()
		return self.focusedTextBox
	end
	return {
		GuiService = guiService,
		UserInputService = userInputService,
		selectionChanged = selectionChanged,
		menuChanged = menuChanged,
	}
end

local MOUSE_MOVEMENT = Enum.UserInputType.MouseMovement
local MOUSE_BUTTON1 = Enum.UserInputType.MouseButton1
local TOUCH = Enum.UserInputType.Touch
local GAMEPAD1 = Enum.UserInputType.Gamepad1
local BUTTON_A = Enum.KeyCode.ButtonA
local BUTTON_B = Enum.KeyCode.ButtonB
local UNKNOWN_KEY = Enum.KeyCode.Unknown

local function fakeInput(kind, keyCode)
	return { UserInputType = kind, KeyCode = keyCode or UNKNOWN_KEY, Position = Vector2.new(5, 5) }
end

test("interact · hover follows the pointer in and out", function()
	local gui = fakeGui()
	local hovering = Flux.Interact.hover(gui)
	expect(hovering:get() == false, "starts unhovered")

	gui.InputBegan:Fire(fakeInput(MOUSE_MOVEMENT))
	expect(hovering:get() == true, "the pointer entering hovers")
	gui.InputEnded:Fire(fakeInput(MOUSE_MOVEMENT))
	expect(hovering:get() == false, "the pointer leaving unhovers")

	local touch = fakeInput(TOUCH)
	gui.InputChanged:Fire(touch)
	expect(hovering:get() == true, "a touch contact moving over the object hovers")
	gui.InputEnded:Fire(touch)
	expect(hovering:get() == false, "lifting the touch unhovers")

	gui.InputBegan:Fire(fakeInput(MOUSE_BUTTON1))
	expect(hovering:get() == false, "a button press is not hover")
	hovering:Destroy()
end)

test("interact · hover drops while an input-claiming gui covers the object", function()
	local cover = fakeCover()
	local gui = fakeGui(cover)
	local hovering = Flux.Interact.hover(gui)

	gui.InputChanged:Fire(fakeInput(MOUSE_MOVEMENT))
	expect(hovering:get() == false, "an Active gui above claims the pointer")
	cover.InputSink = SINK_NONE
	gui.InputChanged:Fire(fakeInput(MOUSE_MOVEMENT))
	expect(hovering:get() == true, "the pointer reaches the object once the cover stops sinking input")
	cover.InputSink = SINK_ALL
	gui.InputChanged:Fire(fakeInput(MOUSE_MOVEMENT))
	expect(hovering:get() == false, "a cover arriving mid-hover drops it on the next move")
	hovering:Destroy()
end)

local function hoverWorld()
	local world = { at = {} }
	local root = { queries = 0 }
	function root:GetGuiObjectsAtPosition(x, y)
		root.queries += 1
		return world.at(x, y)
	end
	local lastInput = MOUSE_MOVEMENT
	world.root = root
	world.env = {
		GuiService = { MenuIsOpen = false },
		UserInputService = {
			InputChanged = fakeSignal(),
			InputEnded = fakeSignal(),
			LastInputTypeChanged = fakeSignal(),
			WindowFocusReleased = fakeSignal(),
			GetLastInputType = function()
				return lastInput
			end,
		},
		RunService = { Heartbeat = fakeSignal() },
	}
	function world.input(kind)
		lastInput = kind
		world.env.UserInputService.LastInputTypeChanged:Fire(kind)
	end
	function world.gui(parent)
		local gui = fakeGui()
		gui.MouseEnter = fakeSignal()
		gui.MouseLeave = fakeSignal()
		gui.InputSink = SINK_NONE
		function gui:FindFirstAncestorWhichIsA()
			return root
		end
		function gui:IsA()
			return false
		end
		function gui:IsDescendantOf(other)
			return parent ~= nil and (parent == other or parent:IsDescendantOf(other))
		end
		return gui
	end
	function world.frame()
		world.env.RunService.Heartbeat:Fire(1 / 60)
	end
	function world.listening()
		local uis = world.env.UserInputService
		return world.env.RunService.Heartbeat:listeners()
			+ uis.InputChanged:listeners()
			+ uis.InputEnded:listeners()
			+ uis.LastInputTypeChanged:listeners()
			+ uis.WindowFocusReleased:listeners()
	end
	return world
end

local function moveAt(x, y)
	local move = fakeInput(MOUSE_MOVEMENT)
	move.Position = Vector2.new(x, y)
	return move
end

test("interact · a menu over a hovered card unhovers it on the next frame, and closing it hovers it again", function()
	local world = hoverWorld()
	local card = world.gui()
	local row = world.gui()
	row.InputSink = SINK_ALL
	local menuOpen = false
	world.at = function(x)
		return if menuOpen and x >= 50 then { row, card } else { card }
	end
	local hovering = InteractModule._hoverWith(card, world.env)
	expect(world.listening() == 0, "nothing listens globally while nothing is hovered")

	card.InputChanged:Fire(moveAt(60, 10))
	expect(hovering:get() == true, "the pointer on the card hovers it")
	expect(world.listening() > 0, "and the tracker steps each frame while it is")

	menuOpen = true
	world.frame()
	expect(hovering:get() == false, "a menu opening under a still pointer unhovers the card on the next frame")
	menuOpen = false
	world.frame()
	expect(hovering:get() == true, "and closing it with the pointer still there hovers it again")

	menuOpen = true
	world.env.UserInputService.InputChanged:Fire(moveAt(20, 10))
	world.frame()
	expect(hovering:get() == true, "on the card's uncovered half it stays hovered")
	world.env.UserInputService.InputChanged:Fire(moveAt(70, 10))
	world.frame()
	expect(hovering:get() == false, "moving onto the menu inside the card's bounds unhovers it")

	world.at = function()
		return {}
	end
	world.frame()
	expect(hovering:get() == false, "a scroll or hide that takes the card from under the pointer unhovers it")
	expect(world.listening() == 0, "and the tracker stops once nothing is under the pointer")
	hovering:Destroy()
end)

test("interact · hover asks one hit test per frame, however many objects are hovered", function()
	local world = hoverWorld()
	local outer = world.gui()
	local inner = world.gui(outer)
	world.at = function()
		return { inner, outer }
	end
	local outerHover = InteractModule._hoverWith(outer, world.env, { within = true })
	local innerHover = InteractModule._hoverWith(inner, world.env)
	outer.InputChanged:Fire(moveAt(5, 5))
	inner.InputChanged:Fire(moveAt(5, 5))
	local before = world.root.queries
	world.frame()
	expect(world.root.queries - before == 1, "two hovered objects, one query a frame")
	expect(outerHover:get() and innerHover:get(), "and both are hovered")
	outerHover:Destroy()
	innerHover:Destroy()
	expect(world.listening() == 0, "destroying the last hover disconnects the tracker")
end)

test("interact · with within, only a gui outside the object covers it", function()
	local world = hoverWorld()
	local rowArea = world.gui()
	local button = world.gui(rowArea)
	button.InputSink = SINK_ALL
	local panel = world.gui()
	panel.InputSink = SINK_ALL
	local above = { button, rowArea }
	world.at = function()
		return above
	end
	local prev = InteractModule._useHoverServices(world.env)
	local within = Flux.Interact.hover(rowArea, { within = true })
	local plain = Flux.Interact.hover(rowArea)
	rowArea.InputChanged:Fire(moveAt(5, 5))
	world.frame()
	expect(within:get() == true, "its own button doesn't cover it with within")
	expect(plain:get() == false, "but does without")
	above = { panel, button, rowArea }
	world.frame()
	expect(within:get() == false, "a panel on top covers it either way")
	within:Destroy()
	plain:Destroy()
	InteractModule._useHoverServices(prev)
end)

test("interact · hover under a cover joins on enter and lights when the cover goes, the pointer still", function()
	local world = hoverWorld()
	local card = world.gui()
	local sheet = world.gui()
	sheet.InputSink = SINK_ALL
	local open = true
	world.at = function()
		return if open then { sheet, card } else { card }
	end
	local hovering = InteractModule._hoverWith(card, world.env)
	card.MouseEnter:Fire(5, 5)
	world.env.UserInputService.InputChanged:Fire(moveAt(5, 5))
	world.frame()
	expect(hovering:get() == false, "entering under a sheet doesn't hover")
	open = false
	world.frame()
	expect(hovering:get() == true, "the sheet closing does")
	world.env.GuiService.MenuIsOpen = true
	world.frame()
	expect(hovering:get() == false, "nothing is hovered under the Roblox menu")
	world.env.GuiService.MenuIsOpen = false
	world.frame()
	expect(hovering:get() == true)
	card.MouseLeave:Fire(0, 0)
	expect(hovering:get() == false, "leaving unhovers at once")
	expect(world.listening() == 0)
	hovering:Destroy()
end)

test("interact · the native menu releases touch hover without a mouse position", function()
	local world = hoverWorld()
	local card = world.gui()
	world.at = function()
		return { card }
	end
	local hovering = InteractModule._hoverWith(card, world.env)
	card.InputBegan:Fire(fakeInput(TOUCH))
	expect.eq(hovering:get(), true)
	world.env.GuiService.MenuIsOpen = true
	world.frame()
	expect.eq(hovering:get(), false, "opening the system menu releases held touch hover")
	expect.eq(world.listening(), 0, "the touch tracker disconnects while the system menu owns input")
	card.InputBegan:Fire(fakeInput(TOUCH))
	expect.eq(hovering:get(), false, "the system menu keeps fresh touches")
	world.env.GuiService.MenuIsOpen = false
	card.InputBegan:Fire(fakeInput(TOUCH))
	expect.eq(hovering:get(), true, "a fresh contact works after the menu closes")
	hovering:Destroy()
end)

test("interact · touch and gamepad leave no hover behind", function()
	local world = hoverWorld()
	local card = world.gui()
	world.at = function()
		return { card }
	end
	local hovering = InteractModule._hoverWith(card, world.env)

	local touch = fakeInput(TOUCH)
	card.InputBegan:Fire(touch)
	expect(hovering:get() == true, "a touch contact on the card hovers it")
	world.env.UserInputService.InputEnded:Fire(touch)
	expect(hovering:get() == false, "lifting it anywhere, not only on the card, unhovers it")
	expect(world.listening() == 0)

	card.InputChanged:Fire(moveAt(5, 5))
	expect(hovering:get() == true)
	world.input(TOUCH)
	expect(hovering:get() == false, "a touch taking over from the mouse unhovers what the mouse hovered")
	world.input(MOUSE_MOVEMENT)
	card.InputChanged:Fire(moveAt(5, 5))
	world.input(GAMEPAD1)
	expect(hovering:get() == false, "and so does a gamepad")
	world.input(MOUSE_MOVEMENT)
	card.MouseEnter:Fire(5, 5)
	card.InputChanged:Fire(moveAt(5, 5))
	world.env.UserInputService.WindowFocusReleased:Fire()
	expect(hovering:get() == false, "and the window losing focus")
	world.input(TOUCH)
	card.MouseEnter:Fire(5, 5)
	expect(world.listening() == 0, "an enter the engine sends for a tap doesn't start the tracker")
	hovering:Destroy()
end)

test("interact · press holds until that input ends, wherever it is released", function()
	local env = fakeServices()
	local gui = fakeGui()
	local pressed = InteractModule._pressWith(gui, env)
	local ended = env.UserInputService.InputEnded

	local click = fakeInput(MOUSE_BUTTON1)
	gui.InputBegan:Fire(click)
	expect(pressed:get() == true, "a mouse press on the object presses it")
	expect(ended:listeners() == 1, "the release is watched while held")

	ended:Fire(fakeInput(TOUCH))
	expect(pressed:get() == true, "an unrelated input ending does not release")
	ended:Fire(click)
	expect(pressed:get() == false, "the same input ending anywhere releases")
	expect(ended:listeners() == 0, "the release listener is dropped")

	gui.InputBegan:Fire(fakeInput(MOUSE_MOVEMENT))
	expect(pressed:get() == false, "pointer movement never presses")
	pressed:Destroy()
end)

test("interact · press follows the first touch only", function()
	local env = fakeServices()
	local gui = fakeGui()
	local pressed = InteractModule._pressWith(gui, env)

	local first, second = fakeInput(TOUCH), fakeInput(TOUCH)
	gui.InputBegan:Fire(first)
	gui.InputBegan:Fire(second)
	env.UserInputService.InputEnded:Fire(second)
	expect(pressed:get() == true, "lifting another finger keeps the press")
	env.UserInputService.InputEnded:Fire(first)
	expect(pressed:get() == false, "lifting the pressing finger releases")
	pressed:Destroy()
end)

test("interact · the native Roblox menu releases contact and keeps activation", function()
	local env = fakeServices()
	local gui = fakeGui()
	local pressed = InteractModule._pressWith(gui, env)
	local input = fakeInput(MOUSE_BUTTON1)
	gui.InputBegan:Fire(input)
	expect.eq(pressed:get(), true)
	env.GuiService.MenuIsOpen = true
	env.menuChanged:Fire()
	expect.eq(pressed:get(), false, "opening the native menu releases an existing contact")
	gui.InputBegan:Fire(fakeInput(MOUSE_BUTTON1))
	expect.eq(pressed:get(), false, "pointer presses cannot reach the dashboard under the menu")
	env.GuiService.SelectedObject = gui
	env.UserInputService.InputBegan:Fire(fakeInput(GAMEPAD1, BUTTON_A))
	expect.eq(pressed:get(), false, "the native menu keeps gamepad activation")
	env.GuiService.MenuIsOpen = false
	env.menuChanged:Fire()
	gui.InputBegan:Fire(input)
	expect.eq(pressed:get(), true, "a new contact works once the menu closes")
	pressed:Destroy()
	expect.eq(env.menuChanged:listeners(), 0, "the native menu is watched only while a contact is held")
end)

test("interact · press activates the gamepad-selected object", function()
	local env = fakeServices()
	local gui = fakeGui()
	local pressed = InteractModule._pressWith(gui, env)

	local buttonA = fakeInput(GAMEPAD1, BUTTON_A)
	env.UserInputService.InputBegan:Fire(buttonA)
	expect(pressed:get() == false, "ButtonA does nothing unless the object is selected")

	env.GuiService.SelectedObject = gui
	env.UserInputService.InputBegan:Fire(fakeInput(GAMEPAD1, BUTTON_B))
	expect(pressed:get() == false, "other buttons do not activate")
	env.UserInputService.InputBegan:Fire(buttonA)
	expect(pressed:get() == true, "ButtonA presses the selected object")
	env.UserInputService.InputEnded:Fire(fakeInput(GAMEPAD1, BUTTON_A))
	expect(pressed:get() == false, "releasing ButtonA releases, even on a fresh InputObject")

	env.UserInputService.focusedTextBox = {}
	env.UserInputService.InputBegan:Fire(buttonA)
	expect(pressed:get() == false, "while a text box has focus the key is its own, not the selected object's")
	env.UserInputService.focusedTextBox = nil
	pressed:Destroy()
end)

test("interact · press ignores a press claimed by a gui above", function()
	local env = fakeServices()
	local gui = fakeGui(fakeCover())
	local pressed = InteractModule._pressWith(gui, env)
	gui.InputBegan:Fire(fakeInput(MOUSE_BUTTON1))
	expect(pressed:get() == false, "a covered object is not pressed")
	expect(env.UserInputService.InputEnded:listeners() == 0, "and no release is watched")
	pressed:Destroy()
end)

test("interact · selected follows GuiService.SelectedObject", function()
	local env = fakeServices()
	local a, b = fakeGui(), fakeGui()
	env.GuiService.SelectedObject = a
	local aSelected = InteractModule._selectedWith(a, env)
	local bSelected = InteractModule._selectedWith(b, env)
	expect(aSelected:get() == true and bSelected:get() == false, "seeded from the current selection")

	env.GuiService.SelectedObject = b
	env.selectionChanged:Fire()
	expect(aSelected:get() == false and bSelected:get() == true, "the selection moves between objects")
	aSelected:Destroy()
	bSelected:Destroy()
end)

test("interact · every press and selection share one engine listener each", function()
	local env = fakeServices()
	local a, b, c = fakeGui(), fakeGui(), fakeGui()
	local presses =
		{ InteractModule._pressWith(a, env), InteractModule._pressWith(b, env), InteractModule._pressWith(c, env) }
	local selections = {
		InteractModule._selectedWith(a, env),
		InteractModule._selectedWith(b, env),
		InteractModule._selectedWith(c, env),
	}
	env.GuiService.SelectedObject = b
	env.selectionChanged:Fire()
	env.UserInputService.InputBegan:Fire(fakeInput(GAMEPAD1, BUTTON_A))
	expect(presses[2]:get() == true, "ButtonA presses the selected object")
	expect(presses[1]:get() == false and presses[3]:get() == false, "and nothing else")
	env.UserInputService.InputEnded:Fire(fakeInput(GAMEPAD1, BUTTON_A))

	env.GuiService.SelectedObject = c
	env.selectionChanged:Fire()
	expect(selections[2]:get() == false and selections[3]:get() == true, "a selection change flips the two it concerns")
	expect(selections[1]:get() == false, "one it never touched stays as it was")

	presses[1]:Destroy()
	presses[2]:Destroy()
	env.UserInputService.InputBegan:Fire(fakeInput(GAMEPAD1, BUTTON_A))
	expect(presses[3]:get() == true, "the listener stays while any press remains")
	env.UserInputService.InputEnded:Fire(fakeInput(GAMEPAD1, BUTTON_A))
	presses[3]:Destroy()
	expect(env.UserInputService.InputBegan:listeners() == 0, "the last press takes the InputBegan listener with it")
	for _, node in selections do
		node:Destroy()
	end
	expect(env.selectionChanged:listeners() == 0, "the last selection takes the SelectedObject listener with it")
end)

test("interact · two states on one object both hear it, and destroying one leaves the rest listening", function()
	local env = fakeServices()
	local gui = fakeGui()
	local first = InteractModule._pressWith(gui, env)
	local second = InteractModule._pressWith(gui, env)
	env.GuiService.SelectedObject = gui
	env.UserInputService.InputBegan:Fire(fakeInput(GAMEPAD1, BUTTON_A))
	expect(first:get() == true and second:get() == true, "a tooltip's press and the control's both press")
	env.UserInputService.InputEnded:Fire(fakeInput(GAMEPAD1, BUTTON_A))

	local a, b = fakeGui(), fakeGui()
	local aSelected = InteractModule._selectedWith(a, env)
	local bSelected = InteractModule._selectedWith(b, env)
	local reaction = Flux.effect(function()
		if aSelected:get() then
			bSelected:Destroy()
		end
	end)
	env.GuiService.SelectedObject = a
	env.selectionChanged:Fire()
	Flux.flush()
	expect(aSelected:get() == true and bSelected:peek() == nil, "the selection lands and b's state is gone")
	env.GuiService.SelectedObject = b
	env.selectionChanged:Fire()
	expect(aSelected:get() == false, "a still hears the selection leave it")
	reaction:Destroy()
	aSelected:Destroy()
	first:Destroy()
	second:Destroy()
end)

test("interact · hover, press and selected on one services table keep separate listeners", function()
	local world = hoverWorld()
	local env = world.env
	local services = fakeServices()
	env.UserInputService.InputBegan = services.UserInputService.InputBegan
	env.UserInputService.GetFocusedTextBox = function()
		return nil
	end
	env.GuiService.GetPropertyChangedSignal = services.GuiService.GetPropertyChangedSignal
	local card = world.gui()
	world.at = function()
		return { card }
	end
	local hovering = InteractModule._hoverWith(card, env)
	local pressed = InteractModule._pressWith(card, env)
	local isSelected = InteractModule._selectedWith(card, env)
	card.InputChanged:Fire(moveAt(5, 5))
	expect(hovering:get() == true and world.listening() > 0, "the hover tracker runs")
	expect(env.UserInputService.InputBegan:listeners() > 0, "beside the activate listener")
	expect(services.selectionChanged:listeners() > 0, "and the selection listener")

	pressed:Destroy()
	expect(env.UserInputService.InputBegan:listeners() == 0, "dropping the press drops only the activate listener")
	expect(world.listening() > 0 and hovering:get() == true, "the hover goes on")
	isSelected:Destroy()
	expect(services.selectionChanged:listeners() == 0, "dropping the selection drops its listener")
	hovering:Destroy()
	expect(world.listening() == 0, "and the last hover stops the tracker")
end)

test("interact · the hit test is asked once per input per point", function()
	local queries = 0
	local root = {}
	function root:GetGuiObjectsAtPosition()
		queries += 1
		return {}
	end
	local function guiUnder()
		local gui = fakeGui()
		function gui:FindFirstAncestorWhichIsA()
			return root
		end
		return gui
	end
	local outer, inner = guiUnder(), guiUnder()
	local outerHover = Flux.Interact.hover(outer)
	local innerHover = Flux.Interact.hover(inner)

	local move = fakeInput(MOUSE_MOVEMENT)
	move.Position = Vector2.new(5, 5)
	outer.InputChanged:Fire(move)
	inner.InputChanged:Fire(move)
	outer.InputChanged:Fire(move)
	expect(queries == 1, "three moves over nested objects at one point ask once")
	expect(outerHover:get() == true and innerHover:get() == true, "and both hover")

	move.Position = Vector2.new(6, 5)
	outer.InputChanged:Fire(move)
	expect(queries == 2, "a new point asks again")
	local another = fakeInput(MOUSE_MOVEMENT)
	another.Position = Vector2.new(6, 5)
	outer.InputChanged:Fire(another)
	expect(queries == 3, "and so does another input at the same point")
	outerHover:Destroy()
	innerHover:Destroy()
end)

test("interact · focused seeds from IsFocused and follows focus events", function()
	local box = fakeGui()
	function box:IsFocused()
		return true
	end
	local isFocused = Flux.Interact.focused(box)
	expect(isFocused:get() == true, "seeded from IsFocused")

	box.FocusLost:Fire(false)
	expect(isFocused:get() == false, "FocusLost clears it")
	box.Focused:Fire()
	expect(isFocused:get() == true, "Focused sets it")
	isFocused:Destroy()
end)

test("interact · states disconnect with their scope or their object", function()
	local env = fakeServices()
	local gui = fakeGui()
	local function listening()
		local count = env.UserInputService.InputBegan:listeners()
			+ env.UserInputService.InputEnded:listeners()
			+ env.selectionChanged:listeners()
		for _, name in { "InputBegan", "InputChanged", "InputEnded", "Destroying", "Focused", "FocusLost" } do
			count += gui[name]:listeners()
		end
		return count
	end

	local scope = Flux.scope(function()
		Flux.Interact.hover(gui)
		InteractModule._pressWith(gui, env)
		InteractModule._selectedWith(gui, env)
		Flux.Interact.focused(gui)
	end)
	gui.InputBegan:Fire(fakeInput(MOUSE_BUTTON1))
	expect(listening() > 0, "the states listen while their scope lives")
	scope:Destroy()
	expect(listening() == 0, "destroying the scope disconnects every listener, including a held press")

	local hovering = Flux.Interact.hover(gui)
	gui.InputBegan:Fire(fakeInput(MOUSE_MOVEMENT))
	expect(hovering:get() == true, "an unowned state works too")
	gui.Destroying:Fire()
	expect(hovering:get() == false, "destroying the object settles the state")
	expect(listening() == 0, "and disconnects it")
	hovering:Destroy()
end)

sert.model(
	"interact · hover, press, selected, focused, sunk and covered match geometric hit-testing and multi-touch isolation",
	{
		init = function()
			local UDim2 = env.UDim2
			local simEnv = env.engine
				or sert.env.new({
					isClient = true,
					isStudio = true,
					strict = true,
					datatypes = {
						Enum = Enum,
						UDim2 = UDim2,
						Vector2 = Vector2,
						Vector3 = env.Compat.Vector3,
					},
				})
			local services = {
				GuiService = simEnv.game:GetService("GuiService"),
				UserInputService = simEnv.game:GetService("UserInputService"),
				RunService = simEnv.game:GetService("RunService"),
			}
			local input = simEnv:input()
			local screen = simEnv.Instance.new("ScreenGui")
			screen.Parent = simEnv.LocalPlayer.PlayerGui

			local overlay = simEnv.Instance.new("Frame")
			overlay.Position = UDim2.fromOffset(0, 0)
			overlay.Size = UDim2.fromOffset(300, 100)
			overlay.InputSink = SINK_NONE
			overlay.ZIndex = 3
			overlay.Parent = screen

			local g1 = simEnv.Instance.new("TextBox")
			g1.Position = UDim2.fromOffset(20, 20)
			g1.Size = UDim2.fromOffset(80, 60)
			g1.InputSink = SINK_ACTIVATE
			g1.ZIndex = 2
			g1.Parent = screen

			local g2 = simEnv.Instance.new("TextBox")
			g2.Position = UDim2.fromOffset(140, 20)
			g2.Size = UDim2.fromOffset(80, 60)
			g2.InputSink = SINK_ACTIVATE
			g2.ZIndex = 2
			g2.Parent = screen

			local guis = { g1, g2 }
			local positions = {
				[0] = Vector2.new(260, 50),
				[1] = Vector2.new(60, 50),
				[2] = Vector2.new(180, 50),
			}
			input:move(positions[0])

			local prevHoverServices = InteractModule._useHoverServices(services)
			local hovered = {}
			local pressed = {}
			local selected = {}
			local focused = {}
			local scope = Flux.scope(function()
				for i, gui in guis do
					hovered[i] = InteractModule._hoverWith(gui, services)
					pressed[i] = InteractModule._pressWith(gui, services)
					selected[i] = InteractModule._selectedWith(gui, services)
					focused[i] = Flux.Interact.focused(gui)
				end
			end)
			local state = {
				pointerTarget = 0,
				overlayActive = false,
				activeTouchSlot = { [1] = nil :: number?, [2] = nil :: number? },
				heldTouchHover = { [1] = nil :: number?, [2] = nil :: number? },
				heldPress = { [1] = nil :: string?, [2] = nil :: string? },
				selectedIdx = nil :: number?,
				menuOpen = false,
				focused = { false, false },
			}
			local sut = {
				simEnv = simEnv,
				services = services,
				input = input,
				screen = screen,
				overlay = overlay,
				guis = guis,
				positions = positions,
				pointerTarget = 0,
				activeTouches = {} :: { [number]: any },
				hovered = hovered,
				pressed = pressed,
				selected = selected,
				focused = focused,
				scope = scope,
				prevHoverServices = prevHoverServices,
			}
			return state, sut
		end,
		teardown = function(sut)
			sut.services.GuiService.MenuIsOpen = false
			sut.services.GuiService.SelectedObject = nil
			InteractModule._useHoverServices(sut.prevHoverServices)
			sut.scope:Destroy()
			sut.screen:Destroy()
		end,
		actions = {
			hover = {
				weight = 3,
				gen = function(g)
					return g:int(0, 2)
				end,
				run = function(sut, target)
					local pos = sut.positions[target]
					sut.input:move(pos)
					if sut.pointerTarget ~= 0 and sut.pointerTarget ~= target then
						sut.guis[sut.pointerTarget].MouseLeave:Fire(pos.X, pos.Y)
					end
					if target ~= 0 then
						sut.guis[target].MouseEnter:Fire(pos.X, pos.Y)
					end
					sut.pointerTarget = target
					sut.simEnv:step(1 / 60)
				end,
				next = function(state, target)
					state.pointerTarget = target
				end,
			},
			ToggleOverlay = {
				weight = 2,
				gen = function(g)
					return g:bool()
				end,
				run = function(sut, active)
					sut.overlay.InputSink = if active then SINK_ALL else SINK_NONE
					sut.simEnv:step(1 / 60)
				end,
				next = function(state, active)
					state.overlayActive = active
				end,
			},
			TouchPress = {
				weight = 3,
				gen = function(g)
					return { idx = g:int(1, 2), slot = g:int(1, 2) }
				end,
				run = function(sut, arg)
					if sut.activeTouches[arg.slot] ~= nil then
						return
					end
					local pos = sut.positions[arg.idx]
					local t = { UserInputType = TOUCH, KeyCode = UNKNOWN_KEY, Position = pos }
					sut.activeTouches[arg.slot] = t
					sut.guis[arg.idx].InputBegan:Fire(t)
				end,
				next = function(state, arg)
					if state.activeTouchSlot[arg.slot] ~= nil then
						return
					end
					state.activeTouchSlot[arg.slot] = arg.idx
					if not state.menuOpen and not state.overlayActive then
						if state.heldTouchHover[arg.idx] == nil then
							state.heldTouchHover[arg.idx] = arg.slot
						end
						if state.heldPress[arg.idx] == nil then
							state.heldPress[arg.idx] = `touch{arg.slot}`
						end
					end
				end,
			},
			TouchRelease = {
				weight = 3,
				gen = function(g)
					return g:int(1, 2)
				end,
				run = function(sut, slot)
					local t = sut.activeTouches[slot]
					if t == nil then
						return
					end
					sut.activeTouches[slot] = nil
					sut.services.UserInputService.InputEnded:Fire(t)
					sut.simEnv:step(1 / 60)
				end,
				next = function(state, slot)
					if state.activeTouchSlot[slot] == nil then
						return
					end
					state.activeTouchSlot[slot] = nil
					for i = 1, 2 do
						if state.heldTouchHover[i] == slot then
							state.heldTouchHover[i] = nil
						end
						if state.heldPress[i] == `touch{slot}` then
							state.heldPress[i] = nil
						end
					end
				end,
			},
			mouseDown = {
				weight = 3,
				gen = function(g)
					return g:int(1, 2)
				end,
				run = function(sut, idx)
					local pos = sut.positions[idx]
					sut.guis[idx].InputBegan:Fire({
						UserInputType = MOUSE_BUTTON1,
						KeyCode = UNKNOWN_KEY,
						Position = pos,
					})
				end,
				next = function(state, idx)
					if not state.menuOpen and not state.overlayActive and state.heldPress[idx] == nil then
						state.heldPress[idx] = "mouse"
					end
				end,
			},
			mouseUp = {
				weight = 3,
				run = function(sut)
					sut.services.UserInputService.InputEnded:Fire(fakeInput(MOUSE_BUTTON1))
				end,
				next = function(state)
					for i = 1, 2 do
						if state.heldPress[i] == "mouse" then
							state.heldPress[i] = nil
						end
					end
				end,
			},
			select = {
				weight = 3,
				gen = function(g)
					return g:int(0, 2)
				end,
				run = function(sut, idx)
					sut.services.GuiService.SelectedObject = if idx == 0 then nil else sut.guis[idx]
				end,
				next = function(state, idx)
					state.selectedIdx = if idx == 0 then nil else idx
				end,
			},
			gamepadDown = {
				weight = 2,
				run = function(sut)
					sut.services.UserInputService.InputBegan:Fire(fakeInput(GAMEPAD1, BUTTON_A))
				end,
				next = function(state)
					local idx = state.selectedIdx
					if not state.menuOpen and idx ~= nil and state.heldPress[idx] == nil then
						state.heldPress[idx] = "gamepad"
					end
				end,
			},
			gamepadUp = {
				weight = 2,
				run = function(sut)
					sut.services.UserInputService.InputEnded:Fire(fakeInput(GAMEPAD1, BUTTON_A))
				end,
				next = function(state)
					for i = 1, 2 do
						if state.heldPress[i] == "gamepad" then
							state.heldPress[i] = nil
						end
					end
				end,
			},
			menu = {
				weight = 2,
				gen = function(g)
					return g:bool()
				end,
				run = function(sut, open)
					sut.services.GuiService.MenuIsOpen = open
					sut.simEnv:step(1 / 60)
				end,
				next = function(state, open)
					state.menuOpen = open
					if open then
						state.heldPress = { nil, nil }
						state.heldTouchHover = { nil, nil }
					end
				end,
			},
			focus = {
				weight = 2,
				gen = function(g)
					return { idx = g:int(1, 2), gain = g:bool() }
				end,
				run = function(sut, arg)
					if arg.gain then
						sut.guis[arg.idx].Focused:Fire()
					else
						sut.guis[arg.idx].FocusLost:Fire()
					end
				end,
				next = function(state, arg)
					state.focused[arg.idx] = arg.gain
				end,
			},
		},
		never = {
			pressedWhileMenuOpen = function(state, sut)
				return state.menuOpen and (sut.pressed[1]:peek() or sut.pressed[2]:peek())
			end,
			hoveredWhileMenuOpen = function(state, sut)
				return state.menuOpen and (sut.hovered[1]:peek() or sut.hovered[2]:peek())
			end,
			pointerHoveredWhileOverlaySinks = function(state, sut)
				return state.overlayActive
					and (
						(state.heldTouchHover[1] == nil and sut.hovered[1]:peek())
						or (state.heldTouchHover[2] == nil and sut.hovered[2]:peek())
					)
			end,
		},
		invariants = {
			hoverAndGeometryMatchReference = function(state, sut)
				local ptr = sut.positions[state.pointerTarget]
				local expectedClaimed = state.menuOpen or state.overlayActive
				for i = 1, 2 do
					local center = sut.positions[i]
					sert.eq(
						Flux.Interact.pointIn(ptr.X, ptr.Y, sut.guis[i]),
						state.pointerTarget == i,
						`pointIn[{i}] at pointer`
					)
					if not IS_ROBLOX then
						sert.eq(
							Flux.Interact.sunk(center.X, center.Y, sut.guis[i]),
							expectedClaimed,
							`sunk[{i}] at center`
						)
						sert.eq(
							Flux.Interact.covered(center.X, center.Y, sut.guis[i]),
							expectedClaimed,
							`covered[{i}] at center`
						)
					end
					local expectedHover = not state.menuOpen
						and (state.heldTouchHover[i] ~= nil or (state.pointerTarget == i and not state.overlayActive))
					sert.eq(sut.hovered[i]:peek(), expectedHover, `hovered[{i}]`)
				end
			end,
			pressedMatchesActive = function(state, sut)
				for i = 1, 2 do
					sert.eq(sut.pressed[i]:peek(), state.heldPress[i] ~= nil, `pressed[{i}]`)
				end
			end,
			selectedMatchesGuiService = function(state, sut)
				for i = 1, 2 do
					sert.eq(sut.selected[i]:peek(), state.selectedIdx == i, `selected[{i}]`)
				end
			end,
			focusedMatchesTextBox = function(state, sut)
				for i = 1, 2 do
					sert.eq(sut.focused[i]:peek(), state.focused[i], `focused[{i}]`)
				end
			end,
		},
	},
	{
		runs = 120,
		size = 16,
		length = 16,
		exhaustive = { size = 2 },
	}
)

ctest("interact · selected and focused mirror a real player gui", function()
	local GuiService = game:GetService("GuiService")
	local player = game:GetService("Players").LocalPlayer
	local gui = Flux.new("ScreenGui")({ DisplayOrder = 1000, Parent = player:WaitForChild("PlayerGui") })
	local button = Flux.new("TextButton")({ Parent = gui, Size = UDim2.fromOffset(100, 40), Selectable = true })
	local box =
		Flux.new("TextBox")({ Parent = gui, Position = UDim2.fromOffset(0, 60), Size = UDim2.fromOffset(100, 40) })
	local isSelected = Flux.Interact.selected(button)
	local isFocused = Flux.Interact.focused(box)

	GuiService.SelectedObject = button
	env.settle()
	expect(isSelected:get() == true, "selecting the button sets selected")
	GuiService.SelectedObject = nil
	env.settle()
	expect(isSelected:get() == false, "clearing the selection clears it")

	box:CaptureFocus()
	env.settle()
	expect(isFocused:get() == true, "capturing focus sets focused")
	box:ReleaseFocus()
	env.settle()
	expect(isFocused:get() == false, "releasing focus clears it")

	isSelected:Destroy()
	isFocused:Destroy()
	gui:Destroy()
end)

local engineTest = if env.engine ~= nil then test else sert.skip
engineTest("interact · press, selected and focused on the engine's own services", function()
	local services = env.Compat.services
	local gui = env.Instance.new("ScreenGui")
	local button = Flux.new("TextButton")({ Parent = gui })
	local box = Flux.new("TextBox")({ Parent = gui })
	local pressed, isSelected, isFocused
	local scope = Flux.scope(function()
		pressed = Flux.Interact.press(button)
		isSelected = Flux.Interact.selected(button)
		isFocused = Flux.Interact.focused(box)
	end)
	local click = fakeInput(MOUSE_BUTTON1)
	button.InputBegan:Fire(click)
	services.GuiService.SelectedObject = button
	box:CaptureFocus()
	env.settle()
	expect(pressed:get() and isSelected:get() and isFocused:get(), "a click, the selection and focus each land")
	services.UserInputService.InputEnded:Fire(click)
	services.GuiService.SelectedObject = nil
	box:ReleaseFocus()
	env.settle()
	expect(not pressed:get() and not isSelected:get() and not isFocused:get(), "and each ends")
	scope:Destroy()
	gui:Destroy()
end)

engineTest("interact · sunk, covered, hover and press with PlayerGui hit testing and engine:input()", function()
	local UDim2 = env.UDim2
	local services = env.Compat.services
	local playerGui = env.engine.LocalPlayer.PlayerGui
	local input = env.engine:input()

	local gui = Flux.new("ScreenGui")({
		Parent = playerGui,
	})
	-- `GetGuiObjectsAtPosition` in `sert.env` visits descendants in hierarchy order, so an overlay placed
	-- before `under` sits above it in hit-test order.
	local over = Flux.new("Frame")({
		Parent = gui,
		Position = UDim2.fromOffset(20, 20),
		Size = UDim2.fromOffset(100, 60),
		InputSink = SINK_ALL,
		ZIndex = 3,
	})
	local button = Flux.new("TextButton")({
		Parent = gui,
		Position = UDim2.fromOffset(20, 20),
		Size = UDim2.fromOffset(100, 60),
		InputSink = SINK_ACTIVATE,
		ZIndex = 2,
	})
	local under = Flux.new("Frame")({
		Parent = gui,
		Position = UDim2.fromOffset(20, 20),
		Size = UDim2.fromOffset(100, 60),
		ZIndex = 1,
	})

	local x, y = 50, 40
	expect.eq(Flux.Interact.sunk(x, y, button), true, "All overlay above sinks the button")
	expect.eq(Flux.Interact.covered(x, y, under), true, "All overlay above covers the container")

	over.InputSink = SINK_NONE
	expect.eq(Flux.Interact.sunk(x, y, button), false, "None overlay permits the underlying button")
	expect.eq(Flux.Interact.sunk(x, y, under), true, "button with Activate above under sinks the point for under")
	expect.eq(Flux.Interact.covered(x, y, button), false, "topmost active button is not covered when overlay is None")

	local hovering, pressed
	local scope = Flux.scope(function()
		hovering = Flux.Interact.hover(button)
		pressed = Flux.Interact.press(button)
	end)

	-- Hover via MouseEnter + engine:input():move + frame step
	input:move(Vector2.new(x, y))
	button.MouseEnter:Fire(x, y)
	env.frame()
	expect.eq(hovering:get(), true, "pointer over uncovered button hovers it")

	over.InputSink = SINK_ALL
	env.frame()
	expect.eq(hovering:get(), false, "overlay claiming input unhovers button on next frame")

	over.InputSink = SINK_NONE
	env.frame()
	expect.eq(hovering:get(), true, "clearing overlay input sink restores hover")

	input:move(Vector2.new(300, 300))
	button.MouseLeave:Fire(300, 300)
	env.frame()
	expect.eq(hovering:get(), false, "leaving button bounds drops hover")

	-- Press viaGuiService selection + engine:input():press / release (Return & ButtonA)
	services.GuiService.SelectedObject = button
	input:press(Enum.KeyCode.Return)
	expect.eq(pressed:get(), true, "engine:input():press(Return) activates selected button")
	input:release(Enum.KeyCode.Return)
	expect.eq(pressed:get(), false, "engine:input():release(Return) settles press")

	-- Click dispatch via engine:input():click
	local clicks = 0
	button.Activated:Connect(function()
		clicks += 1
	end)
	input:click(button)
	expect.eq(clicks, 1, "engine:input():click dispatches Activated on button")

	services.GuiService.SelectedObject = nil
	scope:Destroy()
	gui:Destroy()
end)

test("interact · multi-touch hover isolation and nil-services press/selected fallback", function()
	local gui = fakeGui()
	local hovering = Flux.Interact.hover(gui)
	local touch1 = fakeInput(TOUCH)
	local touch2 = fakeInput(TOUCH)
	gui.InputBegan:Fire(touch1)
	expect(hovering:get() == true, "first touch hovers")
	gui.InputEnded:Fire(touch2)
	expect(hovering:get() == true, "unrelated second touch ending does not drop first touch's hover")
	gui.InputEnded:Fire(touch1)
	expect(hovering:get() == false, "primary touch ending drops hover")
	hovering:Destroy()

	local btn = fakeGui()
	local pressed = InteractModule._pressWith(btn :: any, nil)
	local sel = InteractModule._selectedWith(btn :: any, nil)
	expect(pressed:get() == false and sel:get() == false, "nil services start false")
	local tap = fakeInput(TOUCH)
	btn.InputBegan:Fire(tap)
	expect(pressed:get() == true, "press without services tracks object.InputBegan")
	btn.InputEnded:Fire(tap)
	expect(pressed:get() == false, "press without services releases on object.InputEnded")
	pressed:Destroy()
	sel:Destroy()
end)

return {}
