# Contributing to sgh

Thanks for taking an interest. Bug reports, questions and pull requests are all welcome.

## Getting set up

sgh has no build step. Clone it and run it:

```sh
git clone https://github.com/lenixbyte/sgh.git
cd sgh
./bin/sgh version
```

To try your working copy in a real shell without touching your installed one:

```sh
SGH_HOME=/tmp/sgh-scratch eval "$(./bin/sgh init zsh)"
```

You will want [`shellcheck`](https://www.shellcheck.net/) and
[`shfmt`](https://github.com/mvdan/sh) locally; CI runs both.

## Before opening a pull request

```sh
shellcheck bin/sgh install.sh tests/test.sh
shfmt -d bin/sgh install.sh tests/test.sh
SHELLS="bash zsh dash fish" tests/test.sh
```

The suite runs against a throwaway `$SGH_HOME` with a stub `gh` on `PATH`, so it never
touches real accounts, your keyring, or the network. **New behaviour needs a test.**
Several real bugs were caught only because the suite runs under every shell — it is not
ceremony.

## Shell constraints that are easy to break

This is the part worth reading before you change `bin/sgh`.

- **`switch` cannot be a plain subprocess.** No program can change the environment of the
  shell that invoked it. `switch` prints shell code (`sgh __shellcode`) which the wrapper
  function from `sgh init` evaluates. Anything that needs to affect the calling shell has
  to go through that path.
- **A shell parses a whole `if` before choosing a branch.** bash-only syntax
  (`COMPREPLY=(...)`) or zsh-only syntax (`${(f)...}`) breaks *other* shells even inside
  a branch they would never run. Keep shell-specific code inside `eval '...'` or inside a
  quoted heredoc that is only ever printed.
- **`bin/sgh` must run under `/bin/sh`.** That means dash on Debian and Ubuntu. No arrays,
  no `[[ ]]`, no `${var/pattern/replacement}`. `local` is fine — every shell we target
  supports it.
- **No globs over the profiles directory.** zsh's `nomatch` turns an unmatched glob into
  an error rather than an empty list. Use `find`.
- **Anything printed for `eval` must be quoted.** Paths come from `$HOME` and can contain
  spaces or quotes; use `shquote` / `fishquote`. There is a test for this.
- **fish is a different language, not a dialect.** Its syntax appears only in the fish
  branches of `init` and `completions`, never in `bin/sgh` itself.
- **Tokens are never copied between profiles.** gh owns them — in the OS keyring, or in a
  profile's own `hosts.yml` when gh is configured to store them in files. sgh only ever
  points gh at a directory.

## Style

- Tabs for indentation; `shfmt` settles the rest.
- Comments explain *why*, not what. If a line looks odd, say what would break without it.
- Internal helpers are lowercase; anything that ends up in a user's shell is prefixed
  `__sgh_` or `_sgh_` so it does not collide with their names.

## Commit messages

A one-line summary in the imperative mood, then a blank line, then the reasoning: what
was wrong, and why this fixes it. Explain the trap for anything subtle — the shell has a
lot of them.

## Reporting bugs

Open an issue with your shell, OS and `gh --version`, plus the output of `sgh version`
and the exact command you ran. For anything security-related, please follow
[SECURITY.md](SECURITY.md) instead of opening a public issue.
