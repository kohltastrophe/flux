--!nonstrict
local env = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any

local Flux = env.Flux
local sert = env.sert
local test = sert.test
local expect = sert
local flush = Flux.flush
local settle = env.settle
local Instance = env.Instance
local workspace = env.workspace
local Find = Flux.Find
local expectError = sert.fails

local function tagsOf(instance: Instance): string
	local tags = instance:GetTags()
	table.sort(tags)
	return table.concat(tags, ",")
end

test("new · rejects a non-string className", function()
	expectError(function()
		Flux.new(123 :: any)
	end, "String expected, got number")
end)

test("edit · __TAG takes a string, an array, a node, a function or a mixed array; reactive tags swap", function()
	local status, alive = Flux.signal("Idle"), Flux.signal(true)
	local cases = {
		{ "Enemy", "Enemy", "Enemy" },
		{ { "Enemy", "Boss" }, "Boss,Enemy", "Boss,Enemy" },
		{ status, "Idle", "Running" },
		{
			function()
				return if alive() then "Alive" else "Dead"
			end,
			"Alive",
			"Dead",
		},
		{ { "Enemy", status }, "Enemy,Idle", "Enemy,Running" },
	}
	local frames = {}
	local s = Flux.scope(function()
		for i, case in cases do
			frames[i] = Instance.new("Frame")
			Flux.edit(frames[i])({ __TAG = case[1] })
		end
	end)
	flush()
	for i, case in cases do
		expect.eq(tagsOf(frames[i]), case[2], `case {i} applied`)
	end
	status:set("Running")
	alive:set(false)
	flush()
	for i, case in cases do
		expect.eq(tagsOf(frames[i]), case[3], `case {i} after its nodes changed`)
	end
	s:Destroy()
	status:set("Done")
	flush()
	expect.eq(tagsOf(frames[3]), "Running", "the scope's Destroy ends the binding, leaving the last tag in place")
	for _, frame in frames do
		frame:Destroy()
	end
end)

test("edit · a __TAG node diffs its table or string value, keeping tags a static sibling declares", function()
	local frame = Instance.new("Frame")
	local tags = Flux.signal({ "A", "B" } :: any)
	local s = Flux.scope(function()
		Flux.edit(frame)({ __TAG = { "S", tags } })
	end)
	flush()
	expect.eq(tagsOf(frame), "A,B,S")
	for _, step in
		{ { { "B", "C" }, "B,C,S" }, { "B", "B,S" }, { { "B", "D" }, "B,D,S" }, { "S", "S" }, { "E", "E,S" } }
	do
		tags:set(step[1])
		flush()
		expect.eq(
			tagsOf(frame),
			step[2],
			`after {if type(step[1]) == "table" then table.concat(step[1], "+") else step[1]}`
		)
	end
	s:Destroy()
	frame:Destroy()
end)

test("edit · a __TAG node bound without an owner stops when the instance is destroyed", function()
	local frame = Instance.new("Frame")
	local status = Flux.signal("Idle")
	Flux.edit(frame)({ __TAG = status })
	status:set("Running")
	flush()
	expect.eq(tagsOf(frame), "Running", "the node's tag swaps on the flush")
	frame:Destroy()
	settle()
	status:set("Done")
	flush()
	expect.eq(tagsOf(frame), "Running", "the binding ends with the instance")
end)

test("edit · __EVENT rejects a node, a non-function value or an event key", function()
	local label = Instance.new("TextButton")
	local mirror = Flux.signal(nil)
	expectError(function()
		Flux.edit(label)({ __EVENT = { Text = mirror } })
	end, "use Flux.model(node) for two-way binding or Flux.property(instance, prop) to follow a property")
	expectError(function()
		Flux.edit(label)({ __EVENT = { __ATTR = { Level = mirror } } })
	end, "__EVENT.__ATTR.Level is a node")
	expectError(function()
		Flux.edit(label)({ __EVENT = { __TAG = { Boss = mirror } } })
	end, "__EVENT.__TAG.Boss is a node")
	expectError(function()
		Flux.edit(label)({ __EVENT = { Text = "nope" } })
	end, "expects a function")
	expectError(function()
		Flux.edit(label)({ __EVENT = { Activated = function() end } })
	end, "connect `Activated` as a top-level key")
	label:Destroy()
end)

test("edit · __EVENT listeners get the new value and end with the scope; a frozen map is taken as is", function()
	local label = Instance.new("TextLabel")
	label:SetAttribute("Score", 1)
	local texts, scores = {}, {}
	local s = Flux.scope(function()
		Flux.edit(label)({
			__EVENT = table.freeze({
				Text = function(text)
					table.insert(texts, text)
				end,
				__ATTR = table.freeze({
					Score = function(score)
						table.insert(scores, score)
					end,
				}),
			}),
		})
	end)
	settle()
	expect(#texts == 0 and #scores == 0, "nothing fires on connect")
	label.Text = "b"
	label:SetAttribute("Score", 2)
	settle()
	expect(texts[1] == "b" and scores[1] == 2, "each listener is called with the new value")
	s:Destroy()
	label.Text = "c"
	label:SetAttribute("Score", 3)
	settle()
	expect(#texts == 1 and #scores == 1, "both connections end with the scope")
	label:Destroy()
end)

test("edit · handlers run with the contexts provided where they were declared", function()
	local ctx = Flux.context("default")
	local label = Instance.new("TextLabel")
	local seen = {}
	local s = Flux.scope(function()
		ctx:provide("declared", function()
			Flux.edit(label)({
				__EVENT = {
					Text = function()
						table.insert(seen, `listener {ctx:get()}`)
					end,
				},
				function()
					table.insert(seen, `action {ctx:get()}`)
				end,
			})
		end)
	end)
	settle()
	label.Text = "b"
	settle()
	expect(table.find(seen, "action declared") ~= nil, "an init action reads the declared value")
	expect(table.find(seen, "listener declared") ~= nil, "a change listener reads the declared value")
	expect(ctx:get() == "default", "and the caller's value is restored")
	s:Destroy()
	label:Destroy()
end)

test("edit · handlers declared outside any provide read what their caller provides", function()
	local listeners = {}
	local stub = { Text = "a" }
	function stub:GetPropertyChangedSignal()
		return {
			Connect = function(_, fn)
				table.insert(listeners, fn)
				return { Disconnect = function() end }
			end,
		}
	end
	stub.Destroying = {
		Once = function()
			return { Disconnect = function() end }
		end,
	}
	local ctx = Flux.context("default")
	local seen
	local s = Flux.scope(function()
		Flux.edit(stub)({
			__EVENT = {
				Text = function()
					seen = ctx:get()
				end,
			},
		})
	end)
	ctx:provide("caller", function()
		listeners[1]()
	end)
	expect(seen == "caller", "connected as is: nothing to restore")
	s:Destroy()
end)

test("edit · init actions run via task.defer, after the instance is parented", function()
	local ran, parentSeen = 0, nil
	local holder = Instance.new("Folder")
	local frame = Flux.new("Frame")({
		Parent = holder,
		function(inst)
			ran += 1
			parentSeen = inst.Parent
		end,
	})
	expect(ran == 0, "an init action waits for the deferred queue")
	settle()
	expect(ran == 1, "init action ran")
	expect(parentSeen == holder, "and saw the Parent the table set last")
	frame:Destroy()
	holder:Destroy()
end)

test("new · an event handler runs with the contexts provided where it was declared", function()
	local ctx = Flux.context("default")
	local seen = {}
	local event = ctx:provide("declared", function()
		return Flux.new("BindableEvent")({
			Event = function(tag)
				table.insert(seen, `{tag} {ctx:get()}`)
			end,
		})
	end)
	ctx:provide("caller", function()
		event:Fire("bound")
	end)
	settle()
	expect(table.find(seen, "bound declared") ~= nil, "a handler declared under provide reads that value")
	event:Destroy()
end)

test("new · a node or a function value binds a property, and edit binds one on an existing instance", function()
	local text, count = Flux("hello"), Flux(1)
	local existing = Instance.new("TextLabel")
	local label, counter
	local s = Flux.scope(function()
		label = Flux.new("TextLabel")({ Text = text })
		counter = Flux.new("TextLabel")({
			Text = function()
				return "Count: " .. count
			end,
		})
		Flux.edit(existing)({ Name = "Edited", Text = text })
	end)
	flush()
	expect(label.Text == "hello" and counter.Text == "Count: 1", "bound to the initial values")
	expect(existing.Name == "Edited" and existing.Text == "hello", "edit applies static props and bindings")
	text("world")
	count(2)
	flush()
	expect(label.Text == "world" and counter.Text == "Count: 2", "properties track their node and function")
	expect(existing.Text == "world", "and so does the existing instance's")
	s:Destroy()
	existing:Destroy()
end)

test("new · children at numeric indices and in plain arrays are parented and numbered", function()
	local a, b, c, parent
	local s = Flux.scope(function()
		a = Flux.new("TextLabel")({ Name = "A" })
		b = Flux.new("TextLabel")({ Name = "B" })
		c = Flux.new("TextLabel")({ Name = "C" })
		parent = Flux.new("Frame")({
			Name = "Parent",
			a,
			{ b, c },
		})
	end)
	expect(a.Parent == parent and b.Parent == parent and c.Parent == parent, "every child parented")
	expect(a.LayoutOrder == 1 and b.LayoutOrder == 2 and c.LayoutOrder == 3, "children get incrementing LayoutOrder")
	s:Destroy()
end)

test("new · an explicit LayoutOrder 0 is kept, siblings still auto-number", function()
	local first, second, third
	local s = Flux.scope(function()
		first = Flux.new("TextLabel")({ Name = "First", LayoutOrder = 0 })
		second = Flux.new("TextLabel")({ Name = "Second" })
		third = Flux.new("TextLabel")({ Name = "Third", LayoutOrder = 1 })
		Flux.new("Frame")({ first, second, third })
	end)
	expect(first.LayoutOrder == 0, "an explicit zero stays zero instead of taking its index")
	expect(second.LayoutOrder == 1, "the next child without an order numbers from 1")
	expect(third.LayoutOrder == 1, "an explicit order is never touched")
	s:Destroy()
end)

test("new · array flattening binds a node child (Flux.show)", function()
	local cond = Flux.signal(true)
	local static, shown, parent
	local s = Flux.scope(function()
		shown = Flux.show(cond, function()
			return Flux.new("Frame")({ Name = "Shown" })
		end)
		static = Flux.new("TextLabel")({ Name = "Static" })
		parent = Flux.new("Frame")({
			Name = "Parent",
			{ static, shown },
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

test("new · Flux.model two-way binds a property", function()
	local text = Flux.signal("hello")
	local box
	local s = Flux.scope(function()
		box = Flux.new("TextBox")({
			Text = Flux.model(text),
		})
	end)
	flush()
	expect(box.Text == "hello", "instance is driven from the node (authored value wins)")

	text:set("world")
	flush()
	expect(box.Text == "world", "writing the node updates the instance")

	box.Text = "typed"
	settle()
	flush()
	expect(text() == "typed", "changing the instance writes back to the node")
	s:Destroy()
end)

test("new · Flux.model two-way binds an attribute via __ATTR", function()
	local level = Flux.signal(1)
	local frame
	local s = Flux.scope(function()
		frame = Flux.new("Frame")({
			__ATTR = { Level = Flux.model(level) },
		})
	end)
	flush()
	expect(frame:GetAttribute("Level") == 1, "attribute driven from the node")

	level:set(5)
	flush()
	expect(frame:GetAttribute("Level") == 5, "writing the node updates the attribute")

	frame:SetAttribute("Level", 9)
	settle()
	flush()
	expect(level() == 9, "changing the attribute writes back to the node")
	s:Destroy()
end)

test("new · __REF (callback and node forms)", function()
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

test("new · __ATTR sets static attributes", function()
	local f = Flux.new("Frame")({ __ATTR = { Level = 7, Tag = "boss" } })
	expect(f:GetAttribute("Level") == 7, "static numeric attribute set")
	expect(f:GetAttribute("Tag") == "boss", "static string attribute set")
	f:Destroy()
end)

test("new · directive keys in nested tables at numeric indices", function()
	local lvl = Flux.signal(1)
	local status = Flux.signal("Idle")
	local cleaned = 0
	local captured
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({
			{ __ATTR = { Level = lvl } },
			{ __ATTR = { Kind = "NPC" } },
			{ __TAG = { "Enemy", status } },
			{
				__REF = function(inst)
					captured = inst
				end,
			},
			{
				__CLEAN = {
					function()
						cleaned += 1
					end,
				},
			},
		})
	end)
	flush()
	expect(f:GetAttribute("Level") == 1, "reactive nested attr applied")
	expect(f:GetAttribute("Kind") == "NPC", "second nested attr applied")
	expect(f:HasTag("Enemy") and f:HasTag("Idle"), "tag array applied static and node values")
	expect(captured == f, "ref callback received the instance")
	lvl:set(2)
	status:set("Running")
	flush()
	expect(f:GetAttribute("Level") == 2, "nested attr tracks its node")
	expect(f:HasTag("Running") and not f:HasTag("Idle"), "node inside the tag array swaps")
	s:Destroy()
	expect(cleaned == 1, "nested __CLEAN ran on scope destroy")
end)

test("edit · nested event and tag directives accumulate", function()
	local label = Instance.new("TextLabel")
	label.Text = "start"
	local a, b = 0, 0
	local mirror
	local function follow(text)
		mirror = text
	end
	local s = Flux.scope(function()
		Flux.edit(label)({
			{ __TAG = "Enemy" },
			{ __TAG = "Boss" },
			{
				__EVENT = {
					Text = function()
						a += 1
					end,
				},
			},
			{
				__EVENT = {
					Text = function()
						b += 1
					end,
				},
			},
			{ __EVENT = { Text = follow } },
		})
	end)
	expect(label:HasTag("Enemy") and label:HasTag("Boss"), "each nested tag applied")
	label.Text = "next"
	settle()
	expect(a == 1 and b == 1, "both nested event handlers connected")
	expect(mirror == "next", "and a third, called with the new value")
	label:Destroy()
	s:Destroy()
end)

test("new · duplicate attr names dedupe with the root table winning", function()
	local f
	local s = Flux.scope(function()
		f = Flux.new("Frame")({
			__ATTR = { Kind = "root" },
			{ __ATTR = { Kind = "nested", Other = "kept" } },
		})
	end)
	expect(f:GetAttribute("Kind") == "root", "root __ATTR wins over a nested duplicate")
	expect(f:GetAttribute("Other") == "kept", "non-duplicate nested attr still applied")
	s:Destroy()
end)

test("new · _attr_Name prefix sets static, node, function, and Flux.model attributes", function()
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
	settle()
	expect(twoWay() == "enraged", "Flux.model _attr_Name writes back when attribute changes")
	s:Destroy()
end)

test("new & edit · _tag_Name prefix sets static, node, function, and Flux.model tags", function()
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
	settle()
	expect(stunned() == true, "Flux.model _tag_Name writes true back when tag is added")

	stunned:set(false)
	flush()
	expect(not frame:HasTag("Stunned"), "Flux.model _tag_Name removes tag when node is set to false")

	local existing = Instance.new("Frame")
	existing:AddTag("Legacy")
	existing:AddTag("Shared")
	local s2 = Flux.scope(function()
		Flux.edit(existing)({
			_tag_Legacy = false,
			__TAG = "Shared",
			{
				_tag_Shared = false,
			},
		})
	end)
	expect(not existing:HasTag("Legacy"), "pre-existing unmanaged tag stripped when _tag_Name is false")
	expect(existing:HasTag("Shared"), "managed __TAG ref is preserved")
	existing:Destroy()
	s2:Destroy()
	s:Destroy()
end)

test("edit · _tag_Name replaces prior static, reactive, and Flux.model claims on the same tag", function()
	local sig1 = Flux.signal(true)
	local sig2 = Flux.signal(false)
	local model1 = Flux.signal(true)
	local model2 = Flux.signal(false)
	local getterRuns = 0
	local getterSig = Flux.signal(true)
	local btn
	local s = Flux.scope(function()
		btn = Flux.new("TextButton")({
			Parent = workspace,
			__TAG = "Kept",
			_tag_Kept = true,
			_tag_Static = true,
			_tag_Reactive = sig1,
			_tag_Getter = function()
				getterRuns += 1
				return getterSig()
			end,
			_tag_TwoWay = Flux.model(model1),
		})
	end)
	flush()
	expect(
		btn:HasTag("Kept")
			and btn:HasTag("Static")
			and btn:HasTag("Reactive")
			and btn:HasTag("Getter")
			and btn:HasTag("TwoWay"),
		"all initial _tag_Name bindings applied"
	)

	local s2 = Flux.scope(function()
		Flux.edit(btn)({
			_tag_Kept = false,
			_tag_Static = false,
			_tag_Reactive = sig2,
			_tag_Getter = false,
			_tag_TwoWay = Flux.model(model2),
		})
	end)
	flush()
	expect(btn:HasTag("Kept"), "__TAG ref stays when _tag_Kept claim is released")
	expect(not btn:HasTag("Static"), "static _tag_Name = false overrides prior _tag_Name = true")
	expect(not btn:HasTag("Reactive"), "new reactive _tag_Name overrides prior reactive _tag_Name")
	expect(not btn:HasTag("Getter"), "static false overrides prior getter _tag_Name")
	expect(not btn:HasTag("TwoWay") and model2() == false, "new Flux.model overrides prior Flux.model _tag_Name")

	local beforeRuns = getterRuns
	sig1:set(false)
	flush()
	sig1:set(true)
	getterSig:set(false)
	flush()
	expect(not btn:HasTag("Reactive"), "old reactive _tag_Name no longer drives the instance")
	expect(getterRuns == beforeRuns, "old getter _tag_Name node was disposed")

	sig2:set(true)
	flush()
	expect(btn:HasTag("Reactive"), "new reactive _tag_Name drives the instance")

	model1:set(false)
	flush()
	btn:AddTag("TwoWay")
	settle()
	expect(model2() == true and model1() == false, "only the new Flux.model receives tag writebacks")

	s2:Destroy()
	s:Destroy()
end)

test(
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
		settle()
		expect(seenText == "hello", "_PropName listener received new property value")
		expect(seenScore == 42, "__attr_Name listener received new attribute value")
		expect(seenTag == true, "__tag_Name listener received true when tag added")
		expect(seenEventTag == true, "__EVENT.__TAG listener received true when tag added")

		label:RemoveTag("Marked")
		label:RemoveTag("Pinned")
		settle()
		expect(seenTag == false, "__tag_Name listener received false when tag removed")
		expect(seenEventTag == false, "__EVENT.__TAG listener received false when tag removed")

		local bindable = Instance.new("BindableEvent")
		expectError(function()
			Flux.edit(bindable)({
				_Event = function() end,
			})
		end, "connect `Event` as a top-level key")
		bindable:Destroy()

		expectError(function()
			Flux.edit(label)({ _attr_ = 1 })
		end, 'after "_attr_" cannot be empty')
		expectError(function()
			Flux.edit(label)({ _tag_ = true })
		end, 'after "_tag_" cannot be empty')
		expectError(function()
			Flux.edit(label)({ _ = function() end })
		end, 'after "_" cannot be empty')
		expectError(function()
			Flux.edit(label)({ __attr_ = function() end })
		end, 'after "__attr_" cannot be empty')
		expectError(function()
			Flux.edit(label)({ __tag_ = function() end })
		end, 'after "__tag_" cannot be empty')
		expectError(function()
			Flux.edit(label)({ _Text = 123 :: any })
		end, '"_Text" expects a function')
		expectError(function()
			Flux.edit(label)({ __attr_Score = Flux.signal(0) :: any })
		end, '"__attr_Score" is a node')
		expectError(function()
			Flux.edit(label)({ __tag_Marked = Flux.signal(false) :: any })
		end, '"__tag_Marked" is a node')

		label:Destroy()
		s:Destroy()
	end
)

test("new · flattened tables deduplicate _attr_Name with __ATTR, _tag_Name, and _Prop/__attr_/__tag_", function()
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
			_attr_A = "root-prefix",
			__ATTR = { B = "root-table" },
			_tag_Boss = true,
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
				_attr_A = "child-prefix",
				_attr_B = "child-prefix-b",
				__ATTR = { A = "child-table" },
				_tag_Boss = false,
				_attr_C = "child-only",
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
	flush()
	expect(label:GetAttribute("A") == "root-prefix", "root _attr_A wins over flattened _attr_A and __ATTR.A")
	expect(label:GetAttribute("B") == "root-table", "root __ATTR.B wins over flattened _attr_B")
	expect(label:GetAttribute("C") == "child-only", "unseen flattened _attr_C is applied")
	expect(label:HasTag("Boss"), "root _tag_Boss wins over flattened _tag_Boss")
	expect(label.Parent == p1, "initial Parent getter mounted under p1")
	useSecond:set(true)
	flush()
	expect(label.Parent == p2, "Parent getter updated parent to p2")

	label.Text = "changed"
	label:SetAttribute("Count", 5)
	label:AddTag("Tracked")
	settle()
	expect(rootTextSeen == 1 and childTextSeen == 0, "root _Text wins over flattened _Text")
	expect(rootAttrSeen == 1 and childAttrSeen == 0, "root __attr_Count wins over flattened __attr_Count")
	expect(rootTagSeen == 1 and childTagSeen == 0, "root __tag_Tracked wins over flattened __tag_Tracked")

	s:Destroy()
	p1:Destroy()
	p2:Destroy()
end)

test("new · defaults applied and toggleable via Flux.Flags; AutoButtonColor is off either way", function()
	local btn
	local s = Flux.scope(function()
		btn = Flux.new("ImageButton")({})
	end)
	expect(btn.BorderSizePixel == 0, "class defaults applied when Flags.defaults is true")
	expect(btn.AutoButtonColor == false, "AutoButtonColor off")
	s:Destroy()
	Flux.Flags.defaults = false
	local btn2, btn3
	local s2 = Flux.scope(function()
		btn2 = Flux.new("ImageButton")({})
		btn3 = Flux.new("TextButton")({ AutoButtonColor = true })
	end)
	local borderWithoutDefaults = btn2.BorderSizePixel
	local autoColorWithoutDefaults = btn2.AutoButtonColor
	local autoColorOverridden = btn3.AutoButtonColor
	s2:Destroy()
	expect(borderWithoutDefaults == 1, "no class defaults applied when Flags.defaults is false")
	expect(autoColorWithoutDefaults == false, "AutoButtonColor stays off with the defaults disabled")
	expect(autoColorOverridden == true, "your own properties still win")
end)

test("edit · __CLEAN runs once on an immediate destroy, owned or not; a node Parent keeps following", function()
	local screen = Instance.new("ScreenGui")
	local parentFrame = Instance.new("Frame")
	parentFrame.Parent = screen
	local parentNode = Flux.signal(parentFrame)
	for _, owned in { false, true } do
		local cleaned = 0
		local child = Instance.new("Frame")
		local function build()
			Flux.edit(child)({
				Parent = parentNode,
				__CLEAN = {
					function()
						cleaned += 1
					end,
				},
			})
		end
		local s = if owned then Flux.scope(build) else build()
		expect(child.Parent == parentFrame, `node-driven Parent applied (owned: {owned})`)
		child:Destroy()
		settle()
		expect(cleaned == 1, `__CLEAN flushed on immediate destroy (owned: {owned})`)
		if s then
			s:Destroy()
			expect(cleaned == 1, "scope destroy does not re-run the cleanup")
		end
	end

	local child2 = Instance.new("Frame")
	Flux.edit(child2)({ Parent = parentNode })
	local otherParent = Instance.new("Frame")
	otherParent.Parent = screen
	parentNode:set(otherParent)
	flush()
	expect(child2.Parent == otherParent, "node Parent retargets")
	screen:Destroy()
end)

local TAG_POOL = { { "A" }, { "B" }, { "A", "B" }, { "B", "C" }, {} }

sert.model("edit · reactive properties, attributes, tags and two-way models stay synchronized", {
	init = function()
		local textSig = Flux.signal("t0")
		local attrSig = Flux.signal(1)
		local tagBool = Flux.signal(false)
		local tagSet = Flux.signal({ "A" } :: any)

		local box
		local scope = Flux.scope(function()
			box = Flux.new("TextBox")({
				Text = Flux.model(textSig),
				_attr_Score = Flux.model(attrSig),
				_tag_Flag = tagBool,
				__TAG = { "Static", tagSet },
			})
		end)
		flush()

		local state = {
			expectedText = "t0",
			expectedAttr = 1,
			expectedFlag = false,
			expectedSet = { "A" } :: { string },
		}
		local sut = {
			scope = scope,
			box = box,
			textSig = textSig,
			attrSig = attrSig,
			tagBool = tagBool,
			tagSet = tagSet,
		}
		return state, sut
	end,
	teardown = function(sut)
		sut.scope:Destroy()
		Flux.flush()
	end,
	actions = {
		nodeText = {
			weight = 2,
			gen = function(g)
				return "n" .. tostring(g:int(1, 9))
			end,
			run = function(sut, text)
				sut.textSig:set(text)
				flush()
			end,
			next = function(state, text)
				state.expectedText = text
			end,
		},
		instText = {
			weight = 2,
			gen = function(g)
				return "i" .. tostring(g:int(1, 9))
			end,
			run = function(sut, text)
				sut.box.Text = text
				settle()
				flush()
			end,
			next = function(state, text)
				state.expectedText = text
			end,
		},
		nodeAttr = {
			weight = 2,
			gen = function(g)
				return g:int(1, 20)
			end,
			run = function(sut, score)
				sut.attrSig:set(score)
				flush()
			end,
			next = function(state, score)
				state.expectedAttr = score
			end,
		},
		instAttr = {
			weight = 2,
			gen = function(g)
				return g:int(1, 20)
			end,
			run = function(sut, score)
				sut.box:SetAttribute("Score", score)
				settle()
				flush()
			end,
			next = function(state, score)
				state.expectedAttr = score
			end,
		},
		flag = {
			weight = 2,
			gen = function(g)
				return g:bool()
			end,
			run = function(sut, flag)
				sut.tagBool:set(flag)
				flush()
			end,
			next = function(state, flag)
				state.expectedFlag = flag
			end,
		},
		tags = {
			weight = 2,
			gen = function(g)
				return TAG_POOL[g:int(1, #TAG_POOL)]
			end,
			run = function(sut, set)
				sut.tagSet:set(set)
				flush()
			end,
			next = function(state, set)
				state.expectedSet = set
			end,
		},
	},
	never = {
		staticTagLost = function(_state, sut)
			return not sut.box:HasTag("Static")
		end,
	},
	invariants = {
		textSynchronized = function(state, sut)
			sert.eq(sut.box.Text, state.expectedText, "box.Text")
			sert.eq(sut.textSig:peek(), state.expectedText, "textSig")
		end,
		attrSynchronized = function(state, sut)
			sert.eq(sut.box:GetAttribute("Score"), state.expectedAttr, "Score attr")
			sert.eq(sut.attrSig:peek(), state.expectedAttr, "attrSig")
		end,
		tagsSynchronized = function(state, sut)
			sert.eq(sut.box:HasTag("Flag"), state.expectedFlag, "Flag tag")
			for _, t in { "A", "B", "C" } do
				local inSet = table.find(state.expectedSet, t) ~= nil
				sert.eq(sut.box:HasTag(t), inSet, `tag {t}`)
			end
		end,
	},
}, {
	runs = 120,
	length = 14,
	exhaustive = { size = 2 },
})

test("edit · a later edit replaces a property's binding instead of stacking it", function()
	local first = Flux.signal(1)
	local second = Flux.signal(0.5)
	local frame
	local s = Flux.scope(function()
		frame = Flux.new("Frame")({ BackgroundTransparency = first })
	end)
	flush()
	expect.near(frame.BackgroundTransparency, 1, nil, "first binding applied")

	-- static override releases the first binding
	Flux.edit(frame)({ BackgroundTransparency = 0 })
	first:set(0.75)
	flush()
	expect.near(frame.BackgroundTransparency, 0, nil, "static override sticks after the old source changes")

	-- node override replaces, and the older source stays released
	Flux.edit(frame)({ BackgroundTransparency = second })
	flush()
	expect.near(frame.BackgroundTransparency, 0.5, nil, "node override applied")
	first:set(0.25)
	second:set(0.4)
	flush()
	expect.near(frame.BackgroundTransparency, 0.4, nil, "only the newest binding drives the property")

	-- a getter override replaces the node and disposes on the next override
	local getterRuns = 0
	Flux.edit(frame)({
		BackgroundTransparency = function()
			getterRuns += 1
			return second() / 2
		end,
	})
	flush()
	expect.near(frame.BackgroundTransparency, 0.2, nil, "getter override applied")
	Flux.edit(frame)({ BackgroundTransparency = 0.9 })
	local runsAtOverride = getterRuns
	second:set(0.1)
	flush()
	expect.near(frame.BackgroundTransparency, 0.9, nil, "static override replaced the getter")
	expect.eq(getterRuns, runsAtOverride, "the replaced getter node was disposed, not recomputed")

	s:Destroy()
end)

test("edit · attribute and Parent overrides replace their bindings", function()
	local score = Flux.signal(1)
	local p1 = Instance.new("Folder")
	local p2 = Instance.new("Folder")
	local parent = Flux.signal(p1)
	local frame
	local s = Flux.scope(function()
		frame = Flux.new("Frame")({ _attr_Score = score, Parent = parent })
	end)
	flush()
	expect(frame:GetAttribute("Score") == 1 and frame.Parent == p1, "initial attribute and Parent bound")

	Flux.edit(frame)({ _attr_Score = 7, Parent = p2 })
	score:set(2)
	parent:set(p1)
	flush()
	expect.eq(frame:GetAttribute("Score"), 7, "static attribute override sticks")
	expect(frame.Parent == p2, "static Parent override sticks")

	s:Destroy()
	p1:Destroy()
	p2:Destroy()
end)

test("edit · a replaced binding's original cleanup stays safe to run", function()
	local first = Flux.signal("a")
	local second = Flux.signal("b")
	local label = Instance.new("TextLabel")
	local s1 = Flux.scope(function()
		Flux.edit(label)({ Text = first })
	end)
	local s2 = Flux.scope(function()
		Flux.edit(label)({ Text = second })
	end)
	flush()
	expect.eq(label.Text, "b", "override applied")
	-- disposing the original edit must not release the newer binding
	s1:Destroy()
	second:set("c")
	flush()
	expect.eq(label.Text, "c", "newer binding survives the older edit's cleanup")
	s2:Destroy()
	second:set("d")
	flush()
	expect.eq(label.Text, "c", "binding released with its own edit")
	label:Destroy()
end)

-- Find ----------------------------------------------------------------------------------------------------------------

local function make(class: string, name: string, parent: Instance?): Instance
	local inst = Instance.new(class)
	inst.Name = name
	inst.Parent = parent
	return inst
end

test("find.parent · a selector miss warns without erroring", function()
	local orphan = Instance.new("Folder")
	local warned = env.warnings(function()
		Flux.edit(orphan)({ Find.Parent()({ Name = "target" }) })
	end)
	expect.eq(warned[1], "[Flux] Instance expected for a Find selector, got nil", "a miss warns")
	expect.eq(orphan.Name, "Folder", "and applies nothing")
	orphan:Destroy()
end)

local walkPath = Find.Path("")({})[2]

test("find.path · walks dot-separated child names", function()
	local root = make("Folder", "Root")
	local a = make("Folder", "A", root)
	local b = make("Folder", "B", a)
	make("Folder", "Decoy", root)

	expect(walkPath(root, "A.B") == b, "descends two named segments")
	expect(walkPath(root, "A") == a, "resolves a single segment")
	expect(walkPath(root, "A.Missing") == nil, "returns nil when a segment misses")
	expect(walkPath(root, "Missing.B") == nil, "returns nil when the first segment misses")
	root:Destroy()
end)

test("find.path · Parent and ^ segments climb, empty segments are skipped", function()
	local root = make("Folder", "Root")
	local a = make("Folder", "A", root)
	local b = make("Folder", "B", a)

	expect(walkPath(b, "Parent") == a, "'Parent' climbs one level")
	expect(walkPath(b, "^.^") == root, "'^' chains climb multiple levels")
	expect(walkPath(b, "^.B") == b, "climb then descend round-trips")
	expect(walkPath(root, "^") == nil, "climbing past a nil Parent returns nil")
	expect(walkPath(root, "") == root, "empty path resolves to the instance itself")
	expect(walkPath(root, ".A..B.") == b, "stray dots are skipped, not treated as misses")
	root:Destroy()
end)

test("find · each selector resolves its target through Flux.edit and applies props to it alone", function()
	local screen = make("ScreenGui", "Grand")
	local mid = make("Folder", "Mid", screen)
	local a = make("Frame", "A", mid)
	local b = make("Frame", "B", a)
	local label = make("TextLabel", "Label", mid)
	local button = make("TextButton", "Button", mid)
	local boxed1, boxed2 = make("Frame", "Boxed", mid), make("Frame", "Boxed", mid)
	local unboxed = make("Frame", "Unboxed", mid)
	local guis = { a, b, label, button, boxed1, boxed2, unboxed } :: { any }

	local cases = {
		{ "Child", Find.Child("A"), mid, { a } },
		{ "ChildClass", Find.ChildClass("TextLabel"), mid, { label } },
		{ "ChildIsA", Find.ChildIsA("GuiButton"), mid, { button } },
		{ "Descendant", Find.Descendant("B"), screen, { b } },
		{ "Path", Find.Path("A.B"), mid, { b } },
		{ "Path climbing", Find.Path("^.^.Label"), b, { label } },
		{ "QueryFirst", Find.QueryFirst("#Boxed"), mid, { boxed1 } },
		{ "Query", Find.Query("#Boxed"), mid, { boxed1, boxed2 } },
	}
	for i, case in cases do
		local name, selector, from, targets = case[1], case[2], case[3], case[4]
		Flux.edit(from)({ selector({ LayoutOrder = i }) })
		for _, gui in guis do
			local hit = table.find(targets, gui) ~= nil
			expect((gui.LayoutOrder == i) == hit, `{name}: {gui.Name} {if hit then "applied" else "untouched"}`)
		end
	end

	Flux.edit(b)({ Find.Ancestor("Mid")({ Name = "MidRenamed" }) })
	expect(mid.Name == "MidRenamed" and screen.Name == "Grand", "Ancestor: the named ancestor, not another")
	Flux.edit(b)({ Find.Parent()({ Name = "ARenamed" }) })
	expect(a.Name == "ARenamed", "Parent: the direct parent")
	for _, selector in { Find.AncestorClass("ScreenGui"), Find.AncestorIsA("LayerCollector") } do
		screen.Enabled = true
		Flux.edit(b)({ selector({ Enabled = false }) })
		expect(screen.Enabled == false, "AncestorClass / AncestorIsA (inherited) resolve the ScreenGui")
	end
	screen:Destroy()
end)

-- Split ---------------------------------------------------------------------------------------------------------------

test("split · separates named keys from everything else", function()
	local size = Flux("md")
	local child = {}
	local event = {}
	local function onClick() end
	local input = { variant = "filled", size = size, onClick = onClick, Name = "Save", [1] = child, __EVENT = event }

	local own, rest = Flux.split(input, { "variant", "size", "onClick" })
	expect(own.variant == "filled" and own.size == size and own.onClick == onClick, "named keys move by reference")
	expect(own.Name == nil and own[1] == nil, "nothing else lands in the named group")
	expect(
		rest.Name == "Save" and rest[1] == child and rest.__EVENT == event,
		"instance props, children and directives stay in the rest"
	)
	expect(rest.variant == nil and rest.size == nil, "named keys leave the rest")
	expect(input.variant == "filled" and own ~= input and rest ~= input, "the input is left untouched")
end)

test("split · takes schemas and several groups, first group wins", function()
	local DEFAULTS = { label = "", disabled = false }
	local style, own, rest = Flux.split(
		{ label = "Row", color = "red", disabled = true, Name = "Item" },
		{ "color", "label" },
		DEFAULTS
	)
	expect(style.color == "red" and style.label == "Row", "the first group takes the keys it names")
	expect(own.disabled == true and own.label == nil, "a schema names the second group; label was already claimed")
	expect(rest.Name == "Item" and rest.label == nil, "the rest gets what no group named")
end)

test("split · a nil props table yields empty groups", function()
	local own, rest = Flux.split(nil, { "a" })
	expect(next(own) == nil and next(rest) == nil, "both tables are empty")
	local onlyRest = Flux.split({ a = 1 })
	expect(onlyRest.a == 1, "with no groups, everything is the rest")
end)

test("edit · LayoutOrder model/node pinning, Find numeric ordering, and __REF post-children ordering", function()
	local orderNode = Flux.signal(0)
	local c1 = Flux.new("Frame")({ Name = "C1", LayoutOrder = orderNode })
	local c2 = Flux.new("Frame")({ Name = "C2" })
	local parent = Flux.new("Frame")({ c1, c2 })
	flush()
	expect(
		c1.LayoutOrder == 0 and c2.LayoutOrder == 1,
		"reactive LayoutOrder=0 is pinned and not overwritten by auto-numbering"
	)
	parent:Destroy()

	local modelOrder = Flux.signal(0)
	local m1 = Flux.new("Frame")({ Name = "M1", LayoutOrder = Flux.model(modelOrder) })
	local m2 = Flux.new("Frame")({ Name = "M2" })
	local parent2 = Flux.new("Frame")({ m1, m2 })
	flush()
	expect(m1.LayoutOrder == 0 and m2.LayoutOrder == 1, "Flux.model LayoutOrder=0 is pinned and not overwritten")
	parent2:Destroy()

	local refSawChild = false
	local foundChild = false
	local refCleaned = false
	local host = Flux.new("Frame")({
		[10] = Flux.new("TextLabel")({ Name = "Second" }),
		[2] = Flux.new("TextLabel")({ Name = "Target", Text = "Initial" }),
		[5] = Flux.Find.Child("Target")({ Text = "Hydrated" }),
		__REF = function(inst: Instance)
			local target = inst:FindFirstChild("Target") :: TextLabel?
			refSawChild = target ~= nil
			foundChild = target ~= nil and target.Text == "Hydrated"
			return function()
				refCleaned = true
			end
		end,
	})
	expect(refSawChild and foundChild, "__REF runs after numeric children and Find selectors")
	expect(
		(host:FindFirstChild("Target") :: TextLabel).LayoutOrder == 1
			and (host:FindFirstChild("Second") :: TextLabel).LayoutOrder == 2,
		"sparse numeric child keys sort in ascending order"
	)
	host:Destroy()
	expect(refCleaned, "__REF cleanup function runs on Destroy")

	local auto1 = Flux.new("Frame")({ BackgroundTransparency = 0 })
	local auto2 = Flux.new("Frame")({ BackgroundTransparency = Flux.signal(0.5) })
	local auto3 = Flux.new("Frame")({ Visible = Flux.model(Flux.signal(true)) })
	local autoHost = Flux.new("Frame")({ auto1, auto2, auto3 })
	flush()
	expect(
		auto1.LayoutOrder == 1 and auto2.LayoutOrder == 2 and auto3.LayoutOrder == 3,
		"non-LayoutOrder zero/node/model properties do not pin LayoutOrder=0"
	)
	autoHost:Destroy()

	local preTagged = Instance.new("Folder")
	local tagSig = Flux.signal(1 :: any)
	Flux.edit(preTagged)({ _tag_Preexisting = Flux.model(tagSig) })
	expect(tagSig:peek() == true, "_tag_Name model normalizes initial HasTag boolean")
	preTagged:Destroy()

	local childA = Instance.new("Frame")
	local childB = Instance.new("Frame")
	local childC = Instance.new("Frame")
	local dynChildren = Flux.signal({ childA, childB } :: any)
	local dynHost = Flux.new("Frame")({ dynChildren })
	flush()
	expect(childA.Parent == dynHost and childB.Parent == dynHost, "initial 2 children mounted")
	dynChildren:set({ childA, childC })
	flush()
	expect(
		childA.Parent == dynHost and childB.Parent == nil and childC.Parent == dynHost,
		"2-to-2 swap keeps shared child and unparents removed child"
	)
	dynChildren:set({ childA })
	flush()
	expect(childA.Parent == dynHost and childC.Parent == nil, "2-to-1 table keeps remaining child")
	dynChildren:set(childC)
	flush()
	expect(childA.Parent == nil and childC.Parent == dynHost, "table-to-Instance unparents old child")
	dynHost:Destroy()
	childA:Destroy()
	childB:Destroy()
	childC:Destroy()
end)

return {}
