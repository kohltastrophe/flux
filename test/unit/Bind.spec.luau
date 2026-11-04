--!nonstrict
local env = if game ~= nil
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Flux, sert, IS_ROBLOX = env.Flux, env.sert, env.IS_ROBLOX

local test = sert.test
local expect = sert
local settle = env.settle
local Instance = env.Instance
local workspace = env.workspace
local Bind = if IS_ROBLOX
	then require((game :: any).ReplicatedStorage.Flux.Bind) :: any
	else require("../../src/Bind") :: any
local expectError = sert.fails
local flush = Flux.flush

test("property · follows a property and an attribute via $ and _attr_, and stops when destroyed", function()
	local box = Instance.new("TextBox")
	box.Text = "a"
	box:SetAttribute("Health", 10)
	local text = Flux.property(box, "Text")
	local health = Flux.property(box, "$Health")
	local healthUnderscore = Flux.property(box, "_attr_Health")
	local terse = Flux(box, "Text")
	local terseAttr = Flux(box, "$Health")
	expect(
		text:get() == "a"
			and terse:get() == "a"
			and health:get() == 10
			and healthUnderscore:get() == 10
			and terseAttr:get() == 10,
		"seeded from the instance"
	)
	box.Text = "b"
	box:SetAttribute("Health", 5)
	settle()
	expect(
		text:get() == "b"
			and terse:get() == "b"
			and health:get() == 5
			and healthUnderscore:get() == 5
			and terseAttr:get() == 5,
		"follows changes"
	)
	text:Destroy()
	healthUnderscore:Destroy()
	terseAttr:Destroy()
	box.Text = "c"
	settle()
	expect(text:peek() ~= "c" and terse:get() == "c", "a destroyed node stops following")
	box:Destroy()
end)

test("property · follows an instance tag reactively via # and _tag_ prefixes", function()
	local frame = Instance.new("Frame")
	local other = Instance.new("Frame")
	frame:AddTag("PreExisting")
	frame.Parent = workspace
	other.Parent = workspace

	local hasEnemy = Flux.property(frame, "#Enemy")
	local hasEnemyUnderscore = Flux.property(frame, "_tag_Enemy")
	local viaCall = Flux(frame, "#Enemy")
	local hasPre = Flux.property(frame, "#PreExisting")
	expect(
		hasEnemy:get() == false and hasEnemyUnderscore:get() == false and viaCall:get() == false,
		"seeded with false when tag is absent"
	)
	expect(hasPre:get() == true, "seeded with true when tag is already present")

	other:AddTag("Enemy")
	settle()
	expect(hasEnemy:get() == false and hasEnemyUnderscore:get() == false, "tag added to another instance is ignored")

	frame:AddTag("Enemy")
	settle()
	expect(
		hasEnemy:get() == true and hasEnemyUnderscore:get() == true and viaCall:get() == true,
		"updates to true when tag is added"
	)

	frame.Parent = nil
	settle()
	expect(hasEnemy:get() == true, "unparenting an instance does not falsely clear its #Tag node")
	frame.Parent = workspace

	frame:RemoveTag("Enemy")
	settle()
	expect(
		hasEnemy:get() == false and hasEnemyUnderscore:get() == false and viaCall:get() == false,
		"updates to false when tag is removed"
	)

	hasEnemy:Destroy()
	hasEnemyUnderscore:Destroy()
	frame:AddTag("Enemy")
	settle()
	expect(hasEnemy:get() == nil and viaCall:get() == true, "destroyed tag node stops following")

	viaCall:Destroy()
	hasPre:Destroy()
	other:Destroy()
	frame:Destroy()
end)

test("property & call · reject non-Instance, missing property, non-string or empty prefix names", function()
	expectError(function()
		Flux.property({} :: any, "Text")
	end, "expects an Instance")
	expectError(function()
		Flux(123, "Name")
	end, "only an Instance takes a property name")

	local box = Instance.new("TextBox")
	expectError(function()
		Flux(box)
	end, "expects a property")
	expectError(function()
		Flux(box, true)
	end, "expects a property")
	expectError(function()
		Flux.property(box, 5 :: any)
	end, "expects a property")
	expectError(function()
		Flux.property(box, "$")
	end, 'after "$" cannot be empty')
	expectError(function()
		Flux.property(box, "#")
	end, 'after "#" cannot be empty')
	expectError(function()
		Flux.property(box, "_attr_")
	end, 'after "_attr_" cannot be empty')
	expectError(function()
		Flux.property(box, "_tag_")
	end, 'after "_tag_" cannot be empty')
	box:Destroy()
end)

test("bind.to · a failing write is warned and the remaining bindings still apply", function()
	local holder = Instance.new("ObjectValue")
	holder.Name = "Holder"
	local label = Instance.new("TextLabel")
	local v = Flux(nil :: any)
	Bind.to(v, holder, "Value")
	Bind.to(v, label, "Tint", true)

	local red = env.Color3.new(1, 0, 0)
	local warned = env.warnings(function()
		v:set(red)
		flush()
	end)
	expect(#warned >= 1, "the failing write warned")
	expect(
		string.find(warned[1], 'failed to set property "Value" of Holder', 1, true) ~= nil,
		`with the instance and key: {warned[1]}`
	)
	expect(label:GetAttribute("Tint") == red, "the other write applied")

	local target = Instance.new("Folder")
	v:set(target)
	flush()
	expect(holder.Value == target, "binding keeps working after a failed write")

	holder:Destroy()
	label:Destroy()
	target:Destroy()
end)

test("bind.children · a stale disconnect doesn't sever the live binding, to another parent or the same one", function()
	for _, same in { false, true } do
		local screen = Instance.new("ScreenGui")
		local parentA = Instance.new("Frame")
		parentA.Parent = screen
		local parentB = if same then parentA else Instance.new("Frame")
		parentB.Parent = screen

		local c1 = Instance.new("Frame")
		local node = Flux.signal(c1)
		local discA = Bind.children(node, parentA)
		local discB = Bind.children(node, parentB)
		expect(c1.Parent == parentB, "rebound")

		discA()
		local c2 = Instance.new("Frame")
		node:set(c2)
		flush()
		expect(c2.Parent == parentB, `the live binding survives the stale unbind (same parent: {same})`)

		discB()
		local c3 = Instance.new("Frame")
		node:set(c3)
		flush()
		expect(c3.Parent == nil and c2.Parent == nil, `the current unbind still works (same parent: {same})`)
		screen:Destroy()
	end
end)

test("bind.to · a shared node keeps writing after the first binding's scope dies", function()
	local node = Flux.signal("one")
	local first, second = Instance.new("StringValue"), Instance.new("StringValue")
	local scopeA = Flux.scope(function()
		Bind.to(node, first, "Value")
	end)
	Bind.to(node, second, "Value")

	node:set("two")
	flush()
	expect(second.Value == "two", "binding written while scopeA is alive")

	scopeA:Destroy()
	node:set("three")
	flush()
	expect(second.Value == "three", "surviving binding still written after scopeA dies")
	first:Destroy()
	second:Destroy()
end)

test("bind.children · re-parenting before a change flushes doesn't leak old children", function()
	local screen = Instance.new("ScreenGui")
	local A = Instance.new("Frame")
	A.Name = "A"
	A.Parent = screen
	local B = Instance.new("Frame")
	B.Name = "B"
	B.Parent = screen

	local c1 = Instance.new("Frame")
	local c2 = Instance.new("Frame")
	local node = Flux.signal(c1)

	Bind.children(node, A)
	expect(c1.Parent == A, "c1 parented under A")

	node:set(c2)
	Bind.children(node, B)

	expect(c2.Parent == B, "c2 parented under B")
	expect(c1.Parent == nil, "stale c1 is not left behind under A")
	flush()
	screen:Destroy()
end)

test("bind.children · mounting a nested node doesn't subscribe the code that built the parent", function()
	local first, second = Instance.new("Frame"), Instance.new("Frame")
	local inner = Flux.signal(first)
	local children = Flux.signal({ inner })
	local builds, frame = 0, nil
	local s = Flux.scope(function()
		Flux.effect(function()
			builds += 1
			frame = Flux.new("Frame")({ children })
		end)
	end)
	flush()
	expect(builds == 1 and first.Parent == frame, "built once, with the nested node's child mounted")
	inner:set(second)
	flush()
	expect(builds == 1, `the effect that built the frame didn't re-run: {builds} builds`)
	expect(second.Parent == frame and first.Parent == nil, "the binding itself still follows the nested node")
	s:Destroy()
	first:Destroy()
	second:Destroy()
end)

test("bind · a property that fills a cache it read shows what it filled", function()
	local key = Flux.signal("a")
	local function lookup(): () -> string
		local cache = Flux.signal({})
		return function(): string
			local k = key:get()
			local hit = cache:get()[k]
			if hit then
				return hit
			end
			env.task.spawn(function()
				local current = cache:peek()
				local filled = table.clone(current)
				filled[k] = string.upper(k)
				cache:set(filled)
			end)
			return "..."
		end
	end
	local byFunction, byComputed
	local scope = Flux.scope(function()
		byFunction = Flux.new("TextLabel")({ Text = lookup() })
		byComputed = Flux.new("TextLabel")({ Text = Flux.computed(lookup()) })
	end)
	flush()
	expect(byFunction.Text == "A", `a bound function shows the first answer, not {byFunction.Text}`)
	expect(byComputed.Text == "A", `a bound computed shows the first answer, not {byComputed.Text}`)
	key:set("b")
	flush()
	expect(byFunction.Text == "B" and byComputed.Text == "B", `and the next: {byFunction.Text}, {byComputed.Text}`)
	scope:Destroy()
end)

test("model · isModel and modelNode recognise a model; Flux.model rejects a non-node", function()
	local node = Flux("text")
	local model = Flux.model(node)
	expect(Flux.isModel(model) and Flux.modelNode(model) == node, "a model and its node")
	expect(not Flux.isModel(node) and Flux.modelNode(node) == nil, "a node is not a model")
	expect(not Flux.isModel("text") and Flux.modelNode(nil) == nil, "nor is a plain value")
	expectError(function()
		Flux.model("not a node")
	end, "expects a reactive node")
end)

test("bind · late Bind.children attachment, model destroy pruning, and untracked initial Bind.to write", function()
	local inner = Flux.signal(Flux.new("Frame")({ Name = "First" }))
	local outer = Flux.signal({ inner })
	local p1 = Flux.new("Folder")({})
	local p2 = Flux.new("Folder")({})

	local scope1 = Flux.scope(function()
		Flux.edit(p1)({ outer })
	end)
	flush()
	expect(p1:FindFirstChild("First") ~= nil, "p1 received initial nested child")

	local scope2 = Flux.scope(function()
		Flux.edit(p2)({ outer })
	end)
	flush()

	local second = Flux.new("Frame")({ Name = "Second" })
	inner:set(second)
	flush()
	expect(p2:FindFirstChild("Second") ~= nil, "p2 tracks inner child node even when attached after outer flushed")
	scope1:Destroy()
	scope2:Destroy()
	p1:Destroy()
	p2:Destroy()

	local shared = Flux.signal("hello")
	local sharedTag = Flux.signal(true)
	local boxA = Flux.new("TextBox")({ Text = Flux.model(shared), _tag_Active = Flux.model(sharedTag) })
	local boxB = Flux.new("TextBox")({ Text = Flux.model(shared), _tag_Active = Flux.model(sharedTag) })
	boxA:Destroy()
	boxB:Destroy()
	local afterCount = if (shared :: any)[1].destroys then #(shared :: any)[1].destroys else 0
	local afterTagCount = if (sharedTag :: any)[1].destroys then #(sharedTag :: any)[1].destroys else 0
	expect(
		afterCount == 1 and afterTagCount == 0,
		`destroying model-bound instances prunes node destroys: {afterCount}/{afterTagCount}`
	)
	shared:Destroy()
	sharedTag:Destroy()

	local source = Flux.signal("init")
	local outerTrigger = Flux.signal(0)
	local outerRuns = 0
	local frame = Flux.new("Frame")({})
	local listenerScope = Flux.scope(function()
		local propNode = Flux.property(frame, "Name")
		Flux.effect(function()
			propNode()
		end)
	end)
	flush()
	local ownerScope = Flux.scope(function()
		Flux.effect(function()
			outerRuns += 1
			outerTrigger()
			Flux.edit(frame)({ Name = source })
		end)
	end)
	flush()
	expect(
		outerRuns == 1 and frame.Name == "init",
		"initial synchronous Bind.to write does not re-trigger enclosing effect"
	)
	ownerScope:Destroy()
	listenerScope:Destroy()
	frame:Destroy()
end)

local function syncMountedChildren(sut: any, mountedIds: { number })
	for _, c in sut.pool do
		c.Parent = nil
		c.LayoutOrder = 0
	end
	local list = {}
	for _, id in mountedIds do
		table.insert(list, sut.pool[id])
	end
	sut.childrenSig:set(list)
	flush()
end

sert.model("bind · dynamic DOM hierarchy and two-way Flux.property/Flux.model binding reconciliation", {
	init = function()
		local textSig = Flux.signal("t0")
		local attrSig = Flux.signal(10)
		local tagSig = Flux.signal(false)
		local childrenSig = Flux.signal({} :: { any })

		local pool = {
			Flux.new("Frame")({ Name = "Child1" }),
			Flux.new("Frame")({ Name = "Child2" }),
			Flux.new("Frame")({ Name = "Child3" }),
			Flux.new("Frame")({ Name = "Child4" }),
		}

		local host, propText, propAttr, propTag
		local scope = Flux.scope(function()
			host = Flux.new("TextBox")({
				Name = "BindHost",
				Parent = workspace,
				Text = Flux.model(textSig),
				_attr_Score = Flux.model(attrSig),
				_tag_Active = Flux.model(tagSig),
				childrenSig,
			})
			propText = Flux.property(host, "Text")
			propAttr = Flux.property(host, "$Score")
			propTag = Flux.property(host, "#Active")
		end)
		flush()
		settle()

		local state = {
			mounted = {} :: { number },
			text = "t0",
			score = 10,
			active = false,
		}
		local sut = {
			scope = scope,
			host = host,
			pool = pool,
			childrenSig = childrenSig,
			textSig = textSig,
			attrSig = attrSig,
			tagSig = tagSig,
			propText = propText,
			propAttr = propAttr,
			propTag = propTag,
		}
		return state, sut
	end,
	teardown = function(sut)
		sut.scope:Destroy()
		for _, c in sut.pool do
			c:Destroy()
		end
		sut.host:Destroy()
		flush()
		sert.eq(env.idle(Flux), nil, "zero-leak reactive state on teardown")
		sert.eq(env.drained(Flux), nil, "zero pending effects on teardown")
	end,
	actions = {
		MountChild = {
			weight = 3,
			gen = function(g)
				return g:int(1, 4)
			end,
			run = function(sut, id, state)
				if table.find(state.mounted, id) ~= nil then
					return
				end
				local nextIds = table.clone(state.mounted)
				table.insert(nextIds, id)
				syncMountedChildren(sut, nextIds)
			end,
			next = function(state, id)
				if table.find(state.mounted, id) == nil then
					table.insert(state.mounted, id)
				end
			end,
		},
		UnmountChild = {
			weight = 2,
			gen = function(g)
				return g:int(1, 4)
			end,
			run = function(sut, id, state)
				local idx = table.find(state.mounted, id)
				if idx == nil then
					return
				end
				local nextIds = table.clone(state.mounted)
				table.remove(nextIds, idx)
				syncMountedChildren(sut, nextIds)
			end,
			next = function(state, id)
				local idx = table.find(state.mounted, id)
				if idx ~= nil then
					table.remove(state.mounted, idx)
				end
			end,
		},
		ReorderChildren = {
			weight = 2,
			run = function(sut, _arg, state)
				if #state.mounted < 2 then
					return
				end
				local nextIds = {}
				for i = #state.mounted, 1, -1 do
					table.insert(nextIds, state.mounted[i])
				end
				syncMountedChildren(sut, nextIds)
			end,
			next = function(state)
				if #state.mounted < 2 then
					return
				end
				local rev = {}
				for i = #state.mounted, 1, -1 do
					table.insert(rev, state.mounted[i])
				end
				state.mounted = rev
			end,
		},
		WriteSignalProp = {
			weight = 2,
			gen = function(g)
				return `sig_{g:int(1, 20)}`
			end,
			run = function(sut, val)
				sut.textSig:set(val)
				flush()
			end,
			next = function(state, val)
				state.text = val
			end,
		},
		MutateInstanceProp = {
			weight = 2,
			gen = function(g)
				return `inst_{g:int(1, 20)}`
			end,
			run = function(sut, val)
				sut.host.Text = val
				settle()
				flush()
			end,
			next = function(state, val)
				state.text = val
			end,
		},
		MutateAttribute = {
			weight = 2,
			gen = function(g)
				return { score = g:int(1, 50), viaInstance = g:bool() }
			end,
			run = function(sut, arg)
				if arg.viaInstance then
					sut.host:SetAttribute("Score", arg.score)
					settle()
				else
					sut.attrSig:set(arg.score)
				end
				flush()
			end,
			next = function(state, arg)
				state.score = arg.score
			end,
		},
		ToggleTag = {
			weight = 2,
			gen = function(g)
				return { active = g:bool(), viaInstance = g:bool() }
			end,
			run = function(sut, arg)
				if arg.viaInstance then
					if arg.active then
						sut.host:AddTag("Active")
					else
						sut.host:RemoveTag("Active")
					end
				else
					sut.tagSig:set(arg.active)
					flush()
				end
				settle()
				flush()
			end,
			next = function(state, arg)
				state.active = arg.active
			end,
		},
	},
	never = {
		unmountedChildRetainedInHost = function(state, sut)
			for id, inst in sut.pool do
				if table.find(state.mounted, id) == nil and inst.Parent ~= nil then
					return true
				end
			end
			return false
		end,
	},
	invariants = {
		childrenOrderMatchesState = function(state, sut)
			local children = sut.host:GetChildren()
			sert.eq(#children, #state.mounted, "mounted child count")
			for idx, id in state.mounted do
				local expected = sut.pool[id]
				sert.eq(children[idx], expected, `GetChildren()[{idx}] identity`)
				sert.eq((children[idx] :: Frame).LayoutOrder, idx, `GetChildren()[{idx}] LayoutOrder`)
			end
		end,
		twoWayPropertyAndModelParity = function(state, sut)
			sert.eq(sut.host.Text, state.text, "host.Text")
			sert.eq(sut.textSig:peek(), state.text, "textSig")
			sert.eq(sut.propText:peek(), state.text, "Flux.property Text")

			sert.eq(sut.host:GetAttribute("Score"), state.score, "host Score attribute")
			sert.eq(sut.attrSig:peek(), state.score, "attrSig")
			sert.eq(sut.propAttr:peek(), state.score, "Flux.property $Score")

			sert.eq(sut.host:HasTag("Active"), state.active, "host Active tag")
			sert.eq(sut.tagSig:peek(), state.active, "tagSig")
			sert.eq(sut.propTag:peek(), state.active, "Flux.property #Active")
		end,
	},
}, {
	runs = 120,
	length = 16,
	exhaustive = { size = 2 },
})

test("listen · fires only on updates after subscribing and stops when disconnected or destroyed", function()
	local v = Flux(1)
	local received = {}
	local disconnect = Flux.listen(v, function(val)
		table.insert(received, val)
	end)
	expect(type(disconnect) == "function", "listen returns a disconnect function")
	flush()
	expect(#received == 0, "listen does not fire on initial flush when value has not changed")

	v(2)
	flush()
	expect(#received == 1 and received[1] == 2, "listener receives first update")

	v(3)
	flush()
	expect(#received == 2 and received[2] == 3, "listener receives subsequent updates")

	disconnect()
	disconnect()
	v(4)
	flush()
	expect(#received == 2, "listener stops firing after disconnect")

	local received2 = {}
	Flux.listen(v, function(val)
		table.insert(received2, val)
	end)
	v:Destroy()
	v(5)
	flush()
	expect(#received2 == 0, "destroyed node clears listeners")
end)

test("listen · hears immediate mutation before first flush and survives scope teardown on shared node", function()
	local v = Flux("a")
	local seen = {}
	Flux.listen(v, function(val)
		table.insert(seen, val)
	end)
	v("b")
	flush()
	expect(#seen == 1 and seen[1] == "b", "mutation immediately after listen before first flush is observed")

	local shared = Flux.signal("one")
	local out = {}
	local scopeA = Flux.scope(function()
		Flux.listen(shared, function() end)
	end)
	Flux.listen(shared, function(val)
		table.insert(out, val)
	end)
	shared:set("two")
	flush()
	expect(out[#out] == "two", "listener notified while scopeA is alive")

	scopeA:Destroy()
	shared:set("three")
	flush()
	expect(out[#out] == "three", "surviving listener still notified after first listener's scope dies")
end)

test("listen · callbacks run untracked, ownerless, and safe across mid-flush add/remove and Bind.children", function()
	local src = Flux(10)
	local unrelated = Flux(100)
	local ownerSeen: any = "unset"
	local reactiveSeen: any = "unset"
	local innerDisposed = 0
	local runs = 0

	Flux.listen(src, function(_val)
		runs += 1
		ownerSeen = Flux.getOwner()
		reactiveSeen = Flux.isReactive()
		local _ = unrelated()
		local c = Flux.computed(function()
			return 1
		end)
		c:onDestroy(function()
			innerDisposed += 1
		end)
	end)

	src(20)
	flush()
	expect(
		runs == 1 and ownerSeen == nil and reactiveSeen == false,
		"listener ran untracked and ownerless on src update"
	)

	unrelated(200)
	flush()
	expect(runs == 1, "reading unrelated signal inside listener does not subscribe src's bind effect")

	src(30)
	flush()
	expect(runs == 2 and innerDisposed == 0, "listener runs ownerless without bind effect adopting created nodes")

	-- Multi-listener mid-flush add and disconnect safety
	local multi = Flux(0)
	local log = {}
	local discA: () -> ()
	local discB: () -> ()
	local function addC()
		Flux.listen(multi, function(v2)
			table.insert(log, `C:{v2}`)
		end)
	end
	discA = Flux.listen(multi, function(val)
		table.insert(log, `A:{val}`)
		discB()
		addC()
	end)
	discB = Flux.listen(multi, function(val)
		table.insert(log, `B:{val}`)
		discA()
		addC()
	end)

	multi(1)
	flush()
	expect(#log == 1, "disconnecting sibling listener mid-flush prevents it from firing, and newly added C waits")
	multi(2)
	flush()
	expect(table.find(log, "C:2") ~= nil, "listener added mid-flush fires on subsequent update")

	-- Re-attaching Bind.children on a listened node does not falsely trigger listeners
	local childA = Instance.new("Frame")
	local childB = Instance.new("Frame")
	local parent1 = Instance.new("Frame")
	local parent2 = Instance.new("Frame")
	local childNode = Flux.signal(childA)
	local childEvents = 0
	Flux.listen(childNode, function()
		childEvents += 1
	end)
	local unbind1 = Bind.children(childNode, parent1)
	flush()
	local unbind2 = Bind.children(childNode, parent2)
	flush()
	expect(
		childEvents == 0,
		"attaching or re-parenting Bind.children does not fire listen when node value is unchanged"
	)
	childNode:set(childB)
	flush()
	expect(childEvents == 1, "listener still fires when childNode updates after Bind.children restart")
	unbind1()
	unbind2()
	childA:Destroy()
	childB:Destroy()
	parent1:Destroy()
	parent2:Destroy()

	expectError(function()
		Flux.listen("not a node" :: any, function() end)
	end, "expects a reactive node")
	expectError(function()
		Flux.listen(src, "not a function" :: any)
	end, "expects a function")
end)

return {}
