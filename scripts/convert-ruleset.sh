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
  json_file="$OUTPUT_DIR/${base_name}.json"
  srs_file="$OUTPUT_DIR/${base_name}.srs"

  echo "  → Converting: $list_file → $srs_file"

  # Transform Clash rule format to sing-box JSON source format.
  # sing-box rule-set compile expects a JSON file:
  #   { "version": 2, "rules": [ { "domain_suffix": "..." }, ... ] }
  #
  # Clash rule type → sing-box headless rule key mapping:
  #   DOMAIN         → domain
  #   DOMAIN-SUFFIX  → domain_suffix
  #   DOMAIN-KEYWORD → domain_keyword
  #   DOMAIN-REGEX   → domain_regex
  #   IP-CIDR        → ip_cidr
  #   IP-CIDR6       → ip_cidr

  tsv_file="${json_file}.tmp.tsv"
  > "$tsv_file"

  while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Skip comment lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # Strip trailing \r for Windows line endings
    line="${line%$'\r'}"

    # Parse RULE_TYPE,value (split on first comma only)
    rule_type="${line%%,*}"
    value="${line#*,}"

    case "$rule_type" in
      DOMAIN)
        printf 'domain\t%s\n' "$value" >> "$tsv_file"
        ;;
      DOMAIN-SUFFIX)
        printf 'domain_suffix\t%s\n' "$value" >> "$tsv_file"
        ;;
      DOMAIN-KEYWORD)
        printf 'domain_keyword\t%s\n' "$value" >> "$tsv_file"
        ;;
      DOMAIN-REGEX)
        printf 'domain_regex\t%s\n' "$value" >> "$tsv_file"
        ;;
      IP-CIDR|IP-CIDR6)
        # Strip Clash modifiers like ",no-resolve" — sing-box ip_cidr only accepts pure CIDR
        cidr="${value%%,*}"
        printf 'ip_cidr\t%s\n' "$cidr" >> "$tsv_file"
        ;;
      GEOIP|MATCH|FINAL|PROCESS-NAME|USER-AGENT|URL-REGEX|SRC-IP-CIDR|DST-PORT|SRC-PORT|AND|OR|NOT)
        # Unsupported rule types — skip silently
        ;;
    esac
  done < "$list_file"

  # Build JSON with jq (available on GitHub Actions ubuntu-latest)
  jq -R 'split("\t") | select(length == 2) | {(.[0]): .[1]}' "$tsv_file" \
    | jq -s '{version: 2, rules: .}' > "$json_file"

  rm -f "$tsv_file"

  rule_count=$(jq '.rules | length' "$json_file")
  echo "    Rules extracted: ${rule_count}"

  # Compile to binary SRS format
  sing-box rule-set compile "$json_file" -o "$srs_file"

  echo "    ✓ Generated: $srs_file ($(du -h "$srs_file" | cut -f1))"
done < <(find "$INPUT_DIR" -maxdepth 1 -name '*.list' -print0)

echo "==> Done."
