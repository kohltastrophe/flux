---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "Flux"
  text: "Fine-grained reactive UI for Luau"
  tagline: Be lazy. Do more. Go fast.
  # image:
  #   src: /assets/img/logo.svg
  #   alt: Flux
  actions:
    - theme: brand
      text: What is Flux?
      link: /guide/introduction
    - theme: alt
      text: Getting Started
      link: /guide/introduction/getting-started
    - theme: alt
      text: GitHub
      link: https://github.com/kohltastrophe/flux
---

<div class="showcase-container">
<div class="showcase-row">

<div class="showcase-text">

<h1 align="center">Be lazy <text style="opacity: 0.26">yet effective</text></h1>

Flux exploits Luau's type checker to its absolute limit, if you're going to be lazy, your editor should do the heavy lifting. The moment you declare an instance like a `TextLabel` or a `Frame`, you get zero-guesswork autocomplete for every valid property, event, and expected type.

<img src="/autocomplete.min.svg" alt="Editor autocomplete for Flux: choosing the Frame class, completing the inherited Name property, and a red squiggle on an invalid property." style="display:block;width:100%;max-width:560px;margin:1.5rem auto;" />

</div>
<div class="showcase-code">

<h1 align="center">Do more <text style="opacity: 0.26">with less</text></h1>

Flux cuts boilerplate with `__call` metamethods and full <b>operator overloading</b> on every reactive node, so reading and writing state takes zero ceremony. Forget `:get()` and `:set(1)`, just use `count()` to read and `count(1)` to write. Arithmetic, comparison, and concatenation operators automatically subscribe, so reactive expressions read like the plain Luau around them.

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

<h1 align="center">Go fast <text style="opacity: 0.26">waste nothing</text></h1>

Virtual DOM libraries rebuild and diff component trees; naive reactive graphs re-run downstream bindings on every intermediate write. Flux does neither: dormant computations sleep with zero subscriptions until something observes them, and active bindings batch updates to the frame, settling in dependency order and stopping early the moment a derived value is unchanged. No virtual DOM diffing, no intermediate glitches, and no wasted CPU cycles.

<a href="https://github.com/kohltastrophe/luau-reactivity-benchmark"><img src="https://raw.githubusercontent.com/kohltastrophe/luau-reactivity-benchmark/assets/chart-small.svg" width="100%" alt="Luau reactivity benchmark"></a>

</div>
</div>
</div>
