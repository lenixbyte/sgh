#!/bin/sh
# sgh installer.
#
#   curl -fsSL https://raw.githubusercontent.com/lenixbyte/sgh/main/install.sh | sh
#   ./install.sh                 from a checkout
#   ./install.sh --uninstall     remove it again (profiles are kept)
#
# Installs one shell file and adds a `source` line to your shell rc. sgh has to
# be sourced rather than run, because only a shell function can change the
# environment of the terminal you are typing in.

set -eu

REPO="${SGH_REPO:-lenixbyte/sgh}"
BRANCH="${SGH_BRANCH:-main}"
DEST="${SGH_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/sgh}"
BEGIN="# >>> sgh >>>"
END="# <<< sgh <<<"

say() { printf '%s\n' "$*"; }
die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

# Every rc file we should touch, based on which shells are actually set up.
rc_files() {
	case "${SHELL:-}" in
	*/zsh) [ -f "$HOME/.zshrc" ] && printf '%s\n' "$HOME/.zshrc" ;;
	esac
	# zsh users who have not created .zshrc yet still want one.
	if [ "${SHELL##*/}" = zsh ] && [ ! -f "$HOME/.zshrc" ]; then
		printf '%s\n' "$HOME/.zshrc"
	fi
	if [ -f "$HOME/.bashrc" ]; then
		printf '%s\n' "$HOME/.bashrc"
	elif [ -f "$HOME/.bash_profile" ]; then
		printf '%s\n' "$HOME/.bash_profile"
	fi
}

strip_block() { # remove any previous sgh block from $1
	[ -f "$1" ] || return 0
	grep -q "^$BEGIN$" "$1" 2>/dev/null || return 0
	awk -v b="$BEGIN" -v e="$END" '
		$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }
	' "$1" >"$1.sgh-tmp" && mv "$1.sgh-tmp" "$1"
}

uninstall() {
	for rc in $(rc_files); do
		if [ -f "$rc" ] && grep -q "^$BEGIN$" "$rc"; then
			strip_block "$rc"
			say "Removed the sgh block from ${rc#"$HOME"/}"
		fi
	done
	[ -d "$DEST" ] && rm -rf "$DEST" && say "Removed $DEST"
	say ""
	say "Your profiles are untouched in ${XDG_CONFIG_HOME:-$HOME/.config}/sgh."
	say "Delete that directory too if you want them gone."
	exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

# ── install the file ──────────────────────────────────────────────────

mkdir -p "$DEST"
here="$(dirname "$0" 2>/dev/null || echo .)"

if [ -f "$here/sgh.sh" ]; then
	cp "$here/sgh.sh" "$DEST/sgh.sh"
	say "Installed from this checkout → $DEST/sgh.sh"
else
	url="https://raw.githubusercontent.com/$REPO/$BRANCH/sgh.sh"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$DEST/sgh.sh" || die "download failed: $url"
	elif command -v wget >/dev/null 2>&1; then
		wget -qO "$DEST/sgh.sh" "$url" || die "download failed: $url"
	else
		die "need curl or wget"
	fi
	say "Downloaded sgh → $DEST/sgh.sh"
fi

# Sanity check before we wire it into anyone's shell startup.
sh -c ". '$DEST/sgh.sh'; sgh version" >/dev/null 2>&1 ||
	die "the downloaded sgh.sh does not load cleanly — nothing was added to your shell rc"

# ── wire it into the shell ────────────────────────────────────────────

added=''
for rc in $(rc_files); do
	strip_block "$rc" # replace an older install rather than stacking blocks
	touch "$rc"
	{
		printf '%s\n' "$BEGIN"
		printf '# a different GitHub account in every terminal — https://github.com/%s\n' "$REPO"
		printf '[ -f "%s/sgh.sh" ] && . "%s/sgh.sh"\n' "$DEST" "$DEST"
		printf '%s\n' "$END"
	} >>"$rc"
	say "Wired into ${rc#"$HOME"/}"
	added="yes"
done

[ -n "$added" ] || say "No shell rc found — add this line to yours: . $DEST/sgh.sh"

say ""
say "Done. Start a new terminal (or run: . $DEST/sgh.sh), then:"
say ""
if command -v gh >/dev/null 2>&1; then
	say "  sgh import        turn your existing gh logins into profiles"
	say "  sgh add work      or log in to an account from scratch"
else
	say "  install the GitHub CLI first: https://cli.github.com"
	say "  then run: sgh add work"
fi
say "  sgh switch work   point this terminal at an account"
say "  sgh help          everything else"
