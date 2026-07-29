# sgh

**A different GitHub account in every terminal.**

The GitHub CLI keeps one active account in `~/.config/gh/hosts.yml`. So when you
`gh auth switch` in one terminal, every other terminal switches too — your work
window quietly becomes your personal account halfway through a `gh pr create`.

`sgh` gives each account its own gh config directory and selects it with
`$GH_CONFIG_DIR`, which is per-shell. Two terminals, two identities, no fighting.

```console
$ sgh switch work            # terminal 1
work → octocat-work

$ sgh switch personal        # terminal 2 — terminal 1 is untouched
personal → octocat
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/lenixbyte/sgh/main/install.sh | sh
```

Then open a new terminal and turn your existing logins into profiles:

```sh
sgh import
```

Your tokens are reused, so there is nothing to log in to again.

<details>
<summary>Other ways to install</summary>

**From a checkout**

```sh
git clone https://github.com/lenixbyte/sgh.git && ./sgh/install.sh
```

**By hand** — sgh is one file. Put it anywhere and source it from your shell rc:

```sh
echo '. /path/to/sgh.sh' >> ~/.zshrc     # or ~/.bashrc
```

**Uninstall**

```sh
./install.sh --uninstall     # or just delete the block from your rc
```

Profiles in `~/.config/sgh` are kept.

</details>

Requires [`gh`](https://cli.github.com) and bash or zsh. macOS, Linux and WSL.

## Use

```
sgh list                       Show every profile; * marks this terminal's
sgh switch <name>              Point THIS terminal at a profile
sgh switch none                Fall back to the plain gh config
sgh who [-q]                   Show the account this terminal is using
sgh add <name>                 Create a profile and log in to it
sgh add <name> --link <login>  Create a profile from an account already in
                               your keyring — no new login
sgh delete <name> [--logout]   Remove a profile
sgh default [<name>|--clear]   Profile that new terminals start as
sgh exec <name> -- <cmd>       Run one command as that account, no switching
sgh import                     Turn your existing gh logins into profiles
sgh path                       Print the gh config dir this terminal uses
```

`use` works as an alias for `switch`, `rm` for `delete`, `ls` for `list`.

```console
$ sgh list
  PROFILE          ACCOUNT
* work             octocat-work                  default
  personal         octocat
  client           octocat@github.acme.com

  * = active in this terminal
```

Run something as another account without switching:

```sh
sgh exec personal -- gh repo list
sgh exec work -- git push
```

## What it covers

- **`gh` commands** — everything reads the profile's config dir.
- **`git clone` / `push` / `pull` over https** — gh installs itself as git's
  credential helper, and it inherits the same environment.
- **GitHub Enterprise** — profiles are per host, so `sgh add client --host
  github.acme.com` works alongside github.com ones.

**SSH remotes are not affected.** With `git@github.com:…` your SSH key decides
who you are, not gh. Use https remotes, or set up per-account keys in
`~/.ssh/config`.

## Nice to have

**Show the profile in your prompt** so you always know which account a terminal
is holding:

```sh
# zsh
RPROMPT='$(sgh who -q)'

# bash
PS1="$PS1\$(sgh who -q) "
```

**A git identity per profile.** Anything in
`~/.config/sgh/profiles/<name>/env.sh` is sourced when you switch:

```sh
export GIT_AUTHOR_EMAIL=you@personal.dev
export GIT_COMMITTER_EMAIL=you@personal.dev
```

Define the same variables in every profile — a variable set by one profile is
not unset by switching to a profile that does not mention it.

**`sgh switch` with no arguments** opens an [fzf](https://github.com/junegunn/fzf)
picker, if you have fzf.

## How it works

```
~/.config/sgh/
├── default                 profile new terminals start as
└── profiles/
    ├── work/
    │   ├── gh/             ← a complete gh config dir; $GH_CONFIG_DIR points here
    │   └── env.sh          optional, sourced on switch
    └── personal/
```

`sgh switch` exports `GH_CONFIG_DIR`. That is the whole trick — environment
variables are per-process, so each terminal gets its own answer to "who am I?"
while gh's own `hosts.yml` stays out of it.

Tokens are not copied around. They stay wherever gh put them: your OS keyring on
most setups, or inside the profile's own `hosts.yml` if gh was storing tokens in
files. `sgh delete` leaves credentials alone unless you pass `--logout`, because
two profiles can point at the same account.

`sgh` must be **sourced, not executed** — a child process cannot change the
environment of the shell you are typing in. That is why it is a shell function
and not a binary, and it is the same reason `nvm` and `sphp` work this way.

## Development

```sh
tests/test.sh                       # runs the suite under bash and zsh
SHELLS="bash zsh dash" tests/test.sh
shellcheck sgh.sh install.sh
```

The suite runs against a throwaway `$SGH_HOME` with a stub `gh`, so it never
touches your real accounts, keyring, or the network.

## License

MIT
