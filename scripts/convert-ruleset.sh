#!/usr/bin/env bash
set -euo pipefail

# convert-ruleset.sh — Convert Clash .list rule files to sing-box binary .srs format
#
# Usage: bash scripts/convert-ruleset.sh <input_dir> <output_dir>

INPUT_DIR="${1:?Usage: $0 <input_dir> <output_dir>}"
OUTPUT_DIR="${2:?Usage: $0 <input_dir> <output_dir>}"

mkdir -p "$OUTPUT_DIR"

echo "==> Scanning $INPUT_DIR for .list files..."

# Use process substitution to avoid subshell issues with set -e
while IFS= read -r -d '' list_file; do
  base_name=$(basename "$list_file" .list)
  source_file="$OUTPUT_DIR/${base_name}.source"
  srs_file="$OUTPUT_DIR/${base_name}.srs"

  echo "  → Converting: $list_file → $srs_file"

  # Transform Clash rule format to sing-box source format.
  # Clash:       DOMAIN-SUFFIX,example.com
  # sing-box:    domain-suffix:example.com
  #
  # Mapping:
  #   DOMAIN         → domain:
  #   DOMAIN-SUFFIX  → domain-suffix:
  #   DOMAIN-KEYWORD → domain-keyword:
  #   DOMAIN-REGEX   → domain-regex:
  #   IP-CIDR        → ip-cidr:
  #   IP-CIDR6       → ip-cidr:

  > "$source_file"
  while IFS= read -r line; do
    # Skip empty lines
    if [[ -z "$line" ]]; then
      continue
    fi

    # Keep comment lines
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
      echo "$line" >> "$source_file"
      continue
    fi

    # Strip trailing \r for Windows line endings
    line="${line%$'\r'}"

    # Parse RULE_TYPE,value (split on first comma only)
    rule_type="${line%%,*}"
    value="${line#*,}"

    case "$rule_type" in
      DOMAIN)
        echo "domain:${value}" >> "$source_file"
        ;;
      DOMAIN-SUFFIX)
        echo "domain-suffix:${value}" >> "$source_file"
        ;;
      DOMAIN-KEYWORD)
        echo "domain-keyword:${value}" >> "$source_file"
        ;;
      DOMAIN-REGEX)
        echo "domain-regex:${value}" >> "$source_file"
        ;;
      IP-CIDR|IP-CIDR6)
        echo "ip-cidr:${value}" >> "$source_file"
        ;;
      GEOIP|MATCH|FINAL|PROCESS-NAME|USER-AGENT|URL-REGEX|SRC-IP-CIDR|DST-PORT|SRC-PORT)
        echo "# SKIPPED (unsupported): ${line}" >> "$source_file"
        ;;
      *)
        echo "# SKIPPED (unknown type): ${line}" >> "$source_file"
        ;;
    esac
  done < "$list_file"

  # Compile to binary SRS format
  sing-box rule-set compile "$source_file" -o "$srs_file"

  echo "    ✓ Generated: $srs_file ($(du -h "$srs_file" | cut -f1))"
done < <(find "$INPUT_DIR" -maxdepth 1 -name '*.list' -print0)

echo "==> Done."
