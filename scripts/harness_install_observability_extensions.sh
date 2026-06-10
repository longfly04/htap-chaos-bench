#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/harness_common.sh"

if ! is_source_runtime; then
  log "skipping observability extension install outside source runtime"
  exit 0
fi

install_enabled="${INSTALL_OBSERVABILITY_EXTENSIONS:-false}"
if [[ "$install_enabled" != "true" ]]; then
  log "observability extension auto-install is disabled"
  exit 0
fi

source_root="${OBSERVABILITY_EXTENSION_SOURCE_ROOT:-}"
[[ -n "$source_root" ]] || fail "OBSERVABILITY_EXTENSION_SOURCE_ROOT is required when INSTALL_OBSERVABILITY_EXTENSIONS=true"
pg_config_path="$(source_pg_config)"
make_bin="${MAKE_BIN:-make}"

extension_names_raw="${OBSERVABILITY_EXTENSION_SOURCE_NAMES:-pg_wait_sampling pgmeminfo system_stats pg_stat_kcache}"
read -r -a extension_names <<< "${extension_names_raw//,/ }"
[[ ${#extension_names[@]} -gt 0 ]] || fail "OBSERVABILITY_EXTENSION_SOURCE_NAMES resolved to an empty list"

for extension_name in "${extension_names[@]}"; do
  [[ -n "$extension_name" ]] || continue
  extension_dir="$source_root/$extension_name"
  [[ -d "$extension_dir" ]] || fail "extension source directory not found: $extension_dir"
  [[ -f "$extension_dir/Makefile" ]] || fail "extension source directory is missing a Makefile: $extension_dir"
  log "building observability extension $extension_name from $extension_dir"
  "$make_bin" -C "$extension_dir" USE_PGXS=1 PG_CONFIG="$pg_config_path"
  log "installing observability extension $extension_name"
  "$make_bin" -C "$extension_dir" USE_PGXS=1 PG_CONFIG="$pg_config_path" install
  log "installed observability extension $extension_name"
done
