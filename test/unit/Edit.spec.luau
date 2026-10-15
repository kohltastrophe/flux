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
	else
		Flux.Clock.drain()
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

rtest("new · Flux.model two-way binds an attribute via __ATTR", function()
	local level = Flux.signal(1)
	local frame
	local s = Flux.scope(function()
		frame = Flux.new("Frame")({
			__ATTR = { Level = Flux.model(level) },
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

rtest("new · __REF (callback and node forms)", function()
	local captured
	local refNode = Flux.signal(nil)
	local s = Flux.scope(function()
		Flux.new("Frame")({
			__REF = function(inst)
				captured = inst
			end,
		})
		Flux.new("Frame")({ __REF = refNode })
	end)
	expect(captured ~= nil and captured:IsA("Frame"), "__REF callback received the instance")
	expect(refNode() ~= nil and refNode():IsA("Frame"), "__REF node set to the instance")
	s:Destroy()
end)

rtest("new · __ATTR (static and reactive)", function()
	local lvl = Flux(1)
	local f, f2
	local s = Flux.scope(function()
		f = Flux.new("Frame")({ __ATTR = { Level = 7, Tag = "boss" } })
		f2 = Flux.new("Frame")({ __ATTR = { Level = lvl } })
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

rtest("new · __TAG static string and array of strings", function()
	local f, f2
	local s = Flux.scope(function()
		f = Flux.new("Frame")({ __TAG = "Enemy" })
		f2 = Flux.new("Frame")({ __TAG = { "Enemy", "Boss" } })
	end)
	expect(f:HasTag("Enemy"), "single string tag applied")
	expect(f2:HasTag("Enemy") and f2:HasTag("Boss"), "every tag in an array applied")
	s:Destroy()
end)

rtest("new · __TAG reactive string node swaps the tag", function()
	local tag = Flux.signal("Idle")
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({ __TAG = tag })
	end)
	expect(f:HasTag("Idle"), "initial node value applied on mount")
	tag:set("Running")
	flush()
	expect(f:HasTag("Running"), "new tag added when the node changes")
	expect(not f:HasTag("Idle"), "previous tag removed when the node changes")
	s:Destroy()
end)

rtest("new · __TAG node with a table value diffs adds and removes", function()
	local tags = Flux.signal({ "A", "B" })
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({ __TAG = tags })
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

rtest("new · __TAG inline function is an implicit memo", function()
	local alive = Flux.signal(true)
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({
			__TAG = function()
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

rtest("new · __TAG mixed array of static strings and nodes", function()
	local state = Flux.signal("Idle")
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({ __TAG = { "Enemy", state } })
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
		f = Flux.new("Frame")({ __TAG = { "Enemy", status } })
	end)
	expect(f:HasTag("Enemy"), "shared tag applied")
	status:set("Boss")
	flush()
	expect(f:HasTag("Enemy"), "statically declared tag survives the node moving off it")
	expect(f:HasTag("Boss"), "new node tag applied")
	s:Destroy()
end)

rtest("edit · frozen __EVENT maps are accepted without mutation", function()
	local label = Instance.new("TextLabel")
	local changes = 0
	local frozen = table.freeze({
		Text = function()
			changes += 1
		end,
	})
	local s = Flux.scope(function()
		Flux.edit(label)({ __EVENT = frozen })
	end)
	label.Text = "updated"
	task.wait() -- let the property-changed signal fire
	expect(changes == 1, "handler from a frozen event map connected")
	label:Destroy()
	s:Destroy()
end)

rtest("edit · __TAG stops tracking after scope destroy", function()
	local f = Instance.new("Frame")
	local tag = Flux.signal("A")
	local s = Flux.scope(function()
		Flux.edit(f)({ __TAG = tag })
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
	-- Default for Frame sets BorderSizePixel = 0 (Roblox default is 1)
	local frame
	local s = Flux.scope(function()
		frame = Flux.new("Frame")({})
	end)
	expect(frame.BorderSizePixel == 0, "class defaults applied when Flags.defaults is true")
	s:Destroy()
	Flux.Flags.defaults = false -- afterEach restores it to true, even if the assert below throws
	local frame2
	local s2 = Flux.scope(function()
		frame2 = Flux.new("Frame")({})
	end)
	local borderWithoutDefaults = frame2.BorderSizePixel
	s2:Destroy()
	expect(borderWithoutDefaults == 1, "no defaults applied when Flags.defaults is false")
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

rtest("edit · node-driven Parent + __CLEAN survive immediate destroy", function()
	-- the Destroying connection is hooked BEFORE parenting, so a destroy
	-- right after edit() still flushes __CLEAN
	local screen = Instance.new("ScreenGui")
	local parentFrame = Instance.new("Frame")
	parentFrame.Parent = screen

	local cleaned = 0
	local child = Instance.new("Frame")
	local parentNode = Flux.signal(parentFrame)
	Flux.edit(child)({
		Parent = parentNode,
		__CLEAN = {
			function()
				cleaned += 1
			end,
		},
	})
	expect(child.Parent == parentFrame, "node-driven Parent applied")
	child:Destroy()
	task.wait() -- let deferred Destroying handlers run
	expect(cleaned == 1, "__CLEAN flushed on immediate destroy")

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

rtest("edit · __CLEAN runs exactly once across instance and scope destroy", function()
	local f = Instance.new("Frame")
	local cleaned = 0
	local s = Flux.scope(function()
		Flux.edit(f)({
			__CLEAN = {
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

rtest("edit · __EVENT rejects an RBXScriptSignal and directs to top-level key", function()
	local bindable = Instance.new("BindableEvent")
	sert.fails(function()
		Flux.edit(bindable)({
			__EVENT = {
				Event = function() end,
			},
		})
	end, "connect `Event` as a top-level key")
	bindable:Destroy()
end)

rtest("edit · __EVENT GetPropertyChangedSignal handler", function()
	local label = Instance.new("TextLabel")
	local changes = 0
	local s = Flux.scope(function()
		Flux.edit(label)({
			__EVENT = {
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

rtest("edit · __EVENT.__ATTR attribute-changed handler", function()
	local frame = Instance.new("Frame")
	frame:SetAttribute("Score", 1)
	local attrChanges = 0
	local s = Flux.scope(function()
		Flux.edit(frame)({
			__EVENT = {
				__ATTR = {
					Score = function()
						attrChanges += 1
					end,
				},
			},
		})
	end)
	frame:SetAttribute("Score", 2)
	task.wait() -- let the attribute-changed signal fire its connection
	expect(attrChanges == 1, "attribute-changed handler ran on SetAttribute")
	frame:Destroy()
	s:Destroy()
end)

rtest("new · _attr_Name prefix sets static, node, function, and Flux.model attributes", function()
	local level = Flux.signal(3)
	local bonus = Flux.signal(2)
	local twoWay = Flux.signal("initial")
	local frame
	local s = Flux.scope(function()
		frame = Flux.new("Frame")({
			_attr_Kind = "Boss",
			_attr_Level = level,
			_attr_Total = function()
				return level() + bonus()
			end,
			_attr_Status = Flux.model(twoWay),
		})
	end)
	flush()
	expect(frame:GetAttribute("Kind") == "Boss", "static _attr_Name assigned")
	expect(frame:GetAttribute("Level") == 3, "node _attr_Name initial value")
	expect(frame:GetAttribute("Total") == 5, "function _attr_Name initial value")
	expect(frame:GetAttribute("Status") == "initial", "Flux.model _attr_Name initial value")

	level:set(10)
	flush()
	expect(frame:GetAttribute("Level") == 10, "node _attr_Name updates")
	expect(frame:GetAttribute("Total") == 12, "function _attr_Name updates")

	frame:SetAttribute("Status", "enraged")
	task.wait()
	flush()
	expect(twoWay() == "enraged", "Flux.model _attr_Name writes back when attribute changes")
	s:Destroy()
end)

rtest("new & edit · _tag_Name prefix sets static, node, function, and Flux.model tags", function()
	local alive = Flux.signal(true)
	local hp = Flux.signal(100)
	local stunned = Flux.signal(false)
	local frame
	local s = Flux.scope(function()
		frame = Flux.new("Frame")({
			Parent = workspace,
			_tag_Enemy = true,
			_tag_Ignored = false,
			_tag_Alive = alive,
			_tag_LowHealth = function()
				return hp() < 25
			end,
			_tag_Stunned = Flux.model(stunned),
		})
	end)
	flush()
	expect(frame:HasTag("Enemy"), "static true _tag_Name applied")
	expect(not frame:HasTag("Ignored"), "static false _tag_Name not applied")
	expect(frame:HasTag("Alive"), "node _tag_Name applied when truthy")
	expect(not frame:HasTag("LowHealth"), "function _tag_Name false initially")
	expect(not frame:HasTag("Stunned"), "Flux.model _tag_Name false initially")

	alive:set(false)
	hp:set(10)
	flush()
	expect(not frame:HasTag("Alive"), "node _tag_Name removed when falsy")
	expect(frame:HasTag("LowHealth"), "function _tag_Name added when truthy")

	frame:AddTag("Stunned")
	task.wait()
	flush()
	expect(stunned() == true, "Flux.model _tag_Name writes true back when tag is added")

	stunned:set(false)
	flush()
	expect(not frame:HasTag("Stunned"), "Flux.model _tag_Name removes tag when node is set to false")

	-- Stripping a pre-existing unmanaged tag via Flux.edit with _tag_Name = false
	local existing = Instance.new("Frame")
	existing:AddTag("Legacy")
	existing:AddTag("Shared")
	local s2 = Flux.scope(function()
		Flux.edit(existing)({
			_tag_Legacy = false,
			__TAG = "Shared",
			{
				_tag_Shared = false, -- flattened child cannot strip a ref-counted tag
			},
		})
	end)
	expect(not existing:HasTag("Legacy"), "pre-existing unmanaged tag stripped when _tag_Name is false")
	expect(existing:HasTag("Shared"), "managed __TAG ref is preserved")
	existing:Destroy()
	s2:Destroy()
	s:Destroy()
end)

rtest(
	"edit · _PropName, __attr_Name, __tag_Name, and __EVENT.__TAG connect changed listeners and validate errors",
	function()
		local label = Instance.new("TextLabel")
		label.Parent = workspace
		label:SetAttribute("Score", 1)
		local seenText: string? = nil
		local seenScore: number? = nil
		local seenTag: boolean? = nil
		local seenEventTag: boolean? = nil
		local s = Flux.scope(function()
			Flux.edit(label)({
				_Text = function(newText)
					seenText = newText
				end,
				__attr_Score = function(newScore)
					seenScore = newScore
				end,
				__tag_Marked = function(hasTag)
					seenTag = hasTag
				end,
				__EVENT = {
					__TAG = {
						Pinned = function(hasTag)
							seenEventTag = hasTag
						end,
					},
				},
			})
		end)
		expect(
			seenText == nil and seenScore == nil and seenTag == nil and seenEventTag == nil,
			"changed listeners do not fire on initial connect"
		)

		label.Text = "hello"
		label:SetAttribute("Score", 42)
		label:AddTag("Marked")
		label:AddTag("Pinned")
		task.wait()
		expect(seenText == "hello", "_PropName listener received new property value")
		expect(seenScore == 42, "__attr_Name listener received new attribute value")
		expect(seenTag == true, "__tag_Name listener received true when tag added")
		expect(seenEventTag == true, "__EVENT.__TAG listener received true when tag added")

		label:RemoveTag("Marked")
		label:RemoveTag("Pinned")
		task.wait()
		expect(seenTag == false, "__tag_Name listener received false when tag removed")
		expect(seenEventTag == false, "__EVENT.__TAG listener received false when tag removed")

		local bindable = Instance.new("BindableEvent")
		sert.fails(function()
			Flux.edit(bindable)({
				_Event = function() end,
			})
		end, "connect `Event` as a top-level key")
		bindable:Destroy()

		sert.fails(function()
			Flux.edit(label)({ _attr_ = 1 })
		end, 'after "_attr_" cannot be empty')
		sert.fails(function()
			Flux.edit(label)({ _tag_ = true })
		end, 'after "_tag_" cannot be empty')
		sert.fails(function()
			Flux.edit(label)({ _ = function() end })
		end, 'after "_" cannot be empty')
		sert.fails(function()
			Flux.edit(label)({ __attr_ = function() end })
		end, 'after "__attr_" cannot be empty')
		sert.fails(function()
			Flux.edit(label)({ __tag_ = function() end })
		end, 'after "__tag_" cannot be empty')
		sert.fails(function()
			Flux.edit(label)({ _Text = 123 :: any })
		end, '"_Text" expects a function')
		sert.fails(function()
			Flux.edit(label)({ __attr_Score = Flux.signal(0) :: any })
		end, '"__attr_Score" is a node')
		sert.fails(function()
			Flux.edit(label)({ __tag_Marked = Flux.signal(false) :: any })
		end, '"__tag_Marked" is a node')

		label:Destroy()
		s:Destroy()
	end
)

rtest("new · flattened tables deduplicate _attr_Name with __ATTR and _tag_Name", function()
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({
			_attr_A = "root-prefix",
			__ATTR = { B = "root-table" },
			_tag_Boss = true,
			{
				_attr_A = "child-prefix",
				_attr_B = "child-prefix-b",
				__ATTR = { A = "child-table" },
				_tag_Boss = false,
				_attr_C = "child-only",
			},
		})
	end)
	expect(f:GetAttribute("A") == "root-prefix", "root _attr_A wins over flattened _attr_A and __ATTR.A")
	expect(f:GetAttribute("B") == "root-table", "root __ATTR.B wins over flattened _attr_B")
	expect(f:GetAttribute("C") == "child-only", "unseen flattened _attr_C is applied")
	expect(f:HasTag("Boss"), "root _tag_Boss wins over flattened _tag_Boss")
	s:Destroy()
end)

test("split · non-table props returns empty Own and Rest tables without erroring", function()
	local own, rest = Flux.split(nil :: any, { "Label" })
	expect(next(own) == nil and next(rest) == nil, "split(nil) returns two empty tables")
end)

rtest("edit · reactive Parent getter function and flattened _Prop/__attr_/__tag_ deduplication", function()
	local p1 = Instance.new("Folder")
	local p2 = Instance.new("Folder")
	p1.Parent = workspace
	p2.Parent = workspace
	local useSecond = Flux.signal(false)
	local rootTextSeen = 0
	local childTextSeen = 0
	local rootAttrSeen = 0
	local childAttrSeen = 0
	local rootTagSeen = 0
	local childTagSeen = 0

	local label
	local s = Flux.scope(function()
		label = Flux.new("TextLabel")({
			Parent = function()
				return if useSecond() then p2 else p1
			end,
			_Text = function()
				rootTextSeen += 1
			end,
			__attr_Count = function()
				rootAttrSeen += 1
			end,
			__tag_Tracked = function()
				rootTagSeen += 1
			end,
			{
				_Text = function()
					childTextSeen += 1
				end,
				__attr_Count = function()
					childAttrSeen += 1
				end,
				__tag_Tracked = function()
					childTagSeen += 1
				end,
			},
		})
	end)
	Flux.flush()
	expect(label.Parent == p1, "initial Parent getter mounted under p1")
	useSecond:set(true)
	Flux.flush()
	expect(label.Parent == p2, "Parent getter updated parent to p2")

	label.Text = "changed"
	label:SetAttribute("Count", 5)
	label:AddTag("Tracked")
	task.wait()
	expect(rootTextSeen == 1 and childTextSeen == 0, "root _Text wins over flattened _Text")
	expect(rootAttrSeen == 1 and childAttrSeen == 0, "root __attr_Count wins over flattened __attr_Count")
	expect(rootTagSeen == 1 and childTagSeen == 0, "root __tag_Tracked wins over flattened __tag_Tracked")

	s:Destroy()
	p1:Destroy()
	p2:Destroy()
end)

return {}
