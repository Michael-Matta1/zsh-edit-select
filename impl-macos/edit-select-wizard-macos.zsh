# Copyright (c) 2025 Michael Matta
# Version: 0.6.3
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select


# Configuration & Constants


typeset -g _EDIT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select/config"
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SELECT_ALL='^A'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_PASTE+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_PASTE='^V'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_CUT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_CUT='^X'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_UNDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_UNDO='^Z'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_REDO+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_REDO='^[[90;6u'
# Copy: Ctrl+Shift+C (^[[67;6u) — most terminals require configuration to send
# this sequence; see Terminal Setup in the documentation. Plain Ctrl+C cannot
# be used because terminals intercept it as SIGINT.
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_COPY+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_COPY='^[[67;6u'
# Word navigation: standard xterm/VT sequences for Ctrl+Left / Ctrl+Right.
# If your terminal sends different sequences, configure them here.
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_WORD_LEFT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_WORD_LEFT='^[[1;5D'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT='^[[1;5C'
# Buffer navigation: standard xterm/VT sequences for Ctrl+Shift+Home / Ctrl+Shift+End.
# If your terminal sends different sequences, configure them here.
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_BUFFER_START+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_BUFFER_START='^[[1;6H'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_BUFFER_END+x} ]]   && typeset -gr _EDIT_SELECT_DEFAULT_KEY_BUFFER_END='^[[1;6F'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT+x} ]]  && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SEL_WORD_LEFT='^[[1;6D'
[[ -z ${_EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT+x} ]] && typeset -gr _EDIT_SELECT_DEFAULT_KEY_SEL_WORD_RIGHT='^[[1;6C'


# Color & Visual Utilities


# Initialize terminal color variables used throughout the wizard.
# Idempotent: exits immediately if colors are already set.
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

# Render the full-screen gradient ASCII-art banner.
# Clears the screen and scrollback buffer before drawing.
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


# Pause execution and wait for the user to press Enter.
function _zesw_prompt_continue() {
	printf "\n%s▶ Press Enter to continue...%s " "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"
	read -r
}

# Print a numbered menu option with consistent accent-color formatting. Args: number, label.
function _zesw_print_option() {
	printf "  %s%2s.%s %s\n" "$_ZESW_CLR_HILITE" "$1" "$_ZESW_CLR_RESET" "$2"
}

# Print a styled arrow prompt and message, leaving the cursor ready for input. Args: prompt text.
function _zesw_input_prompt() {
	printf "\n%s▶%s %s " "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET" "$1"
}

# Print a key/value status row with a dim bullet icon. Args: label, value (may contain color codes).
function _zesw_status_line() {
	printf "  %s●%s %-18s %s\n" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET" "$1:" "$2"
}

# Print a success message prefixed with a green check mark. Args: message.
function _zesw_success() {
	printf "\n%s✓%s %s\n" "$_ZESW_CLR_HILITE" "$_ZESW_CLR_RESET" "$1"
}

# Print an error message prefixed with a red × mark. Args: message.
function _zesw_error() {
	printf "\n%s✗%s %s\n" "$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET" "$1"
}

# Print an accented section divider with a centered title. Args: title.
function _zesw_section_header() {
	printf "\n%s─── %s ───%s\n" "$_ZESW_CLR_ACCENT" "$1" "$_ZESW_CLR_RESET"
}

# Print a plain dim horizontal rule line.
function _zesw_separator() {
	printf "%s────────────────────────────────────────────────────────────────%s\n" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"
}

# Print an informational line prefixed with an ℹ icon. Args: message.
function _zesw_info() {
	printf "  %s ℹ%s  %s\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET" "$1"
}

# Print a yes/no confirmation prompt, leaving the cursor ready for input. Args: question.
function _zesw_confirm_prompt() {
	printf "\n%s?%s %s %s[y/N]:%s " "$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET" "$1" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"
}

# Key capture function for custom keybindings
function _zesw_capture_key() {
	local result_var=""
	local key_sequence=""

	printf "%s▶%s Press the key combination you want to use: " "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"

	# Read raw key input
	read -k 1 key_sequence

	# Handle multi-byte sequences (escape sequences)
	if [[ "$key_sequence" == $'\e' ]]; then
		local byte=""

		# read -t 0 -k 1 attempts a non-blocking read (zero timeout). On POSIX PTYs
		# this uses select(2) internally. If a byte is available it is consumed and
		# stored in $byte (return 0). If no byte is available it returns non-zero
		# immediately and $byte is empty, so we fall back to a 25 ms timed read to
		# catch sequences that arrive slightly after the initial ESC (slow terminals
		# or heavy load). The while loop then drains any remaining buffered bytes.
		if ! read -t 0 -k 1 byte 2>/dev/null; then
			read -t 0.025 -k 1 byte 2>/dev/null
		fi
		key_sequence+="$byte"
		byte=""
		while IFS= read -t 0 -k 1 byte 2>/dev/null; do
			key_sequence+="$byte"
			byte=""
		done
	fi

	printf "\n"

	# Convert to ZLE notation if needed
	if [[ "$key_sequence" == $'\e'* ]]; then
		# It's an escape sequence, convert to ^[ notation
		result_var="^[${key_sequence#$'\e'}"
	elif [[ "$key_sequence" =~ ^[[:cntrl:]]$ ]]; then
		# It's a control character, convert to ^ notation
		local char_code=$(( #key_sequence ))
		if (( char_code > 0 && char_code < 32 )); then
			local letter=${(#)$(( char_code + 64 ))}
			result_var="^$letter"
		elif (( char_code == 127 )); then
			result_var="^?"
		else
			result_var="$key_sequence"
		fi
	else
		result_var="$key_sequence"
	fi

	if [[ "$result_var" == '^[' ]]; then
		printf "%s ✗%s  Bare ESC cannot be used as a binding.\n" \
			"$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET"
		eval "$1=''"
		return 1
	fi

	# Display captured key
	printf "%s ℹ%s  Captured key: %s%s%s\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET" "$_ZESW_CLR_HILITE" "$result_var" "$_ZESW_CLR_RESET"
	eval "$1=\${result_var}"
}

# Prompt user to choose between auto-detecting or manually entering a custom
# keybinding sequence. Stores result in the variable named by $1.
# Returns 0 on success, 1 if cancelled/empty.
function _zesw_read_custom_key() {
	local _rck_input="" _rck_method=""

	printf "\n"
	_zesw_info "How would you like to enter the keybinding?"
	printf "\n"
	_zesw_print_option 1 "Auto-detect       ${_ZESW_CLR_DIM}— Press the key and we'll detect it${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Enter manually    ${_ZESW_CLR_DIM}— Type the escape sequence (e.g. ^[[1;6H)${_ZESW_CLR_RESET}"
	printf "\n"
	_zesw_info "${_ZESW_CLR_WARN}Note:${_ZESW_CLR_RESET} Auto-detect may not work for complex keybindings such as those involving Shift"
	_zesw_input_prompt "Choose (1-2):"
	read -r _rck_method

	case "$_rck_method" in
		1)
			_zesw_capture_key _rck_input || return 1
			;;
		2)
			_zesw_input_prompt "Type the key pattern and press Enter:"
			read -r _rck_input
			;;
		*)
			_zesw_error "Invalid choice. Operation cancelled."
			return 1
			;;
	esac

	if [[ -z $_rck_input ]]; then
		_zesw_error "No binding entered. Operation cancelled."
		return 1
	fi
	eval "$1=\${_rck_input}"
	return 0
}

# Return "enabled" or "disabled" reflecting the current EDIT_SELECT_MOUSE_REPLACEMENT value.
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


# Remove all lines matching a given key from the config file. Args: key.
function edit-select::delete-config-key() {
	[[ -f "$_EDIT_SELECT_CONFIG_FILE" ]] || return
	local -a filtered=("${(@)${(@f)$(<$_EDIT_SELECT_CONFIG_FILE)}:#${1}=*}")
	(( ${#filtered[@]} )) && printf '%s\n' "${filtered[@]}" > "$_EDIT_SELECT_CONFIG_FILE" || rm -f "$_EDIT_SELECT_CONFIG_FILE"
}

# Persist a key/value pair to the config file, creating it when needed.
# Values are written as key="value" except for EDIT_SELECT_MOUSE_REPLACEMENT which is unquoted.
# Args: key, value.
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

# Initialize all EDIT_SELECT_KEY_* variables, falling back to _EDIT_SELECT_DEFAULT_KEY_* if unset.
# Called at wizard startup and after loading a saved session.
function edit-select::load-keybindings() {
	EDIT_SELECT_KEY_SELECT_ALL="${EDIT_SELECT_KEY_SELECT_ALL:-$_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL}"
	EDIT_SELECT_KEY_PASTE="${EDIT_SELECT_KEY_PASTE:-$_EDIT_SELECT_DEFAULT_KEY_PASTE}"
	EDIT_SELECT_KEY_CUT="${EDIT_SELECT_KEY_CUT:-$_EDIT_SELECT_DEFAULT_KEY_CUT}"
	EDIT_SELECT_KEY_COPY="${EDIT_SELECT_KEY_COPY:-$_EDIT_SELECT_DEFAULT_KEY_COPY}"
	EDIT_SELECT_KEY_UNDO="${EDIT_SELECT_KEY_UNDO:-$_EDIT_SELECT_DEFAULT_KEY_UNDO}"
	EDIT_SELECT_KEY_REDO="${EDIT_SELECT_KEY_REDO:-$_EDIT_SELECT_DEFAULT_KEY_REDO}"
	EDIT_SELECT_KEY_WORD_LEFT="${EDIT_SELECT_KEY_WORD_LEFT:-$_EDIT_SELECT_DEFAULT_KEY_WORD_LEFT}"
	EDIT_SELECT_KEY_WORD_RIGHT="${EDIT_SELECT_KEY_WORD_RIGHT:-$_EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT}"
	EDIT_SELECT_KEY_BUFFER_START="${EDIT_SELECT_KEY_BUFFER_START:-$_EDIT_SELECT_DEFAULT_KEY_BUFFER_START}"
	EDIT_SELECT_KEY_BUFFER_END="${EDIT_SELECT_KEY_BUFFER_END:-$_EDIT_SELECT_DEFAULT_KEY_BUFFER_END}"
}

# Remove any stale or hardcoded ZLE bindings that overlap with configurable keys, then
# rebind every EDIT_SELECT_KEY_* to its corresponding widget in the emacs and edit-select keymaps.
function edit-select::apply-keybindings() {
	local key
	for key in '^A' '^V' '^X'; do bindkey -M emacs -r "$key" 2>/dev/null; done
	bindkey -r '^X' 2>/dev/null

	bindkey -M emacs -r '^Z' 2>/dev/null
	bindkey -r '^Z' 2>/dev/null
	bindkey -M emacs -r '^[[90;6u' 2>/dev/null
	bindkey -r '^[[90;6u' 2>/dev/null

	# Remove hardcoded defaults before re-applying configurable versions
	bindkey -M emacs -r '^[[67;6u' 2>/dev/null
	bindkey -M edit-select -r '^[[67;6u' 2>/dev/null
	bindkey -M emacs -r '^[[1;5D' 2>/dev/null
	bindkey -M edit-select -r '^[[1;5D' 2>/dev/null
	bindkey -M emacs -r '^[[1;5C' 2>/dev/null
	bindkey -M edit-select -r '^[[1;5C' 2>/dev/null
	bindkey -M emacs -r '^[[1;6H' 2>/dev/null
	bindkey -M edit-select -r '^[[1;6H' 2>/dev/null
	bindkey -M emacs -r '^[[1;6F' 2>/dev/null
	bindkey -M edit-select -r '^[[1;6F' 2>/dev/null

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
	if [[ -n $EDIT_SELECT_KEY_COPY ]]; then
		bindkey -M emacs "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
		bindkey -M edit-select "$EDIT_SELECT_KEY_COPY" edit-select::copy-region
	fi
	if [[ -n $EDIT_SELECT_KEY_UNDO ]]; then
		bindkey -M emacs "$EDIT_SELECT_KEY_UNDO" undo
		bindkey "$EDIT_SELECT_KEY_UNDO" undo
	fi
	if [[ -n $EDIT_SELECT_KEY_REDO ]]; then
		bindkey -M emacs "$EDIT_SELECT_KEY_REDO" redo
		bindkey "$EDIT_SELECT_KEY_REDO" redo
	fi
	if [[ -n $EDIT_SELECT_KEY_WORD_LEFT ]]; then
		bindkey -M emacs "$EDIT_SELECT_KEY_WORD_LEFT" backward-word
	fi
	if [[ -n $EDIT_SELECT_KEY_WORD_RIGHT ]]; then
		bindkey -M emacs "$EDIT_SELECT_KEY_WORD_RIGHT" forward-word
	fi
	if [[ -n $EDIT_SELECT_KEY_BUFFER_START ]]; then
		bindkey -M emacs "$EDIT_SELECT_KEY_BUFFER_START" edit-select::beginning-of-buffer
		bindkey -M edit-select "$EDIT_SELECT_KEY_BUFFER_START" edit-select::beginning-of-buffer
	fi
	if [[ -n $EDIT_SELECT_KEY_BUFFER_END ]]; then
		bindkey -M emacs "$EDIT_SELECT_KEY_BUFFER_END" edit-select::end-of-buffer
		bindkey -M edit-select "$EDIT_SELECT_KEY_BUFFER_END" edit-select::end-of-buffer
	fi
}


# Main Menu


# Render the top-level wizard menu showing the current configuration summary and prompt for a choice.
function edit-select::show-menu() {
	_zesw_banner

	_zesw_section_header "Current Configuration"
	_zesw_status_line "Platform" "macOS"
	# macOS-specific: show Accessibility (PRIMARY selection) permission status.
	if [[ -x "${_EDIT_SELECT_PLUGIN_DIR}/backends/macos/zes-macos-clipboard-agent" ]]; then
		if "${_EDIT_SELECT_PLUGIN_DIR}/backends/macos/zes-macos-clipboard-agent" \
				--check-ax 2>/dev/null; then
			_zesw_status_line "Mouse Selection" \
				"${_ZESW_CLR_HILITE}Active (AX) ✓${_ZESW_CLR_RESET}"
		else
			_zesw_status_line "Mouse Selection" \
				"${_ZESW_CLR_WARN}Clipboard only — run 'edit-select setup-ax'${_ZESW_CLR_RESET}"
		fi
	fi
	_zesw_status_line "Mouse Replace" "$(_zesw_get_mouse_status)"

	_zesw_section_header "Configuration Options"
	_zesw_print_option 1 "Mouse Replacement     ${_ZESW_CLR_DIM}— Enable/disable mouse replacement${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Key Bindings          ${_ZESW_CLR_DIM}— Customize Ctrl+A, Ctrl+C, Ctrl+V, Ctrl+X, ...${_ZESW_CLR_RESET}"
	_zesw_separator
	_zesw_print_option 3 "View Full Configuration"
	_zesw_print_option 4 "Reset to Defaults"
	_zesw_print_option 5 "Exit Wizard"

	_zesw_input_prompt "Choose option (1-5):"
}


# Mouse Configuration


# Apply and persist a mouse-replacement enable/disable choice. Args: "enabled" | "disabled".
function edit-select::set-mouse-replacement() {
	local value
	[[ $1 == enabled ]] && value=1 || value=0

	_zesw_loading "Applying configuration" 2

	edit-select::save-config "EDIT_SELECT_MOUSE_REPLACEMENT" "$value"
	typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=$value
	edit-select::apply-mouse-replacement-config

	if (( value )); then
		_zesw_success "Mouse replacement enabled"
	else
		_zesw_success "Mouse replacement disabled"
	fi
	_zesw_prompt_continue
}

# Interactive loop to enable or disable the mouse-region replacement feature.
function edit-select::configure-mouse-replacement() {
	while true; do
		_zesw_banner

		_zesw_section_header "Current Setting"
		_zesw_status_line "Status" "$(_zesw_get_mouse_status)"

		_zesw_info "When enabled, typing replaces an active mouse selection"

		_zesw_section_header "Options"
		_zesw_print_option 1 "Enable   ${_ZESW_CLR_DIM}— Typing replaces the mouse selection${_ZESW_CLR_RESET}"
		_zesw_print_option 2 "Disable  ${_ZESW_CLR_DIM}— Use standard shell behavior${_ZESW_CLR_RESET}"
		_zesw_separator
		_zesw_print_option 3 "Back"

		_zesw_input_prompt "Choose option (1-3):"
		read -r choice

		if ! _zesw_validate_choice "$choice" 1 3; then
			_zesw_error "Invalid choice. Please enter a number between 1-3."
			_zesw_prompt_continue
			continue
		fi

		case "$choice" in
			1) edit-select::set-mouse-replacement enabled ;;
			2) edit-select::set-mouse-replacement disabled ;;
			3) return ;;
		esac
	done
}


# Individual Keybinding Configurations


# Interactive menu to set the Select All keybinding.
function edit-select::configure-select-all() {
	_zesw_banner

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_SELECT_ALL${_ZESW_CLR_RESET}"

	_zesw_info "Select the entire command line"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+A          ${_ZESW_CLR_DIM}— Default binding${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Ctrl+Shift+A    ${_ZESW_CLR_DIM}— Alternative (may require terminal configuration)${_ZESW_CLR_RESET}"
	_zesw_print_option 3 "Custom binding  ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
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
			local _zes_old_key="$EDIT_SELECT_KEY_SELECT_ALL"
			[[ -n "$_zes_old_key" ]] && bindkey -M emacs -r "$_zes_old_key" 2>/dev/null
			typeset -g EDIT_SELECT_KEY_SELECT_ALL="^A"
			edit-select::save-config "EDIT_SELECT_KEY_SELECT_ALL" "^A"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+A binding" 2
			_zesw_success "Select All bound to Ctrl+A"
			;;
		2)
			local _zes_old_key="$EDIT_SELECT_KEY_SELECT_ALL"
			[[ -n "$_zes_old_key" ]] && bindkey -M emacs -r "$_zes_old_key" 2>/dev/null
			typeset -g EDIT_SELECT_KEY_SELECT_ALL="^[[65;6u"
			edit-select::save-config "EDIT_SELECT_KEY_SELECT_ALL" "^[[65;6u"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Shift+A binding" 2
			_zesw_success "Select All bound to Ctrl+Shift+A"
			;;
		3)
			if _zesw_read_custom_key custom_key; then
				local _zes_old_key="$EDIT_SELECT_KEY_SELECT_ALL"
				[[ -n "$_zes_old_key" ]] && bindkey -M emacs -r "$_zes_old_key" 2>/dev/null
				typeset -g EDIT_SELECT_KEY_SELECT_ALL="$custom_key"
				edit-select::save-config "EDIT_SELECT_KEY_SELECT_ALL" "$custom_key"
				edit-select::apply-keybindings
				_zesw_loading "Applying custom binding" 2
				_zesw_success "Select All bound to custom key"
			fi
			;;
		4) return ;;
	esac
	_zesw_prompt_continue
}

# Interactive menu to set the Paste keybinding.
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
			local _zes_old_key="$EDIT_SELECT_KEY_PASTE"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_PASTE="^V"
			edit-select::save-config "EDIT_SELECT_KEY_PASTE" "^V"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+V binding" 2
			_zesw_success "Paste bound to Ctrl+V"
			;;
		2)
			local _zes_old_key="$EDIT_SELECT_KEY_PASTE"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_PASTE="^[[86;6u"
			edit-select::save-config "EDIT_SELECT_KEY_PASTE" "^[[86;6u"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Shift+V binding" 2
			_zesw_success "Paste bound to Ctrl+Shift+V"
			;;
		3)
			if _zesw_read_custom_key custom_key; then
				local _zes_old_key="$EDIT_SELECT_KEY_PASTE"
				[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
				typeset -g EDIT_SELECT_KEY_PASTE="$custom_key"
				edit-select::save-config "EDIT_SELECT_KEY_PASTE" "$custom_key"
				edit-select::apply-keybindings
				_zesw_loading "Applying custom binding" 2
				_zesw_success "Paste bound to custom key"
			fi
			;;
		4) return ;;
	esac
	_zesw_prompt_continue
}

# Interactive menu to set the Cut keybinding.
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
			local _zes_old_key="$EDIT_SELECT_KEY_CUT"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; bindkey -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_CUT="^X"
			edit-select::save-config "EDIT_SELECT_KEY_CUT" "^X"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+X binding" 2
			_zesw_success "Cut bound to Ctrl+X"
			;;
		2)
			local _zes_old_key="$EDIT_SELECT_KEY_CUT"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; bindkey -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_CUT="^[[88;6u"
			edit-select::save-config "EDIT_SELECT_KEY_CUT" "^[[88;6u"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Shift+X binding" 2
			_zesw_success "Cut bound to Ctrl+Shift+X"
			;;
		3)
			if _zesw_read_custom_key custom_key; then
				local _zes_old_key="$EDIT_SELECT_KEY_CUT"
				[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; bindkey -r "$_zes_old_key" 2>/dev/null; }
				typeset -g EDIT_SELECT_KEY_CUT="$custom_key"
				edit-select::save-config "EDIT_SELECT_KEY_CUT" "$custom_key"
				edit-select::apply-keybindings
				_zesw_loading "Applying custom binding" 2
				_zesw_success "Cut bound to custom key"
			fi
			;;
		4) return ;;
	esac
	_zesw_prompt_continue
}

# Interactive menu to set the Copy keybinding.
function edit-select::configure-copy() {
	_zesw_banner

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_COPY${_ZESW_CLR_RESET}"

	_zesw_info "Copy selected text to the clipboard"

	printf "\n  %s⚠%s  Ctrl+C cannot be used for copy — terminals intercept it as SIGINT.\n" \
		"$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET"
	printf "  %s ℹ%s  Shift-based shortcuts (e.g. Ctrl+Shift+C) require your terminal to send\n" \
		"$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
	printf "         a special escape sequence to the shell. Most terminals support this\n"
	printf "         but may need configuration. Run 'cat' and press the key combination\n"
	printf "         to see what sequence your terminal sends. See Terminal Setup in the\n"
	printf "         documentation for per-terminal configuration steps.\n"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+Shift+C     ${_ZESW_CLR_DIM}— Default (^[[67;6u, may require terminal configuration)${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Ctrl+Y           ${_ZESW_CLR_DIM}— Alternative without Shift requirement${_ZESW_CLR_RESET}"
	_zesw_print_option 3 "Custom binding   ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
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
			local _zes_old_key="$EDIT_SELECT_KEY_COPY"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_COPY="^[[67;6u"
			edit-select::save-config "EDIT_SELECT_KEY_COPY" "^[[67;6u"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Shift+C binding" 2
			_zesw_success "Copy bound to Ctrl+Shift+C"
			;;
		2)
			local _zes_old_key="$EDIT_SELECT_KEY_COPY"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_COPY="^Y"
			edit-select::save-config "EDIT_SELECT_KEY_COPY" "^Y"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Y binding" 2
			_zesw_success "Copy bound to Ctrl+Y"
			;;
		3)
			if _zesw_read_custom_key custom_key; then
				local _zes_old_key="$EDIT_SELECT_KEY_COPY"
				[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
				typeset -g EDIT_SELECT_KEY_COPY="$custom_key"
				edit-select::save-config "EDIT_SELECT_KEY_COPY" "$custom_key"
				edit-select::apply-keybindings
				_zesw_loading "Applying custom binding" 2
				_zesw_success "Copy bound to custom key"
			fi
			;;
		4) return ;;
	esac
	_zesw_prompt_continue
}

# Interactive menu to set the Word Left navigation keybinding.
function edit-select::configure-word-left() {
	_zesw_banner

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_WORD_LEFT${_ZESW_CLR_RESET}"

	_zesw_info "Move cursor one word to the left"

	printf "\n  %s ℹ%s  The sequence your terminal sends for Ctrl+Left varies by terminal.\n" \
		"$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
	printf "         Run 'cat' and press Ctrl+Left to see the exact sequence yours sends.\n"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+Left        ${_ZESW_CLR_DIM}— Default (^[[1;5D, standard xterm/VT sequence)${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Ctrl+Left alt    ${_ZESW_CLR_DIM}— Alternative (^[b, some terminal emulators)${_ZESW_CLR_RESET}"
	_zesw_print_option 3 "Custom binding   ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
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
			local _zes_old_key="$EDIT_SELECT_KEY_WORD_LEFT"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_WORD_LEFT="^[[1;5D"
			edit-select::save-config "EDIT_SELECT_KEY_WORD_LEFT" "^[[1;5D"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Left binding" 2
			_zesw_success "Word Left bound to Ctrl+Left (^[[1;5D)"
			;;
		2)
			local _zes_old_key="$EDIT_SELECT_KEY_WORD_LEFT"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_WORD_LEFT="^[b"
			edit-select::save-config "EDIT_SELECT_KEY_WORD_LEFT" "^[b"
			edit-select::apply-keybindings
			_zesw_loading "Applying Alt+B binding" 2
			_zesw_success "Word Left bound to ^[b"
			;;
		3)
			if _zesw_read_custom_key custom_key; then
				local _zes_old_key="$EDIT_SELECT_KEY_WORD_LEFT"
				[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
				typeset -g EDIT_SELECT_KEY_WORD_LEFT="$custom_key"
				edit-select::save-config "EDIT_SELECT_KEY_WORD_LEFT" "$custom_key"
				edit-select::apply-keybindings
				_zesw_loading "Applying custom binding" 2
				_zesw_success "Word Left bound to custom key"
			fi
			;;
		4) return ;;
	esac
	_zesw_prompt_continue
}

# Interactive menu to set the Word Right navigation keybinding.
function edit-select::configure-word-right() {
	_zesw_banner

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_WORD_RIGHT${_ZESW_CLR_RESET}"

	_zesw_info "Move cursor one word to the right"

	printf "\n  %s ℹ%s  The sequence your terminal sends for Ctrl+Right varies by terminal.\n" \
		"$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
	printf "         Run 'cat' and press Ctrl+Right to see the exact sequence yours sends.\n"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+Right       ${_ZESW_CLR_DIM}— Default (^[[1;5C, standard xterm/VT sequence)${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Ctrl+Right alt   ${_ZESW_CLR_DIM}— Alternative (^[f, some terminal emulators)${_ZESW_CLR_RESET}"
	_zesw_print_option 3 "Custom binding   ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
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
			local _zes_old_key="$EDIT_SELECT_KEY_WORD_RIGHT"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_WORD_RIGHT="^[[1;5C"
			edit-select::save-config "EDIT_SELECT_KEY_WORD_RIGHT" "^[[1;5C"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Right binding" 2
			_zesw_success "Word Right bound to Ctrl+Right (^[[1;5C)"
			;;
		2)
			local _zes_old_key="$EDIT_SELECT_KEY_WORD_RIGHT"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_WORD_RIGHT="^[f"
			edit-select::save-config "EDIT_SELECT_KEY_WORD_RIGHT" "^[f"
			edit-select::apply-keybindings
			_zesw_loading "Applying Alt+F binding" 2
			_zesw_success "Word Right bound to ^[f"
			;;
		3)
			if _zesw_read_custom_key custom_key; then
				local _zes_old_key="$EDIT_SELECT_KEY_WORD_RIGHT"
				[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
				typeset -g EDIT_SELECT_KEY_WORD_RIGHT="$custom_key"
				edit-select::save-config "EDIT_SELECT_KEY_WORD_RIGHT" "$custom_key"
				edit-select::apply-keybindings
				_zesw_loading "Applying custom binding" 2
				_zesw_success "Word Right bound to custom key"
			fi
			;;
		4) return ;;
	esac
	_zesw_prompt_continue
}

# Interactive menu to set the Buffer Start navigation keybinding (Ctrl+Shift+Home by default).
function edit-select::configure-buffer-start() {
	_zesw_banner

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_BUFFER_START${_ZESW_CLR_RESET}"

	_zesw_info "Select from cursor to beginning of buffer"

	printf "\n  %s ℹ%s  The sequence your terminal sends for Ctrl+Shift+Home varies by terminal.\n" \
		"$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
	printf "         Run 'cat' and press Ctrl+Shift+Home to see the exact sequence yours sends.\n"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+Shift+Home  ${_ZESW_CLR_DIM}— Default (^[[1;6H, standard xterm/VT sequence)${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Custom binding   ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
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
			local _zes_old_key="$EDIT_SELECT_KEY_BUFFER_START"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_BUFFER_START="^[[1;6H"
			edit-select::save-config "EDIT_SELECT_KEY_BUFFER_START" "^[[1;6H"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Shift+Home binding" 2
			_zesw_success "Buffer Start bound to Ctrl+Shift+Home (^[[1;6H)"
			;;
		2)
			if _zesw_read_custom_key custom_key; then
				local _zes_old_key="$EDIT_SELECT_KEY_BUFFER_START"
				[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
				typeset -g EDIT_SELECT_KEY_BUFFER_START="$custom_key"
				edit-select::save-config "EDIT_SELECT_KEY_BUFFER_START" "$custom_key"
				edit-select::apply-keybindings
				_zesw_loading "Applying custom binding" 2
				_zesw_success "Buffer Start bound to custom key"
			fi
			;;
		3) return ;;
	esac
	_zesw_prompt_continue
}

# Interactive menu to set the Buffer End navigation keybinding (Ctrl+Shift+End by default).
function edit-select::configure-buffer-end() {
	_zesw_banner

	_zesw_section_header "Current Setting"
	_zesw_status_line "Binding" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_BUFFER_END${_ZESW_CLR_RESET}"

	_zesw_info "Select from cursor to end of buffer"

	printf "\n  %s ℹ%s  The sequence your terminal sends for Ctrl+Shift+End varies by terminal.\n" \
		"$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"
	printf "         Run 'cat' and press Ctrl+Shift+End to see the exact sequence yours sends.\n"

	_zesw_section_header "Available Presets"
	_zesw_print_option 1 "Ctrl+Shift+End   ${_ZESW_CLR_DIM}— Default (^[[1;6F, standard xterm/VT sequence)${_ZESW_CLR_RESET}"
	_zesw_print_option 2 "Custom binding   ${_ZESW_CLR_DIM}— Enter your own key sequence${_ZESW_CLR_RESET}"
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
			local _zes_old_key="$EDIT_SELECT_KEY_BUFFER_END"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_BUFFER_END="^[[1;6F"
			edit-select::save-config "EDIT_SELECT_KEY_BUFFER_END" "^[[1;6F"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Shift+End binding" 2
			_zesw_success "Buffer End bound to Ctrl+Shift+End (^[[1;6F)"
			;;
		2)
			if _zesw_read_custom_key custom_key; then
				local _zes_old_key="$EDIT_SELECT_KEY_BUFFER_END"
				[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -M edit-select -r "$_zes_old_key" 2>/dev/null; }
				typeset -g EDIT_SELECT_KEY_BUFFER_END="$custom_key"
				edit-select::save-config "EDIT_SELECT_KEY_BUFFER_END" "$custom_key"
				edit-select::apply-keybindings
				_zesw_loading "Applying custom binding" 2
				_zesw_success "Buffer End bound to custom key"
			fi
			;;
		3) return ;;
	esac
	_zesw_prompt_continue
}

# Interactive menu to set the Undo keybinding.
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
			local _zes_old_key="$EDIT_SELECT_KEY_UNDO"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_UNDO="^Z"
			edit-select::save-config "EDIT_SELECT_KEY_UNDO" "^Z"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Z binding" 2
			_zesw_success "Undo bound to Ctrl+Z"
			;;
		2)
			if _zesw_read_custom_key custom_key; then
				local _zes_old_key="$EDIT_SELECT_KEY_UNDO"
				[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -r "$_zes_old_key" 2>/dev/null; }
				typeset -g EDIT_SELECT_KEY_UNDO="$custom_key"
				edit-select::save-config "EDIT_SELECT_KEY_UNDO" "$custom_key"
				edit-select::apply-keybindings
				_zesw_loading "Applying custom binding" 2
				_zesw_success "Undo bound to custom key"
			fi
			;;
		3) return ;;
	esac
	_zesw_prompt_continue
}

# Interactive menu to set the Redo keybinding.
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
			local _zes_old_key="$EDIT_SELECT_KEY_REDO"
			[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -r "$_zes_old_key" 2>/dev/null; }
			typeset -g EDIT_SELECT_KEY_REDO="^[[90;6u"
			edit-select::save-config "EDIT_SELECT_KEY_REDO" "^[[90;6u"
			edit-select::apply-keybindings
			_zesw_loading "Applying Ctrl+Shift+Z binding" 2
			_zesw_success "Redo bound to Ctrl+Shift+Z"
			;;
		2)
			if _zesw_read_custom_key custom_key; then
				local _zes_old_key="$EDIT_SELECT_KEY_REDO"
				[[ -n "$_zes_old_key" ]] && { bindkey -M emacs -r "$_zes_old_key" 2>/dev/null; bindkey -r "$_zes_old_key" 2>/dev/null; }
				typeset -g EDIT_SELECT_KEY_REDO="$custom_key"
				edit-select::save-config "EDIT_SELECT_KEY_REDO" "$custom_key"
				edit-select::apply-keybindings
				_zesw_loading "Applying custom binding" 2
				_zesw_success "Redo bound to custom key"
			fi
			;;
		3) return ;;
	esac
	_zesw_prompt_continue
}

# Resets all keybindings to their default values after user confirmation.
function edit-select::reset-keybindings() {
	_zesw_banner

	printf "\n%s⚠ WARNING ⚠%s\n" "$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET"
	printf "This will reset all keybindings to their defaults.\n\n"

	_zesw_section_header "Default Keybindings"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Select All  → Ctrl+A\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Paste       → Ctrl+V\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Cut         → Ctrl+X\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Copy        → Ctrl+Shift+C (^[[67;6u, may require terminal configuration)\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Undo        → Ctrl+Z\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Redo        → Ctrl+Shift+Z\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Word Left   → Ctrl+Left (^[[1;5D)\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Word Right  → Ctrl+Right (^[[1;5C)\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Buffer Start → Ctrl+Shift+Home (^[[1;6H)\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Buffer End  → Ctrl+Shift+End (^[[1;6F)\n"

	_zesw_confirm_prompt "Reset all keybindings to defaults?"
	read -r confirm
	if [[ $confirm =~ ^[Yy]$ ]]; then
		_zesw_loading "Resetting keybindings" 3

		# Remove all old bindings before resetting to defaults
		local _k
		for _k in "$EDIT_SELECT_KEY_SELECT_ALL" "$EDIT_SELECT_KEY_PASTE" "$EDIT_SELECT_KEY_CUT" "$EDIT_SELECT_KEY_COPY"; do
			[[ -n "$_k" ]] && { bindkey -M emacs -r "$_k" 2>/dev/null; bindkey -M edit-select -r "$_k" 2>/dev/null; }
		done
		for _k in "$EDIT_SELECT_KEY_CUT"; do
			[[ -n "$_k" ]] && bindkey -r "$_k" 2>/dev/null
		done
		for _k in "$EDIT_SELECT_KEY_UNDO" "$EDIT_SELECT_KEY_REDO"; do
			[[ -n "$_k" ]] && { bindkey -M emacs -r "$_k" 2>/dev/null; bindkey -r "$_k" 2>/dev/null; }
		done
		for _k in "$EDIT_SELECT_KEY_WORD_LEFT" "$EDIT_SELECT_KEY_WORD_RIGHT" "$EDIT_SELECT_KEY_BUFFER_START" "$EDIT_SELECT_KEY_BUFFER_END"; do
			[[ -n "$_k" ]] && { bindkey -M emacs -r "$_k" 2>/dev/null; bindkey -M edit-select -r "$_k" 2>/dev/null; }
		done

		typeset -g EDIT_SELECT_KEY_SELECT_ALL="$_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL"
		typeset -g EDIT_SELECT_KEY_PASTE="$_EDIT_SELECT_DEFAULT_KEY_PASTE"
		typeset -g EDIT_SELECT_KEY_CUT="$_EDIT_SELECT_DEFAULT_KEY_CUT"
		typeset -g EDIT_SELECT_KEY_COPY="$_EDIT_SELECT_DEFAULT_KEY_COPY"
		typeset -g EDIT_SELECT_KEY_UNDO="$_EDIT_SELECT_DEFAULT_KEY_UNDO"
		typeset -g EDIT_SELECT_KEY_REDO="$_EDIT_SELECT_DEFAULT_KEY_REDO"
		typeset -g EDIT_SELECT_KEY_WORD_LEFT="$_EDIT_SELECT_DEFAULT_KEY_WORD_LEFT"
		typeset -g EDIT_SELECT_KEY_WORD_RIGHT="$_EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT"
		typeset -g EDIT_SELECT_KEY_BUFFER_START="$_EDIT_SELECT_DEFAULT_KEY_BUFFER_START"
		typeset -g EDIT_SELECT_KEY_BUFFER_END="$_EDIT_SELECT_DEFAULT_KEY_BUFFER_END"
		edit-select::save-config "EDIT_SELECT_KEY_SELECT_ALL" "$_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL"
		edit-select::save-config "EDIT_SELECT_KEY_PASTE" "$_EDIT_SELECT_DEFAULT_KEY_PASTE"
		edit-select::save-config "EDIT_SELECT_KEY_CUT" "$_EDIT_SELECT_DEFAULT_KEY_CUT"
		edit-select::save-config "EDIT_SELECT_KEY_COPY" "$_EDIT_SELECT_DEFAULT_KEY_COPY"
		edit-select::save-config "EDIT_SELECT_KEY_UNDO" "$_EDIT_SELECT_DEFAULT_KEY_UNDO"
		edit-select::save-config "EDIT_SELECT_KEY_REDO" "$_EDIT_SELECT_DEFAULT_KEY_REDO"
		edit-select::save-config "EDIT_SELECT_KEY_WORD_LEFT" "$_EDIT_SELECT_DEFAULT_KEY_WORD_LEFT"
		edit-select::save-config "EDIT_SELECT_KEY_WORD_RIGHT" "$_EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT"
		edit-select::save-config "EDIT_SELECT_KEY_BUFFER_START" "$_EDIT_SELECT_DEFAULT_KEY_BUFFER_START"
		edit-select::save-config "EDIT_SELECT_KEY_BUFFER_END" "$_EDIT_SELECT_DEFAULT_KEY_BUFFER_END"
		edit-select::apply-keybindings
		_zesw_success "All keybindings reset to defaults"
	else
		_zesw_info "Reset cancelled — No changes made"
	fi
	_zesw_prompt_continue
}


# Keybindings Menu


# Interactive menu to configure all keybindings for the plugin.
function edit-select::configure-keybindings() {
	while true; do
		_zesw_banner

		_zesw_section_header "Current Bindings"
		_zesw_status_line "Select All" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_SELECT_ALL${_ZESW_CLR_RESET}"
		_zesw_status_line "Paste" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_PASTE${_ZESW_CLR_RESET}"
		_zesw_status_line "Cut" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_CUT${_ZESW_CLR_RESET}"
		_zesw_status_line "Copy" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_COPY${_ZESW_CLR_RESET}"
		_zesw_status_line "Undo" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_UNDO${_ZESW_CLR_RESET}"
		_zesw_status_line "Redo" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_REDO${_ZESW_CLR_RESET}"
		_zesw_status_line "Word Left" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_WORD_LEFT${_ZESW_CLR_RESET}"
		_zesw_status_line "Word Right" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_WORD_RIGHT${_ZESW_CLR_RESET}"
		_zesw_status_line "Buffer Start" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_BUFFER_START${_ZESW_CLR_RESET}"
		_zesw_status_line "Buffer End" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_BUFFER_END${_ZESW_CLR_RESET}"

		_zesw_info "Customize keyboard shortcuts for selection operations"

		_zesw_section_header "Configure Individual Keys"
		_zesw_print_option 1 "Select All    ${_ZESW_CLR_DIM}— Select entire command line${_ZESW_CLR_RESET}"
		_zesw_print_option 2 "Paste         ${_ZESW_CLR_DIM}— Insert from clipboard${_ZESW_CLR_RESET}"
		_zesw_print_option 3 "Cut           ${_ZESW_CLR_DIM}— Delete selection and copy to clipboard${_ZESW_CLR_RESET}"
		_zesw_print_option 4 "Copy          ${_ZESW_CLR_DIM}— Copy selection to clipboard (may require terminal configuration)${_ZESW_CLR_RESET}"
		_zesw_print_option 5 "Undo          ${_ZESW_CLR_DIM}— Undo last edit${_ZESW_CLR_RESET}"
		_zesw_print_option 6 "Redo          ${_ZESW_CLR_DIM}— Redo last undone edit (may require terminal configuration)${_ZESW_CLR_RESET}"
		_zesw_print_option 7 "Word Left     ${_ZESW_CLR_DIM}— Move cursor one word left (Ctrl+Left)${_ZESW_CLR_RESET}"
		_zesw_print_option 8 "Word Right    ${_ZESW_CLR_DIM}— Move cursor one word right (Ctrl+Right)${_ZESW_CLR_RESET}"
		_zesw_print_option 9 "Buffer Start  ${_ZESW_CLR_DIM}— Select to beginning of buffer (Ctrl+Shift+Home)${_ZESW_CLR_RESET}"
		_zesw_print_option 10 "Buffer End    ${_ZESW_CLR_DIM}— Select to end of buffer (Ctrl+Shift+End)${_ZESW_CLR_RESET}"
		_zesw_separator
		_zesw_print_option 11 "Reset All to Defaults"
		_zesw_print_option 12 "Back to main menu"

		_zesw_input_prompt "Choose option (1-12):"
		read -r choice

		if ! _zesw_validate_choice "$choice" 1 12; then
			_zesw_error "Invalid choice. Please enter a number between 1-12."
			_zesw_prompt_continue
			continue
		fi

		case "$choice" in
			1) edit-select::configure-select-all ;;
			2) edit-select::configure-paste ;;
			3) edit-select::configure-cut ;;
			4) edit-select::configure-copy ;;
			5) edit-select::configure-undo ;;
			6) edit-select::configure-redo ;;
			7) edit-select::configure-word-left ;;
			8) edit-select::configure-word-right ;;
			9) edit-select::configure-buffer-start ;;
			10) edit-select::configure-buffer-end ;;
			11) edit-select::reset-keybindings ;;
			12) return ;;
		esac
	done
}


# Configuration View & Reset


# Resets the entire plugin configuration to defaults after user confirmation.
function edit-select::reset-config() {
	_zesw_banner

	printf "\n%s⚠ WARNING ⚠%s\n" "$_ZESW_CLR_WARN" "$_ZESW_CLR_RESET"
	printf "This will permanently delete all custom settings and restore factory defaults.\n\n"

	_zesw_section_header "What Will Be Reset"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Mouse replacement → Enabled\n"
	printf "  ${_ZESW_CLR_HILITE}•${_ZESW_CLR_RESET} Keybindings → Ctrl+A, Ctrl+V, Ctrl+X, Ctrl+Shift+C, Ctrl+Z, Ctrl+Shift+Z, Ctrl+Left, Ctrl+Right, Ctrl+Shift+Home, Ctrl+Shift+End\n"

	_zesw_confirm_prompt "Permanently delete configuration and reset to defaults?"
	read -r confirm
	if [[ $confirm =~ ^[Yy]$ ]]; then
		_zesw_loading "Deleting configuration" 2
		rm -f "$_EDIT_SELECT_CONFIG_FILE"

		# Remove all old bindings before resetting to defaults
		local _k
		for _k in "$EDIT_SELECT_KEY_SELECT_ALL" "$EDIT_SELECT_KEY_PASTE" "$EDIT_SELECT_KEY_CUT" "$EDIT_SELECT_KEY_COPY"; do
			[[ -n "$_k" ]] && { bindkey -M emacs -r "$_k" 2>/dev/null; bindkey -M edit-select -r "$_k" 2>/dev/null; }
		done
		for _k in "$EDIT_SELECT_KEY_CUT"; do
			[[ -n "$_k" ]] && bindkey -r "$_k" 2>/dev/null
		done
		for _k in "$EDIT_SELECT_KEY_UNDO" "$EDIT_SELECT_KEY_REDO"; do
			[[ -n "$_k" ]] && { bindkey -M emacs -r "$_k" 2>/dev/null; bindkey -r "$_k" 2>/dev/null; }
		done
		for _k in "$EDIT_SELECT_KEY_WORD_LEFT" "$EDIT_SELECT_KEY_WORD_RIGHT" "$EDIT_SELECT_KEY_BUFFER_START" "$EDIT_SELECT_KEY_BUFFER_END"; do
			[[ -n "$_k" ]] && { bindkey -M emacs -r "$_k" 2>/dev/null; bindkey -M edit-select -r "$_k" 2>/dev/null; }
		done

		typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=1
		typeset -g EDIT_SELECT_KEY_SELECT_ALL="$_EDIT_SELECT_DEFAULT_KEY_SELECT_ALL"
		typeset -g EDIT_SELECT_KEY_PASTE="$_EDIT_SELECT_DEFAULT_KEY_PASTE"
		typeset -g EDIT_SELECT_KEY_CUT="$_EDIT_SELECT_DEFAULT_KEY_CUT"
		typeset -g EDIT_SELECT_KEY_COPY="$_EDIT_SELECT_DEFAULT_KEY_COPY"
		typeset -g EDIT_SELECT_KEY_UNDO="$_EDIT_SELECT_DEFAULT_KEY_UNDO"
		typeset -g EDIT_SELECT_KEY_REDO="$_EDIT_SELECT_DEFAULT_KEY_REDO"
		typeset -g EDIT_SELECT_KEY_WORD_LEFT="$_EDIT_SELECT_DEFAULT_KEY_WORD_LEFT"
		typeset -g EDIT_SELECT_KEY_WORD_RIGHT="$_EDIT_SELECT_DEFAULT_KEY_WORD_RIGHT"
		typeset -g EDIT_SELECT_KEY_BUFFER_START="$_EDIT_SELECT_DEFAULT_KEY_BUFFER_START"
		typeset -g EDIT_SELECT_KEY_BUFFER_END="$_EDIT_SELECT_DEFAULT_KEY_BUFFER_END"
		edit-select::apply-keybindings
		edit-select::apply-mouse-replacement-config
		_zesw_success "All configuration reset to factory defaults"
		_zesw_info "Config file deleted: $_EDIT_SELECT_CONFIG_FILE"
	else
		_zesw_info "Reset cancelled — All settings preserved"
	fi
	_zesw_prompt_continue
}

# Displays the current plugin configuration as a formatted summary.
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
	printf "  %sClipboard:%s NSPasteboard (macOS)\n" "$_ZESW_CLR_ACCENT" "$_ZESW_CLR_RESET"

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
	_zesw_status_line "  Copy" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_COPY${_ZESW_CLR_RESET}"
	_zesw_status_line "  Undo" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_UNDO${_ZESW_CLR_RESET}"
	_zesw_status_line "  Redo" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_REDO${_ZESW_CLR_RESET}"
	_zesw_status_line "  Word Left" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_WORD_LEFT${_ZESW_CLR_RESET}"
	_zesw_status_line "  Word Right" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_WORD_RIGHT${_ZESW_CLR_RESET}"
	_zesw_status_line "  Buffer Start" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_BUFFER_START${_ZESW_CLR_RESET}"
	_zesw_status_line "  Buffer End" "${_ZESW_CLR_HILITE}$EDIT_SELECT_KEY_BUFFER_END${_ZESW_CLR_RESET}"

	_zesw_section_header "Plugin Information"
	printf "  %sPlugin Directory:%s\n" "$_ZESW_CLR_DIM" "$_ZESW_CLR_RESET"
	printf "  %s%s%s\n" "$_ZESW_CLR_DIM" "$_EDIT_SELECT_PLUGIN_DIR" "$_ZESW_CLR_RESET"

	_zesw_prompt_continue
}


# Main Entry Point


# Main entry point for the interactive configuration wizard.
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
