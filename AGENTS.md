# Repository Instructions

This repository maintains local-only helper scripts for running CLIProxyAPI on a user's own machine.

## Safety Rules

- Never commit local install directories, `config.yaml`, `webui-management-key.txt`, `auth/`, OAuth tokens, API keys, management keys, logs, downloads, or generated runtime state.
- Keep generated CLIProxyAPI configuration local-only: bind to `127.0.0.1`, keep remote management disabled, and do not add tunnel, public-domain, VPS, cloud-host, or multi-user assumptions.
- State files belong in the CLIProxyAPI install directory, not in the repository root.
- Do not change menu behavior, output format, or lifecycle semantics without updating Windows, macOS, README, and tests together.

## Client Config / WorkBuddy Adapter

- Treat live CLIProxyAPI `/v1/models` output as the primary source for model IDs.
- Treat the validated CLIProxyAPI `models.json` in the install directory as the capability source. The repository snapshot is `data/cliproxyapi-models.json`.
- Do not guess capabilities from model names when the official catalog is missing the field.
- `supportsImages` means image input or vision for a chat model. It does not mean image generation.
- Image-generation or image-editing models such as `gpt-image-*` and `dall-e*` must not be emitted as `/v1/chat/completions` chat models.
- Do not emit `availableModels` unless the user explicitly asks to restrict the WorkBuddy / CodeBuddy model dropdown.
- `maxInputTokens` and `maxOutputTokens` should remain opt-in output fields.
- `vendor` is user-configurable and defaults to `CLIProxyAPI`.
- Keep `workbuddy-json` as a deprecated compatibility alias for one version; new behavior belongs under `client-config --format workbuddy`.

## Model Catalog Maintenance

- Refresh `data/cliproxyapi-models.json` only from `router-for-me/models` using the same URLs as CLIProxyAPI.
- Validate every downloaded catalog before atomically replacing `<install-dir>/models.json`; invalid sources must not destroy the previous valid file.
- Catalog state belongs in the CLIProxyAPI install directory. Never write refreshed runtime state back into the repository.
- Keep Windows and macOS normalization rules identical, including alias conflicts, duplicate-ID conflicts, reasoning validation, and non-chat safety matching.
- If CodeBuddy / WorkBuddy documentation does not document a reasoning effort value such as `none`, do not put that value in `reasoning.supportedEfforts`.

## Validation

Run the relevant static tests after script or documentation changes:

```powershell
$ErrorActionPreference='Stop'; Get-ChildItem -LiteralPath 'tests' -Filter '*.ps1' | Sort-Object Name | ForEach-Object { & powershell -NoProfile -ExecutionPolicy Bypass -File $_.FullName; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
```

For macOS shell changes, also run:

```powershell
$ErrorActionPreference='Stop'; $bash='C:\Program Files\Git\bin\bash.exe'; & $bash -lc 'bash -n scripts/macos/manage-cliproxyapi.sh'; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; Get-ChildItem -LiteralPath 'tests' -Filter '*.sh' | Sort-Object Name | ForEach-Object { & $bash $_.FullName; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
```
