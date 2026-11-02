--!nonstrict
local env = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("env")) :: any
	else require("../lib/env") :: any
local Model = if game
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Flux.lib"):WaitForChild("Model")) :: any
	else require("../lib/Model") :: any

local Flux = env.Flux
local sert = env.sert
local test = sert.test
local expect = sert
local new = Flux
local flush = Flux.flush

test("show · a throwing component is warned and does not strand tracking", function()
	local cond = Flux.signal(true)
	local node = Flux.show(cond, function()
		error("component boom")
	end)
	local warnings = env.warnings(flush)
	expect(#warnings == 1, `the build error was warned once, got {#warnings}`)
	local probe = Flux.signal(1)
	local seen = 0
	local e = Flux.effect(function()
		probe()
		seen += 1
	end)
	flush()
	probe:set(2)
	flush()
	expect(seen == 2, "tracking restored after a throwing component")
	expect(node() == nil, "output is nil after the failed build")
	e:Destroy()
	node:Destroy()
end)

test("show · the value accessor tracks the live condition without remounting", function()
	local user = Flux.signal({ name = "Ada" })
	local builds, seen = 0, nil
	local node = Flux.show(user, function(value)
		builds += 1
		Flux.effect(function()
			seen = value().name
		end)
		return "panel"
	end)
	flush()
	expect(builds == 1 and seen == "Ada", "mounted once; accessor effect saw the initial value")

	user:set({ name = "Grace" })
	flush()
	expect(builds == 1, "no rebuild across a truthy -> truthy change")
	expect(seen == "Grace", "accessor effect re-ran with the live value")
	node:Destroy()
end)

test("switch · the default branch value accessor tracks the live unmatched value", function()
	local route = Flux.signal("home")
	local defaultBuilds, seen = 0, {}
	local node = Flux.switch(route)({
		home = function(value)
			return "home:" .. value()
		end,
		[Flux.otherwise] = function(value)
			defaultBuilds += 1
			Flux.effect(function()
				seen[#seen + 1] = value()
			end)
			return "default"
		end,
	})
	flush()
	expect(node() == "home:home", "keyed branch value() returns the matched key")

	route:set("about")
	flush()
	route:set("contact")
	flush()
	expect(defaultBuilds == 1, "the one default mount is reused across unmatched values")
	expect(table.concat(seen, ",") == "about,contact", "default accessor tracked each live unmatched value")
	node:Destroy()
end)

test("show and switch · mount, swap and unmount real instances under a parent", function()
	local cond, key = Flux.signal(true), Flux.signal("red")
	local cases = {
		{
			"show",
			function()
				return Flux.show(cond, function()
					return Flux.new("Frame")({ Name = "Branch" })
				end)
			end,
			{ "Branch" },
			function()
				cond:set(false)
			end,
			{},
		},
		{
			"switch",
			function()
				return Flux.switch(key)({
					red = function()
						return Flux.new("Frame")({ Name = "Red" })
					end,
					blue = function()
						return Flux.new("Frame")({ Name = "Blue" })
					end,
				})
			end,
			{ "Red" },
			function()
				key:set("blue")
			end,
			{ "Blue" },
		},
	}
	local function names(parent)
		local list = {}
		for _, child in parent:GetChildren() do
			table.insert(list, child.Name)
		end
		return list
	end
	for _, case in cases do
		local root
		local s = Flux.scope(function()
			root = Flux.new("Frame")({ Name = "Root", case[2]() })
		end)
		flush()
		expect.eq(names(root), case[3], `{case[1]}: mounted under the parent`)
		case[4]()
		flush()
		expect.eq(names(root), case[5], `{case[1]}: after the change`)
		expect.eq(
			env.warnings(function()
				s:Destroy()
			end),
			{},
			`{case[1]}: unmounts without a warning`
		)
	end
end)

test("presence · an exit keeps the branch mounted until done", function()
	local visible = Flux.signal(true)
	local exitingNode, finish
	local builds, cleaned = 0, 0
	local node = Flux.presence(visible, function(exiting, done)
		builds += 1
		exitingNode, finish = exiting, done
		Flux.cleanup(function()
			cleaned += 1
		end)
		return { tag = "P" }
	end)
	flush()
	expect(node().tag == "P" and builds == 1 and exitingNode() == false, "mounted and not exiting")

	finish()
	flush()
	expect(node() ~= nil and cleaned == 0, "done() outside an exit is ignored")

	visible:set(false)
	flush()
	expect(exitingNode() == true, "a falsy condition starts the exit")
	expect(node().tag == "P" and cleaned == 0, "the branch stays mounted while exiting")

	finish()
	flush()
	expect(node() == nil and cleaned == 1, "done() unmounts the branch")

	visible:set(true)
	flush()
	expect(builds == 2 and node().tag == "P", "turning truthy again mounts a fresh branch")
	node:Destroy()
end)

test("presence · re-entering during an exit reverses it", function()
	local visible = Flux.signal(true)
	local exitingNode, finish
	local builds = 0
	local node = Flux.presence(visible, function(exiting, done)
		builds += 1
		exitingNode, finish = exiting, done
		return "P"
	end)
	flush()
	visible:set(false)
	flush()

	finish()
	visible:set(true)
	flush()
	expect(builds == 1 and node() == "P", "the same branch stays; the stale done() is dropped")
	expect(exitingNode() == false, "exiting flips back")

	visible:set(false)
	flush()
	flush()
	expect(exitingNode() == true and node() == "P", "a new exit waits for its own done()")
	finish()
	flush()
	expect(node() == nil, "which unmounts")
	node:Destroy()
end)

test("presence · done() from a branch effect unmounts on the same flush", function()
	local visible = Flux.signal(true)
	local cleaned = 0
	local node = Flux.presence(visible, function(exiting, done)
		Flux.effect(function()
			if exiting() then
				done()
			end
		end)
		Flux.cleanup(function()
			cleaned += 1
		end)
		return "P"
	end)
	flush()
	visible:set(false)
	flush()
	expect(node() == nil and cleaned == 1, "unmounted within one flush")
	node:Destroy()
end)

test("presence · keeps an exiting instance parented until done", function()
	local visible = Flux.signal(true)
	local finish
	local root
	local s = Flux.scope(function()
		local panel = Flux.presence(visible, function(_, done)
			finish = done
			return Flux.new("Frame")({ Name = "Panel" })
		end)
		root = Flux.new("Frame")({ Name = "Root", panel })
	end)
	flush()
	expect(root:FindFirstChild("Panel") ~= nil, "mounted")
	visible:set(false)
	flush()
	expect(root:FindFirstChild("Panel") ~= nil, "still parented while exiting")
	finish()
	flush()
	expect(root:FindFirstChild("Panel") == nil, "unparented after done")
	s:Destroy()
end)

test("presence · destroys exiting node on completion or Destroy, and throwing factory recovers", function()
	local visible = Flux.signal(true)
	local exitDestroyed = 0
	local finishFn: (() -> ())?
	local out = Flux.presence(visible, function(exiting, done)
		exiting:onDestroy(function()
			exitDestroyed += 1
		end)
		finishFn = done
		return "mounted"
	end)
	flush()
	expect(out() == "mounted" and exitDestroyed == 0, "mounted with live exiting node")

	visible:set(false)
	flush()
	expect(exitDestroyed == 0, "exiting node still alive while exit animation is in progress")
	assert(finishFn)()
	flush()
	expect(out() == nil and exitDestroyed == 1, "completing exit destroys the per-mount exiting node")

	visible:set(true)
	flush()
	expect(out() == "mounted" and exitDestroyed == 1, "re-mounted with a fresh exiting node")
	out:Destroy()
	expect(exitDestroyed == 2, "destroying presence output destroys the active exiting node")

	local bad = Flux.presence(Flux.signal(true), function()
		error("presence boom")
	end)
	local warnings = env.warnings(flush)
	expect(#warnings == 1 and bad() == nil, "throwing presence factory warns once and leaves output nil")
	bad:Destroy()
end)

test("show · presence · a branch is torn down before its owner's cleanups", function()
	for _, kind in { "show", "presence" } do
		local order = {}
		local s = Flux.scope(function()
			local function branch()
				Flux.cleanup(function()
					table.insert(order, "branch")
				end)
				return "B"
			end
			local node = if kind == "show" then Flux.show(true, branch) else Flux.presence(true, branch)
			Flux.cleanup(function()
				table.insert(order, "owner")
			end)
			return node
		end)
		flush()
		s:Destroy()
		expect.eq(table.concat(order, ","), "branch,owner", kind)
	end
end)

test("show · an owner's re-run tears down the branch it built before", function()
	local source = Flux.signal(1)
	local cleaned = 0
	local owner = Flux.computed(function()
		source:get()
		return Flux.show(true, function()
			Flux.cleanup(function()
				cleaned += 1
			end)
			return "B"
		end)
	end)
	owner:get()
	flush()
	source:set(2)
	owner:get()
	flush()
	expect.eq(cleaned, 1, "the first run's branch went with the re-run")
	owner:Destroy()
	expect.eq(cleaned, 2)
end)

test("show · a branch can take back an instance before the owner's frames are destroyed", function()
	local lent = env.Instance.new("Frame")
	lent.Name = "Lent"
	local s = Flux.scope(function()
		local branch = Flux.show(true, function()
			Flux.cleanup(function()
				lent.Parent = nil
			end)
			local holder = Flux.new("Frame")({ Name = "Holder" })
			lent.Parent = holder
			return holder
		end)
		Flux.new("Frame")({ Name = "Root", branch })
	end)
	flush()
	expect(lent.Parent ~= nil and lent.Parent.Name == "Holder", "mounted")
	expect.eq(
		env.warnings(function()
			s:Destroy()
		end),
		{},
		"the teardown warns nothing"
	)
	local folder = env.Instance.new("Folder")
	expect(
		pcall(function()
			lent.Parent = folder
		end),
		"the lent frame survived its owner's teardown"
	)
	folder:Destroy()
end)

-- Conditional models ----------------------------------------------------------------------------------------------

local TABLE_A, TABLE_B = { id = "A" }, { id = "B" }
local function showValue(value: any): string
	return if type(value) == "table" then `table {value.id}` else tostring(value)
end

local BRANCH_DOMAIN: { any } = { nil, false, true, 1, TABLE_A, TABLE_B, "x", "y", "z" }
local OTHER_KEY = {}
local BRANCH_CASES = {
	{ id = "show", kind = "show", withFallback = false, useGetter = false, directDestroy = true },
	{ id = "show+fb", kind = "show", withFallback = true, useGetter = true, directDestroy = false },
	{ id = "showKeyed", kind = "showKeyed", withFallback = false, useGetter = true, directDestroy = true },
	{ id = "showKeyed+fb", kind = "showKeyed", withFallback = true, useGetter = false, directDestroy = false },
	{ id = "switch", kind = "switch", withFallback = false, useGetter = false, directDestroy = true },
	{ id = "switch+other", kind = "switch+otherwise", withFallback = false, useGetter = true, directDestroy = false },
}

local function selectCaseBranch(caseSpec: any, value: any): (any, string?)
	local kind = caseSpec.kind
	if kind == "switch" or kind == "switch+otherwise" then
		if value == "x" or value == "y" then
			return value, value
		elseif kind == "switch+otherwise" then
			return OTHER_KEY, "otherwise"
		end
		return value, nil
	end
	local key = if kind == "showKeyed" then value else not not value
	return key, if value then "on" elseif caseSpec.withFallback then "off" else nil
end

local function syncBranchModel(state: any)
	if not state.dirty then
		return
	end
	state.dirty = false
	local value = state.value
	for _, caseSpec in BRANCH_CASES do
		local cState = state.cases[caseSpec.id]
		local key, name = selectCaseBranch(caseSpec, value)
		if not cState.mounted or key ~= cState.activeKey then
			cState.mounted, cState.activeKey = true, key
			if cState.live then
				cState.live.retired = true
			end
			cState.live = nil
			if name then
				cState.count += 1
				cState.live = { name = name, value = value }
			end
		end
	end
end

sert.model("show/showKeyed/switch · the mounted branch follows the source's key", {
	init = function()
		local source = Flux.signal(nil :: any)
		local state: any = {
			value = nil,
			dirty = true,
			cases = {},
		}
		local sut: any = {
			source = source,
			cases = {},
		}
		for _, caseSpec in BRANCH_CASES do
			local mounts = {}
			local function factory(name: string)
				return function(value)
					local mount = { branch = name, cleaned = 0, value = value() }
					table.insert(mounts, mount)
					Flux.cleanup(function()
						mount.cleaned += 1
					end)
					return mount
				end
			end
			local input: any = if caseSpec.useGetter
				then function()
					return source:get()
				end
				else source
			local node
			local owner = Flux.scope(function()
				if caseSpec.kind == "switch" or caseSpec.kind == "switch+otherwise" then
					local map: { [any]: any } = { x = factory("x"), y = factory("y") }
					if caseSpec.kind == "switch+otherwise" then
						map[Flux.otherwise] = factory("otherwise")
					end
					node = Flux.switch(input)(map)
				elseif caseSpec.kind == "show" then
					node = Flux.show(input, factory("on"), if caseSpec.withFallback then factory("off") else nil)
				else
					node = Flux.showKeyed(input, factory("on"), if caseSpec.withFallback then factory("off") else nil)
				end
			end)
			state.cases[caseSpec.id] = { mounted = false, activeKey = nil, live = nil, count = 0 }
			sut.cases[caseSpec.id] = { spec = caseSpec, owner = owner, node = node, mounts = mounts }
		end
		Flux.flush()
		syncBranchModel(state)
		return state, sut
	end,
	teardown = function(sut, state)
		Flux.flush()
		syncBranchModel(state)
		for _, caseSpec in BRANCH_CASES do
			local cSut = sut.cases[caseSpec.id]
			if caseSpec.directDestroy then
				cSut.node:Destroy()
			else
				cSut.owner:Destroy()
			end
		end
		for _, caseSpec in BRANCH_CASES do
			local cSut = sut.cases[caseSpec.id]
			for index, mount in cSut.mounts do
				sert.eq(mount.cleaned, 1, `{caseSpec.id}: mount {index} ({mount.branch}) cleaned up once in all`)
			end
			cSut.owner:Destroy()
		end
		Flux.flush()
	end,
	actions = {
		set = {
			weight = 3,
			gen = function(g)
				return BRANCH_DOMAIN[g:int(1, #BRANCH_DOMAIN)]
			end,
			run = function(sut, value)
				sut.source:set(value)
			end,
			next = function(state, value)
				state.value = value
				state.dirty = true
			end,
		},
		flush = {
			weight = 2,
			run = function()
				Flux.flush()
			end,
			next = function(state)
				syncBranchModel(state)
			end,
		},
	},
	never = {
		mountCleanedTwice = function(_state, sut)
			for _, cSut in sut.cases do
				for _, mount in cSut.mounts do
					if mount.cleaned > 1 then
						return true
					end
				end
			end
			return false
		end,
		activeMountCleanedWhileSynced = function(state, sut)
			if state.dirty then
				return false
			end
			for id, cState in state.cases do
				local mounts = sut.cases[id].mounts
				if cState.live ~= nil and #mounts > 0 and mounts[#mounts].cleaned ~= 0 then
					return true
				end
			end
			return false
		end,
	},
	invariants = {
		mountCountMatchesReference = function(state, sut)
			if state.dirty then
				return
			end
			for _, caseSpec in BRANCH_CASES do
				local cState = state.cases[caseSpec.id]
				local cSut = sut.cases[caseSpec.id]
				sert.eq(#cSut.mounts, cState.count, `{caseSpec.id}: one factory call per key change`)
			end
		end,
		retiredMountsCleanedOnce = function(state, sut)
			if state.dirty then
				return
			end
			for _, caseSpec in BRANCH_CASES do
				local cState = state.cases[caseSpec.id]
				local cSut = sut.cases[caseSpec.id]
				for index, mount in cSut.mounts do
					local alive = index == #cSut.mounts and cState.live ~= nil
					sert.eq(
						mount.cleaned,
						if alive then 0 else 1,
						`{caseSpec.id}: mount {index} ({mount.branch}) cleaned up once when swapped out`
					)
				end
			end
		end,
		liveBranchMatchesReference = function(state, sut)
			if state.dirty then
				return
			end
			for _, caseSpec in BRANCH_CASES do
				local cState = state.cases[caseSpec.id]
				local cSut = sut.cases[caseSpec.id]
				if cState.live then
					local mount = cSut.mounts[#cSut.mounts]
					sert(cSut.node:peek() == mount, `{caseSpec.id}: the output is the live mount`)
					sert.eq(
						mount.branch,
						cState.live.name,
						`{caseSpec.id}: {showValue(state.value)} mounts {cState.live.name}`
					)
					sert(
						mount.value == cState.live.value,
						`{caseSpec.id}: value() in the factory is the value it mounted for`
					)
				else
					sert(cSut.node:peek() == nil, `{caseSpec.id}: no branch for {showValue(state.value)}`)
				end
			end
		end,
	},
}, {
	runs = 150,
	length = 14,
	exhaustive = { size = 2 },
})

local function syncPresenceState(state: any)
	if not state.dirty then
		return
	end
	state.dirty = false
	if state.visible then
		if state.mode == "unmounted" then
			state.mode = "mounted"
			state.count += 1
		elseif state.mode == "exiting" then
			state.mode = "mounted"
		end
		state.pendingDone = false
	else
		if state.pendingDone then
			if state.mode == "exiting" then
				state.mode = "unmounted"
			end
			state.pendingDone = false
		elseif state.mode == "mounted" then
			state.mode = "exiting"
		end
	end
end

sert.model("presence · mounts on truthy, holds during exit, reverses on re-truthy, and unmounts on done", {
	init = function()
		local visible = Flux.signal(false)
		local mounts = {}
		local node
		local owner = Flux.scope(function()
			node = Flux.presence(visible, function(exiting, done)
				local mount = { exiting = exiting, done = done, cleaned = 0 }
				table.insert(mounts, mount)
				Flux.cleanup(function()
					mount.cleaned += 1
				end)
				return mount
			end)
		end)
		Flux.flush()
		local state = {
			mode = "unmounted",
			visible = false,
			count = 0,
			pendingDone = false,
			dirty = false,
		}
		local sut = {
			visible = visible,
			mounts = mounts,
			node = node,
			owner = owner,
		}
		return state, sut
	end,
	teardown = function(sut, state)
		Flux.flush()
		syncPresenceState(state)
		sut.node:Destroy()
		sut.owner:Destroy()
		Flux.flush()
		for i, mount in sut.mounts do
			sert.eq(mount.cleaned, 1, `mount {i} cleaned once after Destroy`)
		end
	end,
	actions = {
		set = {
			weight = 4,
			gen = sert.gen.bool(),
			run = function(sut, v)
				sut.visible:set(v)
			end,
			next = function(state, v)
				state.visible = v
				state.dirty = true
			end,
		},
		done = {
			weight = 3,
			run = function(sut)
				if #sut.mounts > 0 then
					sut.mounts[#sut.mounts].done()
				end
			end,
			next = function(state, _, _)
				if state.count > 0 and state.mode == "exiting" and not state.visible then
					state.pendingDone = true
					state.dirty = true
				end
			end,
		},
		flush = {
			weight = 3,
			run = function()
				Flux.flush()
			end,
			next = function(state)
				syncPresenceState(state)
			end,
		},
	},
	never = {
		cleanedMoreThanOnce = function(_state, sut)
			for _, mount in sut.mounts do
				if mount.cleaned > 1 then
					return true
				end
			end
			return false
		end,
		activeMountCleaned = function(state, sut)
			if state.dirty or state.mode == "unmounted" or #sut.mounts == 0 then
				return false
			end
			return sut.mounts[#sut.mounts].cleaned ~= 0
		end,
	},
	invariants = {
		mountCountMatches = function(state, sut)
			if state.dirty then
				return
			end
			sert.eq(#sut.mounts, state.count, "mount count matches reference")
		end,
		outputMatchesMode = function(state, sut)
			if state.dirty then
				return
			end
			if state.mode == "unmounted" then
				sert(sut.node:peek() == nil, "output is nil when unmounted")
			else
				local active = sut.mounts[#sut.mounts]
				sert(sut.node:peek() == active, "output is the active mount")
				sert.eq(active.exiting:peek(), state.mode == "exiting", "exiting node matches state")
				sert.eq(active.cleaned, 0, "active mount not yet cleaned")
			end
		end,
		retiredMountsCleanedOnce = function(state, sut)
			if state.dirty then
				return
			end
			for i = 1, #sut.mounts - (if state.mode == "unmounted" then 0 else 1) do
				sert.eq(sut.mounts[i].cleaned, 1, `retired mount {i} cleaned once`)
			end
		end,
	},
}, {
	runs = 150,
	length = 16,
	exhaustive = { size = 2 },
})

local PICK_DOMAIN: { any } = { nil, false, "A", "B" }
local function genPickValue(g): any
	return PICK_DOMAIN[g:int(1, #PICK_DOMAIN)]
end

sert.model("pick/fallback · the value matches and a reader re-runs only when it changes", {
	init = function()
		local condSig = Flux.signal(true :: any)
		local trueSig = Flux.signal("A" :: any)
		local falseSig = Flux.signal("B" :: any)
		local valSig = Flux.signal(nil :: any)
		local defSig = Flux.signal("A" :: any)

		local evals = { trueBranch = 0, falseBranch = 0, defBranch = 0 }
		local runs = { pick3 = 0, pick2 = 0, fb = 0 }
		local pick3, pick2, fb
		local rPick3, rPick2, rFb
		local scope = Flux.scope(function()
			pick3 = Flux.pick(condSig, function()
				evals.trueBranch += 1
				return trueSig:get()
			end, function()
				evals.falseBranch += 1
				return falseSig:get()
			end)
			pick2 = Flux.pick(function()
				return condSig:get()
			end, trueSig)
			fb = Flux.fallback(valSig, function()
				evals.defBranch += 1
				return defSig:get()
			end)
			rPick3 = Flux.computed(function()
				runs.pick3 += 1
				return pick3()
			end)
			rPick2 = Flux.computed(function()
				runs.pick2 += 1
				return pick2()
			end)
			rFb = Flux.computed(function()
				runs.fb += 1
				return fb()
			end)
		end)
		sert(rPick3:get() == "A" and runs.pick3 == 1, "pick starts at A")
		sert(rPick2:get() == "A" and runs.pick2 == 1, "pick (omitFalse) starts at A")
		sert(rFb:get() == "A" and runs.fb == 1, "fallback starts at A")

		local state = {
			cond = true :: any,
			whenTrue = "A" :: any,
			whenFalse = "B" :: any,
			val = nil :: any,
			def = "A" :: any,
			expectedPick3 = "A" :: any,
			expectedPick2 = "A" :: any,
			expectedFb = "A" :: any,
			expectedRuns = { pick3 = 1, pick2 = 1, fb = 1 },
			unusedEvaluated = false,
		}
		local sut = {
			scope = scope,
			condSig = condSig,
			trueSig = trueSig,
			falseSig = falseSig,
			valSig = valSig,
			defSig = defSig,
			rPick3 = rPick3,
			rPick2 = rPick2,
			rFb = rFb,
			evals = evals,
			runs = runs,
		}
		return state, sut
	end,
	teardown = function(sut)
		sut.scope:Destroy()
		Flux.flush()
	end,
	actions = {
		setCond = {
			weight = 3,
			gen = genPickValue,
			run = function(sut, value)
				sut.condSig:set(value)
				sut.rPick3:get()
				sut.rPick2:get()
			end,
			next = function(state, value)
				state.cond = value
				local next3 = if state.cond then state.whenTrue else state.whenFalse
				local next2 = if state.cond then state.whenTrue else nil
				if next3 ~= state.expectedPick3 then
					state.expectedRuns.pick3 += 1
					state.expectedPick3 = next3
				end
				if next2 ~= state.expectedPick2 then
					state.expectedRuns.pick2 += 1
					state.expectedPick2 = next2
				end
			end,
		},
		setTrue = {
			weight = 3,
			gen = genPickValue,
			run = function(sut, value, state)
				local beforeEvals = sut.evals.trueBranch
				sut.trueSig:set(value)
				sut.rPick3:get()
				sut.rPick2:get()
				if not state.cond and sut.evals.trueBranch ~= beforeEvals then
					state.unusedEvaluated = true
				end
			end,
			next = function(state, value)
				state.whenTrue = value
				local next3 = if state.cond then state.whenTrue else state.whenFalse
				local next2 = if state.cond then state.whenTrue else nil
				if next3 ~= state.expectedPick3 then
					state.expectedRuns.pick3 += 1
					state.expectedPick3 = next3
				end
				if next2 ~= state.expectedPick2 then
					state.expectedRuns.pick2 += 1
					state.expectedPick2 = next2
				end
			end,
		},
		setFalse = {
			weight = 3,
			gen = genPickValue,
			run = function(sut, value, state)
				local beforeEvals = sut.evals.falseBranch
				sut.falseSig:set(value)
				sut.rPick3:get()
				sut.rPick2:get()
				if state.cond and sut.evals.falseBranch ~= beforeEvals then
					state.unusedEvaluated = true
				end
			end,
			next = function(state, value)
				state.whenFalse = value
				local next3 = if state.cond then state.whenTrue else state.whenFalse
				if next3 ~= state.expectedPick3 then
					state.expectedRuns.pick3 += 1
					state.expectedPick3 = next3
				end
			end,
		},
		setVal = {
			weight = 3,
			gen = genPickValue,
			run = function(sut, value)
				sut.valSig:set(value)
				sut.rFb:get()
			end,
			next = function(state, value)
				state.val = value
				local nextFb = if state.val == nil then state.def else state.val
				if nextFb ~= state.expectedFb then
					state.expectedRuns.fb += 1
					state.expectedFb = nextFb
				end
			end,
		},
		setDefault = {
			weight = 3,
			gen = genPickValue,
			run = function(sut, value, state)
				local beforeEvals = sut.evals.defBranch
				sut.defSig:set(value)
				sut.rFb:get()
				if state.val ~= nil and sut.evals.defBranch ~= beforeEvals then
					state.unusedEvaluated = true
				end
			end,
			next = function(state, value)
				state.def = value
				local nextFb = if state.val == nil then state.def else state.val
				if nextFb ~= state.expectedFb then
					state.expectedRuns.fb += 1
					state.expectedFb = nextFb
				end
			end,
		},
	},
	never = {
		unusedBranchEvaluated = function(state)
			return state.unusedEvaluated
		end,
		spuriousReaderRun = function(state, sut)
			return sut.runs.pick3 ~= state.expectedRuns.pick3
				or sut.runs.pick2 ~= state.expectedRuns.pick2
				or sut.runs.fb ~= state.expectedRuns.fb
		end,
	},
	invariants = {
		pickMatchesReference = function(state, sut)
			sert.eq(sut.rPick3:get(), state.expectedPick3, "pick matches reference")
			sert.eq(sut.runs.pick3, state.expectedRuns.pick3, "pick reader re-runs only when value changes")
		end,
		pickOmitFalseMatchesReference = function(state, sut)
			sert.eq(sut.rPick2:get(), state.expectedPick2, "pick (omitFalse) matches reference")
			sert.eq(sut.runs.pick2, state.expectedRuns.pick2, "pick (omitFalse) reader re-runs only when value changes")
		end,
		fallbackMatchesReference = function(state, sut)
			sert.eq(sut.rFb:get(), state.expectedFb, "fallback matches reference")
			sert.eq(sut.runs.fb, state.expectedRuns.fb, "fallback reader re-runs only when value changes")
		end,
	},
}, {
	runs = 150,
	length = 16,
	exhaustive = { size = 1 },
})

-- For -----------------------------------------------------------------------------------------------------------------

local For = { value = Flux.forValue, index = Flux.forIndex }

test("forValue · duplicates share one mapped instance, with a warning", function()
	local list = new({ "x", "x", "y" })
	local mapRuns = 0
	local mapped = For.value(list, function(indexNode, value)
		mapRuns += 1
		return { value = value }
	end)
	local out
	local warnings = env.warnings(function()
		out = mapped:get()
	end)
	expect(#warnings == 1 and string.find(warnings[1], "duplicate values", 1, true) ~= nil, "warned once")
	expect(out[1] == out[2] and out[1] ~= out[3], "shared mapped instance")
	expect(mapRuns == 2, "mapper runs once per unique value")
	mapped:Destroy()
end)

test("forIndex · node and function elements stay opaque", function()
	local userNode = new(5)
	local items = {}
	local list = new({ userNode })
	local mapped = For.index(list, function(index, item)
		table.insert(items, item)
		return item
	end)
	mapped:get()
	expect(items[1] ~= userNode and items[1]:get() == userNode, "item node boxes the user node")
	list:set({ 42 })
	mapped:get()
	expect(userNode:get() == 5, "reassignment leaves the user node intact")
	list:set({})
	mapped:get()
	expect(getmetatable(userNode) ~= nil, "eviction doesn't destroy the user node")
	mapped:Destroy()
	expect(getmetatable(userNode) ~= nil, "mapper destroy doesn't destroy the user node")

	local fnCalls = 0
	local fnEl = function()
		fnCalls += 1
	end
	local list2 = new({ fnEl })
	local mapped2 = For.index(list2, function(index, item)
		return item:get()
	end)
	expect(mapped2:get()[1] == fnEl and fnCalls == 0, "fn element returned raw, never executed")
end)

test("for · non-table source returns empty array and recovers cleanly after mapFn throws", function()
	local src = new(nil :: any)
	local cleaned = 0
	local nodeDestroyed = 0
	local mapped = For.value(src, function(indexNode, _value)
		indexNode:onDestroy(function()
			nodeDestroyed += 1
		end)
		return function()
			cleaned += 1
		end
	end)
	expect(#mapped:get() == 0, "non-table source maps to empty table")
	src:set({ "row1", "row2" })
	expect(#mapped:get() == 2, "populates once source becomes a table")
	mapped:Destroy()
	expect(nodeDestroyed == 2 and cleaned == 2, "mapper Destroy tears down all row nodes and disposes cached results")

	local shouldThrow = true
	local src2 = new({ "ok", "bad" })
	local mapped2 = For.value(src2, function(_index, val)
		if shouldThrow and val == "bad" then
			error("row boom")
		end
		return string.upper(val)
	end)
	sert.fails(function()
		mapped2:get()
	end, "row boom")

	shouldThrow = false
	src2:set({ "ok", "fixed" })
	local res = mapped2:get()
	expect(#res == 2 and res[1] == "OK" and res[2] == "FIXED", "subsequent evaluation succeeds cleanly")
	mapped2:Destroy()
end)

local function counters(): { maps: number, disposed: number, nodeDestroyed: number, cleaned: number }
	return { maps = 0, disposed = 0, nodeDestroyed = 0, cleaned = 0 }
end

local function makeMapperSpec(map: any, genList: (g: any) -> { any }, keyOf: (list: { any }, i: number) -> any, check)
	local function row(rows: { [any]: any }, key: any)
		local counts = rows[key]
		if counts == nil then
			counts = counters()
			rows[key] = counts
		end
		return counts
	end

	local function readAndCheck(state: any, sut: any)
		local result = sut.mapper:get()
		if not state.changed then
			sert(result == sut.lastResult, "no list change, no rebuild (mapper and teardown reads untracked)")
		end
		sert.eq(#result, #state.current, "one result per element")
		local nextLive = {}
		for i = 1, #state.current do
			local key = keyOf(state.current, i)
			local counts = row(state.rows, key)
			local before = state.live[key]
			if before ~= nil then
				sert(result[i] == before, `the row for {key} keeps its result`)
				sert.eq(counts.maps, counts.disposed + 1, `a surviving row ({key}) is not re-mapped`)
			else
				sert.eq(counts.maps, counts.disposed + 1, `a new row ({key}) is mapped once`)
			end
			nextLive[key] = result[i]
		end
		check(result, state.current)
		state.live = nextLive
		state.changed = false
		sut.lastResult = result
	end

	return {
		init = function()
			local list = Flux.signal({})
			local noise = Flux.signal(0)
			local rows: { [any]: any } = {}
			local mapper
			local owner = Flux.scope(function()
				mapper = map(list, function(a, b, key)
					local counts = row(rows, key)
					counts.maps += 1
					noise:get()
					Flux.cleanup(function()
						counts.cleaned += 1
						noise:get()
					end)
					local node = if Flux.isNode(a) then a else b
					node:onDestroy(function()
						counts.nodeDestroyed += 1
					end)
					return {
						a = a,
						b = b,
						Destroy = function()
							counts.disposed += 1
							noise:get()
						end,
					}
				end)
			end)
			local state = {
				current = {},
				live = {} :: { [any]: any },
				rows = rows,
				changed = true,
			}
			local sut = {
				list = list,
				noise = noise,
				mapper = mapper,
				owner = owner,
				lastResult = nil :: any,
			}
			readAndCheck(state, sut)
			return state, sut
		end,
		teardown = function(sut, state)
			readAndCheck(state, sut)
			sut.mapper:Destroy()
			sut.owner:Destroy()
			Flux.flush()
			for key, counts in state.rows do
				sert.eq(counts.disposed, counts.maps, `{key}: destroying the mapper disposes every row once`)
				sert.eq(counts.nodeDestroyed, counts.maps, `{key}: and destroys every node once`)
				sert.eq(counts.cleaned, counts.maps, `{key}: and runs every cleanup once`)
			end
		end,
		actions = {
			set = {
				weight = 3,
				gen = genList,
				run = function(sut, nextList)
					sut.list:set(table.clone(nextList))
				end,
				next = function(state, nextList)
					state.current = table.clone(nextList)
					state.changed = true
				end,
			},
			noise = {
				weight = 1,
				run = function(sut)
					sut.noise:set(sut.noise:peek() + 1)
				end,
			},
			read = {
				weight = 2,
				run = function(sut, _arg, state)
					readAndCheck(state, sut)
				end,
			},
		},
		never = {
			teardownCountExceedsMaps = function(state)
				for _, counts in state.rows do
					if
						counts.disposed > counts.maps
						or counts.nodeDestroyed > counts.maps
						or counts.cleaned > counts.maps
					then
						return true
					end
				end
				return false
			end,
		},
		invariants = {
			rowLifecyclesBalanced = function(state, sut)
				if state.changed then
					return
				end
				sert.eq(#sut.lastResult, #state.current, "one result per element")
				check(sut.lastResult, state.current)
				for key, counts in state.rows do
					local alive = if state.live[key] ~= nil then 1 else 0
					sert.eq(counts.disposed, counts.maps - alive, `{key}: each removed row's result disposed once`)
					sert.eq(counts.nodeDestroyed, counts.maps - alive, `{key}: and its node destroyed once`)
					sert.eq(counts.cleaned, counts.maps - alive, `{key}: and its cleanup run once`)
				end
			end,
		},
	}
end

local FOR_VALUE_POOL = { "a", "b", "c", "d" }
sert.model(
	"forValue · rows follow unique values: mapped once per new value, torn down once",
	makeMapperSpec(function(source, mapFn)
		return Flux.forValue(source, function(indexNode, value)
			return mapFn(indexNode, value, value)
		end)
	end, function(g)
		local pool, out = table.clone(FOR_VALUE_POOL), {}
		for _ = 1, g:int(0, math.min(#FOR_VALUE_POOL, g.size + 1)) do
			table.insert(out, table.remove(pool, g:int(1, #pool)))
		end
		return out
	end, function(list, i)
		return list[i]
	end, function(result, list)
		for i, value in list do
			sert(result[i].b == value and result[i].a:peek() == i, `row {i} holds {value} with index {i}`)
		end
	end),
	{
		runs = 150,
		length = 12,
		exhaustive = { size = 2 },
	}
)

sert.model(
	"forIndex · rows follow positions: mapped once per new slot, torn down once",
	makeMapperSpec(function(source, mapFn)
		return Flux.forIndex(source, function(index, itemNode)
			return mapFn(index, itemNode, index)
		end)
	end, function(g)
		return g:list(function(g)
			return g:int(1, 3)
		end, 0, math.min(4, g.size + 1))
	end, function(_, i)
		return i
	end, function(result, list)
		for i, value in list do
			sert(result[i].a == i and result[i].b:peek() == value, `slot {i} holds {value}`)
		end
	end),
	{
		runs = 150,
		length = 12,
		exhaustive = { size = 2 },
	}
)

-- Selector ------------------------------------------------------------------------------------------------------------

test("selector · unobserved keys are swept once enough new keys are read", function()
	local active = new("kept")
	local sel = Flux.selector(active)
	local seenKept, seenMany, seenAgain
	local gone = Flux.effect(function()
		sel("gone")
	end)
	local kept = Flux.effect(function()
		seenKept = sel("kept")
	end)
	flush()
	gone:Destroy()

	local many = Flux.effect(function()
		local n = 0
		for k = 1, 100 do
			if not sel(k) then
				n += 1
			end
		end
		seenMany = n
	end)
	flush()
	expect(seenMany == 100, "every key read false")
	expect(sel._nodes.gone == nil, "the unobserved key was swept")
	expect(seenKept == true, "an observed key reads right after the sweep")

	active(7)
	flush()
	expect(seenMany == 99 and seenKept == false, "values flip correctly after a sweep")
	expect(sel:get("gone") == false, "an untracked read of a swept key is right")
	local again = Flux.effect(function()
		seenAgain = sel("gone")
	end)
	flush()
	expect(seenAgain == false, "a swept key is recreated when read again")
	active("gone")
	flush()
	expect(seenAgain == true, "and the new node flips")
	kept:Destroy()
	many:Destroy()
	again:Destroy()
	sel:Destroy()
end)

test("selector · a custom equals re-tests every key after an in-place update", function()
	local row = { id = 1 }
	local source = new(row)
	local sel = Flux.selector(source, function(value, key)
		return value.id == key
	end)
	local reads, seen = {}, {}
	for k = 1, 2 do
		reads[k] = Flux.effect(function()
			seen[k] = sel(k)
		end)
	end
	flush()
	expect(seen[1] == true and seen[2] == false, "seeded by the comparator")
	row.id = 2
	source:update()
	flush()
	expect(seen[1] == false and seen[2] == true, "the same value, mutated, is re-tested")
	for k = 1, 2 do
		reads[k]:Destroy()
	end
	sel:Destroy()
end)

local function selectorRef(custom: boolean, value: number?, key: number): boolean
	if custom then
		return value ~= nil and value % 3 == key % 3
	end
	return value == key
end

local function genSelectorValue(g): number?
	local n = g:int(0, 5)
	return if n == 0 then nil else n
end

local function checkSelectorFlush(state: any, sut: any, where: string)
	Flux.flush()
	local value = sut.source:peek()
	for _, reader in sut.readers do
		local expected = selectorRef(reader.custom, value, reader.key)
		sert.eq(reader.value, expected, `{where}: reader of key {reader.key} (custom: {reader.custom})`)
		if reader.checked ~= nil then
			local flipped = expected ~= reader.checked
			local reran = reader.runs - reader.checkedRuns
			if reran > state.maxReran then
				state.maxReran = reran
			end
			sert(reran <= 1, `{where}: key {reader.key} re-ran at most once`)
			if not flipped and not state.earlyRun then
				if reran ~= 0 then
					state.spuriousRun = true
				end
				sert(reran == 0, `{where}: key {reader.key} did not flip, so did not re-run`)
			end
		end
		reader.checked, reader.checkedRuns = expected, reader.runs
	end
	state.earlyRun = false
	state.dirty = false
end

sert.model("selector · per-key readers match the reference and only flipped keys re-run", {
	init = function()
		local source = Flux.signal(1 :: number?)
		local noise = Flux.signal(0)
		local sut: any = {
			source = source,
			noise = noise,
			getterRuns = 0,
			selStd = nil,
			selCustom = nil,
			selScope = nil,
			readerScope = nil,
			readers = {},
		}
		sut.selScope = Flux.scope(function()
			sut.selStd = Flux.selector(source)
			sut.selCustom = Flux.selector(function()
				sut.getterRuns += 1
				return source:get()
			end, function(v, k)
				return selectorRef(true, v, k)
			end)
		end)
		Flux.flush()
		sut.readerScope = Flux.scope(function() end)
		local state = {
			value = 1 :: number?,
			dirty = false,
			earlyRun = false,
			maxReran = 0,
			spuriousRun = false,
		}
		return state, sut
	end,
	teardown = function(sut, state)
		checkSelectorFlush(state, sut, "end")
		sut.selStd:Destroy()
		sut.selScope:Destroy()
		sut.source:set((sut.source:peek() or 0) + 1)
		Flux.flush()
		for _, reader in sut.readers do
			sert.eq(reader.runs, reader.checkedRuns, `key {reader.key}: a destroyed selector re-runs no reader`)
		end
		sert(not pcall(sut.selStd, 1), "a read after Destroy errors (std)")
		sert(not pcall(sut.selCustom, 1), "a read after Destroy errors (custom)")
		sut.readerScope:Destroy()
		sut.selCustom:Destroy()
		Flux.flush()
	end,
	actions = {
		set = {
			weight = 4,
			gen = genSelectorValue,
			run = function(sut, value)
				sut.source:set(value)
			end,
			next = function(state, value)
				state.value = value
				state.dirty = true
			end,
		},
		noise = {
			weight = 1,
			run = function(sut, _arg, state)
				checkSelectorFlush(state, sut, "before noise")
				sut.noise:set(sut.noise:peek() + 1)
				local before = sut.getterRuns
				checkSelectorFlush(state, sut, "noise")
				sert.eq(sut.getterRuns, before, "an unrelated write does not re-run the source getter")
			end,
		},
		peek = {
			weight = 2,
			gen = function(g)
				return { key = g:int(1, 5), tracked = g:bool(), custom = g:bool() }
			end,
			run = function(sut, arg, state)
				local sel = if arg.custom then sut.selCustom else sut.selStd
				local expected = selectorRef(arg.custom, sut.source:peek(), arg.key)
				if arg.tracked then
					local probe = Flux.computed(function()
						return sel(arg.key)
					end)
					sert.eq(probe:get(), expected, `a fresh tracked read of key {arg.key} is current before the flush`)
					probe:Destroy()
				else
					sert.eq(
						sel:get(arg.key),
						expected,
						`an untracked read of key {arg.key} is current before the flush`
					)
				end
				state.earlyRun = true
			end,
		},
		reader = {
			weight = 3,
			gen = function(g)
				return { key = g:int(1, 5), custom = g:bool() }
			end,
			run = function(sut, arg)
				local sel = if arg.custom then sut.selCustom else sut.selStd
				local reader = Model.reader(sut.readerScope, true, function()
					return sel(arg.key)
				end)
				reader.key = arg.key
				reader.custom = arg.custom
				table.insert(sut.readers, reader)
			end,
			next = function(state)
				state.dirty = true
			end,
		},
		drop = {
			weight = 1,
			gen = function(g)
				return g:int(1, 8)
			end,
			run = function(sut, index)
				if #sut.readers > 0 then
					local i = math.clamp(index, 1, #sut.readers)
					table.remove(sut.readers, i).node:Destroy()
				end
			end,
		},
		flush = {
			weight = 3,
			run = function(sut, _arg, state)
				checkSelectorFlush(state, sut, "flush")
			end,
		},
	},
	never = {
		readerOverran = function(state)
			return state.maxReran > 1
		end,
		unflippedReaderRan = function(state)
			return state.spuriousRun
		end,
	},
	invariants = {
		readersMatchReferenceWhenFlushed = function(state, sut)
			if state.dirty then
				return
			end
			for _, reader in sut.readers do
				if reader.checked ~= nil then
					local expected = selectorRef(reader.custom, state.value, reader.key)
					sert.eq(reader.value, expected, `reader of key {reader.key} matches reference`)
				end
			end
		end,
	},
}, {
	runs = 150,
	length = 16,
	exhaustive = { size = 2 },
})

local flickerTest = if env.IS_ROBLOX and game:GetService("Players").LocalPlayer == nil then sert.skip else test
flickerTest("conditional & list layout · transitions settle cleanly without visibility or rect flicker", function()
	local Layout = sert.roblox.Layout
	local Flicker = sert.roblox.Flicker
	local UDim2 = env.UDim2
	local rs = if env.IS_ROBLOX then game:GetService("RunService") else env.engine.game:GetService("RunService")

	Flicker.drive(env.frame)
	sert.defer(function()
		Flicker.drive(nil)
	end)

	local showBanner = Flux.signal(true)
	local items = Flux.signal({ "Alpha", "Beta" })
	local bannerFrame: Frame? = nil
	local rowFrames: { [string]: Frame } = {}

	local screenParent = if env.IS_ROBLOX
		then (if game:GetService("Players").LocalPlayer
			then game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			else env.workspace)
		else env.engine.LocalPlayer.PlayerGui
	local screen
	local scope = Flux.scope(function()
		screen = Flux.new("ScreenGui")({
			Parent = screenParent,
			Enabled = true,
			Flux.new("Frame")({
				Name = "Column",
				Position = UDim2.fromOffset(16, 16),
				Size = UDim2.fromOffset(240, 200),
				Flux.list({ gap = 6 }),
				Flux.show(showBanner, function()
					local f = Flux.new("Frame")({
						Name = "Banner",
						Size = UDim2.fromOffset(240, 28),
					})
					bannerFrame = f
					return f
				end),
				Flux.forValue(items, function(indexNode, label)
					local row = Flux.new("Frame")({
						Name = `Row_{label}`,
						LayoutOrder = indexNode,
						Size = UDim2.fromOffset(240, 24),
					})
					rowFrames[label] = row
					return row
				end),
			}),
		})
	end)
	sert.defer(function()
		scope:Destroy()
		screen:Destroy()
		Flux.flush()
	end)

	local settled, moving = Layout.settle(screen, { step = env.frame, lead = 1, stable = 2 })
	expect(settled, `initial conditional/list layout settled ({tostring(moving)})`)
	expect(bannerFrame ~= nil and Layout.visible(bannerFrame :: any, screen), "banner is visible")
	expect(rowFrames.Alpha ~= nil and Layout.visible(rowFrames.Alpha, screen), "Row_Alpha is visible")

	local enterResult = Flicker.around(function()
		return rowFrames.Gamma
	end, function()
		items:set({ "Alpha", "Beta", "Gamma" })
	end, { runService = rs, stable = 2, label = "Row_Gamma enter" })
	Flicker.expect(enterResult, "Row_Gamma enter")

	local reorderResult = Flicker.around(function()
		return rowFrames.Beta
	end, function()
		showBanner:set(false)
	end, { runService = rs, stable = 2, motion = 34, label = "Row_Beta shift on banner hide" })
	Flicker.expect(reorderResult, "Row_Beta shift on banner hide")

	local settledAfter, movingAfter = Layout.settle(screen, { step = env.frame, lead = 1, stable = 2 })
	expect(settledAfter, `post-transition layout settled ({tostring(movingAfter)})`)
end)

test("selector · a key read only by an unobserved computed stays right across a sweep", function()
	local active = new("a")
	local sel = Flux.selector(active)
	local lazy = Flux.computed(function()
		return sel("x")
	end)
	expect(lazy() == false, "not selected")
	local many = Flux.effect(function()
		for k = 1, 100 do
			sel(k)
		end
	end)
	flush()
	expect(sel._nodes.x == nil, "the key read only by an unobserved computed was swept")
	active("x")
	flush()
	expect(lazy() == true, "the computed re-runs on its next read and sees the new selection")
	active("a")
	flush()
	expect(lazy() == false, "and keeps following it")
	many:Destroy()
	sel:Destroy()
end)

local lastDynamicControls: {
	showAlert: any,
	tab: any,
	valueItems: any,
	indexItems: any,
} = nil :: any

sert.laws.ui("conditional · dynamic forValue, forIndex, show, and switch UI reconciliation", {
	noTextOverflow = not env.IS_ROBLOX,
	mount = function(_uiEnv, parent, viewport)
		local UDim2 = env.UDim2
		local hostParent, cleanHost = env.mountUi(parent, viewport)
		local showAlert = Flux.signal(true)
		local tab = Flux.signal("value")
		local valueItems = Flux.signal({ "Sword", "Shield", "Potion" })
		local indexItems = Flux.signal({ 10, 20, 30 })

		local root: Frame
		local scope = Flux.scope(function()
			local w = math.min(viewport.X - 24, 420)
			local h = math.min(viewport.Y - 24, 360)
			root = Flux.new("Frame")({
				Name = "DynamicPanel",
				Parent = hostParent,
				Position = UDim2.fromOffset(12, 12),
				Size = UDim2.fromOffset(w, h),
				Flux.padding(10),
				Flux.list({ direction = "y", gap = 6 }),
				Flux.show(showAlert, function()
					return Flux.new("Frame")({
						Name = "AlertBanner",
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 28),
						Flux.new("TextLabel")({
							Name = "AlertText",
							Size = UDim2.fromScale(1, 1),
							Text = "System Online",
							TextSize = 12,
							TextScaled = true,
						}),
					})
				end),
				Flux.switch(tab)({
					value = function()
						return Flux.new("Frame")({
							Name = "ValueList",
							LayoutOrder = 2,
							Size = UDim2.new(1, 0, 0, 140),
							Flux.list({ direction = "y", gap = 4 }),
							Flux.forValue(valueItems, function(idx, item)
								return Flux.new("Frame")({
									Name = `Val_{item}`,
									LayoutOrder = idx,
									Size = UDim2.new(1, 0, 0, 24),
									Flux.new("TextLabel")({
										Size = UDim2.fromScale(1, 1),
										Text = function()
											return `#{idx()} {item}`
										end,
										TextSize = 12,
										TextScaled = true,
									}),
								})
							end),
						})
					end,
					index = function()
						return Flux.new("Frame")({
							Name = "IndexList",
							LayoutOrder = 2,
							Size = UDim2.new(1, 0, 0, 140),
							Flux.list({ direction = "y", gap = 4 }),
							Flux.forIndex(indexItems, function(idx, valNode)
								return Flux.new("Frame")({
									Name = `Idx_{idx}`,
									LayoutOrder = idx,
									Size = UDim2.new(1, 0, 0, 24),
									Flux.new("TextLabel")({
										Size = UDim2.fromScale(1, 1),
										Text = function()
											return `Slot {idx}: {valNode()}`
										end,
										TextSize = 12,
										TextScaled = true,
									}),
								})
							end),
						})
					end,
				}),
			})
		end)
		flush()
		lastDynamicControls = {
			showAlert = showAlert,
			tab = tab,
			valueItems = valueItems,
			indexItems = indexItems,
		}
		sert.defer(function()
			scope:Destroy()
			root:Destroy()
			cleanHost()
			flush()
		end)
		return root
	end,
	check = function(_uiEnv, root, vp)
		local RobloxLayout = sert.roblox.Layout
		local controls = lastDynamicControls
		local checkText = not env.IS_ROBLOX
		RobloxLayout.audit(root, { viewport = vp.size, fitsParent = true, noTextOverflow = checkText })

		local valList = root:FindFirstChild("ValueList") :: Frame
		expect(valList ~= nil, "ValueList initially mounted")
		local sword = valList:FindFirstChild("Val_Sword") :: Frame
		local shield = valList:FindFirstChild("Val_Shield") :: Frame
		local potion = valList:FindFirstChild("Val_Potion") :: Frame
		RobloxLayout.spacing({ sword, shield, potion }, "Y", 4)
		RobloxLayout.aligned({ sword, shield, potion }, "Left")

		-- Reorder + insert + hide banner
		controls.showAlert:set(false)
		controls.valueItems:set({ "Potion", "Bow", "Sword" })
		flush()
		RobloxLayout.audit(root, { viewport = vp.size, fitsParent = true, noTextOverflow = checkText })
		expect(root:FindFirstChild("AlertBanner") == nil, "AlertBanner unmounted when showAlert is false")
		local bow = valList:FindFirstChild("Val_Bow") :: Frame
		expect(valList:FindFirstChild("Val_Shield") == nil, "Val_Shield unmounted")
		RobloxLayout.spacing({ potion, bow, sword }, "Y", 4)

		-- Switch to forIndex tab and mutate
		controls.tab:set("index")
		controls.indexItems:set({ 100, 200, 300, 400 })
		flush()
		RobloxLayout.audit(root, { viewport = vp.size, fitsParent = true, noTextOverflow = checkText })
		local idxList = root:FindFirstChild("IndexList") :: Frame
		expect(idxList ~= nil, "IndexList mounted on switch")
		local i1 = idxList:FindFirstChild("Idx_1") :: Frame
		local i2 = idxList:FindFirstChild("Idx_2") :: Frame
		local i3 = idxList:FindFirstChild("Idx_3") :: Frame
		local i4 = idxList:FindFirstChild("Idx_4") :: Frame
		RobloxLayout.spacing({ i1, i2, i3, i4 }, "Y", 4)
		RobloxLayout.aligned({ i1, i2, i3, i4 }, "Left")
	end,
})

sert.laws.differential("conditional · forValue and forIndex reconciliation matches functional oracle", {
	gen = sert.gen.list(sert.gen.list(sert.gen.pick({ "A", "B", "C", "D", "E", "F" }), 0, 5), 1, 8),
	oracle = function(steps: { { string } })
		local final = steps[#steps]
		local byVal: { string } = {}
		local seen: { [string]: boolean } = {}
		local rank = 0
		for _, item in final do
			if not seen[item] then
				seen[item] = true
				rank += 1
				table.insert(byVal, `{rank}:{item}`)
			end
		end
		local byIdx: { string } = {}
		for i, item in final do
			table.insert(byIdx, `{i}={item}`)
		end
		return `{table.concat(byVal, ",")}|{table.concat(byIdx, ",")}`
	end,
	sut = function(steps: { { string } })
		local valSig = Flux.signal({} :: { string })
		local idxSig = Flux.signal({} :: { string })
		local valContainer: Frame
		local idxContainer: Frame
		local scope = Flux.scope(function()
			valContainer = Flux.new("Frame")({
				Flux.forValue(valSig, function(idxNode, val)
					return Flux.new("TextLabel")({
						Name = val,
						LayoutOrder = idxNode,
						Text = function()
							return `{idxNode()}:{val}`
						end,
					})
				end),
			})
			idxContainer = Flux.new("Frame")({
				Flux.forIndex(idxSig, function(idx, valNode)
					return Flux.new("TextLabel")({
						Name = `Slot_{idx}`,
						LayoutOrder = idx,
						Text = function()
							return `{idx}={valNode()}`
						end,
					})
				end),
			})
		end)
		for _, step in steps do
			local uniq: { string } = {}
			local seen: { [string]: boolean } = {}
			for _, v in step do
				if not seen[v] then
					seen[v] = true
					table.insert(uniq, v)
				end
			end
			valSig:set(uniq)
			idxSig:set(step)
			flush()
		end
		local valChildren = valContainer:GetChildren()
		table.sort(valChildren, function(a: any, b: any)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local gotVal: { string } = {}
		for _, c in valChildren do
			table.insert(gotVal, (c :: TextLabel).Text)
		end

		local idxChildren = idxContainer:GetChildren()
		table.sort(idxChildren, function(a: any, b: any)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local gotIdx: { string } = {}
		for _, c in idxChildren do
			table.insert(gotIdx, (c :: TextLabel).Text)
		end

		scope:Destroy()
		valContainer:Destroy()
		idxContainer:Destroy()
		flush()
		return `{table.concat(gotVal, ",")}|{table.concat(gotIdx, ",")}`
	end,
}, { runs = 60 })

return {}
