#!/usr/bin/env bash
# One command that runs the package and prints what came out of the run.
#
# Everything below is measured, never typed: the test totals come from the
# output of `cargo test`, the refusal count comes from its `--list` output, and
# the component sizes and digests come from the files the build just produced.
#
# No network, no keys, no wallet. Host tests read captured fixtures; the wasm
# build is offline. Expect two to three minutes on a cold cargo cache.
#
#   bash demo/run-demo.sh            full run
#   bash demo/run-demo.sh --no-wasm  skip the component build
set -euo pipefail

cd "$(dirname "$0")/.."

PLUGINS=(lending-health stake-monitor stake-tx-build)
BUILD_WASM=1
[[ "${1:-}" == "--no-wasm" ]] && BUILD_WASM=0

command -v cargo >/dev/null || { echo "cargo not found; install Rust 1.96.1"; exit 1; }

rule() { printf '%s\n' "-------------------------------------------------------------"; }
row()  { printf '  %-16s %s\n' "$1" "$2"; }

echo "solana-portfolio-sentinel: one-command check"
echo "toolchain: $(cargo --version)"
rule

# ---------------------------------------------------------------- host tests
echo "host tests (captured fixtures, no network)"
total_passed=0
declare -A passed_by_plugin
for p in "${PLUGINS[@]}"; do
  out="$(cargo test --locked --quiet --manifest-path "plugins/$p/Cargo.toml" 2>&1)"
  # Every test binary prints one "test result:" line; sum the passed counts.
  n="$(printf '%s\n' "$out" | awk '/^test result:/ { for (i=1;i<=NF;i++) if ($i=="passed;") s+=$(i-1) } END { print s+0 }')"
  failed="$(printf '%s\n' "$out" | awk '/^test result:/ { for (i=1;i<=NF;i++) if ($i=="failed;") s+=$(i-1) } END { print s+0 }')"
  if [[ "$failed" != "0" ]]; then
    printf '%s\n' "$out"
    echo "FAILED: $p reported $failed failing test(s)"
    exit 1
  fi
  passed_by_plugin["$p"]="$n"
  total_passed=$(( total_passed + n ))
  row "$p" "$n passed"
done
row "total" "$total_passed passed"
rule

# ------------------------------------------------------- refusal coverage
# A refusal test is one whose own name states that something is turned away or
# left unknown. The pattern is printed so the number can be re-derived by hand.
PATTERN='reject|refus|denie|denied|unknown|outside|not_allow|non_allowlisted|cannot|disabled|hostile|forged|smuggle'
echo "refusal and unknown-path coverage"
echo "  name filter: /${PATTERN}/"
refusal_total=0
for p in "${PLUGINS[@]}"; do
  listing="$(cargo test --locked --quiet --manifest-path "plugins/$p/Cargo.toml" -- --list 2>/dev/null || true)"
  n="$(printf '%s\n' "$listing" | grep -E ': test$' | grep -Ec "$PATTERN" || true)"
  refusal_total=$(( refusal_total + n ))
  row "$p" "$n of ${passed_by_plugin[$p]}"
done
row "total" "$refusal_total of $total_passed"
rule

# --------------------------------------------------- byte-exact goldens
echo "byte-exact transaction goldens in stake-tx-build"
golden="$(cargo test --locked --quiet --manifest-path plugins/stake-tx-build/Cargo.toml -- --list 2>/dev/null \
  | grep -E ': test$' | grep -Ei 'golden|byte_for_byte|byte_exact' | sed 's/: test$//' || true)"
if [[ -z "$golden" ]]; then
  echo "  none found"
else
  printf '%s\n' "$golden" | while read -r t; do row "" "$t"; done
fi
rule

# -------------------------------------------------------------- components
if [[ "$BUILD_WASM" == "1" ]]; then
  echo "components (wasm32-wasip2, release)"
  for p in "${PLUGINS[@]}"; do
    cargo build --locked --quiet --manifest-path "plugins/$p/Cargo.toml" \
      --target wasm32-wasip2 --release
  done
  found=0
  while IFS= read -r w; do
    found=1
    size="$(wc -c < "$w" | tr -d ' ')"
    if command -v sha256sum >/dev/null; then
      digest="$(sha256sum "$w" | cut -c1-16)"
    else
      digest="$(shasum -a 256 "$w" | cut -c1-16)"
    fi
    row "$(basename "$w")" "$size bytes  sha256:${digest}"
    # `deps/` holds the same component under a build-id path; skip the copy.
  done < <(find plugins -path '*/wasm32-wasip2/release/*.wasm' -not -path '*/deps/*' | sort)
  [[ "$found" == "1" ]] || echo "  no components were produced"
  rule
fi

echo "what this run did not do"
echo "  no network call, no key material read, no transaction signed or sent."
echo "  the numbers above describe this checkout only; REPRODUCE.md pins the host"
echo "  commit these components were compiled against."
