--!strict
return {
	--[[
	Global on/off switch for the automatic per-class defaults system. When `true` (the default), every Roblox
	[`Instance`](https://create.roblox.com/docs/reference/engine/classes/Instance) built by
	[`Flux.new`](https://flux.kohl.gg/guide/roblox/creation#the-flux-new-function) has its matching `Flux.Defaults`
	entries applied first. Set it to `false` to opt out globally and get raw, unstyled instances.

	[Open Documentation](https://flux.kohl.gg/guide/roblox/defaults#disabling-defaults)
	]]
	defaults = true,
}
