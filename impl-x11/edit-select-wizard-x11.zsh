# Copyright (c) 2025 Michael Matta
# Version: 0.5.6
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select


# Configuration & Constants


typeset -g _EDIT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select/config"
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SELECT_ALL='^A'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_PASTE+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_PASTE='^V'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_CUT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_CUT='^X'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_UNDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_UNDO='^Z'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_REDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_REDO='^[[90;6u'


# Color & Visual Utilities


function _zesw_init_colors() {
	[[ -n $_ZESW_CLR_ACCENT ]] && return
	autoload -Uz colors && colors > /dev/null 2>&1 || true
	typeset -g _ZESW_CLR_ACCENT="${fg_bold[cyan]:-}"
	typeset -g _ZESW_CLR_HILITE="${fg_bold[green]:-}"
	typeset -g _ZESW_CLR_WARN="${fg_bold[red]:-}"
	typeset -g _ZESW_CLR_DIM="${fg[245]:-}"
	typeset -g _ZESW_CLR_RESET="${reset_color:-}"
	typeset -g _ZESW_CLR_BORDER='\033[38;2;100;150;255m'
	typeset -g _ZESW_CLR_BLUE='\033[38;2;100;150;255m'
	typeset -g _ZESW_RESET='\033[0m'
	typeset -g _ZESW_BOLD='\033[1m'

	# Pre-cache gradient colors
	typeset -g -A _ZESW_GRADIENT_CACHE
	_ZESW_GRADIENT_CACHE[cyan]='\033[38;2;0;255;255m'
	_ZESW_GRADIENT_CACHE[c1]='\033[38;2;14;245;255m'
	_ZESW_GRADIENT_CACHE[c2]='\033[38;2;29;235;255m'
	_ZESW_GRADIENT_CACHE[c3]='\033[38;2;43;225;255m'
	_ZESW_GRADIENT_CACHE[c4]='\033[38;2;57;215;255m'
	_ZESW_GRADIENT_CACHE[c5]='\033[38;2;71;195;255m'
	_ZESW_GRADIENT_CACHE[c6]='\033[38;2;86;175;255m'
	_ZESW_GRADIENT_CACHE[blue]='\033[38;2;100;150;255m'
}

# RGB color helper for gradients
function _zesw_rgb() { printf "\033[38;2;${1};${2};${3}m"; }

# Animated loading indicator
function _zesw_loading() {
	local msg="$1"
	local duration="${2:-1}"
	printf "%s⚙%s  %s" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET" "$msg"
	local i
	for i in {1..$duration}; do
		sleep 0.15
		printf "."
	done
	printf " %s✓%s\n" "$_ZESW_CLR_HILITE" "$_ZESW_CLR_RESET"
}

function _zesw_banner() {
	# Clear screen and scrollback buffer
	printf '\033[2J\033[3J\033[H'

	local RESET='\033[0m'
	local BOLD='\033[1m'

	# Gradient colors
	local -a colors
	colors=(
		'\033[38;2;0;255;255m'    # Line 1: Cyan
		'\033[38;2;0;230;255m'    # Line 2
		'\033[38;2;0;200;255m'    # Line 3
		'\033[38;2;0;170;255m'    # Line 4
		'\033[38;2;0;140;255m'    # Line 5
		'\033[38;2;0;110;255m'    # Line 6: Blue
		''                         # Line 7: Empty
		'\033[38;2;100;255;100m'  # Line 8: Green
		'\033[38;2;100;255;150m'  # Line 9
		'\033[38;2;100;230;200m'  # Line 10
		'\033[38;2;100;200;230m'  # Line 11
		'\033[38;2;100;170;255m'  # Line 12
		'\033[38;2;100;140;255m'  # Line 13: Blue
	)

	# ASCII art lines
	local -a art_lines
	art_lines=(
		"           ███████╗███████╗██╗  ██╗    ███████╗██████╗ ██╗████████╗        "
		"           ╚══███╔╝██╔════╝██║  ██║    ██╔════╝██╔══██╗██║╚══██╔══╝        "
		"             ███╔╝ ███████╗███████║    █████╗  ██║  ██║██║   ██║           "
		"            ███╔╝  ╚════██║██╔══██║    ██╔══╝  ██║  ██║██║   ██║           "
		"           ███████╗███████║██║  ██║    ███████╗██████╔╝██║   ██║           "
		"           ╚══════╝╚══════╝╚═╝  ╚═╝    ╚══════╝╚═════╝ ╚═╝   ╚═╝           "
		""
		"              ███████╗███████╗██╗     ███████╗ ██████╗████████╗            "
		"              ██╔════╝██╔════╝██║     ██╔════╝██╔════╝╚══██╔══╝            "
		"              ███████╗█████╗  ██║     █████╗  ██║        ██║               "
		"              ╚════██║██╔══╝  ██║     ██╔══╝  ██║        ██║               "
		"              ███████║███████╗███████╗███████╗╚██████╗   ██║               "
		"              ╚══════╝╚══════╝╚══════╝╚══════╝ ╚═════╝   ╚═╝               "
	)

	# Gradient colors
	local c1='\033[38;2;0;255;255m'
	local c2='\033[38;2;11;245;255m'
	local c3='\033[38;2;22;235;255m'
	local c4='\033[38;2;33;225;255m'
	local c5='\033[38;2;44;215;255m'
	local c6='\033[38;2;56;203;255m'
	local c7='\033[38;2;67;191;255m'
	local c8='\033[38;2;78;179;255m'
	local c9='\033[38;2;89;167;255m'
	local c10='\033[38;2;100;150;255m'

	# Build border with gradient
	local top_border="${c1}╔════════${c2}════════${c3}═══════${c4}════════${c5}═══════${c6}════════${c7}═══════${c8}════════${c9}═══════${c10}═══════╗"
	local bottom_border="${c1}╚════════${c2}════════${c3}═══════${c4}════════${c5}═══════${c6}════════${c7}═══════${c8}════════${c9}═══════${c10}═══════╝"

	# Print banner
	printf "\n${top_border}${RESET}\n"
	printf "${c1}║${RESET}                                                                           ${c10}║${RESET}\n"

	# Print ASCII art with gradient
	local i
	for i in {1..${#art_lines[@]}}; do
		if [[ -z "${art_lines[$i]}" ]]; then
			printf "${c1}║${RESET}                                                                           ${c10}║${RESET}\n"
		else
			printf "${c1}║${RESET}${colors[$i]}${art_lines[$i]}${RESET}${c10}║${RESET}\n"
		fi
	done

	# Subtitle with gradient
	printf "${c1}║${RESET}                                                                           ${c10}║${RESET}\n"
	printf "${c1}║${RESET}\033[38;2;255;200;100m${BOLD}                            Configuration Wizard                           ${RESET}${c10}║${RESET}\n"
	printf "${c1}║${RESET}                                                                           ${c10}║${RESET}\n"

	# Bottom border
	printf "${bottom_border}${RESET}\n\n"
}

# Success box with animation
function _zesw_success_box() {
	local msg="$1"
	local show_animation="${2:-true}"  # Enable pulse animation by default

	local gradient_msg="" i char r g b progress

	# Create gradient for the text
	for (( i=0; i<${#msg}; i++ )); do
		char="${msg:$i:1}"
		progress=$(( i * 100 / ${#msg} ))
		r=$(( 0 + 150 * progress / 100 ))     # 0 -> 150
		g=$(( 255 ))                           # constant 255
		b=$(( 255 - 200 * progress / 100 ))   # 255 -> 55
		gradient_msg+="\033[38;2;${r};${g};${b}m${char}"
	done

	# Add padding
	local width=62
	local padding=$(( (width - ${#msg}) / 2 ))
	local padded_gradient="$(printf '%*s' $padding '')${gradient_msg}$(printf '%*s' $((width - ${#msg} - padding)) '')"

	# Gradient colors
	local c1='\033[38;2;0;255;255m'      # Cyan
	local c2='\033[38;2;14;245;255m'
	local c3='\033[38;2;29;235;255m'
	local c4='\033[38;2;43;225;255m'
	local c5='\033[38;2;57;215;255m'
	local c6='\033[38;2;71;195;255m'
	local c7='\033[38;2;86;175;255m'
	local c8='\033[38;2;100;150;255m'    # Blue

	# Build borders with gradient
	local top_border="${c1}╔════════${c2}════════${c3}════════${c4}════════${c5}════════${c6}════════${c7}═══════${c8}═══════╗"
	local bottom_border="${c1}╚════════${c2}════════${c3}════════${c4}════════${c5}════════${c6}════════${c7}═══════${c8}═══════╝"

	# Pulse/glow animation if enabled
	if [[ "$show_animation" == "true" ]]; then
		# Show 3 pulse frames
		local glow1='\033[38;2;150;220;255m'
		local glow2='\033[38;2;100;200;255m'
		local glow3='\033[38;2;50;180;255m'

		# Frame 1: Bright glow
		printf "\033[s"  # Save cursor position
		printf "\n${top_border}${_ZESW_RESET}\n"
		printf "${glow1}║${_ZESW_RESET}${padded_gradient}${_ZESW_RESET}${glow1}║${_ZESW_RESET}\n"
		printf "${bottom_border}${_ZESW_RESET}\n"
		sleep 0.08

		# Frame 2: Medium glow
		printf "\033[u"  # Restore cursor position
		printf "\n${top_border}${_ZESW_RESET}\n"
		printf "${glow2}║${_ZESW_RESET}${padded_gradient}${_ZESW_RESET}${glow2}║${_ZESW_RESET}\n"
		printf "${bottom_border}${_ZESW_RESET}\n"
		sleep 0.08

		# Frame 3: Soft glow
		printf "\033[u"  # Restore cursor position
		printf "\n${top_border}${_ZESW_RESET}\n"
		printf "${glow3}║${_ZESW_RESET}${padded_gradient}${_ZESW_RESET}${glow3}║${_ZESW_RESET}\n"
		printf "${bottom_border}${_ZESW_RESET}\n"
		sleep 0.08
	fi

	# Final frame: Normal colors
	if [[ "$show_animation" == "true" ]]; then
		printf "\033[u"  # Restore cursor position
	fi

	printf "\n${top_border}${_ZESW_RESET}\n"
	printf "${c1}║${_ZESW_RESET}${padded_gradient}${_ZESW_RESET}${c8}║${_ZESW_RESET}"

	printf "\n${bottom_border}${_ZESW_RESET}\n\n"
}


# UI Components


function _zesw_prompt_continue() {
	printf "\n%s▶ Press Enter to continue...%s " "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"
	read -r
}

function _zesw_print_option() {
	printf "  %s%2s.%s %s\n" "$_ZESW_CLR_HILITE" "$1" "$_ZESW_CLR_RESET" "$2"
}

function _zesw_input_prompt() {
	printf "\n%s▶%s %s " "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET" "$1"
}

function _zesw_status_line() {
	printf "  %s●%s %-18s %s\n" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET" "$1:" "$2"
}

function _zesw_success() {
	printf "\n%s✓%s %s\n" "$_ZESW_CLR_HILITE" "$_ZESW_CLR_RESET" "$1"
}

function _zesw_error() {
	printf "\n%s✗%s %s\n" "$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET" "$1"
}

function _zesw_section_header() {
	printf "\n%s─── %s ───%s\n" "$_ZESW_CLR_ACCENT" "$1" "$_ZESW_CLR_RESET"
}

function _zesw_separator() {
	printf "%s────────────────────────────────────────────────────────────────%s\n" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"
}

function _zesw_info() {
	printf "  %s ℹ%s  %s\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET" "$1"
}

function _zesw_confirm_prompt() {
	printf "\n%s?%s %s %s[y/N]:%s " "$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET" "$1" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"
}

function _zesw_get_mouse_status() {
	(( EDIT_SELECT_MOUSE_REPLACEMENT )) && printf "enabled" || printf "disabled"
}

# Validate input
function _zesw_validate_choice() {
	local choice="$1"
	local min="$2"
	local max="$3"
	[[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= min && choice <= max ))
}


# Configuration Management


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


# Main Menu


function edit-select::show-menu() {
	_zesw_banner

	_zesw_section_header "Current Configuration"
	_zesw_status_line "Platform" "X11"
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


# Mouse Configuration


function edit-select::configure-mouse-replacement() {
	while true; do
		_zesw_banner

		_zesw_section_header "Current Setting"
		local binding_desc
		if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
			binding_desc="${_ZESW_CLR_HILITE}^X${_ZESW_CLR_RESET}"
		else
			binding_desc="${_ZESW_CLR_DIM}Not bound${_ZESW_CLR_RESET}"
		fi
		_zesw_status_line "Binding" "$binding_desc"
		_zesw_status_line "Status" "$(_zesw_get_mouse_status)"

		_zesw_info "Delete selection and copy to clipboard"

		_zesw_section_header "Available Presets"
		_zesw_print_option 1 "Ctrl+X                ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
		_zesw_print_option 2 "Ctrl+Shift+X          ${_ZESW_CLR_DIM}— Alternative for terminals with kitty protocol${_ZESW_CLR_RESET}"
		_zesw_print_option 3 "Custom binding        ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
		_zesw_separator
		_zesw_print_option 4 "Back"

		_zesw_input_prompt "Choose option (1-4):"
		read -r choice

		if ! _zesw_validate_choice "$choice" 1 4; then
			_zesw_error "Invalid choice. Please enter a number between 1-4."
			_zesw_prompt_continue
			continue
		fi

		case "$choice" in
			1)
				typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=1
				edit-select::save-config "EDIT_SELECT_MOUSE_REPLACEMENT" 1
				edit-select::apply-mouse-replacement-config
				_zesw_loading "Applying Ctrl+X binding" 2
				_zesw_success "Mouse replacement enabled with Ctrl+X"
				_zesw_prompt_continue
				;;
			2)
				typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=0
				edit-select::save-config "EDIT_SELECT_MOUSE_REPLACEMENT" 0
				edit-select::apply-mouse-replacement-config
				_zesw_loading "Disabling mouse replacement" 2
				_zesw_success "Mouse replacement disabled — Using standard behavior"
				_zesw_prompt_continue
				;;
			3)
				_zesw_info "Custom binding configuration..."
				_zesw_input_prompt "Press your desired key combination:"
				read -k 1 custom_key
				printf "\n"
				_zesw_info "You pressed: ${_ZESW_CLR_HILITE}$custom_key${_ZESW_CLR_RESET}"
				_zesw_confirm_prompt "Apply this binding?"
				read -r confirm
				if [[ $confirm =~ ^[Yy]$ ]]; then
					_zesw_loading "Applying custom binding" 2
					_zesw_success "Custom binding applied"
				else
					_zesw_info "Cancelled"
				fi
				_zesw_prompt_continue
				;;
			4) return ;;
		esac
	done
}


# Individual Keybinding Configurations


function edit-select::configure-select-all() {
	_zesw_banner

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_SELECT_ALL${_ZESW_CLR_RESET}"

	_zesw_info "Delete selection and copy to clipboard"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+X                ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Ctrl+Shift+X          ${_ZESW_CLR_DIM}— Alternative for terminals with kitty protocol${_ZESW_CLR_RESET}"
	_zesw_print_option 3 "Custom binding        ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 4 "Back"

	_zesw_input_prompt "Choose option (1-4):"
	read -r choice

	if ! _zesw_validate_choice "$choice" 1 4; then
		_zesw_error "Invalid choice. Please enter a number between 1-4."
		_zesw_prompt_continue
		return
	fi

	case "$choice" in
		1)
			typeset -g EDIT_SELECT_KEY_SELECT_ALL="^A"
			edit-select::save-config "EDIT_SELECT_KEY_SELECT_ALL" "^A"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+A binding" 2
			_zesw_success "Select All bound to Ctrl+A"
			;;
		2)
			typeset -g EDIT_SELECT_KEY_SELECT_ALL="^[[65;5u"
			edit-select::save-config "EDIT_SELECT_KEY_SELECT_ALL" "^[[65;5u"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Shift+A binding" 2
			_zesw_success "Select All bound to Ctrl+Shift+A"
			;;
		3)
			_zesw_input_prompt "Press your desired key combination:"
			read -k 1 custom_key
			printf "\n"
			typeset -g EDIT_SELECT_KEY_SELECT_ALL="$custom_key"
			edit-select::save-config "EDIT_SELECT_KEY_SELECT_ALL" "$custom_key"
			edit-select::apply-keybindings
			_zesw_loading "Applying custom binding" 2
			_zesw_success "Select All bound to custom key"
			;;
		4) return ;;
	esac
	_zesw_prompt_continue
}

function edit-select::configure-paste() {
	_zesw_banner

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_PASTE${_ZESW_CLR_RESET}"

	_zesw_info "Insert from clipboard"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+V                ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Ctrl+Shift+V          ${_ZESW_CLR_DIM}— Alternative for terminals${_ZESW_CLR_RESET}"
	_zesw_print_option 3 "Custom binding        ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 4 "Back"

	_zesw_input_prompt "Choose option (1-4):"
	read -r choice

	if ! _zesw_validate_choice "$choice" 1 4; then
		_zesw_error "Invalid choice. Please enter a number between 1-4."
		_zesw_prompt_continue
		return
	fi

	case "$choice" in
		1)
			typeset -g EDIT_SELECT_KEY_PASTE="^V"
			edit-select::save-config "EDIT_SELECT_KEY_PASTE" "^V"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+V binding" 2
			_zesw_success "Paste bound to Ctrl+V"
			;;
		2)
			typeset -g EDIT_SELECT_KEY_PASTE="^[[86;5u"
			edit-select::save-config "EDIT_SELECT_KEY_PASTE" "^[[86;5u"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Shift+V binding" 2
			_zesw_success "Paste bound to Ctrl+Shift+V"
			;;
		3)
			_zesw_input_prompt "Press your desired key combination:"
			read -k 1 custom_key
			printf "\n"
			typeset -g EDIT_SELECT_KEY_PASTE="$custom_key"
			edit-select::save-config "EDIT_SELECT_KEY_PASTE" "$custom_key"
			edit-select::apply-keybindings
			_zesw_loading "Applying custom binding" 2
			_zesw_success "Paste bound to custom key"
			;;
		4) return ;;
	esac
	_zesw_prompt_continue
}

function edit-select::configure-cut() {
	_zesw_banner

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_CUT${_ZESW_CLR_RESET}"

	_zesw_info "Delete and copy to clipboard"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+X                ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Ctrl+Shift+X          ${_ZESW_CLR_DIM}— Alternative for terminals${_ZESW_CLR_RESET}"
	_zesw_print_option 3 "Custom binding        ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 4 "Back"

	_zesw_input_prompt "Choose option (1-4):"
	read -r choice

	if ! _zesw_validate_choice "$choice" 1 4; then
		_zesw_error "Invalid choice. Please enter a number between 1-4."
		_zesw_prompt_continue
		return
	fi

	case "$choice" in
		1)
			typeset -g EDIT_SELECT_KEY_CUT="^X"
			edit-select::save-config "EDIT_SELECT_KEY_CUT" "^X"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+X binding" 2
			_zesw_success "Cut bound to Ctrl+X"
			;;
		2)
			typeset -g EDIT_SELECT_KEY_CUT="^[[88;5u"
			edit-select::save-config "EDIT_SELECT_KEY_CUT" "^[[88;5u"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Shift+X binding" 2
			_zesw_success "Cut bound to Ctrl+Shift+X"
			;;
		3)
			_zesw_input_prompt "Press your desired key combination:"
			read -k 1 custom_key
			printf "\n"
			typeset -g EDIT_SELECT_KEY_CUT="$custom_key"
			edit-select::save-config "EDIT_SELECT_KEY_CUT" "$custom_key"
			edit-select::apply-keybindings
			_zesw_loading "Applying custom binding" 2
			_zesw_success "Cut bound to custom key"
			;;
		4) return ;;
	esac
	_zesw_prompt_continue
}

function edit-select::configure-undo() {
	_zesw_banner

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_UNDO${_ZESW_CLR_RESET}"

	_zesw_info "Undo last edit"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+Z                ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Custom binding        ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 3 "Back"

	_zesw_input_prompt "Choose option (1-3):"
	read -r choice

	if ! _zesw_validate_choice "$choice" 1 3; then
		_zesw_error "Invalid choice. Please enter a number between 1-3."
		_zesw_prompt_continue
		return
	fi

	case "$choice" in
		1)
			typeset -g EDIT_SELECT_KEY_UNDO="^Z"
			edit-select::save-config "EDIT_SELECT_KEY_UNDO" "^Z"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Z binding" 2
			_zesw_success "Undo bound to Ctrl+Z"
			;;
		2)
			_zesw_input_prompt "Press your desired key combination:"
			read -k 1 custom_key
			printf "\n"
			typeset -g EDIT_SELECT_KEY_UNDO="$custom_key"
			edit-select::save-config "EDIT_SELECT_KEY_UNDO" "$custom_key"
			edit-select::apply-keybindings
			_zesw_loading "Applying custom binding" 2
			_zesw_success "Undo bound to custom key"
			;;
		3) return ;;
	esac
	_zesw_prompt_continue
}

function edit-select::configure-redo() {
	_zesw_banner

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_REDO${_ZESW_CLR_RESET}"

	_zesw_info "Redo last undone edit"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+Shift+Z          ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Custom binding        ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 3 "Back"

	_zesw_input_prompt "Choose option (1-3):"
	read -r choice

	if ! _zesw_validate_choice "$choice" 1 3; then
		_zesw_error "Invalid choice. Please enter a number between 1-3."
		_zesw_prompt_continue
		return
	fi

	case "$choice" in
		1)
			typeset -g EDIT_SELECT_KEY_REDO="^[[90;6u"
			edit-select::save-config "EDIT_SELECT_KEY_REDO" "^[[90;6u"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Shift+Z binding" 2
			_zesw_success "Redo bound to Ctrl+Shift+Z"
			;;
		2)
			_zesw_input_prompt "Press your desired key combination:"
			read -k 1 custom_key
			printf "\n"
			typeset -g EDIT_SELECT_KEY_REDO="$custom_key"
			edit-select::save-config "EDIT_SELECT_KEY_REDO" "$custom_key"
			edit-select::apply-keybindings
			_zesw_loading "Applying custom binding" 2
			_zesw_success "Redo bound to custom key"
			;;
		3) return ;;
	esac
	_zesw_prompt_continue
}

function edit-select::reset-keybindings() {
	_zesw_banner

	printf "\n%s⚠ WARNING ⚠%s\n" "$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET"
	printf "This will reset all keybindings to their defaults.\n\n"

	_zesw_section_header "Default Keybindings"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Select All → Ctrl+A\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Paste      → Ctrl+V\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Cut        → Ctrl+X\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Undo       → Ctrl+Z\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Redo       → Ctrl+Shift+Z\n"

	_zesw_confirm_prompt "Reset all keybindings to defaults?"
	read -r confirm
	if [[ $confirm =~ ^[Yy]$ ]]; then
		_zesw_loading "Resetting keybindings" 3
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


# Keybindings Menu


function edit-select::configure-keybindings() {
	while true; do
		_zesw_banner

		_zesw_section_header "Current Bindings"
		_zesw_status_line "Select All" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_SELECT_ALL${_ZESW_CLR_RESET}"
		_zesw_status_line "Paste" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_PASTE${_ZESW_CLR_RESET}"
		_zesw_status_line "Cut" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_CUT${_ZESW_CLR_RESET}"
		_zesw_status_line "Undo" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_UNDO${_ZESW_CLR_RESET}"
		_zesw_status_line "Redo" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_REDO${_ZESW_CLR_RESET}"

		_zesw_info "Customize keyboard shortcuts for selection operations"

		_zesw_section_header "Configure Individual Keys"
		_zesw_print_option 1 "Select All ${_ZESW_CLR_DIM}— Select entire command line${_ZESW_CLR_RESET}"
		_zesw_print_option 2 "Paste      ${_ZESW_CLR_DIM}— Insert from clipboard${_ZESW_CLR_RESET}"
		_zesw_print_option 3 "Cut        ${_ZESW_CLR_DIM}— Delete and copy to clipboard${_ZESW_CLR_RESET}"
		_zesw_print_option 4 "Undo       ${_ZESW_CLR_DIM}— Undo last edit${_ZESW_CLR_RESET}"
		_zesw_print_option 5 "Redo       ${_ZESW_CLR_DIM}— Redo last undone edit${_ZESW_CLR_RESET}"
		_zesw_separator
		_zesw_print_option 6 "Reset All to Defaults ${_ZESW_CLR_DIM}(Ctrl+A, Ctrl+V, Ctrl+X, Ctrl+Z, Ctrl+Shift+Z)${_ZESW_CLR_RESET}"
		_zesw_print_option 7 "Back to main menu"

		_zesw_input_prompt "Choose option (1-7):"
		read -r choice

		if ! _zesw_validate_choice "$choice" 1 7; then
			_zesw_error "Invalid choice. Please enter a number between 1-7."
			_zesw_prompt_continue
			continue
		fi

		case "$choice" in
			1) edit-select::configure-select-all ;;
			2) edit-select::configure-paste ;;
			3) edit-select::configure-cut ;;
			4) edit-select::configure-undo ;;
			5) edit-select::configure-redo ;;
			6) edit-select::reset-keybindings ;;
			7) return ;;
		esac
	done
}


# Configuration View & Reset


function edit-select::reset-config() {
	_zesw_banner

	printf "\n%s⚠ WARNING ⚠%s\n" "$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET"
	printf "This will permanently delete all custom settings and restore factory defaults.\n\n"

	_zesw_section_header "What Will Be Reset"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Mouse replacement → Enabled\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Keybindings → Ctrl+A, Ctrl+V, Ctrl+X, Ctrl+Z, Ctrl+Shift+Z\n"

	_zesw_confirm_prompt "Permanently delete configuration and reset to defaults?"
	read -r confirm
	if [[ $confirm =~ ^[Yy]$ ]]; then
		_zesw_loading "Deleting configuration" 2
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
	_zesw_banner

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
	printf "  %sClipboard:%s xclip (X11)\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"

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
	printf "  %s%s%s\n" "$_ZESW_CLR_DIM" "$_EDIT_SELECT_PLUGIN_DIR" "$_ZESW_CLR_RESET"

	_zesw_prompt_continue
}


# Main Entry Point


function edit-select::config-wizard() {
	_zesw_init_colors

	# Initialize mouse replacement if not set
	if [[ -z $EDIT_SELECT_MOUSE_REPLACEMENT ]]; then
		typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=1
	fi

	# Load current keybindings
	edit-select::load-keybindings

	# Main loop
	while true; do
		edit-select::show-menu
		read -r choice

		if ! _zesw_validate_choice "$choice" 1 5; then
			_zesw_error "Invalid choice. Please enter a number between 1-5."
			_zesw_prompt_continue
			continue
		fi

		case "$choice" in
			1) edit-select::configure-mouse-replacement ;;
			2) edit-select::configure-keybindings ;;
			3) edit-select::view-config ;;
			4) edit-select::reset-config ;;
			5)
				# Exit with success box
				printf '\033[2J\033[3J\033[H'
				_zesw_success_box "Configuration Saved"
				_zesw_info "Your changes are active and will persist across shell sessions"
				printf "\n"
				break
				;;
		esac
	done
}
