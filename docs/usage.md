# Usage guide

Everything sgh does, in the order you are likely to need it. For the short version, run
`sgh help`.

## First run

If you already use `gh` with one or more accounts, adopt them:

```console
$ sgh import
  import  octocat-work          → profile 'octocat-work'
  import  octocat               → profile 'octocat'

Imported 2 profile(s). Existing tokens were reused, so no new
login is needed unless gh reports one as expired.
```

Profile names come from the GitHub login. If you would rather have short names, create
them yourself from the same accounts — no new login required:

```sh
sgh add work --link octocat-work
sgh add personal --link octocat
```

To log in to an account that is not on this machine yet:

```sh
sgh add personal            # runs gh auth login inside the new profile
```

## Switching

```sh
sgh switch work             # this terminal, right now
sgh switch none             # back to the plain gh config
sgh who                     # which account am I?
sgh who -q                  # just the profile name, for scripts and prompts
```

Switching affects **only the terminal you ran it in**. That is the point. Other
terminals, and any that are already open, keep whatever they had.

A switch survives subshells, tmux panes, and `exec zsh`, because it is inherited like any
other environment variable.

### Without switching

```sh
sgh exec personal -- gh repo list
sgh exec work -- git push
sgh exec ci -- gh release create v1.0.0
```

`exec` is the right tool in scripts, CI, `Makefile`s, and cron — anywhere there is no
interactive shell to switch.

## What new terminals start as

```sh
sgh default work            # new terminals begin here
sgh default                 # show it
sgh default --clear         # new terminals use the plain gh config again
```

An inherited profile always beats the default, so a switched terminal stays switched when
it spawns a subshell.

## Removing a profile

```sh
sgh delete old-client              # asks first
sgh delete old-client --yes        # does not
sgh delete old-client --logout     # also revokes the credential via gh
```

Without `--logout`, credentials are left alone: two profiles can point at the same
account, and revoking would break the other one.

## GitHub Enterprise

Profiles are per host, so enterprise accounts sit alongside github.com ones:

```sh
sgh add client --host github.acme.com
```

`sgh list` shows the host when it is not github.com:

```console
$ sgh list
  PROFILE          ACCOUNT
* work             octocat-work                  default
  client           admin@github.acme.com
```

## A git identity per profile

Anything in `~/.config/sgh/profiles/<name>/env.sh` is sourced when you switch to it:

```sh
# ~/.config/sgh/profiles/personal/env.sh
export GIT_AUTHOR_EMAIL=you@personal.dev
export GIT_COMMITTER_EMAIL=you@personal.dev
export GIT_AUTHOR_NAME=octocat
export GIT_COMMITTER_NAME=octocat
```

fish cannot source POSIX syntax, so fish users write `env.fish` instead:

```fish
# ~/.config/sgh/profiles/personal/env.fish
set -gx GIT_AUTHOR_EMAIL you@personal.dev
set -gx GIT_COMMITTER_EMAIL you@personal.dev
```

> **Define the same variables in every profile.** Switching to a profile that does not
> mention a variable does not unset what the previous one set — the shell has no idea
> those two things are related.

## Showing the profile in your prompt

```sh
# zsh
RPROMPT='$(sgh who -q)'

# bash
PS1="$PS1\$(sgh who -q) "
```

```fish
# fish — ~/.config/fish/functions/fish_right_prompt.fish
function fish_right_prompt
    sgh who -q
end
```

## Environment variables

| Variable | Meaning |
| --- | --- |
| `SGH_HOME` | Where profiles live. Default `~/.config/sgh` (respects `XDG_CONFIG_HOME`). |
| `SGH_PROFILE` | The active profile. Set by `switch`; read by everything else. |
| `GH_CONFIG_DIR` | What gh actually reads. Set by `switch`; gh's own variable. |
| `NO_COLOR` | Set to disable colour output. |

## Shell hook reference

```sh
eval "$(sgh init bash)"     # bash
eval "$(sgh init zsh)"      # zsh
sgh init fish | source      # fish
```

The hook defines a `sgh` function that intercepts `switch` and passes everything else
through to the executable. It also registers completions, and applies your default
profile when the shell starts.

For a package manager installing completion files instead:

```sh
sgh completions zsh > /usr/local/share/zsh/site-functions/_sgh
sgh completions bash > /etc/bash_completion.d/sgh
sgh completions fish > ~/.config/fish/completions/sgh.fish
```
