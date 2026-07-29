# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-29

First release.

### Added

- Per-terminal GitHub accounts: each profile is its own gh config directory, selected
  through `$GH_CONFIG_DIR`, so two terminals can hold two identities at once.
- `list`, `switch`, `who`, `add`, `delete`, `default`, `exec`, `import`, `path`.
- `sgh init <bash|zsh|fish>` shell hook, plus completions for all three shells.
- `sgh import` adopts accounts you are already logged in to, reusing existing tokens.
- `sgh add --link <login>` builds a profile from a keyring account without a new login.
- `sgh exec <profile> -- <cmd>` runs a single command as another account.
- Optional per-profile `env.sh` (`env.fish` for fish), sourced on switch — commonly used
  for a per-account git identity.
- Installer with checksum-verified releases, and `--uninstall`.

[Unreleased]: https://github.com/lenixbyte/sgh/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lenixbyte/sgh/releases/tag/v0.1.0
