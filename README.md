<div align="right">
<a href="https://flux.kohl.gg"><img align="left" src=".luaudocs/public/logo.svg" width="128" alt="Flux"></a>
<a href="https://flux.kohl.gg"><picture><source media="(prefers-color-scheme: dark)" srcset=".github/img/link-docs-dark.svg"><img alt="Docs" src=".github/img/link-docs.svg"></picture></a>
<a href="https://github.com/kohltastrophe/flux/releases"><picture><source media="(prefers-color-scheme: dark)" srcset=".github/img/link-download-dark.svg"><img alt="Download" src=".github/img/link-download.svg"></picture></a>
<a href="https://create.roblox.com/store/asset/18506925834"><picture><source media="(prefers-color-scheme: dark)" srcset=".github/img/link-creator-dark.svg"><img alt="Get it on the Creator Marketplace" src=".github/img/link-creator.svg"></picture></a>
</div>
<br/>
<br/>
<br/>
<br/>

<div align="center">

# Be lazy. Do more. Go fast.

_Flux is a reactive UI library for Luau. It's strictly typed for accurate autocomplete, batches updates once per frame, and keeps syntax terse enough to read like plain Luau._

[![CI](https://img.shields.io/github/actions/workflow/status/kohltastrophe/flux/ci.yml?style=for-the-badge)](https://github.com/kohltastrophe/flux/actions/workflows/ci.yml) [![Coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/kohltastrophe/flux/badges/coverage.json&style=for-the-badge)](https://github.com/kohltastrophe/flux/actions/workflows/ci.yml) [![License](https://img.shields.io/github/license/kohltastrophe/flux?style=for-the-badge)](LICENSE.md) ![GitHub Release](https://img.shields.io/github/v/release/kohltastrophe/flux?style=for-the-badge)

---

<picture><source media="(prefers-color-scheme: dark)" srcset=".github/img/h3-lazy-dark.svg"><img alt="Be lazy yet effective" src=".github/img/h3-lazy.svg"></picture>

<picture><img src=".luaudocs/public/autocomplete.min.svg" width="396" alt="Editor autocomplete for Flux: choosing the Frame class, completing the inherited Name property, and a type error on an invalid property."></picture>

</div>

Flux leans on Luau's type checker so your editor does the heavy lifting. When you declare a `TextLabel` or `Frame`, you get autocomplete for every valid property, event, and expected type.

---

<div align ="center">

<picture><source media="(prefers-color-scheme: dark)" srcset=".github/img/h3-more-dark.svg"><img alt="Do more with less" src=".github/img/h3-more.svg"></picture>

<div align="left">

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

local count = Flux(0)

new "ScreenGui" {
	Parent = playerGui,

	new "TextButton" {
		Size = UDim2.fromOffset(200, 50),
		Text = function() return `Clicks: {count}` end,
		Activated = function() count(count + 1) end,
	},
}
```

Every reactive node supports `__call` and <b>operator overloading</b>, so reading and writing state takes no extra ceremony. Call `count()` to read and `count(1)` to write. Arithmetic, comparison, and string interpolation track dependencies automatically, so reactive expressions read like normal Luau.

</div>

---

<picture><source media="(prefers-color-scheme: dark)" srcset=".github/img/h3-fast-dark.svg"><img alt="Go fast waste nothing" src=".github/img/h3-fast.svg"></picture>

<a href="https://github.com/kohltastrophe/luau-reactivity-benchmark"><img src="https://raw.githubusercontent.com/kohltastrophe/luau-reactivity-benchmark/assets/chart-small.svg" width="100%" alt="Luau reactivity benchmark"></a>

</div>

Dormant computations sleep with zero subscriptions until something observes them. Active bindings batch updates once per frame and run in dependency order. If a computed value doesn't change, downstream bindings don't re-run.

---

## Batteries Included

Flux includes the building blocks you need for Roblox interfaces:

- **Reactive State:** Track values with [`signal`](https://flux.kohl.gg/guide/concepts/signals), [`computed`](https://flux.kohl.gg/guide/concepts/computeds), [`effect`](https://flux.kohl.gg/guide/concepts/effects), and nested [`store`](https://flux.kohl.gg/guide/concepts/stores) proxies.
- **Networked State:** Replicate server-authoritative and per-player signals to clients with [`Flux.Sync`](https://flux.kohl.gg/guide/concepts/sync).
- **Declarative Instances:** Build trees with [`new`](https://flux.kohl.gg/guide/roblox/creation) or wire up existing templates with [`edit`](https://flux.kohl.gg/guide/roblox/hydration).
- **Scoped Cleanup:** Wrap a tree in [`scope`](https://flux.kohl.gg/guide/concepts/scopes) to tear down all of its instances and reactions with one `Destroy` call.
- **Control Flow & Lists:** Render conditional branches with [`show`](https://flux.kohl.gg/guide/concepts/conditionals) and [`switch`](https://flux.kohl.gg/guide/concepts/conditionals#switching-between-many-branches), or map dynamic lists with [`forValue`](https://flux.kohl.gg/guide/concepts/mapping).
- **Built-in Motion:** Animate any state with physics [springs](https://flux.kohl.gg/guide/motion/spring), [tweens](https://flux.kohl.gg/guide/motion/tween), or perceptual [color](https://flux.kohl.gg/guide/motion/color) blending.
- **UI Utilities:** Read screen [breakpoints](https://flux.kohl.gg/guide/utilities/responsive), track [pointer and gamepad interactions](https://flux.kohl.gg/guide/utilities/interact), and drop in terse [layout constraints](https://flux.kohl.gg/guide/utilities/layout).
- **Async & Testing:** Run cancellable [`async`](https://flux.kohl.gg/guide/concepts/async) tasks, catch failures with [`safe`](https://flux.kohl.gg/guide/tips/errors), and step a virtual [`Clock`](https://flux.kohl.gg/guide/tips/testing) in tests.

## Installation

Download the latest `Flux.rbxm` from [Releases](https://github.com/kohltastrophe/flux/releases), drop it into Roblox Studio, and place the module in `ReplicatedStorage`. Rojo users can sync the `src` directory directly.

Read the **[Getting Started](https://flux.kohl.gg/guide/introduction/getting-started)** guide to build your first component.

## Acknowledgments

Flux is inspired by:

- **[Vide](https://github.com/centau/vide)**
- **[SolidJS](https://github.com/solidjs/solid)**
- **[Reactively](https://github.com/milomg/reactively)**
- **[Fusion](https://github.com/dphfox/Fusion)**

## Sponsors

Flux is free and MIT-licensed. If Flux is useful to you or your team, you can support its development through [GitHub Sponsors](https://github.com/sponsors/kohltastrophe).

## License

Flux is released under the [MIT License](LICENSE.md).
