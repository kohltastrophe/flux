---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "Flux"
  text: "Fast and easy interfaces for Luau."
  tagline: Be lazy. Do more. Go fast.
  # image:
  #   src: /assets/img/logo.svg
  #   alt: Flux
  actions:
    - theme: brand
      text: Overview
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

Flux leans on Luau's type checker so your editor does the heavy lifting. When you declare a `TextLabel` or `Frame`, you get autocomplete for every valid property, event, and expected type.

<img src="/autocomplete.min.svg" alt="Editor autocomplete for Flux: choosing the Frame class, completing the inherited Name property, and a red squiggle on an invalid property." style="display:block;width:100%;max-width:560px;margin:1.5rem auto;" />

</div>
<div class="showcase-code">

<h1 align="center">Do more <text style="opacity: 0.26">with less</text></h1>

Every reactive node supports `__call` and <b>operator overloading</b>, so reading and writing state takes no extra ceremony. Call `count()` to read and `count(1)` to write. Arithmetic, comparison, and string interpolation track dependencies automatically, so reactive expressions read like normal Luau.

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

Dormant computations sleep with zero subscriptions until something observes them. Active bindings batch updates once per frame and run in dependency order. If a computed value doesn't change, downstream bindings don't re-run.

<a href="https://github.com/kohltastrophe/luau-reactivity-benchmark"><img src="https://raw.githubusercontent.com/kohltastrophe/luau-reactivity-benchmark/assets/chart-small.svg" width="100%" alt="Luau reactivity benchmark"></a>

</div>
</div>
</div>
