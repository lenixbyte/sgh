<h1 align="center">sgh</h1>

<p align="center">
  <strong>A different GitHub account in every terminal.</strong>
</p>

<p align="center">
  <a href="https://github.com/lenixbyte/sgh/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/lenixbyte/sgh/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/lenixbyte/sgh/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/lenixbyte/sgh?color=blue"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="Shells" src="https://img.shields.io/badge/shell-bash%20%7C%20zsh%20%7C%20fish-lightgrey">
</p>

---

The GitHub CLI keeps one active account in `~/.config/gh/hosts.yml`. So when you
`gh auth switch` in one terminal, **every other terminal switches too** — your work
window quietly becomes your personal account halfway through a `gh pr create`.

`sgh` gives each account its own gh config directory and selects it with
`$GH_CONFIG_DIR`, which is per-process. Two terminals, two identities, no fighting.

```console
# terminal 1                          # terminal 2
$ sgh switch work                     $ sgh switch personal
work → octocat-work                   personal → octocat

$ gh repo create internal-thing       $ gh repo create side-project
✓ Created repository at work          ✓ Created repository personally
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/lenixbyte/sgh/main/install.sh | sh
```

Open a new terminal, then adopt the accounts you are already logged in to:

```sh
sgh import
```

Existing tokens are reused, so there is nothing to log in to again.

<details>
<summary><strong>Homebrew, manual, and other options</strong></summary>

**Homebrew**

```sh
brew install lenixbyte/tap/sgh
```

Then add the hook to your shell rc (the formula prints this too):

```sh
eval "$(sgh init zsh)"      # bash: sgh init bash · fish: sgh init fish | source
```

**Manual** — sgh is a single POSIX shell script with no dependencies beyond `gh`:

```sh
curl -fsSL https://raw.githubusercontent.com/lenixbyte/sgh/main/bin/sgh -o ~/.local/bin/sgh
chmod +x ~/.local/bin/sgh
echo 'eval "$(sgh init zsh)"' >> ~/.zshrc
```

**From source**

```sh
git clone https://github.com/lenixbyte/sgh.git && ./sgh/install.sh
```

**Uninstall**

```sh
curl -fsSL https://raw.githubusercontent.com/lenixbyte/sgh/main/install.sh | sh -s -- --uninstall
```

Your profiles in `~/.config/sgh` are kept.

</details>

**Requirements:** [`gh`](https://cli.github.com), and bash, zsh or fish.
macOS, Linux, BSD and WSL.

### Why the `init` line?

`sgh switch` has to change the environment of the shell you are typing in, and no
program can do that to its parent — not a shell script, not a Go binary. `sgh init`
prints a small wrapper function that evals what sgh tells it. Every other command works
without the hook. (This is the same mechanism `direnv`, `zoxide` and `fnm` use.)

## Usage

| Command | What it does |
| --- | --- |
| `sgh list` | Show every profile; `*` marks this terminal's |
| `sgh switch <name>` | Point **this** terminal at a profile |
| `sgh switch none` | Fall back to the plain gh config |
| `sgh who [-q]` | Show the account this terminal is using |
| `sgh add <name>` | Create a profile and log in to it |
| `sgh add <name> --link <login>` | Create a profile from an account already in your keyring |
| `sgh delete <name> [--logout]` | Remove a profile |
| `sgh default [<name>]` | Profile that new terminals start as |
| `sgh exec <name> -- <cmd>` | Run one command as that account, without switching |
| `sgh import` | Turn your existing gh logins into profiles |
| `sgh init <shell>` | Print the shell hook |

`use` is an alias for `switch`, `rm` for `delete`, `ls` for `list`.

```console
$ sgh list
  PROFILE          ACCOUNT
* work             octocat-work                  default
  personal         octocat
  client           octocat@github.acme.com

  * = active in this terminal
```

Run something as another account without switching — handy in scripts and CI:

```sh
sgh exec personal -- gh repo list
sgh exec work -- git push
```

Full guide: **[docs/usage.md](docs/usage.md)**.

## What it covers

- **`gh` commands** — everything reads the active profile's config directory.
- **`git clone` / `push` / `pull` over https** — gh installs itself as git's credential
  helper, and it inherits the same environment.
- **GitHub Enterprise** — profiles are per host: `sgh add client --host github.acme.com`
  lives happily beside github.com profiles.

**SSH remotes are not affected.** With `git@github.com:…` your SSH key decides who you
are, not gh. Use https remotes, or per-account keys in `~/.ssh/config`.

## How it works

```
~/.config/sgh/
├── default                 profile new terminals start as
└── profiles/
    ├── work/
    │   ├── gh/             ← a complete gh config dir; $GH_CONFIG_DIR points here
    │   └── env.sh          optional, sourced on switch (env.fish for fish)
    └── personal/
```

`sgh switch` exports `GH_CONFIG_DIR`. That is the whole trick — environment variables
are per-process, so each terminal gets its own answer to "who am I?" while gh's own
`hosts.yml` stays out of it.

Tokens are never copied around. They stay wherever gh put them: your OS keyring on most
setups, or inside the profile's own `hosts.yml` if gh was configured to store tokens in
files. See **[docs/how-it-works.md](docs/how-it-works.md)**.

## Alternatives

sgh is not the only way to do this, and it is not always the right one:

| If you want | Use |
| --- | --- |
| One account at a time, switched occasionally | [`gh auth switch`](https://cli.github.com/manual/gh_auth_switch) — built in, no extra tool |
| The account chosen by **which directory** you are in | [direnv with `GH_CONFIG_DIR`](https://knpw.rs/blg/multiple-gh-users/) |
| The account chosen by **which terminal** you are in | **sgh** |
| A gh extension that manages config dirs | [`gh-multi-account`](https://github.com/matthew-cline/gh-multi-account) |

**Why isn't this a gh extension?** Extensions run as subprocesses, so they cannot change
your shell's environment — `switch` would be impossible. More in
**[docs/faq.md](docs/faq.md)**.

## Contributing

Issues and pull requests are welcome — see **[CONTRIBUTING.md](CONTRIBUTING.md)**. The
test suite runs against a throwaway config with a stub `gh`, so it never touches your
real accounts:

```sh
SHELLS="bash zsh dash fish" tests/test.sh
```

## License

[MIT](LICENSE)
