# How it works

## The problem

`gh` stores its state in `~/.config/gh/hosts.yml`, which has exactly one active account
per host:

```yaml
github.com:
    git_protocol: https
    users:
        octocat-work:
        octocat:
    user: octocat-work     # ← the active account. One value, one file.
```

`gh auth switch` rewrites that `user:` line. Every terminal reads the same file, so there
is nothing per-terminal about it — and no `--account` flag to opt out.

## The trick

`gh` honours `$GH_CONFIG_DIR`, which moves its entire configuration directory. Environment
variables are per-process and inherited by children, so a value set in one terminal is
invisible to another.

sgh gives each account its own config directory and switches between them:

```
~/.config/sgh/
├── default                 profile new terminals start as
└── profiles/
    ├── work/
    │   ├── gh/             ← $GH_CONFIG_DIR points here
    │   │   ├── hosts.yml   one account, marked active
    │   │   └── config.yml  seeded from your existing gh settings
    │   └── env.sh          optional, sourced on switch
    └── personal/
```

`sgh switch work` is, at bottom, `export GH_CONFIG_DIR=~/.config/sgh/profiles/work/gh`.

## Why a shell hook is required

No process can change its parent's environment. Not a shell script, not a compiled
binary — the kernel copies the environment on `fork` and there is no way back. A CLI that
claims to set a variable for you is always doing one of two things:

1. Starting a new shell for you (`sgh exec` does this).
2. Printing shell code for your shell to evaluate (`sgh init` does this).

So `sgh init zsh` prints a function:

```sh
sgh() {
	case "${1:-}" in
	switch | use | sw)
		__sgh_code="$(command sgh __shellcode sh "$@")"
		__sgh_rc=$?
		if [ "$__sgh_rc" -eq 0 ]; then
			eval "$__sgh_code"
			command sgh who
		fi
		unset __sgh_code
		return $__sgh_rc
		;;
	*) command sgh "$@" ;;
	esac
}
```

`sgh __shellcode sh switch work` prints the exports, the function evaluates them, and the
variable lands in the terminal you are typing in. Every other command skips the function
entirely and runs as a normal subprocess.

This is the same mechanism behind `direnv hook`, `zoxide init`, `fnm env` and
`starship init`. It is not a workaround; it is the only thing that works.

## Why git works too

`gh auth setup-git` configures gh as git's credential helper:

```
credential.https://github.com.helper = !gh auth git-credential
```

When git needs a credential it runs that helper as a child process, which inherits
`$GH_CONFIG_DIR` from your terminal. So `git clone`, `git push` and `git pull` over https
follow whatever profile the terminal is on, with no extra configuration.

**SSH is different.** With a `git@github.com:…` remote, git never asks gh for anything —
your SSH key is the identity. sgh has no influence there. Use https remotes, or configure
per-account keys in `~/.ssh/config`.

## Where tokens live

sgh never reads, writes, or copies a token. gh owns them, and puts them in one of two
places:

- **Your OS keyring** (the default) — keyed by host and login. A new profile that names
  an account you have already authenticated simply finds the existing entry, which is why
  `sgh import` and `sgh add --link` need no new login.
- **`hosts.yml` itself**, when gh is configured to store tokens in files. In that case
  `import` and `--link` copy the `oauth_token` line into the new profile, because
  otherwise it would be logged out.

`sgh delete` leaves credentials alone unless you pass `--logout`, since two profiles may
point at the same account.
