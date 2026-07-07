# Repository Instructions

This repository maintains local-only helper scripts for running CLIProxyAPI on a user's own machine.

## Safety Rules

- Never commit local install directories, `config.yaml`, `webui-management-key.txt`, `auth/`, OAuth tokens, API keys, management keys, logs, downloads, or generated runtime state.
- Keep generated CLIProxyAPI configuration local-only: bind to `127.0.0.1`, keep remote management disabled, and do not add tunnel, public-domain, VPS, cloud-host, or multi-user assumptions.
- State files belong in the CLIProxyAPI install directory, not in the repository root.
- Do not change menu behavior, output format, or lifecycle semantics without updating Windows, macOS, README, and tests together.

## WorkBuddy / CodeBuddy Model JSON

- Treat live CLIProxyAPI `/v1/models` output as the primary source for model IDs.
- Do not guess capabilities from model names when official provider documentation or `/v1/models` metadata is missing.
- `supportsImages` means image input or vision for a chat model. It does not mean image generation.
- Image-generation or image-editing models such as `gpt-image-*` and `dall-e*` must not be emitted as `/v1/chat/completions` chat models.
- Do not emit `availableModels` unless the user explicitly asks to restrict the WorkBuddy / CodeBuddy model dropdown.
- `maxInputTokens` and `maxOutputTokens` should remain opt-in output fields.

## Model Capability Research

- Use `docs/workbuddy-model-capabilities-prompt.md` when refreshing model capability research with Codex or another model.
- `data/workbuddy-model-capabilities.candidate.json` is a reviewed candidate cache, not runtime truth.
- Official provider docs are required for every non-base capability field.
- AI or browser extraction is only a lead; verify each capability against official sources before changing script fallback behavior.
- Keep audit fields such as `sources`, `verifiedAt`, `provider`, `match`, and `notes` in maintenance data only. Never copy them into generated WorkBuddy / CodeBuddy `models.json`.
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
