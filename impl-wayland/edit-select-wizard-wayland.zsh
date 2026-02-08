# Copyright (c) 2025 Michael Matta
# Version: 0.5.3
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select

typeset -g _EDIT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select/config"
typeset -g _EDIT_SELECT_WIZARD_DIR="${0:A:h}"
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SELECT_ALL='^A'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_PASTE+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_PASTE='^V'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_CUT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_CUT='^X'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_UNDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_UNDO='^Z'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_REDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_REDO='^[[90;6u'

function _zesw_init_colors() {
	[[ -n $_ZESW_CLR_ACCENT ]] && return
	autoload -Uz colors && colors >/dev/null 2>&1 || true
	typeset -g _ZESW_CLR_ACCENT="${fg_bold[cyan]:-}"
	typeset -g _ZESW_CLR_HILITE="${fg_bold[green]:-}"
	typeset -g _ZESW_CLR_WARN="${fg_bold[red]:-}"
	typeset -g _ZESW_CLR_DIM="${fg[245]:-}"
	typeset -g _ZESW_CLR_RESET="${reset_color:-}"
}

function _zesw_banner() {
	clear
	local title="$1" width=62
	local padding=$(( (width - ${#title}) / 2 ))
	local padded_title="$(printf '%*s' $padding '')${title}$(printf '%*s' $((width - ${#title} - padding)) '')"
	printf "\n%s╔══════════════════════════════════════════════════════════════╗%s\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
	printf "%s║%s%s%s║%s\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_HILITE" "$padded_title" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
	printf "%s╚══════════════════════════════════════════════════════════════╝%s\n\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
}

function _zesw_prompt_continue() { printf "\n%s▶ Press Enter to continue...%s " "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"; read -r; }
function _zesw_print_option() { printf "  %s%2s.%s %s\n" "$_ZESW_CLR_HILITE" "$1" "$_ZESW_CLR_RESET" "$2"; }
function _zesw_input_prompt() { printf "\n%s▶%s %s " "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET" "$1"; }
function _zesw_status_line() { printf "  %s●%s %-18s %s\n" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET" "$1:" "$2"; }
function _zesw_success() { printf "\n%s✓%s %s\n" "$_ZESW_CLR_HILITE" "$_ZESW_CLR_RESET" "$1"; }
function _zesw_error() { printf "\n%s✗%s %s\n" "$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET" "$1"; }
function _zesw_section_header() { printf "\n%s─── %s ───%s\n" "$_ZESW_CLR_ACCENT" "$1" "$_ZESW_CLR_RESET"; }
function _zesw_separator() { printf "%s────────────────────────────────────────────────────────────────%s\n" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"; }
function _zesw_info() { printf "  %s ℹ%s  %s\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET" "$1"; }
function _zesw_confirm_prompt() { printf "\n%s?%s %s %s[y/N]:%s " "$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET" "$1" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"; }

function _zesw_get_monitor_type() {
	case "$_ZES_MONITOR_TYPE" in
		x11) printf "X11 (XWayland - invisible)" ;;
		wayland) printf "Wayland (native)" ;;
		*) printf "Unknown" ;;
	esac
}

function _zesw_get_mouse_status() { (( EDIT_SELECT_MOUSE_REPLACEMENT )) && printf "enabled" || printf "disabled"; }

function edit-select::delete-config-key() {
	[[ -f "$_EDIT_SELECT_CONFIG_FILE" ]] || return
	local -a filtered=("${(@)${(@f)$(<$_EDIT_SELECT_CONFIG_FILE)}:#${1}=*}")
	(( ${#filtered[@]} )) && printf '%s\n' "${filtered[@]}" > "$_EDIT_SELECT_CONFIG_FILE" || rm -f "$_EDIT_SELECT_CONFIG_FILE"
}

function edit-select::save-config() {
	mkdir -p "${_EDIT_SELECT_CONFIG_FILE:h}" >/dev/null 2>&1
	local -a lines
	[[ -f "$_EDIT_SELECT_CONFIG_FILE" ]] && lines=("${(@f)$(<$_EDIT_SELECT_CONFIG_FILE)}")
	lines=("${(@)lines:#${1}=*}")
	if [[ $1 == EDIT_SELECT_MOUSE_REPLACEMENT ]]; then
		lines+=("${1}=${2}")
	else
		lines+=("${1}=\"${2}\"")
	fi
	printf '%s\n' "${lines[@]}" > "$_EDIT_SELECT_CONFIG_FILE"
}

function edit-select::load-keybindings() {
	EDIT_SELECT_KEY_SELECT_ALL="${EDIT_SELECT_KEY_SELECT_ALL:-$_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL}"
	EDIT_SELECT_KEY_PASTE="${EDIT_SELECT_KEY_PASTE:-$_EDIT_SELECT_DEFAULT_KEY_PASTE}"
	EDIT_SELECT_KEY_CUT="${EDIT_SELECT_KEY_CUT:-$_EDIT_SELECT_DEFAULT_KEY_CUT}"
	EDIT_SELECT_KEY_UNDO="${EDIT_SELECT_KEY_UNDO:-$_EDIT_SELECT_DEFAULT_KEY_UNDO}"
	EDIT_SELECT_KEY_REDO="${EDIT_SELECT_KEY_REDO:-$_EDIT_SELECT_DEFAULT_KEY_REDO}"
}

function edit-select::apply-keybindings() {
	local key
	for key in '^A' '^V' '^X'; do bindkey -M emacs -r "$key" 2>/dev/null; done
	bindkey -r '^X' 2>/dev/null
	[[ -n $EDIT_SELECT_KEY_SELECT_ALL ]] && bindkey -M emacs "$EDIT_SELECT_KEY_SELECT_ALL" edit-select::select-all
	if [[ -n $EDIT_SELECT_KEY_PASTE ]]; then
		bindkey -M emacs "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
		bindkey -M edit-select "$EDIT_SELECT_KEY_PASTE" edit-select::paste-clipboard
	fi
	if [[ -n $EDIT_SELECT_KEY_CUT ]]; then
		bindkey -M emacs "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
		bindkey -M edit-select "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
		bindkey "$EDIT_SELECT_KEY_CUT" edit-select::cut-region
	fi
	if [[ -n $EDIT_SELECT_KEY_UNDO ]]; then
		bindkey -M emacs "$EDIT_SELECT_KEY_UNDO" undo
		bindkey "$EDIT_SELECT_KEY_UNDO" undo
	fi
	if [[ -n $EDIT_SELECT_KEY_REDO ]]; then
		bindkey -M emacs "$EDIT_SELECT_KEY_REDO" redo
		bindkey "$EDIT_SELECT_KEY_REDO" redo
	fi
}

function edit-select::show-menu() {
	_zesw_banner "Edit-Select Configuration Wizard"

	_zesw_section_header "Current Configuration"
	_zesw_status_line "Platform" "$(_zesw_get_monitor_type)"
	_zesw_status_line "Mouse Replace" "$(_zesw_get_mouse_status)"

	_zesw_section_header "Configuration Options"
	_zesw_print_option 1 "Mouse Replacement     ${_ZESW_CLR_DIM}— Enable/disable mouse replacement${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Key Bindings          ${_ZESW_CLR_DIM}— Customize Ctrl+A, Ctrl+V, Ctrl+X${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 3 "View Full Configuration"
	_zesw_print_option 4 "Reset to Defaults"
	_zesw_print_option 5 "Exit Wizard"

	_zesw_input_prompt "Choose option (1-5):"
}

function edit-select::configure-mouse-replacement() {
	while true; do
		_zesw_banner "Mouse Replacement"

		_zesw_section_header "Current Status"
		local mouse_status="$(_zesw_get_mouse_status)"
		if [[ $mouse_status == "enabled" ]]; then
			_zesw_status_line "Status" "${_ZESW_CLR_HILITE}Enabled ✓${_ZESW_CLR_RESET}"
		else
			_zesw_status_line "Status" "${_ZESW_CLR_DIM}Disabled${_ZESW_CLR_RESET}"
		fi

		_zesw_info "Integrates mouse selections into ZLE (Zsh Line Editor)"

		_zesw_section_header "Feature Capabilities"
		printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Replace mouse selections by typing over them\n"
		printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Replace mouse selections by pasting over them\n"
		printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Cut mouse selections\n"
		printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Terminal-native text editing workflow\n"

		_zesw_section_header "Options"
		_zesw_print_option 1 "Enable  ${_ZESW_CLR_DIM}— Activate mouse-replacement integration${_ZESW_CLR_RESET}"
		_zesw_print_option 2 "Disable ${_ZESW_CLR_DIM}— Use keyboard-only for selection replacement${_ZESW_CLR_RESET}"
		_zesw_separator
		_zesw_print_option 3 "Back to main menu"

		_zesw_input_prompt "Choose option (1-3):"
		read -r choice
		case "$choice" in
			1) edit-select::set-mouse-replacement enabled; return ;;
			2) edit-select::set-mouse-replacement disabled; return ;;
			3) return ;;
			*) _zesw_error "Invalid choice. Please enter a number between 1-3."; _zesw_prompt_continue ;;
		esac
	done
}

function edit-select::set-mouse-replacement() {
	local value
	[[ $1 == enabled ]] && value=1 || value=0
	edit-select::save-config "EDIT_SELECT_MOUSE_REPLACEMENT" "$value"
	typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=$value
	edit-select::apply-mouse-replacement-config

	if (( value )); then
		_zesw_success "Mouse replacement enabled — Mouse selections now integrated with ZLE"
	else
		_zesw_success "Mouse replacement disabled — Using keyboard-only selection mode"
	fi
	_zesw_prompt_continue
}

function edit-select::configure-select-all() {
	_zesw_banner "Select-All Keybinding"

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_SELECT_ALL${_ZESW_CLR_RESET}"

	_zesw_info "Select the entire command line with one keystroke"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+A          ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Ctrl+Shift+A    ${_ZESW_CLR_DIM}— Alternative for terminals with kitty protocol${_ZESW_CLR_RESET}"
	_zesw_print_option 3 "Custom binding  ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 4 "Back"

	_zesw_input_prompt "Choose option (1-4):"
	read -r choice
	case "$choice" in
		1) edit-select::set-keybinding SELECT_ALL "$_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL" ;;
		2) edit-select::set-keybinding SELECT_ALL "^[[65;6u" ;;
		3)
			_zesw_input_prompt "Enter key sequence (e.g., ^A or ^[[1;5A):"
			read -r custom
			[[ -n $custom ]] && edit-select::set-keybinding SELECT_ALL "$custom" || { _zesw_error "No binding entered. Operation cancelled."; _zesw_prompt_continue; }
			;;
		4) return ;;
		*) _zesw_error "Invalid choice. Please enter a number between 1-4."; _zesw_prompt_continue ;;
	esac
}

function edit-select::configure-paste() {
	_zesw_banner "Paste Keybinding"

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_PASTE${_ZESW_CLR_RESET}"

	_zesw_info "Insert clipboard content at cursor position"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+V          ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Ctrl+Shift+V    ${_ZESW_CLR_DIM}— Alternative for terminals with kitty protocol${_ZESW_CLR_RESET}"
	_zesw_print_option 3 "Custom binding  ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 4 "Back"

	_zesw_input_prompt "Choose option (1-4):"
	read -r choice
	case "$choice" in
		1) edit-select::set-keybinding PASTE "$_EDIT_SELECT_DEFAULT_KEY_PASTE" ;;
		2) edit-select::set-keybinding PASTE "^[[86;6u" ;;
		3)
			_zesw_input_prompt "Enter key sequence (e.g., ^V or ^[[1;5V):"
			read -r custom
			[[ -n $custom ]] && edit-select::set-keybinding PASTE "$custom" || { _zesw_error "No binding entered. Operation cancelled."; _zesw_prompt_continue; }
			;;
		4) return ;;
		*) _zesw_error "Invalid choice. Please enter a number between 1-4."; _zesw_prompt_continue ;;
	esac
}

function edit-select::configure-cut() {
	_zesw_banner "Cut Keybinding"

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_CUT${_ZESW_CLR_RESET}"

	_zesw_info "Delete selection and copy to clipboard"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+X          ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Ctrl+Shift+X    ${_ZESW_CLR_DIM}— Alternative for terminals with kitty protocol${_ZESW_CLR_RESET}"
	_zesw_print_option 3 "Custom binding  ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 4 "Back"

	_zesw_input_prompt "Choose option (1-4):"
	read -r choice
	case "$choice" in
		1) edit-select::set-keybinding CUT "$_EDIT_SELECT_DEFAULT_KEY_CUT" ;;
		2) edit-select::set-keybinding CUT "^[[88;6u" ;;
		3)
			_zesw_input_prompt "Enter key sequence (e.g., ^X or ^[[1;5X):"
			read -r custom
			[[ -n $custom ]] && edit-select::set-keybinding CUT "$custom" || { _zesw_error "No binding entered. Operation cancelled."; _zesw_prompt_continue; }
			;;
		4) return ;;
		*) _zesw_error "Invalid choice. Please enter a number between 1-4."; _zesw_prompt_continue ;;
	esac
}

function edit-select::configure-undo() {
	_zesw_banner "Undo Keybinding"

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_UNDO${_ZESW_CLR_RESET}"

	_zesw_info "Undo last editing action"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+Z          ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Custom binding  ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 3 "Back"

	_zesw_input_prompt "Choose option (1-3):"
	read -r choice
	case "$choice" in
		1) edit-select::set-keybinding UNDO "$_EDIT_SELECT_DEFAULT_KEY_UNDO" ;;
		2)
			_zesw_input_prompt "Enter key sequence (e.g., ^Z or ^[[1;5Z):"
			read -r custom
			[[ -n $custom ]] && edit-select::set-keybinding UNDO "$custom" || { _zesw_error "No binding entered. Operation cancelled."; _zesw_prompt_continue; }
			;;
		3) return ;;
		*) _zesw_error "Invalid choice. Please enter a number between 1-3."; _zesw_prompt_continue ;;
	esac
}

function edit-select::configure-redo() {
	_zesw_banner "Redo Keybinding"

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_REDO${_ZESW_CLR_RESET}"

	_zesw_info "Redo last undone action"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+Shift+Z    ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Ctrl+Y          ${_ZESW_CLR_DIM}— Alternative binding${_ZESW_CLR_RESET}"
	_zesw_print_option 3 "Custom binding  ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 4 "Back"

	_zesw_input_prompt "Choose option (1-4):"
	read -r choice
	case "$choice" in
		1) edit-select::set-keybinding REDO "$_EDIT_SELECT_DEFAULT_KEY_REDO" ;;
		2) edit-select::set-keybinding REDO "^Y" ;;
		3)
			_zesw_input_prompt "Enter key sequence (e.g., ^Y or ^[[1;5Y):"
			read -r custom
			[[ -n $custom ]] && edit-select::set-keybinding REDO "$custom" || { _zesw_error "No binding entered. Operation cancelled."; _zesw_prompt_continue; }
			;;
		4) return ;;
		*) _zesw_error "Invalid choice. Please enter a number between 1-4."; _zesw_prompt_continue ;;
	esac
}

function edit-select::set-keybinding() {
	[[ -z $2 ]] && return 1
	edit-select::save-config "EDIT_SELECT_KEY_${1}" "$2"
	case "$1" in
		SELECT_ALL) typeset -g EDIT_SELECT_KEY_SELECT_ALL="$2" ;;
		PASTE) typeset -g EDIT_SELECT_KEY_PASTE="$2" ;;
		CUT) typeset -g EDIT_SELECT_KEY_CUT="$2" ;;
		UNDO) typeset -g EDIT_SELECT_KEY_UNDO="$2" ;;
		REDO) typeset -g EDIT_SELECT_KEY_REDO="$2" ;;
	esac
	edit-select::apply-keybindings

	local action_name
	case "$1" in
		SELECT_ALL) action_name="Select-All" ;;
		PASTE) action_name="Paste" ;;
		CUT) action_name="Cut" ;;
		UNDO) action_name="Undo" ;;
		REDO) action_name="Redo" ;;
	esac
	_zesw_success "$action_name keybinding updated to: ${_ZESW_CLR_HILITE}$2${_ZESW_CLR_RESET}"
	_zesw_prompt_continue
}

function edit-select::reset-keybindings() {
	_zesw_banner "Reset Keybindings"

	_zesw_section_header "Default Bindings"
	_zesw_status_line "Select All" "${_ZESW_CLR_HILITE}Ctrl+A${_ZESW_CLR_RESET}"
	_zesw_status_line "Paste" "${_ZESW_CLR_HILITE}Ctrl+V${_ZESW_CLR_RESET}"
	_zesw_status_line "Cut" "${_ZESW_CLR_HILITE}Ctrl+X${_ZESW_CLR_RESET}"
	_zesw_status_line "Undo" "${_ZESW_CLR_HILITE}Ctrl+Z${_ZESW_CLR_RESET}"
	_zesw_status_line "Redo" "${_ZESW_CLR_HILITE}Ctrl+Shift+Z${_ZESW_CLR_RESET}"

	_zesw_confirm_prompt "Reset all keybindings to defaults?"
	read -r confirm
	if [[ $confirm =~ ^[Yy]$ ]]; then
		typeset -g EDIT_SELECT_KEY_SELECT_ALL="$_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL"
		typeset -g EDIT_SELECT_KEY_PASTE="$_EDIT_SELECT_DEFAULT_KEY_PASTE"
		typeset -g EDIT_SELECT_KEY_CUT="$_EDIT_SELECT_DEFAULT_KEY_CUT"
		typeset -g EDIT_SELECT_KEY_UNDO="$_EDIT_SELECT_DEFAULT_KEY_UNDO"
		typeset -g EDIT_SELECT_KEY_REDO="$_EDIT_SELECT_DEFAULT_KEY_REDO"
		edit-select::save-config "EDIT_SELECT_KEY_SELECT_ALL" "$_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL"
		edit-select::save-config "EDIT_SELECT_KEY_PASTE" "$_EDIT_SELECT_DEFAULT_KEY_PASTE"
		edit-select::save-config "EDIT_SELECT_KEY_CUT" "$_EDIT_SELECT_DEFAULT_KEY_CUT"
		edit-select::save-config "EDIT_SELECT_KEY_UNDO" "$_EDIT_SELECT_DEFAULT_KEY_UNDO"
		edit-select::save-config "EDIT_SELECT_KEY_REDO" "$_EDIT_SELECT_DEFAULT_KEY_REDO"
		edit-select::apply-keybindings
		_zesw_success "All keybindings reset to defaults"
	else
		_zesw_info "Reset cancelled — No changes made"
	fi
	_zesw_prompt_continue
}

function edit-select::configure-keybindings() {
	while true; do
		_zesw_banner "Key Bindings"

		_zesw_section_header "Current Bindings"
		_zesw_status_line "Select All" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_SELECT_ALL${_ZESW_CLR_RESET}"
		_zesw_status_line "Paste" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_PASTE${_ZESW_CLR_RESET}"
		_zesw_status_line "Cut" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_CUT${_ZESW_CLR_RESET}"
		_zesw_status_line "Undo" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_UNDO${_ZESW_CLR_RESET}"
		_zesw_status_line "Redo" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_REDO${_ZESW_CLR_RESET}"

		_zesw_info "Customize keyboard shortcuts for selection operations"

		_zesw_section_header "Configure Individual Keys"
		_zesw_print_option 1 "Select All ${_ZESW_CLR_DIM}— Select entire command line${_ZESW_CLR_RESET}"
		_zesw_print_option 2 "Paste     ${_ZESW_CLR_DIM}— Insert from clipboard${_ZESW_CLR_RESET}"
		_zesw_print_option 3 "Cut       ${_ZESW_CLR_DIM}— Delete and copy to clipboard${_ZESW_CLR_RESET}"
		_zesw_print_option 4 "Undo      ${_ZESW_CLR_DIM}— Undo last edit${_ZESW_CLR_RESET}"
		_zesw_print_option 5 "Redo      ${_ZESW_CLR_DIM}— Redo last undone edit${_ZESW_CLR_RESET}"
		_zesw_separator
		_zesw_print_option 6 "Reset All to Defaults ${_ZESW_CLR_DIM}(Ctrl+A, Ctrl+V, Ctrl+X, Ctrl+Z, Ctrl+Shift+Z)${_ZESW_CLR_RESET}"
		_zesw_print_option 7 "Back to main menu"

		_zesw_input_prompt "Choose option (1-7):"
		read -r choice
		case "$choice" in
			1) edit-select::configure-select-all ;;
			2) edit-select::configure-paste ;;
			3) edit-select::configure-cut ;;
			4) edit-select::configure-undo ;;
			5) edit-select::configure-redo ;;
			6) edit-select::reset-keybindings ;;
			7) return ;;
			*) _zesw_error "Invalid choice. Please enter a number between 1-7."; _zesw_prompt_continue ;;
		esac
	done
}

function edit-select::reset-config() {
	_zesw_banner "Reset All Configuration"

	printf "\n%s⚠ WARNING ⚠%s\n" "$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET"
	printf "This will permanently delete all custom settings and restore factory defaults.\n\n"

	_zesw_section_header "What Will Be Reset"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Mouse replacement → Enabled\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Keybindings → Ctrl+A, Ctrl+V, Ctrl+X, Ctrl+Z, Ctrl+Shift+Z\n"

	_zesw_confirm_prompt "Permanently delete configuration and reset to defaults?"
	read -r confirm
	if [[ $confirm =~ ^[Yy]$ ]]; then
		rm -f "$_EDIT_SELECT_CONFIG_FILE"
		typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=1
		typeset -g EDIT_SELECT_KEY_SELECT_ALL="$_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL"
		typeset -g EDIT_SELECT_KEY_PASTE="$_EDIT_SELECT_DEFAULT_KEY_PASTE"
		typeset -g EDIT_SELECT_KEY_CUT="$_EDIT_SELECT_DEFAULT_KEY_CUT"
		typeset -g EDIT_SELECT_KEY_UNDO="$_EDIT_SELECT_DEFAULT_KEY_UNDO"
		typeset -g EDIT_SELECT_KEY_REDO="$_EDIT_SELECT_DEFAULT_KEY_REDO"
		edit-select::apply-keybindings
		edit-select::apply-mouse-replacement-config
		_zesw_success "All configuration reset to factory defaults"
		_zesw_info "Config file deleted: $_EDIT_SELECT_CONFIG_FILE"
	else
		_zesw_info "Reset cancelled — All settings preserved"
	fi
	_zesw_prompt_continue
}

function edit-select::view-config() {
	_zesw_banner "Configuration Details"

	_zesw_section_header "Configuration File"
	if [[ -f "$_EDIT_SELECT_CONFIG_FILE" ]]; then
		printf "  %sLocation:%s %s\n" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET" "$_EDIT_SELECT_CONFIG_FILE"
		printf "\n  %sContents:%s\n" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"
		_zesw_separator
		printf "%s" "$_ZESW_CLR_DIM"
		while IFS= read -r _line; do printf "  %s\n" "$_line"; done < "$_EDIT_SELECT_CONFIG_FILE"
		printf "%s" "$_ZESW_CLR_RESET"
		_zesw_separator
	else
		_zesw_info "No custom configuration file found"
		printf "  %sUsing built-in defaults%s\n" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"
	fi

	_zesw_section_header "Active Runtime Settings"
	printf "  %sClipboard:%s wl-copy / wl-paste (Wayland)\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
	printf "  %sMonitor Type:%s %s\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET" "$(_zesw_get_monitor_type)"

	printf "\n  %sMouse Integration:%s\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
	local mouse_status="$(_zesw_get_mouse_status)"
	if [[ $mouse_status == "enabled" ]]; then
		_zesw_status_line "  Status" "${_ZESW_CLR_HILITE}Enabled ✓${_ZESW_CLR_RESET}"
	else
		_zesw_status_line "  Status" "${_ZESW_CLR_DIM}Disabled${_ZESW_CLR_RESET}"
	fi

	printf "\n  %sKeybindings:%s\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
	_zesw_status_line "  Select All" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_SELECT_ALL${_ZESW_CLR_RESET}"
	_zesw_status_line "  Paste" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_PASTE${_ZESW_CLR_RESET}"
	_zesw_status_line "  Cut" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_CUT${_ZESW_CLR_RESET}"
	_zesw_status_line "  Undo" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_UNDO${_ZESW_CLR_RESET}"
	_zesw_status_line "  Redo" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_REDO${_ZESW_CLR_RESET}"

	_zesw_section_header "Plugin Information"
	printf "  %sPlugin Directory:%s\n" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"
	printf "  %s%s%s\n" "$_ZESW_CLR_DIM" "$_EDIT_SELECT_WIZARD_DIR" "$_ZESW_CLR_RESET"

	_zesw_prompt_continue
}

function edit-select::config-wizard() {
	_zesw_init_colors

	if [[ -z $EDIT_SELECT_MOUSE_REPLACEMENT ]]; then
		typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=1
	fi

	edit-select::load-keybindings

	while true; do
		edit-select::show-menu
		read -r choice
		case "$choice" in
			1) edit-select::configure-mouse-replacement ;;
			2) edit-select::configure-keybindings ;;
			3) edit-select::view-config ;;
			4) edit-select::reset-config ;;
			5)
				clear
				local exit_msg="Configuration Saved" width=62
				local padding=$(( (width - ${#exit_msg}) / 2 ))
				local padded_msg="$(printf '%*s' $padding '')${exit_msg}$(printf '%*s' $((width - ${#exit_msg} - padding)) '')"
				printf "\n%s╔══════════════════════════════════════════════════════════════╗%s\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
				printf "%s║%s%s%s║%s\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_HILITE" "$padded_msg" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
				printf "%s╚══════════════════════════════════════════════════════════════╝%s\n\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
				_zesw_info "Your changes are active and will persist across shell sessions"
				break
				;;
			*) _zesw_error "Invalid choice. Please enter a number between 1-5."; _zesw_prompt_continue ;;
		esac
	done
}
