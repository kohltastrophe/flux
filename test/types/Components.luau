--!strict
--[[
	Compile-time checks for the component authoring API. `luau-lsp analyze` type-checks this file during lint; it is
	never run. A regression in Flux.Props, Component, Children, split, scope, or cleanup surfaces here as a lint
	error.
]]

local Flux = require("../../src")

type ButtonProps = Flux.Props<"TextButton", {
	label: Flux.Reactive<string>,
	variant: Flux.Reactive<"filled" | "tonal">?,
	onClick: (() -> ())?,
}>

local OWN: { "label" | "variant" | "onClick" } = { "label", "variant", "onClick" }

local Button: Flux.Component<ButtonProps, TextButton> = function(props: ButtonProps): TextButton
	local own, rest = Flux.split(props, OWN)
	return Flux.edit(Flux.new("TextButton")({
		Text = own.label,
		Activated = function()
			local onClick = own.onClick
			if onClick then
				onClick()
			end
		end,
	}))(rest)
end

local children: Flux.Children = {
	Button({
		label = "Save",
		variant = "tonal",
		Size = UDim2.fromOffset(120, 40),
		onClick = function() end,
	}),
	Flux.show(true, function()
		return Flux.new("Frame")({})
	end),
	function(instance: Instance)
		print(instance.Name)
	end,
}

local _panel: Frame = Flux.new("Frame")({ Name = "Panel", children })

-- A scope body may return nothing, and a stored `() -> ()` (an unsubscribe) is a valid cleanup.
local unsubscribe: () -> () = function() end
local _scope: Flux.Node<any> = Flux.scope(function()
	Flux.cleanup(unsubscribe)
end)

local stats = Flux.store({ hp = 100, name = "Hero" })
local _hp: number = stats.hp
stats.name = "Renamed"
assert(stats.name == "Renamed")

-- Flux.Namespace supports dependency injection and frozen parent barrels (`table.freeze`) while keeping callability.
local barrel: { read Flux: Flux.Namespace } = table.freeze({ Flux = Flux })
local _nsCall: Flux.Node<any> = barrel.Flux(0)
local _nsSync: Flux.SyncSignal<number> = barrel.Flux.Sync("Count", 0)
local _nsFrame: Frame = barrel.Flux.new("Frame")({})

type Merged = Flux.Merge<{ a: number, b: string }, { b: boolean, c: number }>
local _merged: Merged = { a = 1, b = true, c = 2 }

local SCHEMA_BASE = Flux.own({
	label = Flux.prop() :: Flux.Reactive<string>,
})
local SCHEMA_OWN = Flux.own(SCHEMA_BASE, {
	searchable = Flux.prop() :: boolean?,
	variant = Flux.prop() :: Flux.Reactive<"solid" | "tonal">?,
})
type SchemaProps = Flux.Props<"Frame", typeof(SCHEMA_OWN)>
local function SchemaComp(props: SchemaProps): Frame
	local own, rest = Flux.split(props, SCHEMA_OWN)
	local _label: Flux.Reactive<string> = own.label
	local _searchable: boolean? = own.searchable
	local _variant: Flux.Reactive<"solid" | "tonal">? = own.variant
	return Flux.edit(Flux.new("Frame")({}))(rest)
end
local _schemaInst: Frame = SchemaComp({ label = "Search", searchable = true, variant = "tonal", Name = "Box" })

-- Optional props (`Props?`) and intersection props (`A & B`) split cleanly without losing field types.
local function OptSchemaComp(props: SchemaProps?): Frame
	local own, rest = Flux.split(props, SCHEMA_OWN)
	local _optLabel: Flux.Reactive<string>? = own.label
	local _optVariant: Flux.Reactive<"solid" | "tonal">? = own.variant
	return Flux.edit(Flux.new("Frame")({}))(rest)
end
local _optInst: Frame = OptSchemaComp(nil)

type IntersectedProps = Flux.Props<"Frame"> & { label: Flux.Reactive<string>, count: number? }
local function IntersectComp(props: IntersectedProps): Frame
	local own, rest = Flux.split(props, { label = true, count = true })
	local _iLabel: Flux.Reactive<string> = own.label
	local _iCount: number? = own.count
	return Flux.edit(Flux.new("Frame")({}))(rest)
end
local interInput: IntersectedProps = ({ label = "Hi", count = 2, Name = "Inter" } :: any) :: IntersectedProps
local _interInst: Frame = IntersectComp(interInput)
local _partialInter: Flux.Partial<IntersectedProps> = {}

local clonedOpt = Flux.split(nil :: SchemaProps?)
local _clonedName: Flux.Reactive<string>? = clonedOpt.Name

return nil
