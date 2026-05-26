import { defineConfig } from "vitepress";
import type { Highlighter } from "shiki";
import { inlineHighlightPlugin } from "./inline-highlight";

const themes = { light: "github-light", dark: "github-dark" };

let highlighter: Highlighter;

// https://vitepress.dev/reference/site-config
export default defineConfig({
	title: "Flux",
	description: "A next-generation reactive framework for Roblox Luau.",

	base: "/flux/",
	cleanUrls: true,
	head: [
		["link", { rel: "icon", href: "/flux/logo.svg" }],
		["meta", { property: "og:site_name", content: "Flux" }],
		[
			"meta",
			{
				property: "og:title",
				content: "Flux - A next-generation reactive framework for Luau.",
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
				content: "https://kohltastrophe.github.io/flux/logo.svg",
			},
		],
		[
			"meta",
			{ property: "og:url", content: "https://kohltastrophe.github.io/flux/" },
		],
	],

	markdown: {
		defaultHighlightLang: "luau",

		languages: ["luau", "lua", "ts"],

		theme: themes,

		shikiSetup(shiki) {
			highlighter = shiki;
		},

		config(md) {
			md.use(inlineHighlightPlugin, {
				getHighlighter: () => highlighter,
				themes,
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
			// { text: "Reference", link: "/api/" },
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
						{ text: "Values", link: "/guide/concepts/values" },
						{ text: "Computeds", link: "/guide/concepts/computeds" },
						{ text: "Effects", link: "/guide/concepts/effects" },
						{ text: "Scopes", link: "/guide/concepts/scopes" },
						{ text: "Async", link: "/guide/concepts/async" },
						{ text: "Mapping", link: "/guide/concepts/mapping" },
						{ text: "Stores", link: "/guide/concepts/stores" },
						{ text: "Wrapping", link: "/guide/concepts/wrapping" },
					],
				},
				{
					text: "Motion",
					items: [
						{ text: "Spring", link: "/guide/motion/spring" },
						{ text: "Tween", link: "/guide/motion/tween" },
					],
				},
				{
					text: "Roblox",
					items: [
						{ text: "Hydration", link: "/guide/roblox/hydration" },
						{ text: "Creation", link: "/guide/roblox/creation" },
					],
				},
				{
					text: "Tips",
					items: [
						{ text: "Components", link: "/guide/tips/components" },
						{ text: "Optimization", link: "/guide/tips/optimization" },
						{ text: "Error Handling", link: "/guide/tips/errors" },
						{ text: "Sharing State", link: "/guide/tips/sharing" },
					],
				},
			],
		},

		search: {
			provider: "local",
		},

		socialLinks: [
			{ icon: "github", link: "https://github.com/kohltastrophe/flux" },
		],
	},
});
