#!/usr/bin/env bash
# Compare the vendored plugin contract against upstream ZeroClaw.
#
# Why this exists. These components bind the WIT contract vendored in wit/v0.
# The host is a moving target, and when its contract gains a case the linker
# refuses a component built against the older one: the failure is
# "expected enum of 37 names, found 38" on the first tool call, after an install
# that reported success. That is not hypothetical, it happened here on
# 2026-08-31 and cost a rebuild.
#
# What it checks. The plugin-action enum in logging.wit, which is the surface
# that broke before and the only one these components import from ZeroClaw. A
# byte comparison would be wrong: doc comments differ legitimately, and the
# vendored world imports a subset of what upstream declares.
#
# Exit codes: 0 identical, 1 drift found, 2 could not check.

set -euo pipefail

UPSTREAM_URL="${UPSTREAM_WIT_URL:-https://raw.githubusercontent.com/zeroclaw-labs/zeroclaw/master/wit/v0/logging.wit}"
LOCAL_WIT="$(dirname "$0")/../wit/v0/logging.wit"

if [ ! -f "$LOCAL_WIT" ]; then
    echo "FATAL: vendored contract not found at $LOCAL_WIT" >&2
    exit 2
fi

# Variant names inside the enum block, one per line, sorted.
extract_actions() {
    sed -n '/enum plugin-action/,/^[[:space:]]*}/p' "$1" |
        grep -oE '^[[:space:]]+[a-z0-9][a-z0-9-]*,?[[:space:]]*$' |
        tr -d ' ,' |
        sort
}

upstream_file="$(mktemp)"
trap 'rm -f "$upstream_file"' EXIT

if ! curl -fsSL --max-time 30 "$UPSTREAM_URL" -o "$upstream_file"; then
    echo "FATAL: could not fetch the upstream contract from $UPSTREAM_URL" >&2
    echo "A network failure is not a passing check; treat this as unknown." >&2
    exit 2
fi

local_actions="$(extract_actions "$LOCAL_WIT")"
upstream_actions="$(extract_actions "$upstream_file")"

local_count="$(printf '%s\n' "$local_actions" | grep -c . || true)"
upstream_count="$(printf '%s\n' "$upstream_actions" | grep -c . || true)"

# An empty extraction means the file shape changed under the parser, which is
# itself drift worth failing on: a silent zero would otherwise compare equal.
if [ "$local_count" -eq 0 ] || [ "$upstream_count" -eq 0 ]; then
    echo "FATAL: extracted $local_count local and $upstream_count upstream action names." >&2
    echo "One of them is empty, so the enum shape no longer matches this parser." >&2
    exit 2
fi

if [ "$local_actions" = "$upstream_actions" ]; then
    echo "OK: vendored plugin-action matches upstream, $local_count names."
    exit 0
fi

echo "DRIFT: the vendored contract no longer matches upstream." >&2
echo "  local:    $local_count names ($LOCAL_WIT)" >&2
echo "  upstream: $upstream_count names ($UPSTREAM_URL)" >&2
echo "" >&2
echo "Difference (< local, > upstream):" >&2
diff <(printf '%s\n' "$local_actions") <(printf '%s\n' "$upstream_actions") >&2 || true
echo "" >&2
echo "Components built from this tree will refuse to instantiate on a host" >&2
echo "carrying the upstream contract. Re-vendor wit/v0 and rebuild:" >&2
echo "  cp -r ../zeroclaw/wit/v0 ./wit/" >&2
echo "  for p in plugins/*/; do (cd \"\$p\" && cargo build --locked --target wasm32-wasip2 --release); done" >&2
exit 1
