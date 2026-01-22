# Copyright (c) 2025 Michael Matta
# Version: 0.4.0
# Homepage: https://github.com/Michael-Matta1/zsh-edit-select

# Global State Variables
typeset -g _EDIT_SELECT_LAST_PRIMARY=""
typeset -g _EDIT_SELECT_ACTIVE_SELECTION=""
typeset -g _EDIT_SELECT_PENDING_SELECTION=""
typeset -gi _EDIT_SELECT_CLIPBOARD_BACKEND=0  # 0=none, 1=wayland, 2=x11, 3=macos
typeset -gi _EDIT_SELECT_IS_MACOS=0
[[ $OSTYPE == darwin* ]] && _EDIT_SELECT_IS_MACOS=1
typeset -gi EDIT_SELECT_MOUSE_REPLACEMENT=1
typeset -g _EDIT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-edit-select/config"
typeset -g _EDIT_SELECT_PLUGIN_DIR="${0:A:h}"

function edit-select::load-config() {
	[[ -r "$_EDIT_SELECT_CONFIG_FILE" ]] && source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
}

# Clipboard Helpers

function _zes_get_primary() {
	case $_EDIT_SELECT_CLIPBOARD_BACKEND in
		1) wl-paste --primary 2>/dev/null ;;
		2) xclip -selection primary -o 2>/dev/null ;;
		*) return 1 ;;
	esac
}

function _zes_get_clipboard() {
	case $_EDIT_SELECT_CLIPBOARD_BACKEND in
		1) wl-paste 2>/dev/null ;;
		2) xclip -selection clipboard -o 2>/dev/null ;;
		3) pbpaste 2>/dev/null ;;
		*) return 1 ;;
	esac
}

function _zes_copy_to_clipboard() {
	[[ -z "$1" ]] && return 1
	case $_EDIT_SELECT_CLIPBOARD_BACKEND in
		1) printf '%s' "$1" | wl-copy 2>/dev/null ;;
		2) printf '%s' "$1" | xclip -selection clipboard -in 2>/dev/null ;;
		3) printf '%s' "$1" | pbcopy 2>/dev/null ;;
		*) return 1 ;;
	esac
}

function _zes_clear_primary() {
	case $_EDIT_SELECT_CLIPBOARD_BACKEND in
		1) printf '' | wl-copy --primary 2>/dev/null ;;
		2) printf '' | xclip -selection primary -in 2>/dev/null ;;
		*) return 1 ;;
	esac
}

function _zes_sync_after_paste() {
	_EDIT_SELECT_ACTIVE_SELECTION=""
	_EDIT_SELECT_PENDING_SELECTION=""
	_EDIT_SELECT_LAST_PRIMARY=""
	_zes_clear_primary
}

# Mouse Selection Detection

function _zes_detect_mouse_selection() {
	(( !EDIT_SELECT_MOUSE_REPLACEMENT || _EDIT_SELECT_CLIPBOARD_BACKEND == 3 )) && return 1
	[[ -n "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && return 0
	
	local mouse_sel
	mouse_sel=$(_zes_get_primary) || return 1
	[[ -z "$mouse_sel" ]] && return 1
	
	if [[ "$mouse_sel" != "$_EDIT_SELECT_LAST_PRIMARY" ]]; then
		_EDIT_SELECT_LAST_PRIMARY="$mouse_sel"
		_EDIT_SELECT_PENDING_SELECTION=""
		if (( ${#mouse_sel} <= ${#BUFFER} )) && [[ "$BUFFER" == *"$mouse_sel"* ]]; then
			_EDIT_SELECT_ACTIVE_SELECTION="$mouse_sel"
			return 0
		fi
		return 1
	fi
	
	# Handle pending selection (retry after cursor repositioning for duplicates)
	if [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
		local sel="$_EDIT_SELECT_PENDING_SELECTION" sel_len=${#_EDIT_SELECT_PENDING_SELECTION}
		if [[ "$BUFFER" == *"$sel"* ]]; then
			local idx=0
			while (( idx <= ${#BUFFER} - sel_len )); do
				if [[ "${BUFFER:$idx:$sel_len}" == "$sel" ]]; then
					local end_pos=$(( idx + sel_len ))
					if (( CURSOR >= idx && CURSOR <= end_pos )); then
						_EDIT_SELECT_ACTIVE_SELECTION="$sel"
						_EDIT_SELECT_PENDING_SELECTION=""
						return 0
					fi
					(( idx += sel_len ))
				else
					(( idx++ ))
				fi
			done
		fi
		_EDIT_SELECT_PENDING_SELECTION=""
		_EDIT_SELECT_LAST_PRIMARY=""
		_zes_clear_primary
	fi
	return 1
}

function _zes_delete_mouse_selection() {
	[[ -z "$_EDIT_SELECT_ACTIVE_SELECTION" ]] && return 1
	
	local sel="$_EDIT_SELECT_ACTIVE_SELECTION" sel_len=${#_EDIT_SELECT_ACTIVE_SELECTION}
	(( sel_len > ${#BUFFER} )) && { _EDIT_SELECT_ACTIVE_SELECTION=""; return 1; }
	[[ "$BUFFER" != *"$sel"* ]] && { _EDIT_SELECT_ACTIVE_SELECTION=""; return 1; }
	
	# Find all occurrences
	local -a positions=()
	local buf="$BUFFER" idx=0
	while (( idx <= ${#buf} - sel_len )); do
		if [[ "${buf:$idx:$sel_len}" == "$sel" ]]; then
			positions+=($idx)
			(( idx += sel_len ))
		else
			(( idx++ ))
		fi
	done
	
	local num_occurrences=${#positions[@]}
	
	# For multiple occurrences, check if cursor is within one
	local target_pos=-1
	if (( num_occurrences > 1 )); then
		local pos end_pos
		for pos in "${positions[@]}"; do
			end_pos=$(( pos + sel_len ))
			if (( CURSOR >= pos && CURSOR <= end_pos )); then
				target_pos=$pos
				break
			fi
		done
	else
		target_pos=${positions[1]}
	fi
	
	if (( target_pos >= 0 )); then
		BUFFER="${BUFFER:0:$target_pos}${BUFFER:$(( target_pos + sel_len ))}"
		CURSOR=$target_pos
		_EDIT_SELECT_ACTIVE_SELECTION=""
		_EDIT_SELECT_PENDING_SELECTION=""
		_EDIT_SELECT_LAST_PRIMARY=""
		_zes_clear_primary
		return 0
	fi
	
	# Multiple occurrences, cursor not within any - prompt user
	zle -M "Duplicate text: place cursor inside the occurrence you want to modify"
	_EDIT_SELECT_PENDING_SELECTION="$_EDIT_SELECT_ACTIVE_SELECTION"
	_EDIT_SELECT_ACTIVE_SELECTION=""
	return 1
}

# Selection Widgets

function edit-select::select-all() {
	MARK=0
	CURSOR=${#BUFFER}
	REGION_ACTIVE=1
	zle -K edit-select
}
zle -N edit-select::select-all

function _zes_delete_selected_region() {
	zle kill-region -w
	zle -K main
}
zle -N edit-select::kill-region _zes_delete_selected_region

# Mouse Replacement Widgets

function edit-select::delete-mouse-or-backspace() {
	zle -Rc
	if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
		if _zes_detect_mouse_selection && _zes_delete_mouse_selection; then
			return
		elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
			return
		fi
	fi
	zle backward-delete-char -w
}
zle -N edit-select::delete-mouse-or-backspace

function edit-select::delete-mouse-or-delete() {
	zle -Rc
	if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
		if _zes_detect_mouse_selection && _zes_delete_mouse_selection; then
			return
		elif [[ -n "$_EDIT_SELECT_PENDING_SELECTION" ]]; then
			return
		fi
	fi
	zle delete-char -w
}
zle -N edit-select::delete-mouse-or-delete

function edit-select::handle-char() {
	zle -Rc
	if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
		if _zes_detect_mouse_selection; then
			if _zes_delete_mouse_selection; then
				zle self-insert -w
				return
			fi
			return
		fi
	fi
	zle self-insert -w
}
zle -N edit-select::handle-char

function _zes_cancel_region_and_replay_keys() {
	zle deactivate-region -w
	zle -K main
	zle -U "$KEYS"
}
zle -N edit-select::deselect-and-input _zes_cancel_region_and_replay_keys

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

# Clipboard Widgets

function edit-select::copy-region() {
	if (( REGION_ACTIVE )); then
		local start=$(( MARK < CURSOR ? MARK : CURSOR ))
		local length=$(( MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK ))
		_zes_copy_to_clipboard "${BUFFER:$start:$length}"
		_zes_sync_after_paste
		zle deactivate-region -w
		zle -K main
	else
		local primary_sel
		primary_sel=$(_zes_get_primary) || return
		[[ -n "$primary_sel" ]] && _zes_copy_to_clipboard "$primary_sel"
		_zes_sync_after_paste
	fi
}
zle -N edit-select::copy-region

function edit-select::cut-region() {
	if (( REGION_ACTIVE )); then
		local start=$(( MARK < CURSOR ? MARK : CURSOR ))
		local length=$(( MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK ))
		_zes_copy_to_clipboard "${BUFFER:$start:$length}"
		_zes_sync_after_paste
		zle kill-region -w
		zle -K main
	else
		(( !EDIT_SELECT_MOUSE_REPLACEMENT )) && return
		if _zes_detect_mouse_selection; then
			local sel="$_EDIT_SELECT_ACTIVE_SELECTION"
			_zes_delete_mouse_selection && _zes_copy_to_clipboard "$sel"
		fi
	fi
}
zle -N edit-select::cut-region

function edit-select::paste-clipboard() {
	if (( REGION_ACTIVE )); then
		zle kill-region -w
		REGION_ACTIVE=0
		zle -K main
	elif (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
		_zes_detect_mouse_selection
		_zes_delete_mouse_selection
	fi
	local clipboard_content
	clipboard_content=$(_zes_get_clipboard) || return
	[[ -n "$clipboard_content" ]] && LBUFFER="${LBUFFER}${clipboard_content}"
	_zes_sync_after_paste
}
zle -N edit-select::paste-clipboard

function edit-select::bracketed-paste-replace() {
	if (( REGION_ACTIVE )); then
		zle kill-region -w
		REGION_ACTIVE=0
		zle -K main
	elif (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
		_zes_detect_mouse_selection
		_zes_delete_mouse_selection
	fi
	zle .bracketed-paste
	_zes_sync_after_paste
}
zle -N edit-select::bracketed-paste-replace

# Shift-Selection Navigation

function _zes_activate_region_and_dispatch() {
	zle -Rc
	if (( !REGION_ACTIVE )); then
		zle set-mark-command -w
		zle -K edit-select
	fi
	zle "${WIDGET#edit-select::}" -w
}

# Keymap Configuration

function {
	emulate -L zsh
	bindkey -N edit-select
	bindkey -M edit-select -R '^@'-'^?' edit-select::deselect-and-input
	bindkey -M edit-select -R ' '-'~' edit-select::replace-selection
	
	local -a nav_bind=(
		'kLFT'  '^[[1;2D'   ''          'backward-char'
		'kRIT'  '^[[1;2C'   ''          'forward-char'
		'kri'   '^[[1;2A'   ''          'up-line'
		'kind'  '^[[1;2B'   ''          'down-line'
		'kHOM'  '^[[1;2H'   ''          'beginning-of-line'
		'kEND'  '^[[1;2F'   ''          'end-of-line'
		''      '^[[97;6u'  ''          'beginning-of-line'
		''      '^[[101;6u' ''          'end-of-line'
		''      '^[[1;6D'   '^[[1;4D'   'backward-word'
		''      '^[[1;6C'   '^[[1;4C'   'forward-word'
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
	
	local -a dest_bind=(
		'kdch1' '^[[3~' 'edit-select::kill-region'
		'bs'    '^?'    'edit-select::kill-region'
	)
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

# Mouse Replacement Configuration

function edit-select::apply-mouse-replacement-config() {
	if (( EDIT_SELECT_MOUSE_REPLACEMENT )); then
		bindkey -M emacs -R ' '-'~' edit-select::handle-char
		bindkey -M emacs '^?' edit-select::delete-mouse-or-backspace
		bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" edit-select::delete-mouse-or-delete
		bindkey -M emacs '^[[200~' edit-select::bracketed-paste-replace
		bindkey -M emacs '^V' edit-select::paste-clipboard
		bindkey -M edit-select '^V' edit-select::paste-clipboard
	else
		bindkey -M emacs -R ' '-'~' self-insert
		bindkey -M emacs '^?' backward-delete-char
		bindkey -M emacs "${terminfo[kdch1]:-^[[3~}" delete-char
		bindkey -M emacs '^[[200~' bracketed-paste
		bindkey -M emacs '^V' quoted-insert
		bindkey -M edit-select '^V' quoted-insert
		_EDIT_SELECT_LAST_PRIMARY=""
		_EDIT_SELECT_ACTIVE_SELECTION=""
		_EDIT_SELECT_PENDING_SELECTION=""
	fi
}

# User Command Interface

function edit-select() {
	if [[ $1 == conf || $1 == config ]]; then
		local wizard_file="$_EDIT_SELECT_PLUGIN_DIR/edit-select-wizard.zsh"
		if [[ -f "$wizard_file" ]]; then
			source "$wizard_file" 2>/dev/null || {
				print -u2 "Error: Failed to load configuration wizard"
				return 1
			}
			edit-select::config-wizard
		else
			print -u2 "Error: Configuration wizard not found at: $wizard_file"
			return 1
		fi
	else
		print "edit-select - Text selection and clipboard management for Zsh"
		print "\nUsage: edit-select <subcommand>"
		print "\nSubcommands:"
		print "  conf, config    Launch interactive configuration wizard"
	fi
}

# Plugin Initialization

if (( _EDIT_SELECT_IS_MACOS )) && command -v pbcopy &>/dev/null; then
	_EDIT_SELECT_CLIPBOARD_BACKEND=3
elif command -v wl-copy &>/dev/null && [[ -n "$WAYLAND_DISPLAY" ]]; then
	_EDIT_SELECT_CLIPBOARD_BACKEND=1
elif command -v xclip &>/dev/null && [[ -n "$DISPLAY" ]]; then
	_EDIT_SELECT_CLIPBOARD_BACKEND=2
fi

edit-select::load-config

# Backward compatibility: Convert old string-based config values
if [[ -f "$_EDIT_SELECT_CONFIG_FILE" ]]; then
	if grep -q 'EDIT_SELECT_MOUSE_REPLACEMENT="enabled"' "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null; then
		sed -i.bak 's/EDIT_SELECT_MOUSE_REPLACEMENT="enabled"/EDIT_SELECT_MOUSE_REPLACEMENT=1/' "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
		source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
	elif grep -q 'EDIT_SELECT_MOUSE_REPLACEMENT="disabled"' "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null; then
		sed -i.bak 's/EDIT_SELECT_MOUSE_REPLACEMENT="disabled"/EDIT_SELECT_MOUSE_REPLACEMENT=0/' "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
		source "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null
	fi
fi

if [[ -n "$EDIT_SELECT_CLIPBOARD_TYPE" ]]; then
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

# macOS: Default to disabled mouse replacement (no PRIMARY support)
if (( _EDIT_SELECT_CLIPBOARD_BACKEND == 3 )); then
	if [[ ! -f "$_EDIT_SELECT_CONFIG_FILE" ]] || ! grep -q "^EDIT_SELECT_MOUSE_REPLACEMENT=" "$_EDIT_SELECT_CONFIG_FILE" 2>/dev/null; then
		EDIT_SELECT_MOUSE_REPLACEMENT=0
	fi
fi

edit-select::apply-mouse-replacement-config
