# CLIProxyAPI Local Manager Design

## Goal

Build a small GitHub-ready project that installs and maintains CLIProxyAPI for personal local use on Windows and macOS. The manager should keep CLIProxyAPI bound to loopback, help with Codex OAuth, and expose the OpenAI-compatible URL needed by WorkBuddy.

## Scope

- Windows manager implemented in PowerShell plus `.cmd` launchers.
- macOS manager implemented in Bash compatible with the system Bash 3.2.
- User-selectable install directory.
- Install/update latest CLIProxyAPI release from `router-for-me/CLIProxyAPI`.
- Back up old binaries and configs before replacement.
- Generate local-only `config.yaml`.
- Use an install-local `./auth` directory and non-rotating routing defaults.
- Generate service launch scripts inside the selected install directory.
- Start service, run health check, open WebUI, run Codex login commands, query `/v1/models`, and print WorkBuddy settings.

## Non-Goals

- No Docker deployment.
- No VPS or cloud deployment.
- No public network exposure.
- No Windows service or launch daemon setup.
- No multi-account rotation.
- No storage of API keys, Management Keys, OAuth tokens, or auth files in the project state.
- No reuse of a shared global OAuth auth directory by default.

## State

Each platform writes a small ignored state file in the project root:

- `.cliproxyapi-manager-state.windows.json`
- `.cliproxyapi-manager-state.macos.json`

The state stores only:

- selected install directory
- latest installed release tag
- update timestamp

## Platform Notes

Windows uses `Invoke-RestMethod`, `Invoke-WebRequest`, and `Expand-Archive`.

macOS uses `curl`, `unzip`, `tar`, `sed`, `awk`, `find`, and `open`. It does not require `jq` and avoids Bash 4+ syntax.
