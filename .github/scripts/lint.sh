#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

LSP_VERSION=$(grep -o 'luau-lsp@[0-9.]*' rokit.toml | cut -d@ -f2)
if [ -z "$LSP_VERSION" ]; then
	echo "error: could not parse luau-lsp version from rokit.toml" >&2
	exit 1
fi

cleanup() {
	rm -f globalTypes.d.luau .luau-temp-settings.json sourcemap.json
}
trap cleanup EXIT

rojo sourcemap --output sourcemap.json --include-non-scripts
curl -sfL -o globalTypes.d.luau \
	"https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/${LSP_VERSION}/scripts/globalTypes.d.luau"
echo '{"luau-lsp.fflags.enableNewSolver": true}' > .luau-temp-settings.json
luau-lsp analyze --settings=.luau-temp-settings.json --defs=globalTypes.d.luau src/ test/

stylua --check src/ test/
