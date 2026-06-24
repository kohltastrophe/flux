import { defineConfig } from "vitepress";
import type { Highlighter } from "shiki";
import { inlineHighlightPlugin } from "./inline-highlight";

const themes = { light: "github-light", dark: "github-dark" };

const languages = ["luau", "lua", "ts"];

let highlighter: Highlighter;

// https://vitepress.dev/reference/site-config
export default defineConfig({
	title: "Flux",
	description:
		"A declarative, efficient, and flexible Luau library for creating user interfaces.",

	cleanUrls: true,
	lastUpdated: true,
	sitemap: { hostname: "https://flux.kohl.gg" },
	srcExclude: ["**/snippets/**"],
	head: [
		["link", { rel: "icon", href: "logo.svg" }],
		["meta", { property: "og:site_name", content: "Flux" }],
		[
			"meta",
			{
				property: "og:title",
				content:
					"Flux - A declarative, efficient, and flexible Luau library for creating user interfaces.",
			},
		],
		[
			"meta",
			{
				property: "og:description",
				content:
					"Powered by a heavily optimized graph algorithm, strictly typed for uncompromising IntelliSense, and built with a terse syntax that makes building interfaces genuinely fun.",
			},
		],
		[
			"meta",
			{
				property: "og:image",
				content: "https://flux.kohl.gg/logo.png",
			},
		],
		["meta", { property: "og:url", content: "https://flux.kohl.gg/" }],
	],

	markdown: {
		defaultHighlightLang: "luau",

		languages,

		theme: themes,

		shikiSetup(shiki) {
			highlighter = shiki;
		},

		config(md) {
			md.use(inlineHighlightPlugin, {
				getHighlighter: () => highlighter,
				themes,
				languages,
			});
		},
	},

	themeConfig: {
		// https://vitepress.dev/reference/default-theme-config
		logo: "/logo.svg",
		siteTitle: false,

		nav: [
			{ text: "Home", link: "/" },
			{ text: "Guide", link: "/guide/" },
			{ text: "Reference", link: "/api/" },
		],

		sidebar: {
			"/guide/": [
				{
					text: "Introduction",
					items: [
						{ text: "What is Flux?", link: "/guide/" },
						{ text: "Getting Started", link: "/guide/getting-started" },
						{ text: "Developer Tools", link: "/guide/developer-tools" },
					],
				},
				{
					text: "Concepts",
					items: [
						{ text: "Signals", link: "/guide/concepts/signals" },
						{ text: "Computeds", link: "/guide/concepts/computeds" },
						{ text: "Effects", link: "/guide/concepts/effects" },
						{ text: "Scopes", link: "/guide/concepts/scopes" },
						{ text: "Async", link: "/guide/concepts/async" },
						{ text: "Mapping", link: "/guide/concepts/mapping" },
						{
							text: "Conditional rendering",
							link: "/guide/concepts/conditionals",
						},
						{ text: "Selectors", link: "/guide/concepts/selectors" },
						{ text: "Stores", link: "/guide/concepts/stores" },
						{ text: "Wrapping", link: "/guide/concepts/wrapping" },
						{ text: "Tracking", link: "/guide/concepts/tracking" },
						{ text: "Components", link: "/guide/concepts/components" },
						{ text: "Context", link: "/guide/concepts/context" },
					],
				},
				{
					text: "Roblox",
					items: [
						{ text: "Creation", link: "/guide/roblox/creation" },
						{ text: "Hydration", link: "/guide/roblox/hydration" },
						{ text: "Defaults", link: "/guide/roblox/defaults" },
					],
				},
				{
					text: "Motion",
					items: [
						{ text: "Spring", link: "/guide/motion/spring" },
						{ text: "Tween", link: "/guide/motion/tween" },
						{ text: "Color", link: "/guide/motion/color" },
					],
				},
				{
					text: "Utilities",
					items: [
						{ text: "Responsive", link: "/guide/utilities/responsive" },
						{ text: "Layout", link: "/guide/utilities/layout" },
					],
				},
				{
					text: "Tips",
					items: [
						{ text: "Optimization", link: "/guide/tips/optimization" },
						{ text: "Error Handling", link: "/guide/tips/errors" },
						{ text: "Sharing State", link: "/guide/tips/sharing" },
						{ text: "Testing", link: "/guide/tips/testing" },
						{ text: "Strict mode", link: "/guide/tips/strict" },
					],
				},
			],
		},

		editLink: {
			pattern: "https://github.com/kohltastrophe/flux/edit/main/docs/:path",
			text: "Edit this page on GitHub",
		},

		search: {
			provider: "local",
		},

		socialLinks: [
			{ icon: "github", link: "https://github.com/kohltastrophe/flux" },
		],
	},
});
