---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "Flux"
  text: "Next-Generation Reactivity for Luau"
  tagline: Write less. Type better. Run faster.
  # image:
  #   src: /assets/img/logo.svg
  #   alt: Flux
  actions:
    - theme: brand
      text: What is Flux?
      link: /guide/
    - theme: alt
      text: Getting Started
      link: /guide/getting-started
    - theme: alt
      text: GitHub
      link: https://github.com/kohltastrophe/flux
---

<div class="showcase-container">
<div class="showcase-row">

<div class="showcase-text">
<h1>Write less.</h1>

Building software shouldn't feel like a chore. Flux strips away the boilerplate, leaving you with clean, declarative code. State, derived values, and instances flow together naturally without the visual noise.

</div>
<div class="showcase-code">

```luau
local Flux = require(ReplicatedStorage.Flux)
local new = Flux.new

-- Create reactive state
local count = Flux(0)

-- Declaratively build instances
local button = new "TextButton" {
	Name = "Counter",
	Size = UDim2.fromOffset(200, 50),
	-- Operator overloading: reads count reactively
	Text = function() return `Clicks: {count * 1}` end,

	-- Connect to event
	Activated = function()
		count(count + 1) -- __call to set; arithmetic reads count automatically
	end,
}
```

<h1>Type better.</h1>

Never guess a property name again. Flux is built from the ground up to respect Luau's strict typechecker. You get perfect IntelliSense and autocompletion for every creatable instance, property, event, and directive out of the box.

```luau
-- ✅ Full IDE autocomplete triggers for BackgroundTransparency, BorderSizePixel, etc.
local frame = new "Frame" {
	BackgroundColor3 = Color3.new(1, 0, 0),
	Size = UDim2.fromScale(1, 1),
	TypoProperty = true, -- 'TypoProperty' is not a valid property of 'Frame' [!code error]
}
```

<h1>Run faster.</h1>

Inspired by [Reactively](https://milomg.dev/2022-12-01/reactivity) and [SolidJS](https://www.solidjs.com/), Flux uses a highly optimized, lazily evaluated reactive graph. Effects are deferred to the end of the frame by default, derived state only recalculates when it is actively observed **and** its dependencies have actually changed.

```luau
local count = Flux(0)

local expensiveMath = Flux(function()
	print("Crunching numbers...")
	return count ^ 100
end)

-- "Crunching numbers..." is NEVER printed here.
-- State is updated, but lazy evaluation ensures the math is deferred until it is needed.
count(5)
count(10)
```

</div>
</div>
</div>
