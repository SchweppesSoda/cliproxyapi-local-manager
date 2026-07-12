#!/bin/bash

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$repo_root/scripts/macos/manage-cliproxyapi.sh"
install_dir=$(mktemp -d "${TMPDIR:-/tmp}/cliproxyapi-client-config.XXXXXX")
stderr_file="$install_dir/stderr.txt"
trap 'rm -rf "$install_dir"' EXIT

cat > "$install_dir/config.yaml" <<'EOF'
host: "127.0.0.1"
port: 8317
api-keys:
  - "wb-local-test-key"
remote-management:
  allow-remote: false
  secret-key: "mgmt-local-test-key"
EOF

cat > "$install_dir/models.json" <<'EOF'
{
  "codex-plus": [
    {
      "id": "tool-model",
      "display_name": "Tool Model",
      "context_length": 1000,
      "max_completion_tokens": 200,
      "supported_parameters": ["tools"],
      "thinking": { "levels": ["low", "medium", "none"] }
    },
    { "id": "gpt-image-2", "type": "openai" }
  ],
  "gemini": [
    {
      "id": "vision-model",
      "inputTokenLimit": 3000,
      "outputTokenLimit": 400,
      "supportedInputModalities": ["TEXT", "IMAGE"],
      "thinking": { "min": 1, "max": 100 }
    },
    { "id": "conflict-model", "context_length": 100 }
  ],
  "vertex": [
    { "id": "conflict-model", "context_length": 200 }
  ]
}
EOF

output=$(bash "$script" \
  --client-config \
  --format workbuddy \
  --vendor "My Local Provider" \
  --install-dir "$install_dir" \
  --model-ids "tool-model,vision-model,conflict-model,gpt-image-2,unknown-model" \
  --include-token-limits 2>"$stderr_file")

legacy_stderr="$install_dir/legacy-stderr.txt"
legacy_output=$(bash "$script" \
  --workbuddy-json \
  --vendor "My Local Provider" \
  --install-dir "$install_dir" \
  --model-ids "tool-model,vision-model,conflict-model,gpt-image-2,unknown-model" \
  --include-token-limits 2>"$legacy_stderr")
if [ "$legacy_output" != "$output" ]; then
  printf '%s\n' "Deprecated workbuddy-json stdout differs from client-config" >&2
  exit 1
fi
grep -q 'workbuddy-json.*client-config' "$legacy_stderr"

CLIENT_CONFIG_JSON=$output python3 - <<'PY'
import json, os
payload = json.loads(os.environ["CLIENT_CONFIG_JSON"])
models = payload["models"]
assert [m["id"] for m in models] == ["tool-model", "vision-model", "conflict-model", "unknown-model"]
by_id = {m["id"]: m for m in models}
tool = by_id["tool-model"]
assert tool["name"] == "Tool Model"
assert tool["vendor"] == "My Local Provider"
assert tool["supportsToolCall"] is True
assert tool["supportsReasoning"] is True
assert tool["reasoning"]["supportedEfforts"] == ["low", "medium"]
assert "defaultEffort" not in tool["reasoning"]
assert tool["maxInputTokens"] == 1000 and tool["maxOutputTokens"] == 200
vision = by_id["vision-model"]
assert vision["supportsImages"] is True and vision["supportsReasoning"] is True
assert "reasoning" not in vision and "supportsToolCall" not in vision
assert "maxInputTokens" not in by_id["conflict-model"]
for field in ("supportsToolCall", "supportsImages", "supportsReasoning", "reasoning", "maxInputTokens", "maxOutputTokens"):
    assert field not in by_id["unknown-model"]
PY

if ! grep -q 'conflict-model' "$stderr_file" || ! grep -q 'contextTokens' "$stderr_file"; then
  printf '%s\n' "Missing conflict-model catalog warning" >&2
  cat "$stderr_file" >&2
  exit 1
fi
if ! grep -q 'unknown-model' "$stderr_file"; then
  printf '%s\n' "Missing unknown-model catalog warning" >&2
  cat "$stderr_file" >&2
  exit 1
fi

real_python=$(command -v python3)
fake_bin="$install_dir/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/python3" <<'EOF'
#!/bin/sh
count=0
if [ -f "$PY_COUNTER" ]; then
  count=$(cat "$PY_COUNTER")
fi
count=$((count + 1))
printf '%s\n' "$count" > "$PY_COUNTER"
if [ "$count" -ge 2 ]; then
  exit 7
fi
exec "$REAL_PYTHON" "$@"
EOF
chmod +x "$fake_bin/python3"
render_stdout="$install_dir/render-failure-stdout.txt"
render_stderr="$install_dir/render-failure-stderr.txt"
if PATH="$fake_bin:$PATH" REAL_PYTHON="$real_python" PY_COUNTER="$install_dir/python-counter.txt" \
  bash "$script" --client-config --install-dir "$install_dir" --model-ids "tool-model" \
  >"$render_stdout" 2>"$render_stderr"; then
  printf '%s\n' "Renderer failure unexpectedly succeeded" >&2
  exit 1
fi
if [ -s "$render_stdout" ]; then
  printf '%s\n' "Renderer failure emitted partial JSON" >&2
  exit 1
fi

printf '%s\n' '{"bad":{"id":"not-an-array"}}' > "$install_dir/models.json"
seeded_output=$(bash "$script" \
  --client-config \
  --install-dir "$install_dir" \
  --model-ids "gpt-5.5" 2>"$install_dir/seed-stderr.txt")
SEEDED_JSON=$seeded_output INSTALLED_CATALOG="$install_dir/models.json" python3 - <<'PY'
import json, os
payload = json.loads(os.environ["SEEDED_JSON"])
assert payload["models"][0]["supportsReasoning"] is True
with open(os.environ["INSTALLED_CATALOG"], encoding="utf-8-sig") as handle:
    catalog = json.load(handle)
assert "codex-plus" in catalog
PY

printf '%s\n' "MACOS_CLIENT_CONFIG_OK"
