# Security Policy

## Reporting a vulnerability

Please report security issues privately through
[GitHub Security Advisories](https://github.com/lenixbyte/sgh/security/advisories/new)
rather than opening a public issue. You should get a first response within a week.

## Threat model

Worth knowing when assessing risk:

- **sgh never handles your tokens.** It points `gh` at a config directory via
  `$GH_CONFIG_DIR` and gets out of the way. Tokens live wherever gh puts them — your OS
  keyring on most setups, or a profile's own `hosts.yml` when gh is configured to store
  them in files.
- **Profiles are private by default.** Profile directories are created `0700` and any
  `hosts.yml` sgh writes is `0600`.
- **`sgh delete` does not revoke credentials** unless you pass `--logout`. Two profiles
  can point at the same account, so revoking by default would break the other one.
- **`sgh init` output is evaluated by your shell.** Paths embedded in it are quoted with
  `shquote`/`fishquote`, and there is a test asserting a path containing spaces survives.
- **Profile names are restricted** to `[A-Za-z0-9._-]`, which is what stops a name from
  escaping the profiles directory.
- **A profile's `env.sh` is sourced on switch.** It is your file; treat it like any other
  shell startup file and do not paste one in from somewhere you do not trust.

## Supported versions

The latest release is supported. sgh is pre-1.0, so fixes land on `main` and in the next
release rather than in patch branches.
