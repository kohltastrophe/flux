--!nonstrict
local env = if game ~= nil
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Flux, sert = env.Flux, env.sert

local test = sert.test
local rtest = sert.test.roblox
local expect = sert

test("frame · effects auto-flush on the frame hookup", function()
	local a = Flux(1)
	local seen = {}
	local e = Flux.effect(function()
		table.insert(seen, a:get())
	end)
	-- No manual flush: run frames (engine frames in Roblox, Clock.step headless) until the hookup has run the effect.
	expect(
		env.frames(function()
			return seen[1] == 1
		end),
		"creation run flushed by the frame hookup"
	)
	a:set(2)
	expect(
		env.frames(function()
			return seen[#seen] == 2
		end),
		"set flushed by the frame hookup"
	)
	e:Destroy()
end)

rtest("frame · the hookup flushes at PreRender on a client and at Heartbeat elsewhere", function()
	local RunService = game:GetService("RunService")
	local client = RunService:IsClient()
	local frame = if client then RunService.PreRender else RunService.Heartbeat
	local a = Flux(1)
	local seen
	local e = Flux.effect(function()
		seen = a:get()
	end)
	Flux.flush()
	RunService.Heartbeat:Wait() -- start right after a frame's Heartbeat
	a:set(2)
	-- The engine may call this handler before Flux's own; a thread it defers runs after both, in the same frame step.
	local atStep
	local connection
	connection = frame:Connect(function()
		connection:Disconnect()
		task.defer(function()
			atStep = seen
		end)
	end)
	expect(
		env.frames(function()
			return atStep ~= nil
		end),
		"the step ran"
	)
	expect.eq(atStep, 2, `the {if client then "PreRender" else "Heartbeat"} step itself flushed the effect`)
	e:Destroy()
end)

test("init · Flux(table) keeps table signals; Flux(table, second) rejects extra arg", function()
	local customSignal = {
		Connect = function(_self, _fn: (string) -> ())
			return { Disconnect = function() end }
		end,
	}
	local tableNode = Flux(customSignal)
	expect(tableNode:peek() == customSignal, "Flux(customSignalTable) creates a signal holding the table")
	tableNode:Destroy()
	local ok, err = pcall(function()
		Flux(customSignal, "start")
	end)
	expect(
		not ok and string.find(tostring(err), "only an Instance takes a property name", 1, true) ~= nil,
		"Flux(customSignal, initial) errors when not an RBXScriptSignal"
	)
end)

rtest("init · Flux(rbxSignal, initial?) bridges RBXScriptSignal", function()
	local event = Instance.new("BindableEvent")
	local node = Flux(event.Event, "start")
	expect.eq(node:peek(), "start", "Flux(rbxSignal, initial) seeds initial value")
	event:Fire("fired")
	expect(
		env.frames(function()
			return node:peek() == "fired"
		end),
		"Flux(rbxSignal, initial) receives emitted payloads"
	)
	node:Destroy()
	event:Destroy()
end)

test("init · exports mount, portal, merge, scale, and fromSignal", function()
	expect(type(Flux.mount) == "function", "Flux.mount is exported")
	expect(type(Flux.portal) == "function", "Flux.portal is exported")
	expect(type(Flux.merge) == "function", "Flux.merge is exported")
	expect(type(Flux.scale) == "function", "Flux.scale is exported")
	expect(type(Flux.fromSignal) == "function", "Flux.fromSignal is exported")
end)

test("init · exports every public API and namespace member", function()
	local topLevelFns = {
		"signal",
		"computed",
		"effect",
		"createSignal",
		"createMemo",
		"createEffect",
		"getter",
		"setter",
		"scope",
		"flush",
		"cleanup",
		"dispose",
		"getOwner",
		"withOwner",
		"read",
		"raw",
		"untrack",
		"retrack",
		"isNode",
		"isReactive",
		"on",
		"listen",
		"context",
		"bindContext",
		"async",
		"selector",
		"store",
		"split",
		"prop",
		"own",
		"merge",
		"safe",
		"property",
		"fromSignal",
		"model",
		"isModel",
		"modelNode",
		"portal",
		"show",
		"showKeyed",
		"switch",
		"presence",
		"pick",
		"fallback",
		"forValue",
		"forIndex",
		"forKey",
		"spring",
		"tween",
		"padding",
		"corner",
		"stroke",
		"aspectRatio",
		"list",
		"grid",
		"flex",
		"scale",
		"gradient",
		"sizeConstraint",
		"textSizeConstraint",
		"mount",
		"edit",
		"new",
	}
	for _, key in topLevelFns do
		expect(type((Flux :: any)[key]) == "function", `Flux.{key} is exported`)
	end
	expect(type(Flux.otherwise) == "table", "Flux.otherwise sentinel is exported")

	local namespaces: { [string]: { string } } = {
		Clock = {
			"now",
			"wall",
			"delay",
			"wait",
			"defer",
			"cancel",
			"connect",
			"manual",
			"isManual",
			"step",
			"drain",
			"reset",
		},
		Color = {
			"lighten",
			"saturate",
			"rotateHue",
			"grayscale",
			"mix",
			"luminance",
			"contrast",
			"readable",
		},
		Interact = { "pointIn", "sunk", "covered", "hover", "press", "selected", "focused" },
		Motion = { "step" },
		Store = { "insert", "remove", "move", "reconcile", "unwrap", "Destroy" },
		Find = {
			"Ancestor",
			"AncestorClass",
			"AncestorIsA",
			"Child",
			"ChildClass",
			"ChildIsA",
			"Descendant",
			"Parent",
			"Path",
			"Query",
			"QueryFirst",
		},
	}
	for ns, members in namespaces do
		local tbl = (Flux :: any)[ns]
		expect(type(tbl) == "table", `Flux.{ns} is a table`)
		for _, member in members do
			expect(type(tbl[member]) == "function", `Flux.{ns}.{member} is a function`)
		end
	end
	expect(type(Flux.Color.Oklab) == "table" and type(Flux.Color.sRGB) == "table", "Flux.Color sub-tables exported")

	expect(type(Flux.Responsive) == "table", "Flux.Responsive is a table")
	expect(type(Flux.Responsive.config) == "table", "Flux.Responsive.config is a table")
	expect(
		type(Flux.Responsive.scaleOf) == "function" and type(Flux.Responsive.breakpointOf) == "function",
		"Flux.Responsive factories are functions"
	)
	local responsiveNodes = {
		"platform",
		"viewport",
		"scale",
		"breakpoint",
		"displaySize",
		"input",
		"textSize",
		"reducedMotion",
		"preferredTransparency",
	}
	for _, member in responsiveNodes do
		expect(Flux.isNode((Flux.Responsive :: any)[member]), `Flux.Responsive.{member} is a Node`)
	end

	expect(type(Flux.Flags) == "table" and type(Flux.Flags.defaults) == "boolean", "Flux.Flags.defaults is a boolean")
	expect(type(Flux.Sync) == "table", "Flux.Sync is exported as a table")

	local defaultClasses = {
		"Part",
		"BillboardGui",
		"ScreenGui",
		"SurfaceGui",
		"Frame",
		"ImageButton",
		"ImageLabel",
		"VideoFrame",
		"ViewportFrame",
		"ScrollingFrame",
		"TextBox",
		"TextButton",
		"TextLabel",
		"UIListLayout",
		"UIGridLayout",
		"UITableLayout",
		"UIPageLayout",
	}
	expect(type(Flux.Defaults) == "table", "Flux.Defaults is a table")
	expect(env.Compat.Color3 ~= nil, "Compat.Color3 is loaded in unit tests")
	for _, className in defaultClasses do
		expect(type((Flux.Defaults :: any)[className]) == "table", `Flux.Defaults.{className} is a table`)
	end
end)
