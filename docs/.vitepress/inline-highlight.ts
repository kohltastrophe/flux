import type MarkdownIt from "markdown-it";
import type { Highlighter } from "shiki";

export interface InlineHighlightOptions {
	getHighlighter: () => Highlighter;
	themes?: { light: string; dark: string };
	langAlias?: Record<string, string>;
}

const ANNOTATION = /^\{([\w+#.-]+)\}/;

export function inlineHighlightPlugin(
	md: MarkdownIt,
	opts: InlineHighlightOptions,
): void {
	const {
		getHighlighter,
		themes = { light: "github-light", dark: "github-dark" },
		langAlias = {},
	} = opts;

	md.core.ruler.after("inline", "inline_highlight_annotate", (state) => {
		for (const block of state.tokens) {
			if (block.type !== "inline" || !block.children) continue;
			const children = block.children;
			for (let i = 0; i < children.length; i++) {
				const tok = children[i];
				if (tok.type !== "code_inline") continue;
				const next = children[i + 1];
				if (!next || next.type !== "text") continue;
				const m = next.content.match(ANNOTATION);
				if (!m) continue;
				tok.info = m[1];
				next.content = next.content.slice(m[0].length);
			}
		}
		return true;
	});

	const fallback =
		md.renderer.rules.code_inline ??
		((tokens, idx) =>
			`<code>${md.utils.escapeHtml(tokens[idx].content)}</code>`);

	md.renderer.rules.code_inline = (tokens, idx, options, env, self) => {
		const tok = tokens[idx];
		const lang = tok.info;
		if (!lang) return fallback(tokens, idx, options, env, self);

		const hl = getHighlighter();
		const resolved = langAlias[lang] ?? lang;
		const useLang = hl.getLoadedLanguages().includes(resolved)
			? resolved
			: "text";

		try {
			const inner = hl.codeToHtml(tok.content, {
				lang: useLang,
				themes,
				defaultColor: false,
				structure: "inline", // just colored spans — no <pre>/<code>/line wrappers
			});
			return `<code class="shiki-inline">${inner}</code>`;
		} catch {
			return fallback(tokens, idx, options, env, self);
		}
	};
}
