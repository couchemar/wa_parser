#!/usr/bin/env bash
# Generates the real-world WebAssembly fixtures used by
# wa_parser_ex/test/real_world_test.exs.
#
# These are produced by real toolchains rather than hand-written .wat, and are
# far too large to commit (the QuickJS module is ~1.3 MB). They are generated
# instead, and gitignored.
#
# Usage:
#   scripts/fetch-real-world-fixtures.sh
#
# Network access is required the first time; a cached javy in .cache/ is reused
# on later runs.

set -euo pipefail

JAVY_VERSION="9.1.0"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${repo_root}/test_data/real"
cache_dir="${repo_root}/.cache"

mkdir -p "${out_dir}" "${cache_dir}"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) asset="javy-arm-macos" ;;
  Darwin-x86_64) asset="javy-x86_64-macos" ;;
  Linux-x86_64) asset="javy-x86_64-linux" ;;
  Linux-aarch64 | Linux-arm64) asset="javy-arm-linux" ;;
  *)
    echo "unsupported platform: $(uname -s)-$(uname -m)" >&2
    echo "download javy ${JAVY_VERSION} manually and put the binary on PATH" >&2
    exit 1
    ;;
esac

javy="${cache_dir}/javy"

if [ ! -x "${javy}" ]; then
  tarball="${cache_dir}/${asset}-v${JAVY_VERSION}.gz"
  url="https://github.com/bytecodealliance/javy/releases/download/v${JAVY_VERSION}/${asset}-v${JAVY_VERSION}.gz"

  echo "downloading ${asset}-v${JAVY_VERSION}.gz"
  curl -sSL --fail -o "${tarball}" "${url}"
  gunzip -c "${tarball}" > "${javy}"
  chmod +x "${javy}"
fi

echo "javy $("${javy}" --version)"

# The payload is deliberately trivial: the module is essentially all QuickJS, so
# this is the smallest thing that still exercises the whole runtime.
tmp_js="$(mktemp -t javy-input).js"
trap 'rm -f "${tmp_js}"' EXIT
cat > "${tmp_js}" <<'JS'
export function main() {
  return 0;
}
JS

"${javy}" build "${tmp_js}" -o "${out_dir}/quickjs.wasm"

echo "wrote ${out_dir}/quickjs.wasm ($(wc -c < "${out_dir}/quickjs.wasm" | tr -d ' ') bytes)"
