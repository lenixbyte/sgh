#!/bin/sh
# shellcheck disable=SC2016  # the rc lines we write are literal shell, not expansions
# sgh installer.
#
#   curl -fsSL https://raw.githubusercontent.com/lenixbyte/sgh/main/install.sh | sh
#   ./install.sh                 from a checkout
#   ./install.sh --uninstall     remove it again (profiles are kept)
#
# Environment:
#   SGH_INSTALL_DIR   where the executable goes  (default: ~/.local/bin)
#   SGH_VERSION       pin a release, e.g. v0.1.0 (default: latest)
#   SGH_REPO          owner/name                 (default: lenixbyte/sgh)

set -eu

REPO="${SGH_REPO:-lenixbyte/sgh}"
DEST="${SGH_INSTALL_DIR:-$HOME/.local/bin}"
BEGIN="# >>> sgh >>>"
END="# <<< sgh <<<"

say() { printf '%s\n' "$*"; }
die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

fetch() { # fetch <url> <output>
	if have curl; then
		curl -fsSL "$1" -o "$2"
	elif have wget; then
		wget -qO "$2" "$1"
	else
		die "need curl or wget"
	fi
}

fetch_stdout() {
	if have curl; then
		curl -fsSL "$1"
	elif have wget; then
		wget -qO- "$1"
	else
		die "need curl or wget"
	fi
}

sha256_of() {
	if have sha256sum; then
		sha256sum "$1" | cut -d' ' -f1
	elif have shasum; then
		shasum -a 256 "$1" | cut -d' ' -f1
	else
		printf ''
	fi
}

# ── shell wiring ──────────────────────────────────────────────────────

# rc files worth touching, based on which shells are actually set up.
rc_files() {
	if [ "${SHELL##*/}" = zsh ] || [ -f "$HOME/.zshrc" ]; then
		printf '%s\n' "$HOME/.zshrc"
	fi
	if [ -f "$HOME/.bashrc" ]; then
		printf '%s\n' "$HOME/.bashrc"
	elif [ -f "$HOME/.bash_profile" ]; then
		printf '%s\n' "$HOME/.bash_profile"
	fi
	[ -f "$HOME/.config/fish/config.fish" ] && printf '%s\n' "$HOME/.config/fish/config.fish"
}

hook_for() { # the right hook line for a given rc file
	case "$1" in
	*fish*) printf 'sgh init fish | source\n' ;;
	*zshrc*) printf 'eval "$(sgh init zsh)"\n' ;;
	*) printf 'eval "$(sgh init bash)"\n' ;;
	esac
}

path_for() { # $1 = rc file, $2 = dir — fish is a different language, not just syntax sugar
	case "$1" in
	*fish*)
		printf 'if not contains -- %s $PATH\n' "$2"
		printf '    set -gx PATH %s $PATH\n' "$2"
		printf 'end\n'
		;;
	*)
		printf 'case ":$PATH:" in *":%s:"*) ;; *) PATH="%s:$PATH" ;; esac\n' "$2" "$2"
		;;
	esac
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
	if [ -f "$DEST/sgh" ]; then
		rm -f "$DEST/sgh"
		say "Removed $DEST/sgh"
	fi
	say ""
	say "Your profiles are untouched in ${XDG_CONFIG_HOME:-$HOME/.config}/sgh."
	say "Delete that directory too if you want them gone."
	exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

# ── install the executable ────────────────────────────────────────────

mkdir -p "$DEST"
here="$(dirname "$0" 2>/dev/null || echo .)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/sgh-install.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# $0 is not a real file when this is piped from curl, and $here would then be the
# caller's cwd — which must not be mistaken for a checkout.
if [ -f "$0" ] && [ -f "$here/bin/sgh" ]; then
	cp "$here/bin/sgh" "$tmp/sgh"
	say "Installing from this checkout"
else
	version="${SGH_VERSION:-}"
	if [ -z "$version" ]; then
		version="$(fetch_stdout "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null |
			sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)" || true
	fi

	if [ -n "$version" ]; then
		base="https://github.com/$REPO/releases/download/$version"
		say "Downloading sgh $version"
		if fetch "$base/sgh-${version#v}.tar.gz" "$tmp/sgh.tar.gz" 2>/dev/null &&
			fetch "$base/sha256sums.txt" "$tmp/sums.txt" 2>/dev/null; then
			want="$(grep "sgh-${version#v}.tar.gz" "$tmp/sums.txt" | cut -d' ' -f1)"
			got="$(sha256_of "$tmp/sgh.tar.gz")"
			if [ -z "$got" ]; then
				say "warning: no sha256 tool found, skipping checksum verification"
			elif [ "$want" != "$got" ]; then
				die "checksum mismatch — refusing to install (expected $want, got $got)"
			fi
			tar -xzf "$tmp/sgh.tar.gz" -C "$tmp"
			cp "$(find "$tmp" -type f -name sgh -path '*bin*' | head -n 1)" "$tmp/sgh.new"
			mv "$tmp/sgh.new" "$tmp/sgh"
		else
			version=''
		fi
	fi

	# No release yet (or the assets are missing): fall back to the branch tip.
	if [ ! -f "$tmp/sgh" ]; then
		say "No release found — installing from the main branch (unverified)"
		fetch "https://raw.githubusercontent.com/$REPO/main/bin/sgh" "$tmp/sgh" ||
			die "download failed"
	fi
fi

chmod +x "$tmp/sgh"
# Sanity check before this lands anywhere or gets wired into a shell startup.
sh "$tmp/sgh" version >/dev/null 2>&1 || die "the downloaded sgh does not run — nothing was installed"

mv "$tmp/sgh" "$DEST/sgh"
say "Installed $DEST/sgh"

# ── wire up the shells ────────────────────────────────────────────────

added=''
for rc in $(rc_files); do
	strip_block "$rc" # replace an older install rather than stacking blocks
	mkdir -p "$(dirname "$rc")"
	touch "$rc"
	# shellcheck disable=SC2094  # path_for/hook_for only format strings, they read nothing
	{
		printf '%s\n' "$BEGIN"
		printf '# a different GitHub account in every terminal — https://github.com/%s\n' "$REPO"
		# Any install dir that is not already on PATH, not just ~/.local/bin.
		case ":$PATH:" in
		*":$DEST:"*) ;;
		*) path_for "$rc" "$DEST" ;;
		esac
		hook_for "$rc"
		printf '%s\n' "$END"
	} >>"$rc"
	say "Wired into ${rc#"$HOME"/}"
	added="yes"
done

if [ -z "$added" ]; then
	say ""
	say "No shell rc found. Add one of these to yours:"
	say '  bash/zsh   eval "$(sgh init zsh)"'
	say "  fish       sgh init fish | source"
fi

say ""
say "Done. Start a new terminal, then:"
say ""
if have gh; then
	say "  sgh import        turn your existing gh logins into profiles"
	say "  sgh add work      or log in to an account from scratch"
else
	say "  install the GitHub CLI first: https://cli.github.com"
	say "  then run: sgh add work"
fi
say "  sgh switch work   point this terminal at an account"
say "  sgh help          everything else"
