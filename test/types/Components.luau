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

return nil
