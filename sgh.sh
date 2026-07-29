# shellcheck shell=bash
# sgh — a different GitHub account in every terminal.
#
# gh keeps one active account in ~/.config/gh/hosts.yml, so `gh auth switch`
# changes the account in EVERY terminal at once. sgh gives each account its own
# gh config dir and selects it with $GH_CONFIG_DIR, which is per-shell — so two
# terminals can hold two different GitHub identities at the same time.
#
# This file must be SOURCED, not executed: only a shell function can change the
# environment of the shell you are typing in.
#
#   . /path/to/sgh.sh
#
# https://github.com/lenixbyte/sgh — MIT licensed.

SGH_VERSION="0.1.0"
SGH_HOME="${SGH_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/sgh}"

# ── internals ─────────────────────────────────────────────────────────

__sgh_dir() { printf '%s' "$SGH_HOME/profiles/$1"; }
__sgh_gh_dir() { printf '%s' "$SGH_HOME/profiles/$1/gh"; }
__sgh_gh_config() { printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/gh"; }
__sgh_err() { printf 'sgh: %s\n' "$*" >&2; }

# Colours have to be decided here, not inside $(...) — a command substitution's
# stdout is a pipe, so `[ -t 1 ]` would always be false in there.
__sgh_colors() {
	if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
		SGH_B=$(printf '\033[1m')
		SGH_D=$(printf '\033[2m')
		SGH_O=$(printf '\033[0m')
	else
		SGH_B='' SGH_D='' SGH_O=''
	fi
}

__sgh_tilde() {
	case "$1" in
	"$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
	*) printf '%s' "$1" ;;
	esac
}

# Profile names become directory names, so keep them boring. This is also what
# stops `sgh delete ../../..` from being interesting.
__sgh_valid_name() {
	case "$1" in
	"" | . | ..) return 1 ;;
	*[!A-Za-z0-9._-]*) return 1 ;;
	esac
	return 0
}

__sgh_exists() { [ -d "$(__sgh_dir "$1")" ]; }

__sgh_require_gh() {
	command -v gh >/dev/null 2>&1 && return 0
	__sgh_err "the GitHub CLI (gh) is not installed — see https://cli.github.com"
	return 1
}

# Print "<login> <host>" for every account in a gh config dir by reading
# hosts.yml directly. Parsing beats shelling out to `gh auth status`, which
# makes a network call per account and would make `sgh list` feel slow.
__sgh_accounts() {
	local f="$1/hosts.yml"
	[ -f "$f" ] || return 0
	awk '
		function ind(s) { match(s, /^[ \t]*/); return RLENGTH }
		/^[ \t]*$/ { next }
		/^[^ \t#]/ { host = $1; sub(/:$/, "", host); uind = -1; cind = -1; next }
		host == "" { next }
		{
			i = ind($0); key = $1; sub(/:$/, "", key)
			if (key == "users" && uind < 0) { uind = i; next }
			if (uind < 0) next
			if (i <= uind) { uind = -1; cind = -1; next }   # left the users block
			if (cind < 0) cind = i
			# Direct children of users: are the logins; anything deeper is
			# that login s own settings (oauth_token, git_protocol, ...).
			if (i == cind && $0 ~ /:[ \t]*$/) print key, host
		}
	' "$f" | sort -u
}

# One line per profile: "octocat", or "octocat, admin@github.acme.com" when
# more than one host is in play.
__sgh_summary() {
	__sgh_accounts "$(__sgh_gh_dir "$1")" | awk '
		{ one = ($2 == "github.com") ? $1 : $1 "@" $2
		  line = (line == "") ? one : line ", " one }
		END { print (line == "") ? "—" : line }
	'
}

# gh stores tokens in the OS keyring by default, but falls back to writing
# oauth_token into hosts.yml. If this account is one of those, the token has to
# come along or the new profile would be logged out.
__sgh_token_in_file() {
	local src="$1" host="$2" login="$3"
	[ -f "$src" ] || return 0
	awk -v HOST="$host" -v LOGIN="$login" '
		function ind(s) { match(s, /^[ \t]*/); return RLENGTH }
		/^[^ \t#]/ { h = $1; sub(/:$/, "", h); inhost = (h == HOST); uind = -1; lind = -1; next }
		!inhost { next }
		{
			i = ind($0); key = $1; sub(/:$/, "", key)
			if (key == "users" && uind < 0) { uind = i; next }
			if (lind >= 0 && i <= lind) lind = -1
			if (uind >= 0 && lind < 0 && i > uind && key == LOGIN && $0 ~ /:[ \t]*$/) { lind = i; next }
			if (lind >= 0 && i > lind && key == "oauth_token") { print $2; exit }
		}
	' "$src"
}

__sgh_default() {
	[ -f "$SGH_HOME/default" ] || return 0
	head -n 1 "$SGH_HOME/default" 2>/dev/null
}

# find, not a glob: zsh's default nomatch would make `profiles/*` an error
# rather than an empty list when no profiles exist yet.
__sgh_list_names() {
	[ -d "$SGH_HOME/profiles" ] || return 0
	find "$SGH_HOME/profiles" -mindepth 1 -maxdepth 1 -type d 2>/dev/null |
		while IFS= read -r p; do printf '%s\n' "${p##*/}"; done | sort
}

__sgh_write_hosts() {
	# $1=gh dir  $2=login  $3=host  $4=token (optional)
	{
		printf '%s:\n' "$3"
		printf '    git_protocol: https\n'
		printf '    users:\n'
		printf '        %s:\n' "$2"
		[ -n "$4" ] && printf '            oauth_token: %s\n' "$4"
		printf '    user: %s\n' "$2"
	} >"$1/hosts.yml"
	chmod 600 "$1/hosts.yml" 2>/dev/null
	return 0
}

# Build a profile around an account that is already authenticated somewhere in
# the user's gh setup — the token is reused, so there is nothing to log in to.
__sgh_link_profile() {
	local name="$1" login="$2" host="$3" gh_dir src token
	gh_dir="$(__sgh_gh_dir "$name")"
	mkdir -p "$gh_dir" || return 1
	chmod 700 "$(__sgh_dir "$name")" 2>/dev/null

	# Carry over aliases/editor/prompt settings so a new profile does not feel
	# like a factory reset.
	src="$(__sgh_gh_config)/config.yml"
	[ -f "$src" ] && [ ! -f "$gh_dir/config.yml" ] && cp "$src" "$gh_dir/config.yml"

	token="$(__sgh_token_in_file "$(__sgh_gh_config)/hosts.yml" "$host" "$login")"
	__sgh_write_hosts "$gh_dir" "$login" "$host" "$token"
}

__sgh_apply() {
	GH_CONFIG_DIR="$(__sgh_gh_dir "$1")"
	SGH_PROFILE="$1"
	export GH_CONFIG_DIR SGH_PROFILE
	# Optional per-profile extras, commonly GIT_AUTHOR_EMAIL / GIT_COMMITTER_EMAIL.
	# shellcheck source=/dev/null
	[ -f "$(__sgh_dir "$1")/env.sh" ] && . "$(__sgh_dir "$1")/env.sh"
	return 0
}

# ── subcommands ───────────────────────────────────────────────────────

__sgh_cmd_list() {
	local names default n mark tag
	names="$(__sgh_list_names)"
	if [ -z "$names" ]; then
		printf 'No profiles yet.\n\n'
		printf '  sgh import          turn your existing gh logins into profiles\n'
		printf '  sgh add <name>      log in to a new account\n'
		return 0
	fi

	__sgh_colors
	default="$(__sgh_default)"
	printf '%s  %-16s %-30s%s\n' "$SGH_D" "PROFILE" "ACCOUNT" "$SGH_O"

	printf '%s\n' "$names" | while IFS= read -r n; do
		[ -n "$n" ] || continue
		mark='  '
		tag=''
		[ "$n" = "$default" ] && tag='default'
		if [ "$n" = "${SGH_PROFILE:-}" ]; then
			printf '%s* %-16s %-30s%s%s\n' "$SGH_B" "$n" "$(__sgh_summary "$n")" "$tag" "$SGH_O"
		else
			printf '%s%-16s %-30s%s%s%s\n' "$mark" "$n" "$(__sgh_summary "$n")" "$SGH_D" "$tag" "$SGH_O"
		fi
	done

	printf '\n%s* = active in this terminal%s\n' "$SGH_D" "$SGH_O"
	return 0
}

__sgh_cmd_add() {
	local name="$1" link='' host='github.com' gh_dir
	[ $# -gt 0 ] && shift

	if ! __sgh_valid_name "$name"; then
		__sgh_err "usage: sgh add <name> [--link <login>] [--host <host>] [gh auth login flags...]"
		return 1
	fi
	if __sgh_exists "$name"; then
		__sgh_err "profile '$name' already exists"
		return 1
	fi
	__sgh_require_gh || return 1

	while [ $# -gt 0 ]; do
		case "$1" in
		--link)
			link="$2"
			shift 2 || break
			;;
		--host | --hostname)
			host="$2"
			shift 2 || break
			;;
		*) break ;;
		esac
	done

	if [ -n "$link" ]; then
		__sgh_link_profile "$name" "$link" "$host" || return 1
		printf "Created profile '%s' → %s\n" "$name" "$link"
	else
		gh_dir="$(__sgh_gh_dir "$name")"
		mkdir -p "$gh_dir" || return 1
		chmod 700 "$(__sgh_dir "$name")" 2>/dev/null
		[ -f "$(__sgh_gh_config)/config.yml" ] &&
			cp "$(__sgh_gh_config)/config.yml" "$gh_dir/config.yml"

		printf "Logging in to a new account for profile '%s'...\n\n" "$name"
		if ! GH_CONFIG_DIR="$gh_dir" gh auth login --hostname "$host" "$@"; then
			__sgh_err "login failed — removing empty profile '$name'"
			rm -rf -- "$(__sgh_dir "$name")"
			return 1
		fi
		printf "\nCreated profile '%s' → %s\n" "$name" "$(__sgh_summary "$name")"
	fi

	[ -n "$(__sgh_default)" ] || printf '%s\n' "$name" >"$SGH_HOME/default"
	printf 'Use it here with: sgh switch %s\n' "$name"
	return 0
}

__sgh_cmd_switch() {
	local name="$1"

	if [ -z "$name" ]; then
		if command -v fzf >/dev/null 2>&1 && [ -t 0 ]; then
			name="$(__sgh_list_names | fzf --height 40% --reverse --prompt 'sgh switch > ')"
			[ -n "$name" ] || return 1
		else
			__sgh_err "usage: sgh switch <name>   (or 'none' for the plain gh config)"
			__sgh_cmd_list
			return 1
		fi
	fi

	if [ "$name" = none ] || [ "$name" = off ]; then
		unset GH_CONFIG_DIR SGH_PROFILE
		printf 'Unset — this terminal now uses the default gh config.\n'
		return 0
	fi

	if ! __sgh_valid_name "$name" || ! __sgh_exists "$name"; then
		__sgh_err "no such profile: $name"
		return 1
	fi

	__sgh_apply "$name"
	__sgh_cmd_who
	return 0
}

__sgh_cmd_who() {
	if [ "$1" = "-q" ] || [ "$1" = "--quiet" ]; then
		[ -n "${SGH_PROFILE:-}" ] && printf '%s\n' "$SGH_PROFILE"
		return 0
	fi

	if [ -z "${SGH_PROFILE:-}" ]; then
		printf 'No profile active in this terminal (using the default gh config).\n'
		[ -n "$(__sgh_list_names)" ] && printf 'Pick one with: sgh switch <name>\n'
		return 0
	fi

	__sgh_colors
	printf '%s%s%s → %s\n' "$SGH_B" "$SGH_PROFILE" "$SGH_O" "$(__sgh_summary "$SGH_PROFILE")"
	printf '%s%s%s\n' "$SGH_D" "$(__sgh_tilde "${GH_CONFIG_DIR:-}")" "$SGH_O"
	return 0
}

__sgh_cmd_delete() {
	local name="$1" force=0 logout=0 ans
	[ $# -gt 0 ] && shift
	while [ $# -gt 0 ]; do
		case "$1" in
		-y | --yes | -f | --force) force=1 ;;
		--logout) logout=1 ;;
		esac
		shift
	done

	if ! __sgh_valid_name "$name" || ! __sgh_exists "$name"; then
		__sgh_err "no such profile: $name"
		return 1
	fi

	if [ "$force" -ne 1 ]; then
		if [ ! -t 0 ]; then
			__sgh_err "refusing to delete without a terminal — pass --yes"
			return 1
		fi
		printf "Delete profile '%s' (%s)? [y/N] " "$name" "$(__sgh_summary "$name")"
		read -r ans
		case "$ans" in
		y | Y | yes | YES) ;;
		*)
			printf 'Cancelled.\n'
			return 1
			;;
		esac
	fi

	# Credentials stay in the keyring by default: another profile may point at
	# the same account, and revoking the token would break that one too.
	if [ "$logout" -eq 1 ]; then
		GH_CONFIG_DIR="$(__sgh_gh_dir "$name")" gh auth logout 2>/dev/null
	fi

	rm -rf -- "$(__sgh_dir "$name")"
	[ "$(__sgh_default)" = "$name" ] && rm -f "$SGH_HOME/default"
	[ "${SGH_PROFILE:-}" = "$name" ] && unset GH_CONFIG_DIR SGH_PROFILE

	printf "Deleted profile '%s'.\n" "$name"
	[ "$logout" -eq 1 ] ||
		printf 'Its credentials are still in your keyring (--logout removes them too).\n'
	return 0
}

__sgh_cmd_default() {
	local d
	if [ "$1" = "--clear" ]; then
		rm -f "$SGH_HOME/default"
		printf 'Cleared. New terminals will use the default gh config.\n'
		return 0
	fi
	if [ -z "$1" ]; then
		d="$(__sgh_default)"
		printf '%s\n' "${d:-(none)}"
		return 0
	fi
	if ! __sgh_valid_name "$1" || ! __sgh_exists "$1"; then
		__sgh_err "no such profile: $1"
		return 1
	fi
	printf '%s\n' "$1" >"$SGH_HOME/default"
	printf "New terminals will start as '%s'.\n" "$1"
	return 0
}

__sgh_cmd_exec() {
	local name="$1" rc
	[ $# -gt 0 ] && shift
	[ "$1" = "--" ] && shift

	if ! __sgh_valid_name "$name" || ! __sgh_exists "$name"; then
		__sgh_err "usage: sgh exec <name> -- <command> [args...]"
		return 1
	fi
	if [ $# -eq 0 ]; then
		__sgh_err "nothing to run: sgh exec $name -- <command>"
		return 1
	fi

	# A subshell, not a `VAR=x cmd` prefix: prefix assignments persist when the
	# command turns out to be a shell builtin, which would leak the profile
	# into the caller's terminal.
	(
		GH_CONFIG_DIR="$(__sgh_gh_dir "$name")"
		SGH_PROFILE="$name"
		export GH_CONFIG_DIR SGH_PROFILE
		"$@"
	)
	rc=$?
	return $rc
}

__sgh_cmd_import() {
	local src imported=0 login host name
	src="$(__sgh_gh_config)/hosts.yml"
	if [ ! -f "$src" ]; then
		__sgh_err "nothing to import — no accounts in $(__sgh_gh_config)"
		return 1
	fi

	# A here-string keeps the loop in this shell, so `imported` survives it.
	while IFS=' ' read -r login host; do
		[ -n "$login" ] || continue
		name="$(printf '%s' "$login" | tr -c 'A-Za-z0-9._-' '-')"
		if __sgh_exists "$name"; then
			printf "  skip    %-22s profile '%s' already exists\n" "$login" "$name"
			continue
		fi
		if __sgh_link_profile "$name" "$login" "$host"; then
			printf "  import  %-22s → profile '%s'\n" "$login" "$name"
			imported=$((imported + 1))
		fi
	done <<EOF
$(__sgh_accounts "$(__sgh_gh_config)")
EOF

	if [ "$imported" -eq 0 ]; then
		printf 'Nothing new to import.\n\n'
	else
		printf '\nImported %s profile(s). Existing tokens were reused, so no\n' "$imported"
		printf 'new login is needed unless gh reports one as expired.\n\n'
	fi
	__sgh_cmd_list
	return 0
}

__sgh_cmd_help() {
	cat <<EOF
sgh $SGH_VERSION — a different GitHub account in every terminal.

USAGE
  sgh <command> [args]

COMMANDS
  list                       Show every profile; * marks this terminal's
  switch <name>              Point THIS terminal at a profile (alias: use)
  switch none                Fall back to the plain gh config
  who [-q]                   Show the account this terminal is using
  add <name> [flags]         Create a profile and log in to it
  add <name> --link <login>  Create a profile from an account already in
                             your keyring — no new login
  delete <name> [--logout]   Remove a profile (alias: rm)
  default [<name>|--clear]   Profile that new terminals start as
  exec <name> -- <cmd>       Run one command as that account, no switching
  import                     Turn your existing gh logins into profiles
  path                       Print the gh config dir this terminal uses
  help | version

HOW IT WORKS
  Each profile is its own gh config dir under
  $(__sgh_tilde "$SGH_HOME")/profiles/. Switching sets \$GH_CONFIG_DIR, which
  is per-shell — so terminals never fight over one active account. This covers
  gh commands and plain https git clone/push, because git's credential helper
  is gh itself. SSH remotes are unaffected: there your SSH key decides.

EXAMPLES
  sgh import                       # first run: migrate what you already have
  sgh add personal                 # log in to another account
  sgh switch work                  # this terminal is work from now on
  sgh exec personal -- gh repo list
  sgh delete old-client --logout

  Show the profile in your prompt:
    zsh    RPROMPT='\$(sgh who -q)'
    bash   PS1="\$PS1\\\$(sgh who -q) "

  Per-profile git identity — put this in
  $(__sgh_tilde "$SGH_HOME")/profiles/<name>/env.sh:
    export GIT_AUTHOR_EMAIL=you@example.com
    export GIT_COMMITTER_EMAIL=you@example.com
EOF
	return 0
}

# ── entrypoint ────────────────────────────────────────────────────────

sgh() {
	local cmd="${1:-who}"
	[ $# -gt 0 ] && shift

	case "$cmd" in
	ls | list) __sgh_cmd_list "$@" ;;
	use | switch | sw) __sgh_cmd_switch "$@" ;;
	who | current | status) __sgh_cmd_who "$@" ;;
	add | new | login) __sgh_cmd_add "$@" ;;
	rm | remove | delete) __sgh_cmd_delete "$@" ;;
	default) __sgh_cmd_default "$@" ;;
	exec | run) __sgh_cmd_exec "$@" ;;
	import) __sgh_cmd_import "$@" ;;
	path) printf '%s\n' "${GH_CONFIG_DIR:-$(__sgh_gh_config)}" ;;
	help | -h | --help) __sgh_cmd_help ;;
	version | -v | --version) printf 'sgh %s\n' "$SGH_VERSION" ;;
	*)
		__sgh_err "unknown command: $cmd"
		printf "Try 'sgh help'.\n" >&2
		return 1
		;;
	esac
}

# ── completion ────────────────────────────────────────────────────────

SGH_COMMANDS="list switch who add delete default exec import path help version"

if [ -n "${BASH_VERSION:-}" ]; then
	# eval keeps bash-only array syntax away from other shells' parsers: a shell
	# reads the whole `if` before deciding which branch to run.
	eval '
	_sgh_complete_bash() {
		local cur prev
		cur="${COMP_WORDS[COMP_CWORD]}"
		prev="${COMP_WORDS[COMP_CWORD-1]}"
		if [ "$COMP_CWORD" -eq 1 ]; then
			COMPREPLY=( $(compgen -W "$SGH_COMMANDS" -- "$cur") )
		else
			case "$prev" in
				switch|use|sw|delete|rm|remove|default|exec|run)
					COMPREPLY=( $(compgen -W "$(__sgh_list_names) none" -- "$cur") ) ;;
				*) COMPREPLY=() ;;
			esac
		fi
	}
	complete -F _sgh_complete_bash sgh
	' 2>/dev/null
elif [ -n "${ZSH_VERSION:-}" ] && command -v compdef >/dev/null 2>&1; then
	# eval keeps zsh-only completion syntax away from other shells' parsers.
	eval '
	_sgh_complete_zsh() {
		if (( CURRENT == 2 )); then
			compadd ${=SGH_COMMANDS}
		else
			case "${words[2]}" in
				switch|use|sw|delete|rm|remove|default|exec|run)
					compadd ${(f)"$(__sgh_list_names)"} none ;;
			esac
		fi
	}
	compdef _sgh_complete_zsh sgh
	' 2>/dev/null
fi

mkdir -p "$SGH_HOME/profiles" 2>/dev/null

# New shells start on the default profile unless the parent shell already chose
# one — so a switch survives subshells, tmux panes and `exec zsh`.
if [ -z "${SGH_PROFILE:-}" ] && [ "${SGH_AUTO_DEFAULT:-1}" = 1 ]; then
	__sgh_boot="$(__sgh_default)"
	if [ -n "$__sgh_boot" ] && [ -d "$SGH_HOME/profiles/$__sgh_boot" ]; then
		__sgh_apply "$__sgh_boot"
	fi
	unset __sgh_boot
fi
