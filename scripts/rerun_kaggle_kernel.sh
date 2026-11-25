#!/usr/bin/env bash
# Pull the current Kaggle notebook, push it back (which triggers a new run),
# then record status, logs and optional output files.
set -euo pipefail

KERNEL_SLUG="${KERNEL_SLUG:-yongyongwuvip/kaggle-t4-llamacpp-tunnel}"
KAGGLE_ACCELERATOR="${KAGGLE_ACCELERATOR:-NvidiaTeslaT4}"
KAGGLE_TIMEOUT="${KAGGLE_TIMEOUT:-3600}"
STATUS_POLL_SECONDS="${STATUS_POLL_SECONDS:-180}"
STATUS_INTERVAL_SECONDS="${STATUS_INTERVAL_SECONDS:-15}"
OUTPUT_FILE_PATTERN="${OUTPUT_FILE_PATTERN:-ollama_base_url.txt}"
DRY_RUN="${DRY_RUN:-false}"
ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts}"

mkdir -p "$ARTIFACT_DIR"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Kernel: $KERNEL_SLUG"
echo "==> Pulling latest notebook source"
kaggle kernels pull "$KERNEL_SLUG" -p "$WORK_DIR" -m

META_FILE="$(find "$WORK_DIR" -maxdepth 1 -type f -name '*metadata*.json' -print -quit)"
if [ -z "$META_FILE" ]; then
  echo "kernel-metadata.json was not produced by kaggle kernels pull" >&2
  exit 1
fi

python - "$META_FILE" "$KERNEL_SLUG" "$WORK_DIR" <<'PY'
import json
import os
import sys

meta_path, expected_id, work_dir = sys.argv[1:4]
with open(meta_path, encoding="utf-8") as fh:
    meta = json.load(fh)

if meta.get("id") != expected_id:
    print(f"Fixing metadata id: {meta.get('id')} -> {expected_id}")
    meta["id"] = expected_id
    with open(meta_path, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2, ensure_ascii=False)

code_file = meta.get("code_file")
if not code_file:
    raise SystemExit("kernel-metadata.json has no code_file")
code_path = os.path.join(work_dir, code_file)
if not os.path.isfile(code_path):
    raise SystemExit(f"code_file not found after pull: {code_path}")
print(f"Metadata OK: id={meta['id']} code_file={code_file}")
PY

if [ "$DRY_RUN" = "true" ]; then
  echo "DRY_RUN=true: validation complete, skipping push."
  echo "validated" > "$ARTIFACT_DIR/dry_run.txt"
  exit 0
fi

PUSH_ARGS=(-p "$WORK_DIR")
if [ -n "$KAGGLE_ACCELERATOR" ]; then
  PUSH_ARGS+=(--accelerator "$KAGGLE_ACCELERATOR")
fi
if [ -n "$KAGGLE_TIMEOUT" ]; then
  PUSH_ARGS+=(--timeout "$KAGGLE_TIMEOUT")
fi

echo "==> Pushing notebook (creates a new version and starts a run)"
kaggle kernels push "${PUSH_ARGS[@]}" | tee "$ARTIFACT_DIR/push.log"

echo "==> Polling run status for up to ${STATUS_POLL_SECONDS}s"
DEADLINE=$((SECONDS + STATUS_POLL_SECONDS))
while true; do
  STATUS="$(kaggle kernels status "$KERNEL_SLUG" 2>&1 || true)"
  printf '%s\n' "$STATUS" > "$ARTIFACT_DIR/status.txt"
  echo "$STATUS"

  LOWER="$(printf '%s' "$STATUS" | tr '[:upper:]' '[:lower:]')"
  if printf '%s' "$LOWER" | grep -Eq 'complete|error|fail|cancel'; then
    break
  fi
  if (( SECONDS >= DEADLINE )); then
    echo "Polling window closed; kernel may still be RUNNING (expected for a tunnel notebook)."
    break
  fi
  sleep "$STATUS_INTERVAL_SECONDS"
done

echo "==> Saving kernel logs"
kaggle kernels logs "$KERNEL_SLUG" > "$ARTIFACT_DIR/kernel.log" 2>&1 || true

if [ -n "$OUTPUT_FILE_PATTERN" ]; then
  echo "==> Downloading output matching: $OUTPUT_FILE_PATTERN"
  kaggle kernels output "$KERNEL_SLUG" -p "$ARTIFACT_DIR/output" -o \
    --file-pattern "$OUTPUT_FILE_PATTERN" > "$ARTIFACT_DIR/output.log" 2>&1 || true
fi

echo "==> Report files:"
find "$ARTIFACT_DIR" -maxdepth 2 -type f -printf '%p\n'
echo "==> Done."
