#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
	git fetch --quiet --unshallow
fi

npx --yes luaudocs@0.2.0 build
