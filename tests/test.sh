#!/usr/bin/env bash
# sgh test suite. Runs against a throwaway $SGH_HOME with a stub `gh` on PATH,
# so it never touches the real GitHub CLI, your keyring, or the network.
#
#   tests/test.sh            run under the current shell
#   SHELLS="bash zsh" tests/test.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

ok() {
	PASS=$((PASS + 1))
	printf '  \033[32m✓\033[0m %s\n' "$1"
}
no() {
	FAIL=$((FAIL + 1))
	printf '  \033[31m✗\033[0m %s\n' "$1"
	[ $# -gt 1 ] && printf '      %s\n' "$2"
}

is() { # is <desc> <expected> <actual>
	if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi
}
has() { # has <desc> <needle> <haystack>
	case "$3" in
	*"$2"*) ok "$1" ;;
	*) no "$1" "[$2] not found in: $3" ;;
	esac
}
hasnt() {
	case "$3" in
	*"$2"*) no "$1" "[$2] unexpectedly found in: $3" ;;
	*) ok "$1" ;;
	esac
}

# ── sandbox ───────────────────────────────────────────────────────────

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/sgh-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
export XDG_CONFIG_HOME="$SANDBOX/home/.config"
export SGH_HOME="$SANDBOX/home/.config/sgh"
mkdir -p "$XDG_CONFIG_HOME/gh" "$SANDBOX/bin"

# A gh that records how it was called instead of talking to GitHub.
cat >"$SANDBOX/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s\n' "${GH_CONFIG_DIR:-unset}" "$*" >>"$SGH_CALLS"
case "$1 $2" in
  "auth login") mkdir -p "$GH_CONFIG_DIR"
    printf 'github.com:\n    users:\n        stub-user:\n    user: stub-user\n' \
      > "$GH_CONFIG_DIR/hosts.yml" ;;
esac
exit 0
STUB
chmod +x "$SANDBOX/bin/gh"
export PATH="$SANDBOX/bin:$PATH"
export SGH_CALLS="$SANDBOX/calls.log"
: >"$SGH_CALLS"

# An existing multi-account gh setup to import: one keyring-backed account and
# one with the token written into hosts.yml.
cat >"$XDG_CONFIG_HOME/gh/hosts.yml" <<'YML'
github.com:
    git_protocol: https
    users:
        work-acct:
        personal-acct:
            oauth_token: gho_filetoken123
    user: work-acct
github.acme.com:
    users:
        enterprise-acct:
    user: enterprise-acct
YML
printf 'version: "1"\naliases:\n    co: pr checkout\n' >"$XDG_CONFIG_HOME/gh/config.yml"

# ── run one shell's worth of tests ────────────────────────────────────

run_suite() {
	local sh_bin="$1"
	printf '\n\033[1m%s\033[0m\n' "$sh_bin"

	# Each `s` call is a fresh shell = a fresh terminal.
	s() { NO_COLOR=1 "$sh_bin" -c ". '$ROOT/sgh.sh'; $1" 2>&1; }

	rm -rf "$SGH_HOME"
	: >"$SGH_CALLS" # each shell gets its own call log

	local out
	out="$(s 'sgh version')"
	has "version prints" "sgh 0." "$out"

	out="$(s 'sgh help')"
	has "help mentions switch" "switch <name>" "$out"

	out="$(s 'sgh list')"
	has "empty list guides the user" "No profiles yet" "$out"

	# zsh's nomatch would turn an empty profiles dir into a glob error here.
	is "no profiles: nothing on stderr" "" \
		"$(NO_COLOR=1 "$sh_bin" -c ". '$ROOT/sgh.sh'; sgh list; sgh who" 2>&1 >/dev/null)"

	out="$(s 'sgh who')"
	has "who with no profile" "No profile active" "$out"

	# --- import ---
	out="$(s 'sgh import')"
	has "imports keyring account" "work-acct" "$out"
	has "imports file-token account" "personal-acct" "$out"
	has "imports enterprise account" "enterprise-acct" "$out"
	[ -f "$SGH_HOME/profiles/work-acct/gh/hosts.yml" ] &&
		ok "import wrote hosts.yml" || no "import wrote hosts.yml"
	is "import kept the enterprise host" "github.acme.com:" \
		"$(head -n 1 "$SGH_HOME/profiles/enterprise-acct/gh/hosts.yml")"
	has "file-stored token carried over" "gho_filetoken123" \
		"$(cat "$SGH_HOME/profiles/personal-acct/gh/hosts.yml")"
	hasnt "keyring profile got no bogus token" "oauth_token" \
		"$(cat "$SGH_HOME/profiles/work-acct/gh/hosts.yml")"
	has "gh settings seeded into profile" "pr checkout" \
		"$(cat "$SGH_HOME/profiles/work-acct/gh/config.yml")"
	is "import is idempotent" "0" \
		"$(s 'sgh import' | grep -c 'import  ')"

	# --- switch / who ---
	out="$(s 'sgh switch work-acct; sgh who -q')"
	is "switch then who -q" "work-acct" "$(printf '%s' "$out" | tail -n 1)"

	out="$(s 'sgh switch work-acct; printf "%s" "$GH_CONFIG_DIR"')"
	has "switch exports GH_CONFIG_DIR" "profiles/work-acct/gh" "$out"

	out="$(s 'sgh switch nope')"
	has "unknown profile refused" "no such profile" "$out"

	out="$(s 'sgh switch work-acct; sgh switch none; sgh who -q')"
	is "switch none clears" "" "$(printf '%s' "$out" | tail -n 1 | grep -v Unset)"

	out="$(s 'sgh list; sgh switch personal-acct >/dev/null; sgh list')"
	has "list marks the active profile" "* personal-acct" "$out"

	# --- THE point of the tool: two terminals, two identities ---
	local t1 t2
	t1="$(s 'sgh switch work-acct >/dev/null; sgh who -q')"
	t2="$(s 'sgh switch personal-acct >/dev/null; sgh who -q')"
	if [ "$t1" = "work-acct" ] && [ "$t2" = "personal-acct" ]; then
		ok "two shells hold two different accounts"
	else
		no "two shells hold two different accounts" "got [$t1] and [$t2]"
	fi

	# --- default ---
	s 'sgh default personal-acct' >/dev/null
	is "default persists to new shells" "personal-acct" "$(s 'sgh who -q')"
	is "default is reported" "personal-acct" "$(s 'sgh default')"
	is "an explicit switch beats the default" "work-acct" \
		"$(s 'sgh switch work-acct >/dev/null; sgh who -q')"
	is "SGH_PROFILE from the parent shell wins" "work-acct" \
		"$(SGH_PROFILE=work-acct GH_CONFIG_DIR=x s 'sgh who -q')"
	s 'sgh default --clear' >/dev/null
	is "default can be cleared" "" "$(s 'sgh who -q')"

	# --- add ---
	out="$(s 'sgh add ci --link bot-user')"
	has "add --link reports the account" "bot-user" "$out"
	has "add --link needs no login" "0" "$(grep -c 'auth login' "$SGH_CALLS")"
	is "add --link writes the active user" "    user: bot-user" \
		"$(tail -n 1 "$SGH_HOME/profiles/ci/gh/hosts.yml")"

	out="$(s 'sgh add ci --link bot-user')"
	has "duplicate profile refused" "already exists" "$out"

	out="$(s 'sgh add "../escape" --link x')"
	has "path traversal refused" "usage: sgh add" "$out"
	[ -d "$SGH_HOME/profiles/../escape" ] &&
		no "path traversal refused (nothing created)" || ok "traversal created nothing"

	out="$(s 'sgh add fresh')"
	has "add without --link runs gh auth login" "auth login" "$(cat "$SGH_CALLS")"
	has "add reports the new profile" "Created profile 'fresh'" "$out"
	has "gh auth login ran inside the profile dir" "profiles/fresh/gh|auth login" \
		"$(cat "$SGH_CALLS")"

	# --- exec ---
	out="$(s 'sgh exec ci -- printenv GH_CONFIG_DIR')"
	has "exec scopes GH_CONFIG_DIR to the child" "profiles/ci/gh" "$out"
	# `VAR=x cmd` would leak when cmd is a shell builtin, so exec uses a subshell.
	is "exec leaves the shell's own profile alone" "work-acct" \
		"$(s 'sgh switch work-acct >/dev/null; sgh exec ci -- true; sgh who -q')"
	is "exec leaves GH_CONFIG_DIR alone" "same" \
		"$(s 'b="${GH_CONFIG_DIR:-none}"; sgh exec ci -- true
		     [ "$b" = "${GH_CONFIG_DIR:-none}" ] && echo same || echo changed')"
	is "exec forwards the exit code" "7" \
		"$(s 'sgh exec ci -- sh -c "exit 7"; printf "%s" "$?"')"
	out="$(s 'sgh exec ci')"
	has "exec with no command errors" "nothing to run" "$out"

	# --- delete ---
	out="$(s 'sgh delete ci --yes')"
	has "delete confirms" "Deleted profile 'ci'" "$out"
	[ -d "$SGH_HOME/profiles/ci" ] && no "delete removed the dir" || ok "delete removed the dir"
	out="$(s 'sgh delete ci --yes')"
	has "deleting a missing profile errors" "no such profile" "$out"
	out="$(s 'sgh delete fresh </dev/null')"
	has "delete without a tty refuses" "refusing to delete" "$out"
	[ -d "$SGH_HOME/profiles/fresh" ] && ok "refused delete kept the profile" ||
		no "refused delete kept the profile"

	out="$(s 'sgh nonsense')"
	has "unknown command errors" "unknown command" "$out"
	is "unknown command exits non-zero" "1" "$(s 'sgh nonsense >/dev/null 2>&1; printf "%s" "$?"')"

	is "no stray variables leak into the shell" "" \
		"$(s 'sgh list >/dev/null; printf "%s%s%s" "${name:-}" "${cmd:-}" "${f:-}"')"
}

printf '\033[1msgh test suite\033[0m\n'
for shell in ${SHELLS:-bash zsh}; do
	if command -v "$shell" >/dev/null 2>&1; then
		run_suite "$shell"
	else
		printf '\n  (skipping %s — not installed)\n' "$shell"
	fi
done

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
