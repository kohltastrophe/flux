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

local approx = sert.approx

test("edit · init actions run via task.defer", function()
	local ran = 0
	local fake = { Parent = nil }
	Flux.edit(fake)({
		function(inst)
			ran += 1
		end,
	})
	if IS_ROBLOX then
		task.wait() -- real defer runs at the next resumption point
	end
	expect(ran == 1, "init action ran")
end)

rtest("new · static properties", function()
	-- Flux.new inside a scope is owned by it: the instance is destroyed on scope Destroy.
	local frame
	local s = Flux.scope(function()
		frame = Flux.new("Frame")({
			Name = "TestFrame",
			Size = UDim2.fromOffset(100, 50),
			BackgroundTransparency = 0.25,
		})
	end)
	expect(frame:IsA("Frame"), "created the requested class")
	expect(frame.Name == "TestFrame", "string property assigned")
	expect(frame.Size == UDim2.fromOffset(100, 50), "UDim2 property assigned")
	expect(approx(frame.BackgroundTransparency, 0.25), "number property assigned")
	s:Destroy()
end)

rtest("new · reactive property binding (direct node)", function()
	local text = Flux("hello")
	local label
	local s = Flux.scope(function()
		label = Flux.new("TextLabel")({ Text = text })
	end)
	flush()
	expect(label.Text == "hello", "bound to initial node value after flush")
	text("world")
	flush()
	expect(label.Text == "world", "property tracks the node")
	s:Destroy()
end)

rtest("new · inline function binding (implicit memo)", function()
	local count = Flux(1)
	local label
	local s = Flux.scope(function()
		label = Flux.new("TextLabel")({
			Text = function()
				return "Count: " .. count
			end,
		})
	end)
	flush()
	expect(label.Text == "Count: 1", "implicit memo evaluated")
	count(2)
	flush()
	expect(label.Text == "Count: 2", "implicit memo reacts to its dependency")
	s:Destroy()
end)

rtest("new · numeric children are parented", function()
	local parent
	local s = Flux.scope(function()
		parent = Flux.new("Frame")({
			Name = "Parent",
			Flux.new("TextLabel")({ Name = "ChildA" }),
			Flux.new("TextLabel")({ Name = "ChildB" }),
		})
	end)
	expect(parent:FindFirstChild("ChildA") ~= nil, "first child parented")
	expect(parent:FindFirstChild("ChildB") ~= nil, "second child parented")
	s:Destroy()
end)

rtest("new · plain array of instances flattens into children", function()
	local a, b, parent
	local s = Flux.scope(function()
		a = Flux.new("TextLabel")({ Name = "A" })
		b = Flux.new("TextLabel")({ Name = "B" })
		parent = Flux.new("Frame")({
			Name = "Parent",
			{ a, b }, -- a plain array at a numeric index parents each element
		})
	end)
	expect(parent:FindFirstChild("A") ~= nil, "first array child parented")
	expect(parent:FindFirstChild("B") ~= nil, "second array child parented")
	expect(a.LayoutOrder == 1 and b.LayoutOrder == 2, "flattened children get incrementing LayoutOrder")
	s:Destroy()
end)

rtest("new · array flattening binds a node child (Flux.show)", function()
	local cond = Flux.signal(true)
	local static, shown, parent
	local s = Flux.scope(function()
		shown = Flux.show(cond, function()
			return Flux.new("Frame")({ Name = "Shown" })
		end)
		static = Flux.new("TextLabel")({ Name = "Static" })
		parent = Flux.new("Frame")({
			Name = "Parent",
			{ static, shown }, -- array mixes a static child and a reactive children-binder
		})
	end)
	flush()
	expect(parent:FindFirstChild("Static") ~= nil, "static array child parented")
	expect(parent:FindFirstChild("Shown") ~= nil, "node child in the array mounted via Bind.children")
	cond:set(false)
	flush()
	expect(parent:FindFirstChild("Shown") == nil, "node child unmounts when its source goes falsy")
	s:Destroy()
end)

rtest("new · Flux.model two-way binds a property", function()
	local text = Flux.signal("hello")
	local box
	local s = Flux.scope(function()
		box = Flux.new("TextBox")({
			Text = Flux.model(text),
		})
	end)
	flush()
	expect(box.Text == "hello", "instance is driven from the node (authored value wins)")

	text:set("world") -- node -> instance
	flush()
	expect(box.Text == "world", "writing the node updates the instance")

	box.Text = "typed" -- instance -> node (the user typing)
	task.wait() -- let the property-changed signal run node:set
	flush()
	expect(text() == "typed", "changing the instance writes back to the node")
	s:Destroy()
end)

rtest("new · Flux.model two-way binds an attribute via _ATTR", function()
	local level = Flux.signal(1)
	local frame
	local s = Flux.scope(function()
		frame = Flux.new("Frame")({
			_ATTR = { Level = Flux.model(level) },
		})
	end)
	flush()
	expect(frame:GetAttribute("Level") == 1, "attribute driven from the node")

	level:set(5) -- node -> attribute
	flush()
	expect(frame:GetAttribute("Level") == 5, "writing the node updates the attribute")

	frame:SetAttribute("Level", 9) -- attribute -> node
	task.wait() -- let the attribute-changed signal run node:set
	flush()
	expect(level() == 9, "changing the attribute writes back to the node")
	s:Destroy()
end)

rtest("new · _REF (callback and node forms)", function()
	local captured
	local refNode = Flux.signal(nil)
	local s = Flux.scope(function()
		Flux.new("Frame")({
			_REF = function(inst)
				captured = inst
			end,
		})
		Flux.new("Frame")({ _REF = refNode })
	end)
	expect(captured ~= nil and captured:IsA("Frame"), "_REF callback received the instance")
	expect(refNode() ~= nil and refNode():IsA("Frame"), "_REF node set to the instance")
	s:Destroy()
end)

rtest("new · _ATTR (static and reactive)", function()
	local lvl = Flux(1)
	local f, f2
	local s = Flux.scope(function()
		f = Flux.new("Frame")({ _ATTR = { Level = 7, Tag = "boss" } })
		f2 = Flux.new("Frame")({ _ATTR = { Level = lvl } })
	end)
	expect(f:GetAttribute("Level") == 7, "static numeric attribute set")
	expect(f:GetAttribute("Tag") == "boss", "static string attribute set")
	flush()
	expect(f2:GetAttribute("Level") == 1, "reactive attribute initial value")
	lvl(2)
	flush()
	expect(f2:GetAttribute("Level") == 2, "reactive attribute updates")
	s:Destroy()
end)

rtest("new · _TAG static string and array of strings", function()
	local f, f2
	local s = Flux.scope(function()
		f = Flux.new("Frame")({ _TAG = "Enemy" })
		f2 = Flux.new("Frame")({ _TAG = { "Enemy", "Boss" } })
	end)
	expect(f:HasTag("Enemy"), "single string tag applied")
	expect(f2:HasTag("Enemy") and f2:HasTag("Boss"), "every tag in an array applied")
	s:Destroy()
end)

rtest("new · _TAG reactive string node swaps the tag", function()
	local tag = Flux.signal("Idle")
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({ _TAG = tag })
	end)
	expect(f:HasTag("Idle"), "initial node value applied on mount")
	tag:set("Running")
	flush()
	expect(f:HasTag("Running"), "new tag added when the node changes")
	expect(not f:HasTag("Idle"), "previous tag removed when the node changes")
	s:Destroy()
end)

rtest("new · _TAG node with a table value diffs adds and removes", function()
	local tags = Flux.signal({ "A", "B" })
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({ _TAG = tags })
	end)
	expect(f:HasTag("A") and f:HasTag("B"), "initial table tags applied")

	tags:set({ "B", "C" })
	flush()
	expect(not f:HasTag("A"), "dropped tag removed")
	expect(f:HasTag("B"), "kept tag untouched")
	expect(f:HasTag("C"), "added tag applied")

	-- table -> string transition: the shared tag must survive the diff
	tags:set("B")
	flush()
	expect(f:HasTag("B"), "tag shared between old table and new string kept")
	expect(not f:HasTag("C"), "unshared table tag removed")

	-- string -> table transition
	tags:set({ "B", "D" })
	flush()
	expect(f:HasTag("B") and f:HasTag("D"), "string -> table transition applies the new set")
	s:Destroy()
end)

rtest("new · _TAG inline function is an implicit memo", function()
	local alive = Flux.signal(true)
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({
			_TAG = function()
				return alive() and "Alive" or "Dead"
			end,
		})
	end)
	flush()
	expect(f:HasTag("Alive"), "function value evaluated and applied")
	alive:set(false)
	flush()
	expect(f:HasTag("Dead"), "tag tracks the function's dependencies")
	expect(not f:HasTag("Alive"), "stale tag removed")
	s:Destroy()
end)

rtest("new · _TAG mixed array of static strings and nodes", function()
	local state = Flux.signal("Idle")
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({ _TAG = { "Enemy", state } })
	end)
	expect(f:HasTag("Enemy"), "static tag in the array applied")
	expect(f:HasTag("Idle"), "node tag in the array applied")
	state:set("Running")
	flush()
	expect(f:HasTag("Enemy"), "static tag unaffected by node updates")
	expect(f:HasTag("Running") and not f:HasTag("Idle"), "node tag in the array swaps independently")
	s:Destroy()
end)

rtest("new · reactive tag moving off a static sibling keeps the shared tag", function()
	local status = Flux.signal("Enemy")
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({ _TAG = { "Enemy", status } })
	end)
	expect(f:HasTag("Enemy"), "shared tag applied")
	status:set("Boss")
	flush()
	expect(f:HasTag("Enemy"), "statically declared tag survives the node moving off it")
	expect(f:HasTag("Boss"), "new node tag applied")
	s:Destroy()
end)

rtest("edit · _TAG stops tracking after scope destroy", function()
	local f = Instance.new("Frame")
	local tag = Flux.signal("A")
	local s = Flux.scope(function()
		Flux.edit(f)({ _TAG = tag })
	end)
	expect(f:HasTag("A"), "initial tag applied to existing instance")
	tag:set("B")
	flush()
	expect(f:HasTag("B") and not f:HasTag("A"), "tag tracks the node while the scope is alive")
	s:Destroy()
	tag:set("C")
	flush()
	expect(f:HasTag("B"), "last applied tag is left in place after scope destroy")
	expect(not f:HasTag("C"), "listener disconnected by scope destroy")
	f:Destroy()
end)

rtest("new · defaults applied and toggleable via Flux.Flags", function()
	-- Default for ImageButton sets AutoButtonColor = false (Roblox default is true)
	local btn
	local s = Flux.scope(function()
		btn = Flux.new("ImageButton")({})
	end)
	expect(btn.AutoButtonColor == false, "class defaults applied when Flags.defaults is true")
	s:Destroy()
	Flux.Flags.defaults = false -- afterEach restores it to true, even if the assert below throws
	local btn2
	local s2 = Flux.scope(function()
		btn2 = Flux.new("ImageButton")({})
	end)
	local autoColorWithoutDefaults = btn2.AutoButtonColor
	s2:Destroy()
	expect(autoColorWithoutDefaults == true, "no defaults applied when Flags.defaults is false")
end)

rtest("new · function on a signal property connects (signal-prop sugar)", function()
	local fired = 0
	local payload
	-- BindableEvent.Event is an RBXScriptSignal-typed property: a function
	-- assigned to it is connected implicitly (Edit.luau signal-property sugar)
	local bindable
	local s = Flux.scope(function()
		bindable = Flux.new("BindableEvent")({
			Event = function(value)
				fired += 1
				payload = value
			end,
		})
	end)
	bindable:Fire(42)
	task.wait() -- BindableEvent connections fire at the next resumption point
	expect(fired == 1, "function on a signal-typed property was connected and fired")
	expect(payload == 42, "connected handler received the fired argument")
	bindable:Destroy()
	s:Destroy()
end)

rtest("edit · props and reactive bindings on an existing instance", function()
	local existing = Instance.new("Frame")
	local color = Flux(Color3.new(1, 0, 0))
	local s = Flux.scope(function()
		Flux.edit(existing)({
			Name = "Edited",
			BackgroundColor3 = color,
		})
	end)
	flush()
	expect(existing.Name == "Edited", "static prop applied to existing instance")
	expect(existing.BackgroundColor3 == Color3.new(1, 0, 0), "reactive bind initial value")
	color(Color3.new(0, 1, 0))
	flush()
	expect(existing.BackgroundColor3 == Color3.new(0, 1, 0), "reactive bind updates")
	existing:Destroy()
	s:Destroy()
end)

rtest("edit · node-driven Parent + _CLEAN survive immediate destroy", function()
	-- the Destroying connection is hooked BEFORE parenting, so a destroy
	-- right after edit() still flushes _CLEAN
	local screen = Instance.new("ScreenGui")
	local parentFrame = Instance.new("Frame")
	parentFrame.Parent = screen

	local cleaned = 0
	local child = Instance.new("Frame")
	local parentNode = Flux.signal(parentFrame)
	Flux.edit(child)({
		Parent = parentNode,
		_CLEAN = {
			function()
				cleaned += 1
			end,
		},
	})
	expect(child.Parent == parentFrame, "node-driven Parent applied")
	child:Destroy()
	task.wait() -- let deferred Destroying handlers run
	expect(cleaned == 1, "_CLEAN flushed on immediate destroy")

	-- node-driven Parent keeps following on a fresh instance
	local child2 = Instance.new("Frame")
	Flux.edit(child2)({ Parent = parentNode })
	local otherParent = Instance.new("Frame")
	otherParent.Parent = screen
	parentNode:set(otherParent)
	flush()
	expect(child2.Parent == otherParent, "node Parent retargets")
	screen:Destroy()
end)

rtest("edit · _CLEAN runs exactly once across instance and scope destroy", function()
	local f = Instance.new("Frame")
	local cleaned = 0
	local s = Flux.scope(function()
		Flux.edit(f)({
			_CLEAN = {
				function()
					cleaned += 1
				end,
			},
		})
	end)
	f:Destroy()
	task.wait()
	expect(cleaned == 1, "cleaned on instance destroy")
	s:Destroy()
	expect(cleaned == 1, "scope destroy does not re-run the cleanup")
end)

rtest("edit · _EVENT connects an RBXScriptSignal handler", function()
	local bindable = Instance.new("BindableEvent")
	local fired = 0
	local payload
	local s = Flux.scope(function()
		Flux.edit(bindable)({
			_EVENT = {
				-- instance.Event is an RBXScriptSignal: connected via signal:Connect
				Event = function(value)
					fired += 1
					payload = value
				end,
			},
		})
	end)
	bindable:Fire("hello")
	task.wait() -- BindableEvent connections fire at the next resumption point
	expect(fired == 1, "RBXScriptSignal handler ran once after Fire")
	expect(payload == "hello", "handler received the fired argument")
	bindable:Destroy()
	s:Destroy()
end)

rtest("edit · _EVENT GetPropertyChangedSignal handler", function()
	local label = Instance.new("TextLabel")
	local changes = 0
	local s = Flux.scope(function()
		Flux.edit(label)({
			_EVENT = {
				-- Text is NOT a signal: edit() falls back to GetPropertyChangedSignal("Text")
				Text = function()
					changes += 1
				end,
			},
		})
	end)
	expect(changes == 0, "property-changed handler does not fire on connect")
	label.Text = "updated"
	task.wait() -- changed-signal connections fire at the next resumption point
	expect(changes == 1, "GetPropertyChangedSignal handler ran on a real property write")
	label:Destroy()
	s:Destroy()
end)

rtest("edit · _EVENT value <== instance.property bind-from", function()
	local label = Instance.new("TextLabel")
	label.Text = "start"
	local mirror = Flux.signal(nil)
	local s = Flux.scope(function()
		Flux.edit(label)({
			_EVENT = {
				-- a node at a property key reads FROM the instance into the node
				Text = mirror,
			},
		})
	end)
	expect(mirror() == "start", "bind-from seeded the node with the current property value")
	label.Text = "next"
	task.wait() -- let the property-changed signal run node:set
	flush()
	expect(mirror() == "next", "node tracks subsequent property changes")
	label:Destroy()
	s:Destroy()
end)

rtest("edit · _EVENT._ATTR attribute-changed handler and bind-from", function()
	local frame = Instance.new("Frame")
	frame:SetAttribute("Score", 1)
	local attrChanges = 0
	local mirror = Flux.signal(nil)
	local s = Flux.scope(function()
		Flux.edit(frame)({
			_EVENT = {
				_ATTR = {
					-- function => GetAttributeChangedSignal(attr):Connect
					Score = function()
						attrChanges += 1
					end,
					-- node => value <== instance.attr (bind-from the attribute)
					Level = mirror,
				},
			},
		})
	end)
	expect(mirror() == nil, "bind-from seeds node with current (unset) attribute value")
	frame:SetAttribute("Score", 2)
	task.wait() -- let the attribute-changed signal fire its connection
	expect(attrChanges == 1, "attribute-changed handler ran on SetAttribute")
	frame:SetAttribute("Level", 9)
	task.wait() -- let the bind-from attribute-changed signal run node:set
	flush()
	expect(mirror() == 9, "node tracks the attribute via bind-from")
	frame:Destroy()
	s:Destroy()
end)

return {}
