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
local expectError = sert.fails
local flush = Flux.flush

test("model · wraps a node and isModel / modelNode inspect it", function()
	expectError(function()
		Flux.model("not a node")
	end, "expects a reactive node")

	local sig = Flux.signal("abc")
	local wrapped = Flux.model(sig)
	expect(Flux.isModel(wrapped) == true, "isModel recognizes a Flux.model value")
	expect(Flux.isModel(sig) == false and Flux.isModel("abc") == false, "isModel is false for non-model values")
	expect(Flux.modelNode(wrapped) == sig, "modelNode extracts the underlying node")
	expect(Flux.modelNode(sig) == nil and Flux.modelNode(nil) == nil, "modelNode returns nil for non-model values")
end)

test("property & call · validate non-instance arguments", function()
	expectError(function()
		Flux.property("not an instance" :: any, "Name")
	end, "Flux.property expects an Instance")
	expectError(function()
		Flux(123, "Name")
	end, "only an Instance takes a property name")
end)

rtest("property · follows an instance property reactively", function()
	local label = Instance.new("TextLabel")
	label.Text = "initial"
	local prop = Flux.property(label, "Text")
	local viaCall = Flux(label, "Text")
	expect(prop:get() == "initial" and viaCall:get() == "initial", "seeded with initial property value")
	label.Text = "changed"
	task.wait()
	flush()
	expect(prop:get() == "changed" and viaCall:get() == "changed", "updates when property changes")
	prop:Destroy()
	viaCall:Destroy()
	label:Destroy()
end)

rtest("property · follows an instance attribute reactively via $ and _attr_ prefixes", function()
	local frame = Instance.new("Frame")
	frame:SetAttribute("Score", 10)
	local attr = Flux.property(frame, "$Score")
	local attrUnderscore = Flux.property(frame, "_attr_Score")
	local viaCall = Flux(frame, "$Score")
	expect(
		attr:get() == 10 and attrUnderscore:get() == 10 and viaCall:get() == 10,
		"seeded with initial attribute value"
	)
	frame:SetAttribute("Score", 25)
	task.wait()
	flush()
	expect(attr:get() == 25 and attrUnderscore:get() == 25 and viaCall:get() == 25, "updates when attribute changes")
	attr:Destroy()
	attrUnderscore:Destroy()
	viaCall:Destroy()
	frame:Destroy()
end)

rtest("property · follows an instance tag reactively via # and _tag_ prefixes", function()
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
	task.wait()
	flush()
	expect(hasEnemy:get() == false and hasEnemyUnderscore:get() == false, "tag added to another instance is ignored")

	frame:AddTag("Enemy")
	task.wait()
	flush()
	expect(
		hasEnemy:get() == true and hasEnemyUnderscore:get() == true and viaCall:get() == true,
		"updates to true when tag is added"
	)

	-- Unparenting fires GetInstanceRemovedSignal, but HasTag("Enemy") is still true
	frame.Parent = nil
	task.wait()
	flush()
	expect(hasEnemy:get() == true, "unparenting an instance does not falsely clear its #Tag node")
	frame.Parent = workspace

	frame:RemoveTag("Enemy")
	task.wait()
	flush()
	expect(
		hasEnemy:get() == false and hasEnemyUnderscore:get() == false and viaCall:get() == false,
		"updates to false when tag is removed"
	)

	hasEnemy:Destroy()
	hasEnemyUnderscore:Destroy()
	frame:AddTag("Enemy")
	task.wait()
	flush()
	expect(hasEnemy:get() == nil and viaCall:get() == true, "destroyed tag node stops following")

	viaCall:Destroy()
	hasPre:Destroy()
	other:Destroy()
	frame:Destroy()
end)

rtest("property & call · reject non-string or empty prefix names on an Instance", function()
	local frame = Instance.new("Frame")
	expectError(function()
		Flux.property(frame, 123 :: any)
	end, "expects a property")
	expectError(function()
		Flux(frame, 123 :: any)
	end, "expects a property")
	expectError(function()
		Flux.property(frame, "$")
	end, 'after "$" cannot be empty')
	expectError(function()
		Flux.property(frame, "#")
	end, 'after "#" cannot be empty')
	expectError(function()
		Flux.property(frame, "_attr_")
	end, 'after "_attr_" cannot be empty')
	expectError(function()
		Flux.property(frame, "_tag_")
	end, 'after "_tag_" cannot be empty')
	frame:Destroy()
end)

return {}
