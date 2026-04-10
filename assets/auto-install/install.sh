#!/usr/bin/env bash

# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select

# ── Bootstrap URL ──────────────────────────────────────────────────────────
readonly _ZES_BOOTSTRAP_MAIN_INSTALL_URL="https://raw.githubusercontent.com/Michael-Matta1/zsh-edit-select/main/assets/auto-install/install.sh"

# ── Bash requirement checks ────────────────────────────────────────────────
if [ -z "${BASH_VERSION:-}" ]; then
    echo "ERROR: This script must be run with bash, not sh or zsh."
    echo "Usage: bash install.sh"
    exit 1
fi

# Parse bootstrap-relevant flags before full argument parsing exists.
_zes_bootstrap_non_interactive=0
for _zes_bootstrap_arg in "$@"; do
    if [[ "$_zes_bootstrap_arg" == "--non-interactive" ]]; then
        _zes_bootstrap_non_interactive=1
        break
    fi
done
unset _zes_bootstrap_arg

_zes_bootstrap_is_interactive() {
    [[ $_zes_bootstrap_non_interactive -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]
}

_zes_bootstrap_prompt_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local answer=""

    if ! _zes_bootstrap_is_interactive; then
        return 1
    fi

    while true; do
        if [[ "$default" == "y" ]]; then
            printf "%s [Y/n]: " "$question"
        else
            printf "%s [y/N]: " "$question"
        fi

        IFS= read -r answer || answer=""
        answer=$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')
        [[ -z "$answer" ]] && answer="$default"

        case "$answer" in
        y | yes) return 0 ;;
        n | no) return 1 ;;
        *) echo "Please answer y or n." ;;
        esac
    done
}

_zes_bootstrap_activate_brew() {
    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        # shellcheck disable=SC1091
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x "/usr/local/bin/brew" ]]; then
        # shellcheck disable=SC1091
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

_zes_bootstrap_download_script() {
    local url="$1"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -O- "$url" 2>/dev/null
    else
        return 1
    fi
}

_zes_bootstrap_install_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi

    echo "Homebrew was not found on this macOS system."
    if ! _zes_bootstrap_prompt_yes_no "Install Homebrew now?" "y"; then
        return 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "ERROR: curl is required to install Homebrew automatically."
        return 1
    fi

    if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        echo "ERROR: Homebrew installation failed."
        return 1
    fi

    _zes_bootstrap_activate_brew

    if ! command -v brew >/dev/null 2>&1; then
        echo "ERROR: Homebrew was installed but is not on PATH in this shell."
        echo "Open a new terminal and run: brew install bash"
        return 1
    fi

    return 0
}

_zes_bootstrap_relaunch_with_brew_bash() {
    local brew_bash="$1"
    shift
    local installer_payload=""
    local relaunch_script=""

    if [[ -r "$0" ]] && [[ "$0" != /dev/fd/* ]] && [[ "$0" != /proc/self/fd/* ]] && [[ "$0" != "/dev/stdin" ]]; then
        echo "Re-launching installer with: $brew_bash"
        exec "$brew_bash" "$0" "$@"
    fi

    echo "Installer started from a transient stream ($0)."
    echo "Attempting automatic re-launch with Homebrew Bash using a fresh installer copy..."

    installer_payload="$(_zes_bootstrap_download_script "$_ZES_BOOTSTRAP_MAIN_INSTALL_URL")" || installer_payload=""
    if [[ -n "$installer_payload" ]]; then
        installer_payload="${installer_payload#$'\357\273\277'}"
        installer_payload="${installer_payload//$'\r'/}"

        relaunch_script=$(mktemp /tmp/zes-bootstrap-relaunch-XXXXXXXX.sh 2>/dev/null || mktemp 2>/dev/null || true)
        if [[ -n "$relaunch_script" ]]; then
            if printf '%s\n' "$installer_payload" >"$relaunch_script" 2>/dev/null; then
                chmod 700 "$relaunch_script" 2>/dev/null || true
                echo "Re-launching installer with: $brew_bash"
                echo "Installer source: $_ZES_BOOTSTRAP_MAIN_INSTALL_URL"
                exec "$brew_bash" "$relaunch_script" "$@"
            fi
            rm -f "$relaunch_script" 2>/dev/null || true
        fi

        echo "Re-launching installer with: $brew_bash"
        echo "Installer source: $_ZES_BOOTSTRAP_MAIN_INSTALL_URL"
        echo "Using stdin payload fallback (interactive prompts may be limited)."
        exec "$brew_bash" -s -- "$@" <<<"$installer_payload"
    fi

    echo ""
    echo "A modern Bash is installed at: $brew_bash"
    echo "Automatic relaunch failed because the installer script could not be fetched again."
    echo "Please rerun with:"
    echo "  \"$brew_bash\" <(curl -fsSL $_ZES_BOOTSTRAP_MAIN_INSTALL_URL)"
    return 1
}

_zes_bootstrap_macos_bash() {
    local brew_bash=""
    local bash_prefix=""

    if ! _zes_bootstrap_install_homebrew; then
        return 1
    fi

    _zes_bootstrap_activate_brew

    if ! brew list bash >/dev/null 2>&1; then
        if ! _zes_bootstrap_prompt_yes_no "Install modern Bash via Homebrew now?" "y"; then
            return 1
        fi

        if ! brew install bash; then
            echo "ERROR: Failed to install Bash via Homebrew."
            return 1
        fi
    fi

    bash_prefix=$(brew --prefix bash 2>/dev/null || echo "")
    if [[ -n "$bash_prefix" ]] && [[ -x "$bash_prefix/bin/bash" ]]; then
        brew_bash="$bash_prefix/bin/bash"
    elif [[ -x "/opt/homebrew/bin/bash" ]]; then
        brew_bash="/opt/homebrew/bin/bash"
    elif [[ -x "/usr/local/bin/bash" ]]; then
        brew_bash="/usr/local/bin/bash"
    fi

    if [[ -z "$brew_bash" ]]; then
        echo "ERROR: Could not locate Homebrew Bash after installation."
        return 1
    fi

    _zes_bootstrap_relaunch_with_brew_bash "$brew_bash" "$@"
}

if [[ -z "${BASH_VERSINFO[0]}" ]] || [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "ERROR: Bash 4.0 or higher is required (found ${BASH_VERSION:-unknown})"
    echo "This script uses associative arrays which require Bash 4.0+"
    echo ""
    if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
        echo "macOS ships Bash 3.2 by default."
        echo "This installer can bootstrap Homebrew and modern Bash for you."
        echo ""

        if _zes_bootstrap_is_interactive; then
            if _zes_bootstrap_prompt_yes_no "Install Homebrew (if needed) and modern Bash now?" "y"; then
                _zes_bootstrap_macos_bash "$@"
            fi
        else
            echo "Non-interactive mode detected: automatic bootstrap is not available."
        fi

        echo ""
        echo "Install manually with:"
        echo "  brew install bash"
        echo "Then re-run this installer using the Homebrew Bash binary."
    else
        echo "Your distribution should have bash 4+ by default."
        echo "Try: sudo apt install bash  (or equivalent for your distro)"
    fi
    exit 1
fi

# ── Remote module URL ──────────────────────────────────────────────────────
readonly _ZES_BASE_URL="https://raw.githubusercontent.com/Michael-Matta1/zsh-edit-select/main/assets/auto-install/lib"

readonly _ZES_MODULES=(
    "00-globals"
    "01-utils"
    "01-ui"
    "01-system"
    "02-detect"
    "02-detect-plugin"
    "03-deps"
    "03-deps-alt"
    "03-kitty"
    "03-prefs"
    "04-plugin"
    "05-agents"
    "06-terminals"
    "06-terminals-linux"
    "06-terminals-macos"
    "06-terminals-vscode"
    "07-conflicts"
    "07-conflicts-terminals"
    "08-verify"
    "09-summary"
    "10-modes"
    "10-lifecycle"
)

# ── Create temp directory ──────────────────────────────────────────────────
# ZES_INSTALL_TMPDIR is exported so that cleanup() in 01-utils.sh can
# delete it when the installer exits (success or failure).
ZES_INSTALL_TMPDIR=$(mktemp -d /tmp/zes-install-XXXXXXXX 2>/dev/null) || {
    echo "ERROR: Failed to create temporary directory. Check /tmp permissions."
    exit 1
}
chmod 700 "$ZES_INSTALL_TMPDIR"
export ZES_INSTALL_TMPDIR

# Minimal EXIT trap active before modules are loaded.
# After 01-utils.sh is sourced, its own `trap cleanup EXIT` takes over and
# cleanup() will also handle ZES_INSTALL_TMPDIR.
trap 'rm -rf "${ZES_INSTALL_TMPDIR:-}" 2>/dev/null' EXIT

# ── Detect piped stdin ─────────────────────────────────────────────────────
# curl ... | bash consumes stdin, making every `read` call fail silently.
# Detect this early and force non-interactive mode before any module is sourced.
if [[ ! -t 0 ]]; then
    _ZES_FORCE_NON_INTERACTIVE=1
    export _ZES_FORCE_NON_INTERACTIVE
    echo ""
    echo "Detected piped input (curl | bash). Running in non-interactive mode."
    echo ""
else
    _ZES_FORCE_NON_INTERACTIVE=0
    export _ZES_FORCE_NON_INTERACTIVE
fi

# ── Parse loader-only flags ────────────────────────────────────────────────
_ZES_LOCAL_MODE=0
_ZES_LOCAL_LIB_DIR=""

for _arg in "$@"; do
    if [[ "$_arg" == "--local" ]]; then
        _ZES_LOCAL_MODE=1
        # Prefer resolving local modules relative to this loader script so
        # --local works both from repo root and from assets/auto-install.
        _zes_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
        if [[ -n "$_zes_self_dir" ]] && [[ -d "$_zes_self_dir/lib" ]]; then
            _ZES_LOCAL_LIB_DIR="$_zes_self_dir/lib"
        else
            # Backward-compatible fallback for repo-root invocation style.
            _ZES_LOCAL_LIB_DIR="$(pwd)/assets/auto-install/lib"
        fi
        unset _zes_self_dir
        break
    elif [[ "$_arg" == --local=* ]]; then
        _ZES_LOCAL_MODE=1
        _ZES_LOCAL_LIB_DIR="${_arg#--local=}"
        break
    fi
done
unset _arg

# Guard: --local without an explicit path fails silently when the script is
# run via bash <(curl ...) because BASH_SOURCE[0] is /dev/stdin.
if [[ $_ZES_LOCAL_MODE -eq 1 ]]; then
    case "$_ZES_LOCAL_LIB_DIR" in
    "")
        if [[ "${BASH_SOURCE[0]}" == "/dev/stdin" ]] || [[ "${BASH_SOURCE[0]}" == /dev/fd/* ]] || [[ "${BASH_SOURCE[0]}" == /proc/self/fd/* ]]; then
            echo "ERROR: Cannot use --local without an explicit path when piped via bash <(curl ...)"
            echo "Retry from the cloned repository with: bash assets/auto-install/install.sh --local=/path/to/repo/assets/auto-install/lib"
            exit 1
        fi
        ;;
    esac

    # If running from a local plugin tree, infer the plugin root so
    # maintenance modes can target the active installation path directly.
    if [[ -d "$_ZES_LOCAL_LIB_DIR" ]]; then
        _zes_local_plugin_root=""
        _zes_local_plugin_root="$(cd "$_ZES_LOCAL_LIB_DIR/../../.." 2>/dev/null && pwd -P)"
        if [[ -n "$_zes_local_plugin_root" ]] && [[ -f "$_zes_local_plugin_root/zsh-edit-select.plugin.zsh" ]]; then
            export ZES_PLUGIN_DIR_HINT="$_zes_local_plugin_root"
        fi
        unset _zes_local_plugin_root
    fi
fi

# ── Download helper ────────────────────────────────────────────────────────
_zes_download() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -O- "$url" 2>/dev/null
    else
        return 1
    fi
}

# Normalize shell module files before sourcing.
# This strips a UTF-8 BOM and Windows CRLF endings that can break `source`.
_zes_normalize_shell_file() {
    local file_path="$1"
    local tmp_path=""
    local line=""
    local first_line=1

    [[ -f "$file_path" ]] || return 1

    tmp_path=$(mktemp 2>/dev/null) || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $first_line -eq 1 ]]; then
            first_line=0
            line="${line#$'\357\273\277'}"
        fi

        line="${line%$'\r'}"
        if ! printf '%s\n' "$line" >>"$tmp_path"; then
            rm -f "$tmp_path"
            return 1
        fi
    done <"$file_path"

    if mv "$tmp_path" "$file_path" 2>/dev/null; then
        return 0
    fi

    if cp "$tmp_path" "$file_path" 2>/dev/null; then
        rm -f "$tmp_path"
        return 0
    fi

    rm -f "$tmp_path"
    return 1
}

_zes_download_module_set() {
    local base_url="$1"
    local message_level="${2:-ERROR}"
    local _zes_mod=""
    local _zes_mod_path=""

    for _zes_mod in "${_ZES_MODULES[@]}"; do
        _zes_mod_path="$ZES_INSTALL_TMPDIR/${_zes_mod}.sh"
        if ! _zes_download "$base_url/${_zes_mod}.sh" >"$_zes_mod_path" 2>/dev/null; then
            echo "${message_level}: Failed to download module: $_zes_mod"
            return 1
        fi
        if ! _zes_normalize_shell_file "$_zes_mod_path"; then
            echo "${message_level}: Failed to normalize module: $_zes_mod"
            return 1
        fi
    done

    return 0
}

# ── Local mode or remote two-phase download ────────────────────────────────
if [[ $_ZES_LOCAL_MODE -eq 1 ]]; then
    # ── Local mode: source directly from filesystem ────────────────────────
    for _zes_mod in "${_ZES_MODULES[@]}"; do
        _zes_local_file="$_ZES_LOCAL_LIB_DIR/${_zes_mod}.sh"
        _zes_local_tmp="$ZES_INSTALL_TMPDIR/${_zes_mod}.local.sh"
        if [[ ! -f "$_zes_local_file" ]]; then
            echo "ERROR: Module not found: $_zes_local_file"
            exit 1
        fi
        if ! cp "$_zes_local_file" "$_zes_local_tmp" 2>/dev/null; then
            echo "ERROR: Failed to stage local module: $_zes_mod"
            exit 1
        fi
        if ! _zes_normalize_shell_file "$_zes_local_tmp"; then
            echo "ERROR: Failed to normalize local module: $_zes_mod"
            exit 1
        fi
        # shellcheck disable=SC1090
        source "$_zes_local_tmp" || exit 1
    done
    unset _zes_mod _zes_local_file _zes_local_tmp

else
    # ── Remote mode ────────────────────────────────────────────────────────

    # Phase 1: Download all modules.
    echo "Fetching installer modules..."
    if ! _zes_download_module_set "$_ZES_BASE_URL" "ERROR"; then
        echo "ERROR: Could not fetch all required modules from:"
        echo "  $_ZES_BASE_URL"
        echo "Check your network/proxy settings, then retry."
        exit 1
    fi

    echo "Modules fetched from: $_ZES_BASE_URL"

    # Source all modules from temp directory
    for _zes_mod in "${_ZES_MODULES[@]}"; do
        # shellcheck disable=SC1090
        source "$ZES_INSTALL_TMPDIR/${_zes_mod}.sh" || exit 1
    done
fi

# Clean up loader-internal variables so they do not leak into module scope.
unset _ZES_LOCAL_MODE _ZES_LOCAL_LIB_DIR

# ── Run installer (strip loader-only flags from args) ─────────────────────
_zes_main_args=()
for _arg in "$@"; do
    [[ "$_arg" == "--local" || "$_arg" == --local=* ]] && continue
    _zes_main_args+=("$_arg")
done
unset _arg

# Run main function only if not sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "${_zes_main_args[@]}"
fi
