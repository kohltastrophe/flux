---
title: Developer Tools
description: Recommended tools for developing with Flux in Roblox.
outline: deep
---

# Developer Tools

While you can use Flux entirely within Roblox Studio, the modern Roblox development ecosystem relies heavily on external tools to improve code quality, workflow speed, and project maintainability.

Here are the highly recommended community tools to pair with your Flux projects.

## Project Synchronization

### Rojo

[Rojo](https://rojo.space/) is the industry-standard tool that allows you to write code in external editors and seamlessly sync those files into Roblox Studio. Using Rojo is highly recommended when building complex Flux interfaces, as it allows you to utilize external version control, linters, and formatters.

## Code Quality

### Selene

[Selene](https://kampfkarren.github.io/selene/) is a blazing-fast linter for Luau. It helps catch common syntax errors, bad practices, and scoping issues before you ever run your game.

### StyLua

[StyLua](https://github.com/JohnnyMorganz/StyLua) is an opinionated code formatter for Luau. It ensures your Flux components, reactive bindings, and state logic maintain a consistent, readable style across your entire codebase, which is especially vital when collaborating with a team.

## UI Previewing (Storybooks)

Storybooks allow you to view, test, and iterate on your UI components in isolation without having to playtest the entire game.

Because Flux is a standalone reactive library, it does not currently have native, out-of-the-box plugins for these tools. **Manual integration is required** to mount your components.

### Flipbook (Manual Integration)

[Flipbook](https://flipbook.dev/) is a modern storybook plugin for Roblox Studio. To use Flipbook with Flux, you will need to manually write a small wrapper or adapter in your `.story.luau`{lua} files to handle calling your component functions and mounting the resulting `Flux.new`{lua} instances to the provided target.

### Hoarcekat (Manual Integration)

[Hoarcekat](https://github.com/Kampfkarren/hoarcekat) is a classic, widely used interactive UI previewer for Roblox Studio. Similar to Flipbook, you must manually construct your UI and ensure you are using a Flux **Scope** to properly clean up and unmount your reactive state when the story is closed.
