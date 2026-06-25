<div align="right">
<a href="https://flux.kohl.gg"><img align="left" src="docs/public/logo.svg" width="128" alt="Flux"></a>
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

_Flux is a declarative Luau library for creating user interfaces. It runs on fine-grained lazy reactions, is strictly typed for accurate IntelliSense, and keeps the syntax terse enough that interfaces read almost like plain Luau._

[![CI](https://img.shields.io/github/actions/workflow/status/kohltastrophe/flux/ci.yml?style=for-the-badge)](https://github.com/kohltastrophe/flux/actions/workflows/ci.yml) [![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/kohltastrophe/a15338bf8bb30072e690acf47a8e0266/raw/flux-coverage.json&style=for-the-badge)](https://github.com/kohltastrophe/flux/actions/workflows/ci.yml) [![License](https://img.shields.io/github/license/kohltastrophe/flux?style=for-the-badge)](LICENSE.md) [![GitHub Release](https://img.shields.io/github/v/release/kohltastrophe/flux?style=for-the-badge)](https://github.com/kohltastrophe/flux/releases)

---

<picture><source media="(prefers-color-scheme: dark)" srcset=".github/img/h3-lazy-dark.svg"><img alt="Be lazy yet effective" src=".github/img/h3-lazy.svg"></picture>

<picture><img src="docs/public/autocomplete.min.svg" width="396" alt="Editor autocomplete for Flux: choosing the Frame class, completing the inherited Name property, and a type error on an invalid property."></picture>

</div>

Flux exploits Luau's type checker to its absolute limit, if you're going to be lazy, your editor should do the heavy lifting. The moment you declare an instance like a `TextLabel` or a `Frame`, you get zero-guesswork autocomplete for every valid property, event, and expected type.

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

Flux cuts boilerplate with `__call` metamethods and full <b>operator overloading</b> on every reactive node, so your keystrokes can be just as lazy as the engine under the hood. This means you can forget `:get()` and `:set(1)`, just use `count()` to read and `count(1)` to write. Arithmetic, comparison, and concatenation operators automatically subscribe, so reactive expressions read like the plain Luau around them.

</div>

---

<picture><source media="(prefers-color-scheme: dark)" srcset=".github/img/h3-fast-dark.svg"><img alt="Go fast stay lazy" src=".github/img/h3-fast.svg"></picture>

<a href="https://github.com/kohltastrophe/luau-reactivity-benchmark"><img src="https://raw.githubusercontent.com/kohltastrophe/luau-reactivity-benchmark/assets/chart-small.svg" width="100%" alt="Luau reactivity benchmark"></a>

</div>

Most reactive libraries lean on topological sorting, dirty-checking, or a virtual DOM, all of which carry real overhead on the Luau VM. Flux avoids that overhead by being uncompromisingly lazy. It evaluates absolutely nothing until a value is explicitly observed, ensuring that only the exact work a change strictly requires is ever calculated. No over-fetching, no premature rendering, and no wasted CPU cycles; just maximum performance through pure, optimal laziness.

---

## Batteries Included

Lazy reactivity is the engine. On top of it, Flux ships the rest of what you need to build interfaces, all strictly typed:

- **Reactive primitives** - [`signal`](https://flux.kohl.gg/guide/concepts/signals), [`computed`](https://flux.kohl.gg/guide/concepts/computeds), and [`effect`](https://flux.kohl.gg/guide/concepts/effects), plus [stores](https://flux.kohl.gg/guide/concepts/stores) and [context](https://flux.kohl.gg/guide/concepts/context) for shared state, and [`wrap`](https://flux.kohl.gg/guide/concepts/wrapping) to turn plain tables into reactive ones.
- **Declarative instances:** [`new`](https://flux.kohl.gg/guide/roblox/creation) to build and [`edit`](https://flux.kohl.gg/guide/roblox/hydration) to hydrate existing Instances, with scoped lifecycles and cleanup.
- **Lifecycle & cleanup** - [`scope`](https://flux.kohl.gg/guide/concepts/scopes) tracks every node, instance, and effect it creates and tears them all down with a single `Destroy`, including nested child scopes.
- **Control flow** - [`show`](https://flux.kohl.gg/guide/concepts/conditionals) and [`switch`](https://flux.kohl.gg/guide/concepts/conditionals) for conditional rendering, [`forValue` / `forIndex`](https://flux.kohl.gg/guide/concepts/mapping) for keyed mapping, and [`selector`](https://flux.kohl.gg/guide/concepts/selectors) for O(1) selection in large lists.
- **Motion:** physics [springs](https://flux.kohl.gg/guide/motion/spring), [tweens](https://flux.kohl.gg/guide/motion/tween), and perceptual [color](https://flux.kohl.gg/guide/motion/color) interpolation, all stepped once per frame.
- **Responsive & layout:** [`viewport`, `scale`, and `breakpoint`](https://flux.kohl.gg/guide/utilities/responsive) helpers alongside [`padding`, `list`, `grid`, and `flex`](https://flux.kohl.gg/guide/utilities/layout).
- **Async & safety:** [`async`](https://flux.kohl.gg/guide/concepts/async) tasks, [error boundaries](https://flux.kohl.gg/guide/tips/errors), and a [`strict` mode](https://flux.kohl.gg/guide/tips/strict) that catches impure computations in development.

## Installation

Download the latest `Flux.rbxm` from [Releases](https://github.com/kohltastrophe/flux/releases), drop it into Roblox Studio, and place the module in `ReplicatedStorage`. Rojo users can sync the `src` directory directly.

From there, the **[Getting Started](https://flux.kohl.gg/guide/getting-started)** guide covers the core concepts and your first reactive components.

## Acknowledgements

Flux is heavily inspired by:

- **[Vide](https://github.com/centau/vide)**
- **[SolidJS](https://github.com/solidjs/solid)**
- **[Reactively](https://github.com/milomg/reactively)**
- **[Fusion](https://github.com/dphfox/Fusion)**

## License

Flux is released under the [MIT License](LICENSE.md).
