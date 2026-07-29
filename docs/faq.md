# FAQ

### Why isn't this a `gh` extension?

Extensions run as subprocesses of `gh`, so they cannot change your shell's environment —
`sgh switch` would be impossible. An extension could copy config files around to fake it,
but that is exactly the global mutable state that causes the problem in the first place.

### Does sgh store my GitHub tokens?

No. It never reads or writes a token. gh keeps them in your OS keyring (or in its own
`hosts.yml` if you configured file storage), and sgh only points gh at a directory. See
[how-it-works.md](how-it-works.md#where-tokens-live).

### Do I have to log in again for every profile?

No. `sgh import` and `sgh add --link` reuse credentials that are already in your keyring.
You only log in for accounts this machine has never seen.

### Does it work with GitHub Enterprise?

Yes. Profiles are per host: `sgh add client --host github.acme.com`. Enterprise and
github.com profiles coexist, and `sgh list` shows the host when it is not github.com.

### Does it work with SSH remotes?

No, and nothing else could either. With `git@github.com:…` your SSH key is the identity
and gh is never consulted. Use https remotes, or per-account keys in `~/.ssh/config`.

### Can I have the profile follow the directory instead of the terminal?

That is what [direnv](https://direnv.net/) is for — put
`export GH_CONFIG_DIR=~/.config/sgh/profiles/work/gh` in an `.envrc`. The two compose
fine. Per-directory switching may land in sgh itself later.

### What happens to my existing `~/.config/gh`?

Nothing. sgh never modifies it — `import` only reads it. `sgh switch none` returns a
terminal to using it directly.

### Is `gh auth switch` still safe to use?

It still works, and it still changes every terminal at once. Once you are using profiles,
prefer `sgh switch` (this terminal) or `sgh exec` (one command).

### Why does `sgh` need bash, zsh or fish? I use ksh.

The executable itself runs under any POSIX shell, so every command except `switch` works
anywhere. Only the generated hook is shell-specific, and `sgh init ksh` emits the POSIX
version, which should work — it is just not covered by CI.

### Does this work on Windows?

Under WSL, yes. Native PowerShell is not supported: the hook would need a PowerShell
variant. A PR would be welcome.

### How do I uninstall it?

```sh
curl -fsSL https://raw.githubusercontent.com/lenixbyte/sgh/main/install.sh | sh -s -- --uninstall
```

That removes the executable and the shell rc block. Your profiles stay in
`~/.config/sgh` until you delete that directory.
