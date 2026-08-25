#!/usr/bin/env bash
# Shared helpers for scripts/workflow/*.sh drivers.
#
# Source this after `set -euo pipefail`. Several helpers call `exit` directly
# on validation failure, matching the fail-fast contract every driver already
# used before this file existed; they are not meant to be used in a context
# where the caller wants to trap the error instead of exiting.

# require_arg OPTION_NAME REMAINING_ARGC
# Exits 2 unless at least one value remains after the option itself, i.e. the
# caller still has both the option and its value in "$@". Call before
# consuming "$2" and shifting.
require_arg() {
    local option_name="$1"
    local remaining="$2"
    if ((remaining < 2)); then
        echo "$option_name requires a value" >&2
        exit 2
    fi
}

# validate_positive_number OPTION VALUE
validate_positive_number() {
    local option="$1"
    local value="$2"
    if ! awk -v value="$value" 'BEGIN { exit !(value > 0) }'; then
        echo "$option must be positive: $value" >&2
        exit 2
    fi
}

# validate_number OPTION VALUE 'awk predicate over the variable "value"'
validate_number() {
    local option="$1"
    local value="$2"
    local predicate="$3"
    if ! awk -v value="$value" "BEGIN { exit !($predicate) }"; then
        echo "$option has an invalid value: $value" >&2
        exit 2
    fi
}

# validate_real_number OPTION VALUE
validate_real_number() {
    local option="$1"
    local value="$2"
    if [[ ! "$value" =~ ^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$ ]]; then
        echo "$option must be a finite number: $value" >&2
        exit 2
    fi
}

# require_finite_components LABEL VALUE...
# Matches the historical "Periodic translation components must be numeric"
# checks: one label, several values, each checked with the same message.
require_finite_components() {
    local label="$1"
    shift
    local value
    for value in "$@"; do
        awk -v value="$value" \
            'BEGIN { exit !(value ~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$/) }' || {
            echo "$label must be numeric: $value" >&2
            exit 2
        }
    done
}

# absolute_path PATH BASE_DIR
# Resolves PATH against BASE_DIR (normally $project_dir) unless already
# absolute. Uses realpath -m so a not-yet-existing output path still
# resolves.
absolute_path() {
    local path="$1"
    local base="$2"
    if [[ "$path" == /* ]]; then
        realpath -m -- "$path"
    else
        realpath -m -- "$base/$path"
    fi
}

# require_repo_relative_path MESSAGE PATH
# Rejects an absolute path, a colon-containing path (which would corrupt a
# NekMesh module-argument list), or any ".." path-traversal component. This
# is the strictest check previously found across call sites; every caller
# now gets it, including ones that used a narrower check before.
require_repo_relative_path() {
    local message="$1"
    local path="$2"
    if [[ "$path" == /* || "$path" == *:* || "$path" == .. ||
        "$path" == ../* || "$path" == */../* || "$path" == */.. ]]; then
        echo "$message: $path" >&2
        exit 2
    fi
}

# resolve_star_executable NAME_VAR BASE_DIR
# Resolves the star executable stored in the named variable: absolute-izes
# it if it contains a slash, otherwise resolves it through PATH (leaving it
# unchanged if PATH resolution fails, so later existence checks can report a
# clear error).
resolve_star_executable() {
    local -n executable_ref="$1"
    local base="$2"
    if [[ "$executable_ref" == */* ]]; then
        executable_ref="$(absolute_path "$executable_ref" "$base")"
    else
        local resolved
        resolved="$(command -v -- "$executable_ref" || true)"
        if [[ -n "$resolved" ]]; then
            executable_ref="$resolved"
        fi
    fi
}

# require_star_executable EXECUTABLE ALLOW_MISSING
# ALLOW_MISSING is normally "$dry_run": a dry run does not require STAR to
# actually be installed.
require_star_executable() {
    local executable="$1"
    local allow_missing="$2"
    if [[ "$allow_missing" == true ]]; then
        return 0
    fi
    if { [[ "$executable" == */* ]] && [[ ! -x "$executable" ]]; } ||
        { [[ "$executable" != */* ]] && ! command -v -- "$executable" >/dev/null 2>&1; }; then
        echo "STAR executable is missing or not executable: $executable" >&2
        exit 1
    fi
}

# guard_pod_conflicts EXTRA_STAR_ARG...
# Rejects a PoD key passed on the command line, and (when combined with
# --power-on-demand, checked by the caller before invoking this) rejects a
# manually supplied -power/-powerpre. Pass the extra STAR arguments array.
guard_pod_key_on_cli() {
    local star_arg
    for star_arg in "$@"; do
        if [[ "$star_arg" == -podkey || "$star_arg" == -podkey=* ]]; then
            echo "Do not pass a PoD key on the command line; use --power-on-demand with STAR_POD_KEY." >&2
            exit 2
        fi
    done
}

guard_pod_power_flag_conflict() {
    local star_arg
    for star_arg in "$@"; do
        if [[ "$star_arg" == -power || "$star_arg" == -powerpre ]]; then
            echo "Do not combine --power-on-demand with $star_arg." >&2
            exit 2
        fi
    done
}

# require_pod_key
# Exits if STAR_POD_KEY is unset. Deliberately does not return the value
# through command substitution: `x="$(fn)"` runs fn in a subshell, so an
# `unset STAR_POD_KEY` inside it would not clear the variable in the
# caller's shell. Callers must read and unset it directly in their own
# scope, e.g.:
#   require_pod_key
#   pod_key="$STAR_POD_KEY"
#   unset STAR_POD_KEY
require_pod_key() {
    if [[ -z "${STAR_POD_KEY:-}" ]]; then
        echo "--power-on-demand requires the STAR_POD_KEY environment variable." >&2
        exit 2
    fi
}

# provenance_kv KEY VALUE
provenance_kv() {
    printf '%s=%s\n' "$1" "$2"
}

# provenance_sha256 LABEL FILE
# Matches run_remote_pipeline.sh's historical provenance convention:
# sha256[label]=hash
provenance_sha256() {
    local label="$1"
    local file="$2"
    printf 'sha256[%s]=%s\n' "$label" "$(sha256sum "$file" | awk '{print $1}')"
}

# provenance_sha256_field FIELD_PREFIX FILE
# Matches run_star_bootstrap.sh/run_star_mesh.sh/run_star_rans.sh's
# historical provenance convention: field_prefix_sha256=hash
provenance_sha256_field() {
    local field_prefix="$1"
    local file="$2"
    printf '%s_sha256=%s\n' "$field_prefix" "$(sha256sum "$file" | awk '{print $1}')"
}

# publish_file STAGED DEST
# Publishes a staged output file, and removes the backup STAR sometimes
# leaves beside a simulation saved more than once. It is private staging
# data, never a published pipeline result.
publish_file() {
    local staged="$1"
    local dest="$2"
    mv -f -- "$staged" "$dest"
    rm -f -- "${staged}~"
}

# run_stage LABEL LOG_FILE COMMAND...
# Runs COMMAND, redirecting its combined output to LOG_FILE. On failure,
# tails the log to stderr and returns the command's exit status.
run_stage() {
    local label="$1"
    local log="$2"
    shift 2

    printf '[pipeline] %s\n' "$label"
    if "$@" >"$log" 2>&1; then
        printf '[pipeline] completed: %s (log: %s)\n' "$label" "$log"
    else
        local status=$?
        printf '[pipeline] failed: %s, status %s (log: %s)\n' \
            "$label" "$status" "$log" >&2
        tail -n 50 -- "$log" >&2 || true
        return "$status"
    fi
}
