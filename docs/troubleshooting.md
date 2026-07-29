# Troubleshooting

## `sgh: switch needs the shell hook`

`switch` is the one command that has to change your shell's environment, which requires
the hook. Add it to your shell rc and open a new terminal:

```sh
eval "$(sgh init zsh)"      # bash: sgh init bash · fish: sgh init fish | source
```

To run a single command as another account without the hook:

```sh
sgh exec personal -- gh repo list
```

## `sgh: command not found` after installing

The executable went somewhere that is not on your `PATH` — usually `~/.local/bin`. Check:

```sh
ls ~/.local/bin/sgh
echo "$PATH" | tr ':' '\n' | grep -c '.local/bin'
```

The installer adds the directory to `PATH` in your rc. If you installed manually, add it
yourself, or move the file somewhere already on `PATH`.

## `gh` says my token is invalid after switching

The profile points at an account whose credential has expired. Log in again in that
profile only:

```sh
sgh switch personal
gh auth login
```

Other profiles are unaffected.

## The wrong account is used for `git push`

Check three things, in order:

```sh
sgh who                                   # 1. is this terminal on the profile you think?
git remote -v                             # 2. https, or ssh?
git config --get-regexp 'credential.*helper'   # 3. is gh the credential helper?
```

If the remote is `git@github.com:…`, sgh is not involved at all — SSH keys decide the
identity. Switch the remote to https, or set up per-account keys in `~/.ssh/config`.

If the credential helper is missing, run `gh auth setup-git` in the profile.

## A new terminal is on the wrong profile

New terminals start on `sgh default` unless they inherited a profile from their parent:

```sh
sgh default              # what is set
sgh default work         # change it
sgh default --clear      # start on the plain gh config instead
```

Note that a terminal inherits from whatever spawned it — a tmux pane started from a
switched terminal keeps that terminal's profile, which is usually what you want.

## `sgh list` is slow

It should not be — it reads `hosts.yml` directly rather than calling `gh auth status`,
which makes a network request per account. If it is slow, something in your shell is
shadowing `sgh` with a function that does more work. Check with `command -v sgh` and
`type sgh`.

## Colour codes are showing up as text

Your terminal or pager is not interpreting ANSI escapes. Disable colour:

```sh
NO_COLOR=1 sgh list
```

## Something else

Open an issue with your shell, OS, `gh --version`, `sgh version`, and the exact command:
https://github.com/lenixbyte/sgh/issues
