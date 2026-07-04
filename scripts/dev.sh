#!/bin/sh

set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
next_bin="$project_dir/node_modules/next/dist/bin/next"

node_major() {
  "$1" -p "process.versions.node.split('.')[0]" 2>/dev/null || printf '0'
}

is_supported_node() {
  major=$(node_major "$1")
  [ "$major" -ge 20 ] 2>/dev/null && [ "$major" -lt 26 ] 2>/dev/null
}

current_node=$(command -v node 2>/dev/null || true)
if [ -n "$current_node" ] && is_supported_node "$current_node"; then
  exec "$current_node" "$next_bin" dev "$@"
fi

if [ -n "${DEV_NODE:-}" ] && [ -x "$DEV_NODE" ] && is_supported_node "$DEV_NODE"; then
  printf 'Using DEV_NODE=%s for Next.js development.\n' "$DEV_NODE"
  exec "$DEV_NODE" "$next_bin" dev "$@"
fi

runtime_node=$(
  find "$HOME/.cache" -path '*/codex-primary-runtime/dependencies/node/bin/node' -type f 2>/dev/null | head -n 1
)
if [ -n "$runtime_node" ] && [ -x "$runtime_node" ] && is_supported_node "$runtime_node"; then
  printf 'Using bundled Node %s for Next.js development.\n' "$("$runtime_node" -v)"
  exec "$runtime_node" "$next_bin" dev "$@"
fi

if [ -n "$current_node" ]; then
  printf 'ERROR: This project supports Node 20-24 for Next.js development, but PATH has %s.\n' "$("$current_node" -v)" >&2
else
  printf 'ERROR: Node was not found on PATH.\n' >&2
fi
printf 'Install Node 24, or set DEV_NODE to a Node 20-24 executable, then run npm run dev again.\n' >&2
exit 1
