#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/harness_common.sh"

source_root="${SYSBENCH_SOURCE_ROOT:-}"
[[ -n "$source_root" ]] || fail "SYSBENCH_SOURCE_ROOT is required"
[[ -d "$source_root" ]] || fail "sysbench source root not found: $source_root"
[[ -f "$source_root/configure.ac" ]] || fail "sysbench source root is missing configure.ac: $source_root"

jobs="${SYSBENCH_BUILD_JOBS:-}"
if [[ -z "$jobs" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    jobs="$(nproc)"
  else
    jobs=4
  fi
fi

cd "$source_root"
if [[ -n "${SOURCE_PG_BINDIR:-}" || -n "${PGROOT:-}" ]]; then
  export PATH="$(source_pg_bin_dir):$PATH"
fi
if [[ ! -x ./configure ]]; then
  if [[ -x ./autogen.sh ]]; then
    ./autogen.sh
  else
    fail "configure is absent and autogen.sh is unavailable in $source_root"
  fi
fi

if [[ ! -f Makefile ]]; then
  ./configure --with-pgsql --without-mysql
fi

make -j"$jobs"

if [[ -x "$source_root/src/sysbench" ]]; then
  log "built sysbench binary: $source_root/src/sysbench"
  exit 0
fi
if [[ -x "$source_root/src/.libs/sysbench" ]]; then
  log "built sysbench binary: $source_root/src/.libs/sysbench"
  exit 0
fi

fail "sysbench build completed but no binary was found under $source_root/src"
