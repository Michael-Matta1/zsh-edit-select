#!/usr/bin/env bash
# Copyright (c) 2025 Michael Matta
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select
#
# auto-install module: Konsole configuration
# Part of the zsh-edit-select auto-installer.
# Loaded by assets/auto-install/install.sh -- do not run directly.
# shellcheck shell=bash
# shellcheck disable=SC2034

# Sourcing guard -- prevent re-declaration errors if sourced more than once.
[[ -n "${_ZES_MOD_TERMINALS_KONSOLE_LOADED:-}" ]] && return 0
readonly _ZES_MOD_TERMINALS_KONSOLE_LOADED=1

_zes_configure_konsole_ui_file() {
    local config_file="$1"
    local gui_name="$2"
    local shortcut_scheme="$3"
    local scheme_file="${4:-}"
    local operation="${5:-write}"
    local config_dir
    local staged_file
    local script_status=0

    if [[ -L "$config_file" ]]; then
        print_error "Refusing to replace a symlinked Konsole shortcut file: $config_file"
        return 1
    fi
    if [[ -e "$config_file" ]] && { [[ ! -f "$config_file" ]] || [[ ! -r "$config_file" ]] || [[ ! -w "$config_file" ]]; }; then
        print_error "Konsole shortcut file is not a readable, writable regular file: $config_file"
        return 1
    fi

    config_dir="$(dirname "$config_file")"
    if ! mkdir -p "$config_dir" 2>/dev/null; then
        print_error "Could not create Konsole shortcut directory: $config_dir"
        return 1
    fi
    staged_file="$(mktemp "$config_dir/.zsh-edit-select-konsole-ui.XXXXXX" 2>/dev/null)" || {
        print_error "Could not create a temporary Konsole shortcut file."
        return 1
    }

    python3 - "$config_file" "$gui_name" "$shortcut_scheme" "$staged_file" "$scheme_file" "$operation" <<'PYTHON_KONSOLE_UI' || script_status=$?
import os
import re
import stat
import sys
import xml.etree.ElementTree as ET

source_path, gui_name, active_scheme, staged_path, scheme_path, operation = sys.argv[1:]
if gui_name == "session":
    overrides = (("edit_copy", "none"), ("sigint-signal", "none"))
elif gui_name == "konsole":
    overrides = (("next-tab", "Ctrl+PgDown"), ("previous-tab", "Ctrl+PgUp"))
else:
    raise SystemExit("Unsupported Konsole shortcut collection")

if os.path.exists(source_path):
    try:
        with open(source_path, "r", encoding="utf-8") as source:
            source_text = source.read()
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True, insert_pis=True))
        tree = ET.parse(source_path, parser=parser)
    except (OSError, ET.ParseError, TypeError, UnicodeError) as exc:
        raise SystemExit("Cannot safely parse existing Konsole shortcut XML: " + str(exc))
    root = tree.getroot()
    if root.tag.lower() != "gui" or root.get("name") != gui_name:
        raise SystemExit("Existing Konsole shortcut XML has an unexpected root; leaving it unchanged")
else:
    source_text = ""
    root = ET.Element("gui", {"name": gui_name, "version": "1"})
    tree = ET.ElementTree(root)

scheme_shortcuts = {}
if gui_name == "konsole" and active_scheme != "Default" and scheme_path:
    try:
        scheme_root = ET.parse(scheme_path).getroot()
    except (OSError, ET.ParseError, UnicodeError) as exc:
        raise SystemExit("Cannot safely read the active Konsole shortcut scheme: " + str(exc))
    scheme_properties = [
        element for element in scheme_root
        if isinstance(element.tag, str) and element.tag.lower() == "actionproperties"
    ]
    if len(scheme_properties) > 1:
        raise SystemExit("Active Konsole shortcut scheme has duplicate action properties")
    if scheme_properties:
        for action in scheme_properties[0]:
            if isinstance(action.tag, str) and action.tag.lower() == "action":
                name = action.get("name")
                if name in ("next-tab", "previous-tab"):
                    if name in scheme_shortcuts:
                        raise SystemExit("Active Konsole shortcut scheme has duplicate tab action entries")
                    scheme_shortcuts[name] = action.get("shortcut", "")

changed = not os.path.exists(source_path)
schemes = ["Default"]
if active_scheme and active_scheme != "Default":
    schemes.append(active_scheme)

for scheme in schemes:
    properties = [
        element for element in root
        if isinstance(element.tag, str)
        and element.tag.lower() == "actionproperties"
        and element.get("scheme", "Default") == scheme
    ]
    if len(properties) > 1:
        raise SystemExit("Existing Konsole shortcut XML has duplicate action schemes; leaving it unchanged")
    if properties:
        action_properties = properties[0]
    else:
        action_properties = ET.SubElement(root, "ActionProperties", {"scheme": scheme})
        changed = True

    for action_name, shortcut in overrides:
        actions = [
            element for element in action_properties
            if isinstance(element.tag, str)
            and element.tag.lower() == "action"
            and element.get("name") == action_name
        ]
        if len(actions) > 1:
            raise SystemExit("Existing Konsole shortcut XML has duplicate action entries; leaving it unchanged")
        if actions:
            action = actions[0]
        else:
            action = ET.SubElement(action_properties, "Action", {"name": action_name})
            changed = True
        desired_shortcut = shortcut
        if action_name in ("next-tab", "previous-tab"):
            # Only remove the documented conflicting Shift+Arrow binding.
            # Keep any other shortcut the user assigned to this action.
            conflict = "shift+right" if action_name == "next-tab" else "shift+left"
            current_shortcut = action.get("shortcut")
            if current_shortcut is None:
                current_shortcut = scheme_shortcuts.get(action_name, "") if scheme == active_scheme else ""
            existing = [item.strip() for item in current_shortcut.split(";") if item.strip()]
            existing = [item for item in existing if re.sub(r"\s+", "", item).lower() != conflict]
            if existing:
                desired_shortcut = "; ".join(existing)

        if action.get("shortcut") != desired_shortcut:
            action.set("shortcut", desired_shortcut)
            changed = True

if not changed:
    raise SystemExit(3)

declaration = re.search(r"<\?xml\s+[^?]*\?>", source_text)
doctype = re.search(r"<!DOCTYPE\s+gui\s+SYSTEM\s+(['\"])kpartgui\.dtd\1\s*>", source_text, re.IGNORECASE)
if "<!DOCTYPE" in source_text and not doctype:
    raise SystemExit("Existing Konsole shortcut XML uses an unsupported DOCTYPE; leaving it unchanged")
xml_text = (declaration.group(0) if declaration else '<?xml version="1.0"?>') + "\n"
if doctype:
    xml_text += doctype.group(0) + "\n"
xml_text += ET.tostring(root, encoding="unicode", short_empty_elements=True) + "\n"

if operation == "validate":
    raise SystemExit(0)

try:
    with open(staged_path, "w", encoding="utf-8", newline="\n") as staged:
        staged.write(xml_text)
    if os.path.exists(source_path):
        os.chmod(staged_path, stat.S_IMODE(os.stat(source_path).st_mode))
    else:
        os.chmod(staged_path, 0o644)
except OSError as exc:
    raise SystemExit("Could not stage Konsole shortcut XML: " + str(exc))
PYTHON_KONSOLE_UI

    if [[ $script_status -eq 3 ]]; then
        rm -f "$staged_file"
        return 0
    fi
    if [[ $script_status -ne 0 ]]; then
        rm -f "$staged_file"
        return 1
    fi
    if [[ "$operation" == "validate" ]]; then
        rm -f "$staged_file"
        return 0
    fi

    if [[ -f "$config_file" ]] && ! backup_config "$config_file"; then
        rm -f "$staged_file"
        print_error "Could not back up Konsole shortcut file: $config_file"
        return 1
    fi
    if ! mv -f "$staged_file" "$config_file" 2>/dev/null; then
        rm -f "$staged_file"
        print_error "Could not install Konsole shortcut file: $config_file"
        return 1
    fi
    return 0
}


configure_konsole_shortcuts() {
    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
    local shortcut_scheme="Default"
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local shortcut_scheme_file=""

    if ! shortcut_scheme="$(python3 - "$config_file" <<'PYTHON_KONSOLE_SCHEME'
import configparser
import os
import sys

config = configparser.RawConfigParser(interpolation=None, strict=False)
config_dirs = [path for path in os.environ.get("XDG_CONFIG_DIRS", "/etc/xdg").split(os.pathsep)
               if path and os.path.isabs(path)]
for path in [os.path.join(directory, "kdeglobals") for directory in reversed(config_dirs)] + [sys.argv[1]]:
    if not os.path.isfile(path):
        continue
    try:
        with open(path, "r", encoding="utf-8") as source:
            config.read_file(source)
    except (OSError, configparser.Error, UnicodeError) as exc:
        raise SystemExit("Cannot read the active KDE shortcut scheme: " + str(exc))
print(config.get("Shortcut Schemes", "Current Scheme", fallback="Default").strip() or "Default")
PYTHON_KONSOLE_SCHEME
    )"; then
        print_error "Could not determine the active KDE shortcut scheme."
        return 1
    fi

    if [[ "$shortcut_scheme" != "Default" ]] && [[ "$shortcut_scheme" != */* ]]; then
        local -a data_dirs=()
        local data_dir
        local candidate
        IFS=: read -r -a data_dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
        for data_dir in "$data_home" "${data_dirs[@]}"; do
            [[ -n "$data_dir" ]] || continue
            candidate="$data_dir/konsole/shortcuts/$shortcut_scheme"
            if [[ -f "$candidate" ]]; then
                shortcut_scheme_file="$candidate"
                break
            fi
        done
    fi

    if [[ "$shortcut_scheme" != "Default" ]] && [[ -z "$shortcut_scheme_file" ]]; then
        print_error "Could not locate the active Konsole shortcut scheme '$shortcut_scheme'; refusing to overwrite tab shortcuts without preserving its assignments."
        return 1
    fi

    # KXMLGUI keeps this per-user configuration directory named kxmlgui5
    # for both KF5 and KF6 applications.
    local gui_dir="$data_home/kxmlgui5/konsole"
    # Validate both files before changing either one. This prevents a malformed
    # second file from leaving only the session shortcuts (Copy/INT) changed.
    if ! _zes_configure_konsole_ui_file "$gui_dir/konsoleui.rc" "konsole" "$shortcut_scheme" "$shortcut_scheme_file" "validate" ||
        ! _zes_configure_konsole_ui_file "$gui_dir/sessionui.rc" "session" "$shortcut_scheme" "$shortcut_scheme_file" "validate"; then
        MANUAL_STEPS+=("Konsole: review the shortcut files in $gui_dir and apply manual setup step 3 in README.md if needed")
        return 1
    fi

    if ! _zes_configure_konsole_ui_file "$gui_dir/sessionui.rc" "session" "$shortcut_scheme" "$shortcut_scheme_file" ||
        ! _zes_configure_konsole_ui_file "$gui_dir/konsoleui.rc" "konsole" "$shortcut_scheme" "$shortcut_scheme_file"; then
        MANUAL_STEPS+=("Konsole: review the shortcut files in $gui_dir and apply manual setup step 3 in README.md if needed")
        return 1
    fi

    return 0
}


configure_konsole() {
    print_step "Configuring Konsole..."

    local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/konsole"
    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/konsolerc"
    local profile_file="$data_dir/zsh-edit-select.profile"
    local keytab_file="$data_dir/zsh-edit-select.keytab"
    local kwriteconfig=""

    if command_exists kwriteconfig6; then
        kwriteconfig="$(get_full_path kwriteconfig6)"
    elif command_exists kwriteconfig5; then
        kwriteconfig="$(get_full_path kwriteconfig5)"
    elif command_exists kwriteconfig; then
        kwriteconfig="$(get_full_path kwriteconfig)"
    else
        print_error "Could not find kwriteconfig6, kwriteconfig5, or kwriteconfig to set Konsole's default profile."
        MANUAL_STEPS+=("Konsole: apply any missing parts of manual setup steps 1-3 in README.md, preserving existing valid profile/keytab files; or install KDE's kwriteconfig utility and rerun 'edit-select integrate'")
        return 1
    fi

    if ! command_exists python3 || ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
        print_error "Python 3.8 or newer is required to safely update Konsole's shortcut XML."
        MANUAL_STEPS+=("Konsole: apply any missing parts of manual setup steps 1-3 in README.md, preserving existing valid profile/keytab files; or install Python 3.8 or newer and rerun 'edit-select integrate'")
        return 1
    fi

    if ! mkdir -p "$data_dir" "$(dirname "$config_file")" 2>/dev/null; then
        print_error "Could not create Konsole configuration directories."
        MANUAL_STEPS+=("Konsole: apply manual setup steps 1-3 in README.md after making the Konsole configuration directories writable")
        return 1
    fi

    # Check both reserved output paths before creating either one. A collision
    # must never leave a half-installed profile/keytab pair.
    if [[ -e "$keytab_file" || -L "$keytab_file" ]] && {
        [[ ! -f "$keytab_file" ]] ||
            ! grep -qFx 'keyboard "zsh-edit-select"' "$keytab_file" 2>/dev/null ||
            ! grep -qFx 'key Z     +Control+Shift : "\E[90;6u"' "$keytab_file" 2>/dev/null ||
            ! grep -qFx 'key Up    +Shift-Alt-Ctrl-AppScreen : "\E[1;2A"' "$keytab_file" 2>/dev/null ||
            {
                ! grep -qFx 'key C     +Control+Shift : "\E[67;6u"' "$keytab_file" 2>/dev/null &&
                    {
                        ! grep -qFx 'key C     +Control-Shift : "\E[67;6u"' "$keytab_file" 2>/dev/null ||
                            ! grep -qFx 'key C     +Control+Shift : "\x03"' "$keytab_file" 2>/dev/null
                    }
            }
    }; then
        print_error "The existing Konsole keytab does not look like a zsh-edit-select keytab; leaving it and the default profile unchanged."
        MANUAL_STEPS+=("Konsole: review the existing keytab before configuring it: $keytab_file")
        return 1
    fi
    if [[ -e "$profile_file" || -L "$profile_file" ]] && {
        [[ ! -f "$profile_file" ]] || ! awk '
        /^\[General\][[:space:]]*$/ { section = "General"; next }
        /^\[Keyboard\][[:space:]]*$/ { section = "Keyboard"; next }
        /^\[/ { section = "" }
        section == "General" && /^[[:space:]]*Name[[:space:]]*=[[:space:]]*zsh-edit-select[[:space:]]*$/ { name = 1 }
        section == "Keyboard" && /^[[:space:]]*KeyBindings[[:space:]]*=[[:space:]]*zsh-edit-select[[:space:]]*$/ { keybindings = 1 }
        END { exit !(name && keybindings) }
    ' "$profile_file" 2>/dev/null
    }; then
        print_error "The existing Konsole profile is not configured for the zsh-edit-select keytab; leaving it and the default profile unchanged."
        MANUAL_STEPS+=("Konsole: review the existing profile before configuring it: $profile_file")
        return 1
    fi

    if [[ -f "$config_file" ]] && ! backup_config "$config_file"; then
        print_error "Could not back up Konsole configuration file: $config_file"
        return 1
    fi

    local keytab_created=0
    if [[ ! -e "$keytab_file" && ! -L "$keytab_file" ]]; then
        local keytab_tmp
        keytab_tmp="$(mktemp "$data_dir/.zsh-edit-select-keytab.XXXXXX" 2>/dev/null)" || {
            print_error "Could not create a temporary Konsole keytab."
            MANUAL_STEPS+=("Konsole: apply manual setup steps 1-3 in README.md")
            return 1
        }

        if ! cat >"$keytab_tmp" <<'ZES_KONSOLE_KEYTAB'
keyboard "zsh-edit-select"

key Escape : "\E"
key Tab -Shift : "\t"
key Tab +Shift+Ansi : "\E[Z"
key Tab +Shift-Ansi : "\t"
key Backtab +Ansi : "\E[Z"
key Backtab -Ansi : "\t"
key Tab +Control+Ansi : "\E[27;5;9~"
key Backtab +Control+Ansi : "\E[27;6;9~"
key Tab +Control-Ansi : "\t"
key Backtab +Control-Ansi : "\t"
key Return-Shift-NewLine : "\r"
key Return-Shift+NewLine : "\r\n"
key Return+Shift : "\EOM"
key Backspace -Control : "\x7f"
key Backspace +Control : "\b"

key Up -Shift-Ansi : "\EA"
key Down -Shift-Ansi : "\EB"
key Right-Shift-Ansi : "\EC"
key Left -Shift-Ansi : "\ED"

key Up -Shift-AnyMod+Ansi+AppCuKeys : "\EOA"
key Down -Shift-AnyMod+Ansi+AppCuKeys : "\EOB"
key Right -Shift-AnyMod+Ansi+AppCuKeys : "\EOC"
key Left -Shift-AnyMod+Ansi+AppCuKeys : "\EOD"
key Up -Shift-AnyMod+Ansi-AppCuKeys : "\E[A"
key Down -Shift-AnyMod+Ansi-AppCuKeys : "\E[B"
key Right -Shift-AnyMod+Ansi-AppCuKeys : "\E[C"
key Left -Shift-AnyMod+Ansi-AppCuKeys : "\E[D"
key Up -Shift+AnyMod+Ansi : "\E[1;*A"
key Down -Shift+AnyMod+Ansi : "\E[1;*B"
key Right -Shift+AnyMod+Ansi : "\E[1;*C"
key Left -Shift+AnyMod+Ansi : "\E[1;*D"
key Up +Shift+AppScreen : "\E[1;*A"
key Down +Shift+AppScreen : "\E[1;*B"
key Left +Shift+AppScreen : "\E[1;*D"
key Right +Shift+AppScreen : "\E[1;*C"
key Up +Shift+Alt-AppScreen : "\E[1;*A"
key Down +Shift+Alt-AppScreen : "\E[1;*B"
key Left +Shift+Alt-AppScreen : "\E[1;*D"
key Right +Shift+Alt-AppScreen : "\E[1;*C"
key Up +Shift+Ctrl-AppScreen : "\E[1;*A"
key Down +Shift+Ctrl-AppScreen : "\E[1;*B"
key Left +Shift+Ctrl-AppScreen : "\E[1;*D"
key Right +Shift+Ctrl-AppScreen : "\E[1;*C"

key Up -Shift+Ansi+AppCuKeys+KeyPad : "\EOA"
key Down -Shift+Ansi+AppCuKeys+KeyPad : "\EOB"
key Right -Shift+Ansi+AppCuKeys+KeyPad : "\EOC"
key Left -Shift+Ansi+AppCuKeys+KeyPad : "\EOD"
key Up -Shift+Ansi-AppCuKeys+KeyPad : "\E[A"
key Down -Shift+Ansi-AppCuKeys+KeyPad : "\E[B"
key Right -Shift+Ansi-AppCuKeys+KeyPad : "\E[C"
key Left -Shift+Ansi-AppCuKeys+KeyPad : "\E[D"
key Home +AppCuKeys+KeyPad : "\EOH"
key End +AppCuKeys+KeyPad : "\EOF"
key Home -AppCuKeys+KeyPad : "\E[H"
key End -AppCuKeys+KeyPad : "\E[F"
key Insert +KeyPad : "\E[2~"
key Delete +KeyPad : "\E[3~"
key PgUp -Shift+KeyPad : "\E[5~"
key PgDown -Shift+KeyPad : "\E[6~"
key Clear +KeyPad : "\E[E"

key Enter+NewLine : "\r\n"
key Enter-NewLine : "\r"
key Home -AnyMod-AppCuKeys : "\E[H"
key End -AnyMod-AppCuKeys : "\E[F"
key Home -AnyMod+AppCuKeys : "\EOH"
key End -AnyMod+AppCuKeys : "\EOF"
key Home +AnyMod : "\E[1;*H"
key End +AnyMod : "\E[1;*F"
key Insert -AnyMod : "\E[2~"
key Delete -AnyMod : "\E[3~"
key Insert +AnyMod : "\E[2;*~"
key Delete +AnyMod : "\E[3;*~"
key PgUp -Shift-AnyMod : "\E[5~"
key PgDown -Shift-AnyMod : "\E[6~"
key PgUp -Shift+AnyMod : "\E[5;*~"
key PgDown -Shift+AnyMod : "\E[6;*~"
key PgUp +Shift+AppScreen : "\E[5;*~"
key PgDown +Shift+AppScreen : "\E[6;*~"

key F1 -AnyMod : "\EOP"
key F2 -AnyMod : "\EOQ"
key F3 -AnyMod : "\EOR"
key F4 -AnyMod : "\EOS"
key F5 -AnyMod : "\E[15~"
key F6 -AnyMod : "\E[17~"
key F7 -AnyMod : "\E[18~"
key F8 -AnyMod : "\E[19~"
key F9 -AnyMod : "\E[20~"
key F10 -AnyMod : "\E[21~"
key F11 -AnyMod : "\E[23~"
key F12 -AnyMod : "\E[24~"
key F1 +AnyMod : "\EO*P"
key F2 +AnyMod : "\EO*Q"
key F3 +AnyMod : "\EO*R"
key F4 +AnyMod : "\EO*S"
key F5 +AnyMod : "\E[15;*~"
key F6 +AnyMod : "\E[17;*~"
key F7 +AnyMod : "\E[18;*~"
key F8 +AnyMod : "\E[19;*~"
key F9 +AnyMod : "\E[20;*~"
key F10 +AnyMod : "\E[21;*~"
key F11 +AnyMod : "\E[23;*~"
key F12 +AnyMod : "\E[24;*~"

key Space +Control : "\x00"

# Konsole scroll actions (Shift+Up/Down/Home/End removed on purpose for zsh-edit-select)
key PgUp -Ctrl+Shift-AppScreen : scrollPageUp
key PgUp +Ctrl+Shift-AppScreen : scrollPromptUp
key PgDown -Ctrl+Shift-AppScreen : scrollPageDown
key PgDown +Ctrl+Shift-AppScreen : scrollPromptDown

# zsh-edit-select bindings
__ZES_COPY_BINDINGS__
key Z     +Control+Shift : "\E[90;6u"
key Up    +Shift-Alt-Ctrl-AppScreen : "\E[1;2A"
key Down  +Shift-Alt-Ctrl-AppScreen : "\E[1;2B"
key Right +Shift-Alt-Ctrl-AppScreen : "\E[1;2C"
key Left  +Shift-Alt-Ctrl-AppScreen : "\E[1;2D"
ZES_KONSOLE_KEYTAB
        then
            rm -f "$keytab_tmp"
            print_error "Could not write the Konsole keytab."
            MANUAL_STEPS+=("Konsole: apply manual setup steps 1-3 in README.md")
            return 1
        fi
        local expanded_keytab="$keytab_tmp.expanded"
        if ! awk -v reversed="$USER_WANTS_REVERSED_COPY" '
            $0 == "__ZES_COPY_BINDINGS__" {
                if (reversed == "y") {
                    print "key C     +Control-Shift : \"\\E[67;6u\""
                    print "key C     +Control+Shift : \"\\x03\""
                } else {
                    print "key C     +Control+Shift : \"\\E[67;6u\""
                }
                next
            }
            { print }
        ' "$keytab_tmp" >"$expanded_keytab"; then
            rm -f "$keytab_tmp" "$expanded_keytab"
            print_error "Could not generate the Konsole keytab."
            MANUAL_STEPS+=("Konsole: apply manual setup steps 1-3 in README.md")
            return 1
        fi
        chmod 644 "$expanded_keytab" 2>/dev/null || true
        if ! mv "$expanded_keytab" "$keytab_file" 2>/dev/null; then
            rm -f "$keytab_tmp" "$expanded_keytab"
            print_error "Could not install the Konsole keytab: $keytab_file"
            MANUAL_STEPS+=("Konsole: apply manual setup steps 1-3 in README.md")
            return 1
        fi
        rm -f "$keytab_tmp"
        keytab_created=1
    else
        print_info "Keeping existing Konsole keytab: $keytab_file"
    fi

    if [[ ! -e "$profile_file" && ! -L "$profile_file" ]]; then
        local profile_parent
        if ! profile_parent="$(python3 - "$config_file" <<'PYTHON_KONSOLE_PROFILE_PARENT'
import configparser
import os
import sys

config = configparser.RawConfigParser(interpolation=None, strict=False)
config_dirs = [path for path in os.environ.get("XDG_CONFIG_DIRS", "/etc/xdg").split(os.pathsep)
               if path and os.path.isabs(path)]
for path in [os.path.join(directory, "konsolerc") for directory in reversed(config_dirs)] + [sys.argv[1]]:
    if not os.path.isfile(path):
        continue
    try:
        with open(path, "r", encoding="utf-8") as source:
            config.read_file(source)
    except (OSError, configparser.Error, UnicodeError) as exc:
        raise SystemExit("Cannot safely read Konsole configuration: " + str(exc))

parent = config.get("Desktop Entry", "DefaultProfile", fallback="").strip()
if parent in ("", "zsh-edit-select", "zsh-edit-select.profile"):
    parent = "FALLBACK/"
elif parent != "FALLBACK/" and ("/" in parent or "\\" in parent or "\n" in parent or "\r" in parent):
    raise SystemExit("Unexpected Konsole default profile path")
print(parent)
PYTHON_KONSOLE_PROFILE_PARENT
        )"; then
            [[ $keytab_created -eq 1 ]] && rm -f "$keytab_file"
            print_error "Could not safely determine Konsole's current default profile."
            MANUAL_STEPS+=("Konsole: create the zsh-edit-select profile by copying your current default profile, then set its Keyboard Key Bindings to zsh-edit-select and follow manual setup step 3 in README.md")
            return 1
        fi

        local profile_tmp
        profile_tmp="$(mktemp "$data_dir/.zsh-edit-select-profile.XXXXXX" 2>/dev/null)" || {
            [[ $keytab_created -eq 1 ]] && rm -f "$keytab_file"
            print_error "Could not create a temporary Konsole profile."
            MANUAL_STEPS+=("Konsole: apply manual setup steps 1-3 in README.md")
            return 1
        }
        if ! printf '[General]\nName=zsh-edit-select\nParent=%s\n\n[Keyboard]\nKeyBindings=zsh-edit-select\n' "$profile_parent" >"$profile_tmp"; then
            rm -f "$profile_tmp"
            [[ $keytab_created -eq 1 ]] && rm -f "$keytab_file"
            print_error "Could not write the Konsole profile."
            MANUAL_STEPS+=("Konsole: apply manual setup steps 1-3 in README.md")
            return 1
        fi
        chmod 644 "$profile_tmp" 2>/dev/null || true
        if ! mv "$profile_tmp" "$profile_file" 2>/dev/null; then
            rm -f "$profile_tmp"
            [[ $keytab_created -eq 1 ]] && rm -f "$keytab_file"
            print_error "Could not install the Konsole profile: $profile_file"
            MANUAL_STEPS+=("Konsole: apply manual setup steps 1-3 in README.md")
            return 1
        fi
    else
        print_info "Keeping existing Konsole profile: $profile_file"
    fi

    if ! configure_konsole_shortcuts; then
        print_error "Could not configure Konsole's Copy, Interrupt Task, and tab shortcuts."
        MANUAL_STEPS+=("Konsole: set the zsh-edit-select profile as default and apply manual setup steps 2-3 in README.md")
        return 1
    fi

    if ! "$kwriteconfig" --file "$config_file" --group "Desktop Entry" --key "DefaultProfile" "zsh-edit-select.profile"; then
        print_error "Could not set Konsole's default profile."
        MANUAL_STEPS+=("Konsole: set DefaultProfile=zsh-edit-select.profile in [Desktop Entry] of $config_file")
        return 1
    fi

    if [[ $keytab_created -eq 1 ]]; then
        print_success "Created Konsole keytab and profile, selected it as default, and configured the shortcuts" "konsole_config"
    else
        print_success "Configured Konsole profile, selected it as default, and configured the shortcuts" "konsole_config"
    fi

    print_info "Restart Konsole for the profile and shortcut changes to take effect."
}
