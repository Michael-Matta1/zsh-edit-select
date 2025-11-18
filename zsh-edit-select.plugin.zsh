# Copyright (c) 2025 Michael Matta
# Version: 0.3.2
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select

# Mouse selection tracking
typeset -g _EDIT_SELECT_LAST_PRIMARY=""
typeset -g _EDIT_SELECT_ACTIVE_SELECTION=""

# Clipboard backend: 0=none, 1=wayland, 2=x11, 3=macos
typeset -gi _EDIT_SELECT_CLIPBOARD_BACKEND=2

# Platform detection
typeset -gi _EDIT_SELECT_IS_MACOS=0
[[ $OSTYPE == darwin* ]] && _EDIT_SELECT_IS_MACOS=1

# Hook throttling
typeset -gi _EDIT_SELECT_CALL_COUNT=0
typeset -gi EDIT_SELECT_HOOK_THROTTLE="${EDIT_SELECT_HOOK_THROTTLE:-5}"

# Mouse replacement (stored as string for config file compatibility)
typeset -g EDIT_SELECT_MOUSE_REPLACEMENT="enabled"

# Configuration file location
typeset -g _EDIT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select/config"

# Plugin directory
typeset -g _EDIT_SELECT_PLUGIN_DIR="${0:A:h}"

# Load user configuration
function edit-select::load-config() {
	[[ -r $_EDIT_SELECT_CONFIG_FILE ]] && . "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
}

# ==============================================================================
# Selection Management
# ==============================================================================

# Select entire buffer
function edit-select::select-all() {
	MARK=0
	CURSOR=${#BUFFER}
	REGION_ACTIVE=1
	zle -K edit-select
}
zle -N edit-select::select-all

# Delete selected region and return to main mode
function _zes_delete_selected_region() {
	zle kill-region -w
	zle -K main
}
zle -N edit-select::kill-region _zes_delete_selected_region

# Delete mouse selection or perform backspace
function edit-select::delete-mouse-or-backspace() {
	if (( !EDIT_SELECT_MOUSE_REPLACEMENT )); then
		zle backward-delete-char -w
		return
	fi
	
	if [[ -z $_EDIT_SELECT_ACTIVE_SELECTION ]]; then
		local mouse_sel
		(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && mouse_sel=$(wl-paste --primary 2>/dev/null) || mouse_sel=$(xclip -selection primary -o 2>/dev/null)
		
		if [[ -n $mouse_sel && $mouse_sel != $_EDIT_SELECT_LAST_PRIMARY ]]; then
			if (( ${#mouse_sel} <= ${#BUFFER} )) && [[ $BUFFER == *$mouse_sel* ]]; then
				_EDIT_SELECT_ACTIVE_SELECTION=$mouse_sel
			fi
			_EDIT_SELECT_LAST_PRIMARY=$mouse_sel
		fi
	fi
	
	if [[ -n $_EDIT_SELECT_ACTIVE_SELECTION ]]; then
		local before="${BUFFER%%$_EDIT_SELECT_ACTIVE_SELECTION*}"
		if [[ ${BUFFER:${#before}:${#_EDIT_SELECT_ACTIVE_SELECTION}} == $_EDIT_SELECT_ACTIVE_SELECTION ]]; then
			BUFFER="${before}${BUFFER#*$_EDIT_SELECT_ACTIVE_SELECTION}"
			CURSOR=${#before}
			_EDIT_SELECT_ACTIVE_SELECTION=""
			return
		fi
	fi
	
	zle backward-delete-char -w
}
zle -N edit-select::delete-mouse-or-backspace

# Deactivate region and replay input
function _zes_cancel_region_and_replay_keys() {
	zle deactivate-region -w
	zle -K main
	zle -U "$KEYS"
}
zle -N edit-select::deselect-and-input _zes_cancel_region_and_replay_keys

# Replace selection with typed character
function edit-select::replace-selection() {
	if (( REGION_ACTIVE )); then
		zle kill-region -w
		zle -K main
		zle -U "$KEYS"
		return
	fi
	
	zle self-insert -w
}
zle -N edit-select::replace-selection

# Handle character input with mouse selection
function edit-select::handle-char() {
	if (( !EDIT_SELECT_MOUSE_REPLACEMENT )); then
		zle self-insert -w
		return
	fi
	
	if [[ -z $_EDIT_SELECT_ACTIVE_SELECTION ]]; then
		local mouse_sel
		(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && mouse_sel=$(wl-paste --primary 2>/dev/null) || mouse_sel=$(xclip -selection primary -o 2>/dev/null)
		
		if [[ -n $mouse_sel && $mouse_sel != $_EDIT_SELECT_LAST_PRIMARY ]]; then
			if (( ${#mouse_sel} <= ${#BUFFER} )) && [[ $BUFFER == *$mouse_sel* ]]; then
				_EDIT_SELECT_ACTIVE_SELECTION=$mouse_sel
			fi
			_EDIT_SELECT_LAST_PRIMARY=$mouse_sel
		fi
	fi
	
	if [[ -n $_EDIT_SELECT_ACTIVE_SELECTION ]]; then
		local before="${BUFFER%%$_EDIT_SELECT_ACTIVE_SELECTION*}"
		if [[ ${BUFFER:${#before}:${#_EDIT_SELECT_ACTIVE_SELECTION}} == $_EDIT_SELECT_ACTIVE_SELECTION ]]; then
			BUFFER="${before}${BUFFER#*$_EDIT_SELECT_ACTIVE_SELECTION}"
			CURSOR=${#before}
			_EDIT_SELECT_ACTIVE_SELECTION=""
		fi
	fi
	
	zle self-insert -w
}
zle -N edit-select::handle-char

# Track PRIMARY clipboard changes
function edit-select::zle-line-pre-redraw() {
	(( !EDIT_SELECT_MOUSE_REPLACEMENT )) && return
	(( (_EDIT_SELECT_CALL_COUNT++ % EDIT_SELECT_HOOK_THROTTLE) != 0 )) && return
	
	local current_primary
	(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && current_primary=$(wl-paste --primary 2>/dev/null) || current_primary=$(xclip -selection primary -o 2>/dev/null)
	[[ -n $current_primary ]] && _EDIT_SELECT_LAST_PRIMARY=$current_primary
}

# Copy selected region to clipboard
function edit-select::copy-region() {
	if (( REGION_ACTIVE )); then
		local start=$(( MARK < CURSOR ? MARK : CURSOR ))
		local length=$(( MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK ))
		local selected="${BUFFER:$start:$length}"
		
		(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && printf '%s' "$selected" | wl-copy || printf '%s' "$selected" | xclip -selection clipboard -in
		
		if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
			_EDIT_SELECT_LAST_PRIMARY=$selected
			_EDIT_SELECT_ACTIVE_SELECTION=""
		fi
		
		zle deactivate-region -w
		zle -K main
	else
		local primary_sel
		(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && primary_sel=$(wl-paste --primary 2>/dev/null) || primary_sel=$(xclip -selection primary -o 2>/dev/null)
		
		if [[ -n $primary_sel ]]; then
			(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && printf '%s' "$primary_sel" | wl-copy || printf '%s' "$primary_sel" | xclip -selection clipboard -in
			if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
				_EDIT_SELECT_LAST_PRIMARY=$primary_sel
				_EDIT_SELECT_ACTIVE_SELECTION=""
			fi
		fi
	fi
}
zle -N edit-select::copy-region

# Cut selected region to clipboard
function edit-select::cut-region() {
	if (( REGION_ACTIVE )); then
		local start=$(( MARK < CURSOR ? MARK : CURSOR ))
		local length=$(( MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK ))
		local selected="${BUFFER:$start:$length}"
		
		(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && printf '%s' "$selected" | wl-copy || printf '%s' "$selected" | xclip -selection clipboard -in
		
		if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
			_EDIT_SELECT_LAST_PRIMARY=$selected
			_EDIT_SELECT_ACTIVE_SELECTION=""
		fi
		
		zle kill-region -w
		zle -K main
	else
		(( !EDIT_SELECT_MOUSE_REPLACEMENT )) && return
		
		local mouse_sel
		(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && mouse_sel=$(wl-paste --primary 2>/dev/null) || mouse_sel=$(xclip -selection primary -o 2>/dev/null)
		
		if [[ -n $mouse_sel && $mouse_sel != $_EDIT_SELECT_LAST_PRIMARY ]]; then
			if (( ${#mouse_sel} <= ${#BUFFER} )) && [[ $BUFFER == *$mouse_sel* ]]; then
				_EDIT_SELECT_ACTIVE_SELECTION=$mouse_sel
			fi
			_EDIT_SELECT_LAST_PRIMARY=$mouse_sel
		fi
		
		if [[ -n $_EDIT_SELECT_ACTIVE_SELECTION ]]; then
			local before="${BUFFER%%$_EDIT_SELECT_ACTIVE_SELECTION*}"
			if [[ ${BUFFER:${#before}:${#_EDIT_SELECT_ACTIVE_SELECTION}} == $_EDIT_SELECT_ACTIVE_SELECTION ]]; then
				(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && printf '%s' "$_EDIT_SELECT_ACTIVE_SELECTION" | wl-copy || printf '%s' "$_EDIT_SELECT_ACTIVE_SELECTION" | xclip -selection clipboard -in
				
				BUFFER="${before}${BUFFER#*$_EDIT_SELECT_ACTIVE_SELECTION}"
				CURSOR=${#before}
				_EDIT_SELECT_ACTIVE_SELECTION=""
			fi
		fi
	fi
}
zle -N edit-select::cut-region

# Replace selected text with bracketed-paste content
function edit-select::bracketed-paste-replace() {
	if (( REGION_ACTIVE )); then
		zle kill-region -w
		REGION_ACTIVE=0
		zle -K main
	else
		if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
			if [[ -z $_EDIT_SELECT_ACTIVE_SELECTION ]]; then
				local mouse_sel
				(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && mouse_sel=$(wl-paste --primary 2>/dev/null) || mouse_sel=$(xclip -selection primary -o 2>/dev/null)
				
				if [[ -n $mouse_sel && $mouse_sel != $_EDIT_SELECT_LAST_PRIMARY ]]; then
					if (( ${#mouse_sel} <= ${#BUFFER} )) && [[ $BUFFER == *$mouse_sel* ]]; then
						_EDIT_SELECT_ACTIVE_SELECTION=$mouse_sel
					fi
					_EDIT_SELECT_LAST_PRIMARY=$mouse_sel
				fi
			fi
			
			if [[ -n $_EDIT_SELECT_ACTIVE_SELECTION ]]; then
				local before="${BUFFER%%$_EDIT_SELECT_ACTIVE_SELECTION*}"
				if [[ ${BUFFER:${#before}:${#_EDIT_SELECT_ACTIVE_SELECTION}} == $_EDIT_SELECT_ACTIVE_SELECTION ]]; then
					BUFFER="${before}${BUFFER#*$_EDIT_SELECT_ACTIVE_SELECTION}"
					CURSOR=${#before}
					_EDIT_SELECT_ACTIVE_SELECTION=""
				fi
			fi
		fi
	fi
	
	zle .bracketed-paste
	
	if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
		_EDIT_SELECT_ACTIVE_SELECTION=""
		local current_primary
		(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && current_primary=$(wl-paste --primary 2>/dev/null) || current_primary=$(xclip -selection primary -o 2>/dev/null)
		[[ -n $current_primary ]] && _EDIT_SELECT_LAST_PRIMARY=$current_primary
	fi
}
zle -N edit-select::bracketed-paste-replace

# Paste from clipboard
function edit-select::paste-clipboard() {
	if (( REGION_ACTIVE )); then
		zle kill-region -w
		REGION_ACTIVE=0
		zle -K main
	fi
	
	local clipboard_content
	(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && clipboard_content=$(wl-paste 2>/dev/null) || clipboard_content=$(xclip -selection clipboard -o 2>/dev/null)
	[[ -n $clipboard_content ]] && LBUFFER="${LBUFFER}${clipboard_content}"
	
	if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
		_EDIT_SELECT_ACTIVE_SELECTION=""
		local current_primary
		(( _EDIT_SELECT_CLIPBOARD_BACKEND == 1 )) && current_primary=$(wl-paste --primary 2>/dev/null) || current_primary=$(xclip -selection primary -o 2>/dev/null)
		[[ -n $current_primary ]] && _EDIT_SELECT_LAST_PRIMARY=$current_primary
	fi
}
zle -N edit-select::paste-clipboard


# Activate region and dispatch to base widget
function _zes_activate_region_and_dispatch() {
	if (( !REGION_ACTIVE )); then
		zle set-mark-command -w
		zle -K edit-select
	fi
	
	local base_widget="${WIDGET#edit-select::}"
	zle "$base_widget" -w
}

# Keymap Configuration & Shift-Selection Bindings

function {
	emulate -L zsh
	
	bindkey -N edit-select
	bindkey -M edit-select -R '^@'-'^?' edit-select::deselect-and-input
	bindkey -M edit-select -R ' '-'~' edit-select::replace-selection
	
	local -a nav_bind=(
		'kLFT' '^[[1;2D' '' 'backward-char'
		'kRIT' '^[[1;2C' '' 'forward-char'
		'kri' '^[[1;2A' '' 'up-line'
		'kind' '^[[1;2B' '' 'down-line'
		'kHOM' '^[[1;2H' '' 'beginning-of-line'
		'kEND' '^[[1;2F' '' 'end-of-line'
		'' '^[[97;6u' '' 'beginning-of-line'
		'' '^[[101;6u' '' 'end-of-line'
		'' '^[[1;6D' '^[[1;4D' 'backward-word'
		'' '^[[1;6C' '^[[1;4C' 'forward-word'
	)
	
	local i ti esc mac wid seq
	for (( i=1; i<=${#nav_bind}; i+=4 )); do
		ti=${nav_bind[i]}
		esc=${nav_bind[i+1]}
		mac=${nav_bind[i+2]}
		wid=${nav_bind[i+3]}
		
		(( _EDIT_SELECT_IS_MACOS && ${#mac} )) && esc=$mac
		
		seq=${terminfo[$ti]:-$esc}
		zle -N "edit-select::${wid}" _zes_activate_region_and_dispatch
		bindkey -M emacs "$seq" "edit-select::${wid}"
		bindkey -M edit-select "$seq" "edit-select::${wid}"
	done
	
	local -a dest_bind=('kdch1' '^[[3~' 'edit-select::kill-region' 'bs' '^?' 'edit-select::kill-region')
	for (( i=1; i<=${#dest_bind}; i+=3 )); do
		seq=${terminfo[${dest_bind[i]}]:-${dest_bind[i+1]}}
		bindkey -M edit-select "$seq" "${dest_bind[i+2]}"
	done
	
	bindkey -M edit-select '^[[67;6u' edit-select::copy-region
	bindkey -M edit-select '^X' edit-select::cut-region
	bindkey -M edit-select '^[[200~' edit-select::bracketed-paste-replace
	
	bindkey -M emacs '^A' edit-select::select-all
	bindkey -M emacs '^[[67;6u' edit-select::copy-region
	bindkey -M emacs '^X' edit-select::cut-region
	bindkey '^X' edit-select::cut-region
}

# Apply mouse replacement configuration
function edit-select::apply-mouse-replacement-config() {
	if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
		bindkey -M emacs -R ' '-'~' edit-select::handle-char
		bindkey -M emacs '^?' edit-select::delete-mouse-or-backspace
		bindkey -M emacs '^[[200~' edit-select::bracketed-paste-replace
		bindkey -M emacs '^V' edit-select::paste-clipboard
		bindkey -M edit-select '^V' edit-select::paste-clipboard
		
		autoload -Uz add-zle-hook-widget
		add-zle-hook-widget line-pre-redraw edit-select::zle-line-pre-redraw
	else
		bindkey -M emacs -R ' '-'~' self-insert
		bindkey -M emacs '^?' backward-delete-char
		bindkey -M emacs '^[[200~' bracketed-paste
		bindkey -M emacs '^V' quoted-insert
		bindkey -M edit-select '^V' quoted-insert
		
		autoload -Uz add-zle-hook-widget
		add-zle-hook-widget -D line-pre-redraw edit-select::zle-line-pre-redraw
		
		_EDIT_SELECT_LAST_PRIMARY=""
		_EDIT_SELECT_ACTIVE_SELECTION=""
	fi
}

# Configuration wizard command
function edit-select() {
	if [[ $1 == conf || $1 == config ]]; then
		local wizard_file="$_EDIT_SELECT_PLUGIN_DIR/edit-select-wizard.zsh"
		if [[ -f $wizard_file ]]; then
			if ! source "$wizard_file" 2>/dev/null; then
				echo "Error: Failed to load configuration wizard"
				echo "Check file permissions: $wizard_file"
				return 1
			fi
			edit-select::config-wizard
		else
			echo "Error: Configuration wizard file not found at: $wizard_file"
			echo "Please ensure edit-select-wizard.zsh is in the same directory as the plugin."
			return 1
		fi
	else
		echo "edit-select - Text selection and clipboard management for Zsh"
		echo ""
		echo "Usage: edit-select <subcommand>"
		echo ""
		echo "Subcommands:"
		echo "  conf, config    Launch interactive configuration wizard"
		echo ""
	fi
}

# Plugin Initialization

if (( _EDIT_SELECT_IS_MACOS )) && command -v pbcopy &>/dev/null; then
	_EDIT_SELECT_CLIPBOARD_BACKEND=3
elif command -v wl-copy &>/dev/null && [[ -n $WAYLAND_DISPLAY ]]; then
	_EDIT_SELECT_CLIPBOARD_BACKEND=1
elif command -v xclip &>/dev/null && [[ -n $DISPLAY ]]; then
	_EDIT_SELECT_CLIPBOARD_BACKEND=2
else
	_EDIT_SELECT_CLIPBOARD_BACKEND=0
fi

edit-select::load-config

if [[ -n $EDIT_SELECT_CLIPBOARD_TYPE ]]; then
	case $EDIT_SELECT_CLIPBOARD_TYPE in
		macos) (( _EDIT_SELECT_IS_MACOS )) && command -v pbcopy &>/dev/null && _EDIT_SELECT_CLIPBOARD_BACKEND=3 ;;
		wayland) command -v wl-copy &>/dev/null && _EDIT_SELECT_CLIPBOARD_BACKEND=1 ;;
		x11) command -v xclip &>/dev/null && _EDIT_SELECT_CLIPBOARD_BACKEND=2 ;;
	esac
fi

case $EDIT_SELECT_MOUSE_REPLACEMENT in
	enabled|1) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
	disabled|0) EDIT_SELECT_MOUSE_REPLACEMENT=0 ;;
	*) EDIT_SELECT_MOUSE_REPLACEMENT=1 ;;
esac

(( _EDIT_SELECT_CLIPBOARD_BACKEND == 3 && EDIT_SELECT_MOUSE_REPLACEMENT == 1 )) && EDIT_SELECT_MOUSE_REPLACEMENT=0

edit-select::apply-mouse-replacement-config