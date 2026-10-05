#!/usr/bin/env bash
# Runs every check: formatting, tests, a Rojo build and Luau type checking.
# Needs rojo, stylua, lune and luau-lsp on PATH (`rokit install` sets them up).
set -euo pipefail
cd "$(dirname "$0")/.."

LUAU_LSP_VERSION="1.70.1" # keep in step with rokit.toml

echo "== Formatting (StyLua)"
stylua --check src tests

echo "== Tests (Lune)"
lune run tests/run

echo "== Build (Rojo)"
mkdir -p build
rojo build default.project.json -o build/NoobToProObby.rbxlx

echo "== Type check (luau-lsp)"
if [ ! -f globalTypes.d.luau ]; then
	curl -fsSL -o globalTypes.d.luau \
		"https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/${LUAU_LSP_VERSION}/scripts/globalTypes.d.luau"
fi
rojo sourcemap default.project.json --include-non-scripts -o sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=@roblox=globalTypes.d.luau src

echo "All checks passed"
