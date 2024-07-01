<div align="center">
	<img src="docs/img/logo.svg" width="128" />
	<br/><br/>
	<p> A reactive state management library for Luau, inspired by <a href="https://www.solidjs.com/">Solid</a> and <a href="https://vuejs.org/">Vue</a>.</p>
</div>

## Features

- **Concise & Declarative:** Write UI and logic that is easy to read and understand
- **Deferred Updates:** Updates are batched and processed efficiently on the next `RunService.Heartbeat`
- **Reactive Children Binding:** Dynamically manage and update child Instances based on state changes
- **Built-in Spring/Tween Support:** Easily animate state changes for smooth and engaging user experiences

## Basic Usage: Reactive Counter

This example demonstrates a simple counter button. The button's text updates automatically when the `count` state changes.

```luau
-- Assuming Flux is located in ReplicatedStorage
local Flux = require(game.ReplicatedStorage.Flux)
local new = Flux.new
local state = Flux.state

local function Counter()
	-- Create a reactive state variable initialized to 0
	local count = state(0)

	-- Create a TextButton Instance
	return new "TextButton" {
		-- The Text property is a function that depends on 'count'.
		-- Automatically updates the button's text when 'count' changes.
		Text = function()
			return "Count: " .. count
		end,

		-- When the button is activated (clicked)
		Activated = function()
			-- Update the 'count' state. Updates dependent properties (like Text).
			count(count + 1)
		end,

		-- Example of setting initial properties
		Size = UDim2.new(0, 100, 0, 30),
		Position = UDim2.new(0.5, -50, 0.5, -15),
	}
end

-- To use this component:
-- local myCounter = Counter()
-- myCounter.Parent = someGuiElement
```

## Comprehensive Usage: Dynamic UI with Effects and Children

```luau
-- Assuming Flux is located in ReplicatedStorage
local Flux = require(game.ReplicatedStorage.Flux)
local new = Flux.new
local state = Flux.state
local tween = Flux.tween

-- 1. State for Tweening a Color
-- This state will smoothly transition its Color3 value.
local tweenColorState = tween(Color3.new(0, 0, 0), TweenInfo.new(1))

-- 2. State Bound to an Instance Property
-- This state reflects game.Lighting.TimeOfDay and updates when it changes.
local timeState = state(game.Lighting, "TimeOfDay")

-- 3. State for Managing Reactive Children
-- This state will hold a list of child UI elements.
local showChildren = state(false)
local dynamicChildren = Flux.compute(function()
	if showChildren() then
		return {
			new "UITextSizeConstraint" { MaxTextSize = 18 },
			new "UIPadding" { PaddingLeft = UDim.new(0, 5) },
		}
	else
		return -- Return nothing to remove children
	end
end)

-- Create a TextLabel with various reactive bindings
local label
label = new "TextLabel" {
	Parent = script.Parent, -- Parent is assigned last for performance reasons

	-- Static properties
	AutomaticSize = Enum.AutomaticSize.XY,
	TextColor3 = Color3.new(1, 1, 1),

	-- Bind BackgroundColor3 to our tweening color state
	BackgroundColor3 = tweenColorState,

	-- Text property is computed based on timeState and showChildren
	-- It updates automatically when timeState changes
	Text = function()
		-- Conditional dependencies must retrieve value via state() to be tracked
		local conditionalText = if showChildren() then "Visible" else "Hidden"
		return `Time: {timeState} - Children: {conditionalText}`
	end,

	-- RBXScriptSignal connection for the Destroying event
	Destroying = function()
		print("Label is being destroyed!")
	end,

	-- Define children, implicitly sets LayoutOrder to the numeric index for GuiObjects
	new "UICorner" {
		CornerRadius = UDim.new(0, 8), -- Slightly rounded corners
	},

	-- Bind dynamic children
	dynamicChildren,

	-- Initialize Attributes
	[Flux.Attribute] = {
		lastUpdateTimestamp = 0, -- Initial attribute value
	},

	-- Handle Property and Attribute change events
	[Flux.Event] = {
		-- Listen to changes in the Text property
		Text = function()
			print("Label Text Changed to:", label.Text)
			-- Update an attribute reactively
			label:SetAttribute("lastUpdateTimestamp", os.time())
		end,

		-- Listen to changes in a specific attribute
		[Flux.Attribute] = {
			lastUpdateTimestamp = function()
				print("Attribute 'lastUpdateTimestamp' Changed to:", label:GetAttribute("lastUpdateTimestamp"))
			end,
		},
	},

	-- Define resources to be cleaned up when the label is destroyed
	[Flux.Clean] = {
		timeState,
	},
}

-- 4. State Bound to an Instance Attribute
-- This state reflects the 'lastUpdateTimestamp' attribute of the label.
local attributeState = state(label, "Attribute.lastUpdateTimestamp")
local disconnectAttributeWatcher = attributeState:Connect(function(newValue)
	print(`Attribute 'lastUpdateTimestamp' via state:Connect(): {newValue}`)
end)

-- Initial interactions
print("Initial attribute value:", attributeState()) --> 0

-- Simulate some interactions
task.wait(2)
print("--- Simulating changes ---")

-- Parent the children (triggers reactive children update and Text update)
showChildren(true)
task.wait(1)

-- Change game time (triggers timeState update, which updates label.Text)
game.Lighting.ClockTime = 12
task.wait(1)

-- Start the color tween
tweenColorState(Color3.fromRGB(0, 128, 255)) -- Tween to a blue color
task.wait(2)

-- Deparent the children
showChildren(false)
task.wait(1)

-- Manually change an attribute (triggers attributeState and Flux.Event.Attribute.lastUpdateTimestamp)
label:SetAttribute("lastUpdateTimestamp", os.time() + 100)

task.wait(1)
-- label:Destroy() -- This would trigger Flux.Clean and the Destroying event
```

## Core Concepts

A brief look into how Flux achieves its reactivity.

- **Reactive States (`Flux.state`):**
  - These are the foundation. When you create a state, Flux wraps your value in an object that can track dependencies and dependents.
  - When you get a state's value (`myState()`), Flux registers this access if it happens within a reactive context (like a `Flux.compute` function or a property function).
  - When you set a state's value (`myState(newValue)`), Flux notifies all its dependents that they need to update.

- **Computed States (`Flux.compute`):**
  - Functions that depend on one or more states are re-evaluated automatically when those states change.
  - `Flux.compute` creates an explicit reactive computation.
  - Property functions (e.g., `Text = function() return "Name: " .. nameState end`) in `Flux.new` or `Flux.edit` implicitly create computations. Flux detects which states are accessed within these functions and subscribes to their changes.

- **Deferred Updates:**
  - By default (`Flux.deferUpdates(true)`), when a state changes, it doesn't immediately trigger updates down the chain. Instead, it schedules the update for the next `RunService.Heartbeat` event.
  - This batching mechanism is crucial for performance. If multiple states change in the same frame, UI elements and computations are only re-evaluated once with the latest values, preventing redundant work and layout thrashing.

- **Reactive Children Management:**
  - When you assign a state to a numeric index (e.g., `[1] = childrenState`) in `Flux.new` or `Flux.edit`, Flux monitors this state.
  - If `childrenState`'s value changes to an Instance, that Instance becomes a child.
  - If it changes to an array of Instances, those Instances become children.
  - If it changes to `nil` or an empty array, the previously managed children are removed.
  - This allows for dynamic lists of UI elements that respond to your application's state.

- **Automatic Cleanup:**
  - The `Flux.Clean` symbol provides a declarative way to manage the lifecycle of states, connections, or other Instances tied to a specific UI component.
  - When the component Instance is destroyed, everything listed in its `Flux.Clean` table is also cleaned up (states are destroyed, connections disconnected, etc.), preventing memory leaks.

## API Overview

Flux provides a concise API for managing state and creating reactive UIs.

### Core Functions

```luau
Flux.state(initialValue: T? | Instance? | State<T>?, propertyName: string?): State<T>
```

- Creates a new reactive state.
- If `initialValue` is an `Instance` and `propertyName` is provided, it binds the state to the Instance's property. If `propertyName` starts with `"Attribute."` (e.g., `"Attribute.MyCustomAttribute"`), it binds to the specified Instance attribute.
- Examples: `state(workspace, "Gravity")`, `state(myInstance, "Attribute.Value")`.
- Calling `state()` (e.g., `myState()`) gets the current value.
- Calling `state(newValue)` (e.g., `myState(10)`) sets the value and triggers updates.

```luau
Flux.compute<T>(computation: () -> T): State<T>
```

- Creates a derived state whose value is computed by the given function.
- Automatically tracks dependencies on other states used within the computation.
- The computation re-runs automatically when any of its dependencies change.

```luau
Flux.tween<T>(state: T | State<T> | Function, tweenInfo: Stateful<TweenInfo>): State<T>
```

- Applies a tween to a state. When the state's value is set, it will tween to the new value using the provided `TweenInfo`.
- Can take a raw value, existing state, or a computation function directly.

```luau
Flux.new(className: string): (properties: table) -> Instance
```

- A factory function for creating Roblox Instances with reactive property bindings.
- Example: `local frame = Flux.new "Frame" { Size = state(UDim2.new(0,100,0,100)) }`

```luau
Flux.edit(instance: Instance, properties: table): Instance
```

- Applies reactive property bindings to an existing Roblox Instance.

```luau
Flux.deferUpdates(shouldDefer: boolean)
```

- Controls whether state updates should be deferred to the next `RunService.Heartbeat`.
- Pass `true` (default) to defer updates, improving performance by batching changes.
- Pass `false` for immediate updates (can be less performant for many rapid changes).

```luau
Flux.isState(object: any): boolean
```

- Returns `true` if the given object is a Flux state, `false` otherwise.

```luau
Flux.raw(object: any): any
```

- Returns the raw underlying value of a state, or the object itself if it's not a state.

```luau
Flux.rawVariadic(...: any): ...any
```

- Returns the raw underlying values for multiple arguments.

### Special Symbols for `Flux.new` and `Flux.edit`

When defining properties in `Flux.new` or `Flux.edit`:

```luau
[Flux.Attribute] = { attributeName = valueOrState, ... }
```

- Defines or binds Instance attributes.

```luau
[Flux.Event] = { eventName = callback, [Flux.Attribute] = { attributeName = callback } }
```

- Connects to Instance events (e.g., `Activated`, `TextChanged`) or property/attribute change signals.

```luau
[Flux.Clean] = { stateToClean, connectionToDisconnect, instanceToDestroy, ... }
```

- An array of resources that will be cleaned up (e.g., states destroyed, connections disconnected, instances destroyed) when the primary Instance created/edited is destroyed.

### State Object Methods

```luau
state:Connect(callback: (newValue: T) -> ()) -> Function
```

- Registers a callback function that fires whenever the state's value changes.
- Returns a `disconnect` function to stop listening.

```luau
state:Destroy()
```

- Manually cleans up the state, removing its bindings and connections. This is often handled automatically by `Flux.Clean`.
