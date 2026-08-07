#!/bin/sh
# zsh-edit-select hook manager — install or remove git hooks.
#
# Usage: manage-hooks.sh install|remove [plugin_dir]
#
# Called by:
#   - edit-select::setup-hooks (zsh, user-initiated, verbose)
#   - edit-select::remove-hooks (zsh, user-initiated, verbose)
#   - auto-installer (bash, fresh install, output captured and displayed)
#
# This script is verbose (prints status/warnings) when called by the user
# via edit-select setup-hooks/remove-hooks.  When called by the auto-installer,
# output is captured and displayed by the installer.

set -eu

# ${1:-} (not $1): under set -u a bare $1 with no arguments aborts with
# "parameter not set" before the usage branch below can run.
action="${1:-}"
plugin_dir="${2:-}"
[ -z "$plugin_dir" ] && plugin_dir=$(git rev-parse --show-toplevel 2>/dev/null || true)

[ -z "$plugin_dir" ] && { echo "Error: not a git repository" >&2; exit 1; }
[ -f "$plugin_dir/zsh-edit-select.plugin.zsh" ] || {
    echo "Error: not a zsh-edit-select plugin directory" >&2
    exit 1
}

plugin_dir=$(CDPATH= cd -- "$plugin_dir" 2>/dev/null && pwd -P) || {
    echo "Error: cannot resolve plugin directory" >&2
    exit 1
}
git_top=$(git -C "$plugin_dir" rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$git_top" ] && git_top=$(CDPATH= cd -- "$git_top" 2>/dev/null && pwd -P) || true
[ "$git_top" = "$plugin_dir" ] || {
    echo "Error: zsh-edit-select hooks require the plugin to be its own git repository" >&2
    exit 1
}

git_dir=$(git -C "$plugin_dir" rev-parse --git-common-dir 2>/dev/null || true)
[ -z "$git_dir" ] && { echo "Error: not a git repository" >&2; exit 1; }
# --git-common-dir is relative to $plugin_dir when relative at all; absolutize
# it so the collision scan reaches the hooks Git uses for linked worktrees too.
case "$git_dir" in
    /*) : ;;
    *) git_dir="$plugin_dir/$git_dir" ;;
esac
git_hooks_dir="$git_dir/hooks"

if [ "$action" = "install" ]; then
    # Check for pre-existing core.hooksPath.
    # "Is this ours?" detection: core.hooksPath value is exactly "hooks".
    # No file grep needed — the config value is unambiguous.
    current=$(git -C "$plugin_dir" config --get core.hooksPath 2>/dev/null || true)
    already_installed=0
    if [ "$current" = "hooks" ]; then
        # Already ours.  Do NOT early-exit: a prior `git clean` may have removed
        # .zes-hooks-installed (and possibly the agent binaries) while
        # core.hooksPath survived in .git/config.  Fall through to re-chmod,
        # re-assert the marker via the probe below, and re-run the --setup
        # checker (which re-provisions any missing binaries/.zwc).  Skip the
        # collision scan and the config-set — both are only for a fresh install.
        already_installed=1
    elif [ -n "$current" ]; then
        # Collision: user already has core.hooksPath set to something else.
        # Don't overwrite — print warning and exit.
        echo "Warning: core.hooksPath is already set to '$current'." >&2
        echo "Cannot install zsh-edit-select hooks without overwriting this setting." >&2
        echo "To use this feature, integrate manually or unset core.hooksPath first:" >&2
        echo "  git -C \"$plugin_dir\" config --unset core.hooksPath" >&2
        exit 1
    fi

    if [ "$already_installed" = 0 ]; then
        # Check for active hooks in .git/hooks/ that would be disabled
        # when core.hooksPath is set.  We use a portable POSIX shell loop
        # (NOT find -perm -u+x, which is GNU-only and doesn't work on BSD/macOS).
        # *.sample files are excluded because git ships them as inert templates.
        set --
        if [ -d "$git_hooks_dir" ]; then
            for f in "$git_hooks_dir"/*; do
                [ -f "$f" ] || continue
                # Skip .sample files (git's default inert templates)
                case "$f" in *.sample) continue;; esac
                [ -x "$f" ] && set -- "$@" "$f"
            done
        fi
        if [ "$#" -gt 0 ]; then
            echo "Warning: active hooks found in .git/hooks/:" >&2
            for h do echo "  $h" >&2; done
            echo "Setting core.hooksPath will redirect git to hooks/ and these will stop running." >&2
            echo "Our hooks chain to .git/hooks/post-merge and post-rewrite," >&2
            echo "but other hook types (pre-commit, pre-push, etc.) will not fire." >&2
            echo "Run 'edit-select remove-hooks' to restore." >&2
        fi

        # Set core.hooksPath to our tracked hooks/ directory.
        # Relative path ("hooks") is robust to repo moves and works in git worktrees
        # and submodules (verified on git 2.34.1 — the committed hooks/ dir is
        # checked out in each worktree/submodule working directory, and the relative
        # path resolves against that working tree's root regardless of the cwd from
        # which git is invoked, including `git -C` and from a subdirectory).
        git -C "$plugin_dir" config core.hooksPath hooks
    fi

    # Ensure hook files are executable (best-effort — on WSL DrvFs without
    # metadata mount option, chmod may be a no-op; see README troubleshooting).
    chmod +x "$plugin_dir/hooks/post-merge" 2>/dev/null || true
    chmod +x "$plugin_dir/hooks/post-rewrite" 2>/dev/null || true
    chmod +x "$plugin_dir/hooks/manage-hooks.sh" 2>/dev/null || true

    # Create the fast-path marker ONLY when git will actually resolve AND run
    # our post-merge hook.  This mirrors the silent bootstrap's marker invariant
    # in the root loader EXACTLY — the two are separate implementations of
    # the same rule (".zes-hooks-installed present" ⇒ "the hook fires"), so keep
    # them in lockstep if either changes.  The gate is `git rev-parse --git-path
    # hooks/post-merge` resolving to our file AND that file being executable, NOT
    # a bare `[ -x "$plugin_dir/hooks/post-merge" ]`:
    #   - git <2.9 STORES core.hooksPath (git config is schema-less) but never
    #     READS it → runs .git/hooks/ → our hook never fires.  --git-path
    #     resolves to .git/hooks/... (not our file) exactly then, so the marker
    #     is correctly skipped.
    #   - WSL DrvFs no-metadata → our file exists but the exec bit didn't stick
    #     → the -x on the resolved path fails → marker skipped.
    # --git-path returns a repo-relative path; make it absolute before -x.
    hook_eff=$(git -C "$plugin_dir" rev-parse --git-path hooks/post-merge 2>/dev/null || true)
    case "$hook_eff" in
        "") : ;;
        /*) : ;;
        *) hook_eff="$plugin_dir/$hook_eff" ;;
    esac
    if [ -n "$hook_eff" ] && [ -x "$hook_eff" ]; then
        touch "$plugin_dir/.zes-hooks-installed"
        if [ "$already_installed" = 1 ]; then
            echo "zsh-edit-select: Hooks already installed (marker refreshed)."
        else
            echo "zsh-edit-select: Git hooks installed."
            echo "  After future git pulls, you'll be prompted to run 'edit-select update'."
        fi
    else
        # A failed probe invalidates any marker left by an earlier successful
        # install; retaining it would disable the loader's provisioning
        # self-heal even though this hook is now known not to fire.
        rm -f "$plugin_dir/.zes-hooks-installed"
        echo "Warning: git hooks cannot fire in this repository." >&2
        echo "Either git is older than 2.9 (no core.hooksPath support) or the hook" >&2
        echo "files could not be made executable (e.g. WSL DrvFs without the metadata" >&2
        echo "mount option).  core.hooksPath is set, but update notifications will not" >&2
        echo "fire, so the .zes-hooks-installed fast-path marker is intentionally kept" >&2
        echo "absent and startup provisioning stays enabled (no regression)." >&2
        echo "Run 'edit-select update' manually after pulls, or reinstall on a native" >&2
        echo "Linux filesystem with a current git." >&2
    fi

    # Run checker in setup mode — performs binary provisioning and .zwc
    # recompilation but skips the interactive "run edit-select update?" prompt.
    # The prompt is inappropriate here because:
    #   - Fresh install: nothing was "updated via pull" — the repo was cloned.
    #   - Manual setup-hooks: the setup itself already does the provisioning.
    # Error/diagnostic messages (e.g. binary build failure) are still printed.
    # The silent startup bootstrap NEVER calls the checker at all.
    #
    # No /dev/tty check or redirect: setup mode never calls read (the only
    # read is inside the `if (( ! _zes_pp_setup ))` block), so it works
    # headless/CI/Docker/non-interactive without a controlling terminal.
    # `|| true` is load-bearing, not cosmetic: under set -e an assignment
    # whose command substitution fails (zsh absent) would abort the script
    # here — after the hooks were already installed — making the caller
    # report failure for a successful install.  The [ -n ] guard below is
    # the intended skip path.
    zsh_bin=$(command -v zsh 2>/dev/null || true)
    if [ -n "$zsh_bin" ]; then
        "$zsh_bin" "$plugin_dir/hooks/zes-post-pull" --setup
    fi

elif [ "$action" = "remove" ]; then
    # Only unset if it's our value.
    current=$(git -C "$plugin_dir" config --get core.hooksPath 2>/dev/null || true)
    if [ "$current" = "hooks" ]; then
        git -C "$plugin_dir" config --unset core.hooksPath
    fi
    rm -f "$plugin_dir/.zes-hooks-installed"
    echo "zsh-edit-select: Git hooks removed."

else
    echo "Usage: manage-hooks.sh install|remove [plugin_dir]" >&2
    exit 1
fi
