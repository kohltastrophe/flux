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
	expect.eq(#warned, 1, "unknown scale mode warns once per mode")
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

	local oldCam = env.workspace.CurrentCamera
	local altCam = env.Instance.new("Camera")
	rawset(altCam._props, "ViewportSize", Vector2.new(1280, 720))
	env.workspace.CurrentCamera = altCam
	env.settle()
	expect.eq(Responsive.viewport:get(), Vector2.new(1280, 720), "CurrentCamera swap updates viewport immediately")
	rawset(oldCam._props, "ViewportSize", Vector2.new(640, 480))
	oldCam:GetPropertyChangedSignal("ViewportSize"):Fire()
	env.settle()
	expect.eq(Responsive.viewport:get(), Vector2.new(1280, 720), "previous camera signal was disconnected")
	env.workspace.CurrentCamera = nil :: any
	env.settle()
	rawset(altCam._props, "ViewportSize", Vector2.new(800, 600))
	altCam:GetPropertyChangedSignal("ViewportSize"):Fire()
	env.settle()
	expect.eq(Responsive.viewport:get(), Vector2.new(1280, 720), "nil CurrentCamera disconnects active camera")
	rawset(oldCam._props, "ViewportSize", Vector2.new(1920, 1080))
	env.workspace.CurrentCamera = oldCam
	env.settle()
	altCam:Destroy()
end)

sert.laws.ui("responsive · adaptive layout across Phone, Tablet, Desktop, and Console viewports", {
	noTextOverflow = not env.IS_ROBLOX,
	mount = function(_uiEnv, parent, viewport)
		local UDim2 = env.UDim2
		local Enum = env.Enum
		local hostParent, cleanHost = env.mountUi(parent, viewport)
		if env.engine ~= nil then
			env.engine:setViewport(viewport)
		end
		Responsive.viewport:set(viewport)
		Flux.flush()

		local root: Frame
		local scope = Flux.scope(function()
			local cols = Flux.computed(function()
				local bp = Responsive.breakpoint()
				return if bp == "phone" then 1 elseif bp == "tablet" then 2 else 3
			end)
			local pad = Flux.computed(function()
				return if Responsive.breakpoint() == "phone" then 8 else 16
			end)
			local cellW = Flux.computed(function()
				local bp = Responsive.breakpoint()
				local avail = math.min(viewport.X - 24, 960) - (if bp == "phone" then 16 else 32)
				local n = cols()
				return math.floor((avail - (n - 1) * 8) / n)
			end)
			local cellSize = Flux.computed(function()
				return Vector2.new(math.max(80, cellW()), 44)
			end)

			root = Flux.new("Frame")({
				Name = "ResponsiveShell",
				Parent = hostParent,
				Position = UDim2.fromOffset(12, 12),
				Size = UDim2.fromOffset(math.min(viewport.X - 24, 960), math.min(viewport.Y - 24, 540)),
				Flux.padding(pad),
				Flux.list({ direction = "y", gap = 10 }),
				Flux.new("Frame")({
					Name = "TopBar",
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 36),
					Flux.list({ direction = "x", gap = 8, align = "center" }),
					Flux.new("TextLabel")({
						Name = "ModeBadge",
						LayoutOrder = 1,
						Size = UDim2.fromOffset(120, 28),
						Text = function()
							return `BP:{Responsive.breakpoint()}`
						end,
						TextSize = 14,
						TextScaled = true,
					}),
					Flux.switch(Responsive.breakpoint)({
						phone = function()
							return Flux.new("TextLabel")({
								Name = "NavCompact",
								LayoutOrder = 2,
								Size = UDim2.fromOffset(96, 28),
								Text = "Menu",
								TextSize = 14,
								TextScaled = true,
							})
						end,
						tablet = function()
							return Flux.new("TextLabel")({
								Name = "NavMedium",
								LayoutOrder = 2,
								Size = UDim2.fromOffset(160, 28),
								Text = "Home · Shop",
								TextSize = 14,
								TextScaled = true,
							})
						end,
						desktop = function()
							return Flux.new("TextLabel")({
								Name = "NavFull",
								LayoutOrder = 2,
								Size = UDim2.fromOffset(220, 28),
								Text = "Home · Shop · Guild · Ranks",
								TextSize = 14,
								TextScaled = true,
							})
						end,
					}),
				}),
				Flux.new("ScrollingFrame")({
					Name = "CardGrid",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 180),
					CanvasSize = UDim2.fromScale(0, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollingDirection = Enum.ScrollingDirection.Y,
					ClipsDescendants = true,
					Flux.grid({ cell = cellSize, gap = 8, fill = "x" }),
					Flux.new("Frame")({
						Name = "Card1",
						LayoutOrder = 1,
						Flux.new("TextLabel")({
							Size = UDim2.fromScale(1, 1),
							Text = "Slot 1",
							TextSize = 12,
							TextScaled = true,
						}),
					}),
					Flux.new("Frame")({
						Name = "Card2",
						LayoutOrder = 2,
						Flux.new("TextLabel")({
							Size = UDim2.fromScale(1, 1),
							Text = "Slot 2",
							TextSize = 12,
							TextScaled = true,
						}),
					}),
					Flux.new("Frame")({
						Name = "Card3",
						LayoutOrder = 3,
						Flux.new("TextLabel")({
							Size = UDim2.fromScale(1, 1),
							Text = "Slot 3",
							TextSize = 12,
							TextScaled = true,
						}),
					}),
				}),
			})
		end)
		Flux.flush()
		sert.defer(function()
			scope:Destroy()
			root:Destroy()
			cleanHost()
			if env.engine ~= nil then
				env.engine:setViewport(Vector2.new(1920, 1080))
			end
			Responsive.viewport:set(Vector2.new(1920, 1080))
			Flux.flush()
		end)
		return root
	end,
	check = function(_uiEnv, root, vp)
		local RobloxLayout = sert.roblox.Layout
		RobloxLayout.audit(root, { viewport = vp.size, fitsParent = true, noTextOverflow = not env.IS_ROBLOX })

		local expectedBp = if vp.size.X < 600 then "phone" elseif vp.size.X < 1024 then "tablet" else "desktop"
		expect.eq(Responsive.breakpoint:get(), expectedBp, `breakpoint at {vp.name} ({vp.size.X}x{vp.size.Y})`)

		local topBar = root:FindFirstChild("TopBar") :: Frame
		local badge = topBar:FindFirstChild("ModeBadge") :: TextLabel
		expect.eq(badge.Text, `BP:{expectedBp}`, "ModeBadge text reflects active breakpoint")

		local hasCompact = topBar:FindFirstChild("NavCompact") ~= nil
		local hasMedium = topBar:FindFirstChild("NavMedium") ~= nil
		local hasFull = topBar:FindFirstChild("NavFull") ~= nil
		expect.eq(hasCompact, expectedBp == "phone", "NavCompact mounted iff phone")
		expect.eq(hasMedium, expectedBp == "tablet", "NavMedium mounted iff tablet")
		expect.eq(hasFull, expectedBp == "desktop", "NavFull mounted iff desktop")
	end,
})

engineTest(
	"responsive · env:setViewport relayouts live ScreenGui across Phone, Tablet, Desktop, and Console",
	function()
		local RobloxLayout = sert.roblox.Layout
		local UDim2 = env.UDim2
		local screen: ScreenGui
		local panel: Frame
		local scope = Flux.scope(function()
			panel = Flux.new("Frame")({
				Name = "AdaptivePanel",
				Size = UDim2.fromScale(1, 1),
				Flux.padding(12),
				Flux.list({
					direction = function()
						return if Responsive.breakpoint() == "phone" then "y" else "x"
					end,
					gap = 10,
				}),
				Flux.new("Frame")({
					Name = "PaneA",
					LayoutOrder = 1,
					Size = UDim2.fromOffset(150, 80),
				}),
				Flux.new("Frame")({
					Name = "PaneB",
					LayoutOrder = 2,
					Size = UDim2.fromOffset(150, 80),
				}),
			})
			screen = Flux.new("ScreenGui")({
				Name = "ViewportGui",
				Parent = env.Compat.services.Players.LocalPlayer.PlayerGui,
				panel,
			})
		end)
		Flux.flush()

		local viewports = {
			{ name = "Phone", size = Vector2.new(390, 844), bp = "phone", axis = "Y" },
			{ name = "Tablet", size = Vector2.new(820, 1180), bp = "tablet", axis = "X" },
			{ name = "Desktop", size = Vector2.new(1920, 1080), bp = "desktop", axis = "X" },
			{ name = "Console", size = Vector2.new(1920, 1080), bp = "desktop", axis = "X" },
		}
		for _, vp in viewports do
			env.engine:setViewport(vp.size)
			Responsive.viewport:set(vp.size)
			Flux.flush()
			expect.eq(Responsive.breakpoint:get(), vp.bp, `breakpoint matches {vp.name}`)
			expect.eq(screen.AbsoluteSize, vp.size, `ScreenGui AbsoluteSize matches {vp.name} viewport`)
			RobloxLayout.audit(panel, { viewport = vp.size, fitsParent = true })
			local paneA = panel:FindFirstChild("PaneA") :: Frame
			local paneB = panel:FindFirstChild("PaneB") :: Frame
			RobloxLayout.spacing({ paneA, paneB }, vp.axis :: any, 10)
		end

		scope:Destroy()
		screen:Destroy()
		env.engine:setViewport(Vector2.new(1920, 1080))
		Responsive.viewport:set(Vector2.new(1920, 1080))
		Flux.flush()
	end
)

return {}
