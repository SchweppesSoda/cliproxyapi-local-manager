# Client Config Model Catalog Implementation Plan

**Goal:** Replace the duplicated WorkBuddy capability fallback with a catalog-driven `client-config --format workbuddy` workflow that stays consistent on Windows and macOS and remains usable offline.

**Design:** `docs/superpowers/specs/2026-07-11-client-config-model-catalog-design.md`

## Task 1: Add the official catalog snapshot and contract tests

**Files:**
- Add: `data/cliproxyapi-models.json`
- Add: `tests/model-catalog-snapshot.ps1`
- Modify: `tests/windows-workbuddy-json.ps1`
- Modify: `tests/macos-lifecycle-static.ps1`

1. Add failing tests for snapshot schema, non-empty IDs, per-group duplicate rejection, deterministic aliases, thinking shapes, duplicate-ID conflict handling, and the exact non-chat matcher.
2. Add the current official CLIProxyAPI catalog snapshot without local audit or capability fields.
3. Run the focused tests and confirm the snapshot contract passes while new generator expectations still fail.

## Task 2: Implement Windows catalog lifecycle

**Files:**
- Modify: `scripts/windows/manage-cliproxyapi.ps1`
- Add: `tests/windows-model-catalog.ps1`

1. Add failing tests for repository seeding, installed snapshot validation, ordered URL fallback, invalid-content fallback, atomic replacement, and preservation of an existing valid catalog.
2. Implement catalog path resolution, validation, seeding, and sync functions.
3. Call non-fatal remote sync after existing state-save and service-restoration logic for manual and scheduled updates.
4. Re-run focused lifecycle tests.

## Task 3: Implement Windows normalizer and WorkBuddy adapter

**Files:**
- Modify: `scripts/windows/manage-cliproxyapi.ps1`
- Replace/rename coverage in: `tests/windows-workbuddy-json.ps1`
- Modify: `tests/windows-lifecycle-static.ps1`

1. Add failing behavioral tests for `client-config`, `Format`, custom `Vendor`, offline explicit model IDs, omitted unknown capabilities, token opt-in, deterministic duplicate handling, reasoning allowlist, non-chat exclusion, stdout/stderr separation, and the deprecated alias.
2. Implement loader, normalizer, format dispatch, and WorkBuddy adapter.
3. Remove `Get-BuiltInWorkBuddyModelInfo` and default capability claims.
4. Keep the old action as a one-version forwarding alias.
5. Run all Windows-focused tests.

## Task 4: Implement the equivalent macOS workflow

**Files:**
- Modify: `scripts/macos/manage-cliproxyapi.sh`
- Modify: `tests/macos-lifecycle-static.ps1`
- Add or modify shell behavior tests under: `tests/*.sh`

1. Add failing static/behavior tests matching the Windows contract.
2. Implement catalog validation, seeding, ordered sync, normalization, format dispatch, custom vendor, and deprecated alias using the existing supported JSON tooling path.
3. Remove the embedded GPT fallback and lossy default capability output.
4. Run `bash -n` and all focused macOS tests.

## Task 5: Migrate menu, help, documentation, and maintenance rules

**Files:**
- Modify: `README.md`
- Modify: `docs/design.md`
- Modify: `AGENTS.md`
- Modify: `tests/menu-lifecycle-docs.ps1`
- Modify: `tests/readme-workflow-docs.ps1`
- Modify: other static tests that reference WorkBuddy action/function names
- Delete: `data/workbuddy-model-capabilities.candidate.json`
- Delete: `docs/workbuddy-model-capabilities-prompt.md`
- Delete or replace: `tests/workbuddy-capabilities-prompt-docs.ps1`

1. Add failing documentation/menu assertions for the new terminology, arguments, snapshot source, offline behavior, and deprecation.
2. Rename menu item 13 to client model configuration while retaining WorkBuddy as a format.
3. Remove obsolete capability-research guidance and update repository instructions to make the official snapshot the maintenance source.
4. Run documentation/static tests.

## Task 6: Full verification and final review

1. Run every PowerShell test required by `AGENTS.md`.
2. Run macOS shell syntax validation and every shell test required by `AGENTS.md`.
3. Run `git diff --check` and inspect the final diff for secrets or runtime state.
4. Request a read-only subagent review of the implementation and fix Critical/Important findings.
5. Re-run the full verification suite after review fixes.
