#!/usr/bin/env bash
set -euo pipefail

INPUT_DIR="${1:?Usage: $0 <input_dir> <output_dir>}"
OUTPUT_DIR="${2:?Usage: $0 <input_dir> <output_dir>}"

mkdir -p "$OUTPUT_DIR"

echo "==> Scanning $INPUT_DIR for .list files..."

while IFS= read -r -d '' list_file; do
  base_name=$(basename "$list_file" .list)
  mrs_file="$OUTPUT_DIR/${base_name}.mrs"

  echo "  → Converting: $list_file → $mrs_file"

  mihomo convert-ruleset classical text "$list_file" "$mrs_file"

  echo "    ✓ Generated: $mrs_file ($(du -h "$mrs_file" | cut -f1))"
done < <(find "$INPUT_DIR" -maxdepth 1 -name '*.list' -print0)

echo "==> Done."
