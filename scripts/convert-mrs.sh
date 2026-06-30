#!/usr/bin/env bash
set -euo pipefail

INPUT_DIR="${1:?Usage: $0 <input_dir> <output_dir>}"
OUTPUT_DIR="${2:?Usage: $0 <input_dir> <output_dir>}"

mkdir -p "$OUTPUT_DIR"

echo "==> Scanning $INPUT_DIR for .list files..."

while IFS= read -r -d '' list_file; do
  base_name=$(basename "$list_file" .list)
  domain_rules=()
  ipcidr_rules=()

  echo "  → Processing: $list_file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    IFS=',' read -r rule_type value rest <<< "$line"

    case "$rule_type" in
      DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD|DOMAIN-REGEX)
        domain_rules+=("$line")
        ;;
      IP-CIDR|IP-CIDR6)
        cidr="${value%%,*}"
        ipcidr_rules+=("$rule_type,$cidr")
        ;;
      *)
        echo "    ⚠ Skipping unsupported rule: $line"
        ;;
    esac
  done < "$list_file"

  if [[ ${#domain_rules[@]} -gt 0 ]]; then
    domain_mrs="$OUTPUT_DIR/${base_name}.mrs"
    temp_yaml=$(mktemp)
    printf 'rules:\n' > "$temp_yaml"
    for rule in "${domain_rules[@]}"; do
      printf '  - %s\n' "$rule" >> "$temp_yaml"
    done
    echo "    → Converting domain rules to MRS"
    mihomo convert-ruleset domain yaml "$temp_yaml" "$domain_mrs"
    echo "    ✓ Generated: $domain_mrs ($(du -h "$domain_mrs" | cut -f1))"
    rm -f "$temp_yaml"
  fi

  if [[ ${#ipcidr_rules[@]} -gt 0 ]]; then
    ipcidr_mrs="$OUTPUT_DIR/${base_name}-ip.mrs"
    temp_yaml=$(mktemp)
    printf 'rules:\n' > "$temp_yaml"
    for rule in "${ipcidr_rules[@]}"; do
      printf '  - %s\n' "$rule" >> "$temp_yaml"
    done
    echo "    → Converting IP-CIDR rules to MRS"
    mihomo convert-ruleset ipcidr yaml "$temp_yaml" "$ipcidr_mrs"
    echo "    ✓ Generated: $ipcidr_mrs ($(du -h "$ipcidr_mrs" | cut -f1))"
    rm -f "$temp_yaml"
  fi

  if [[ ${#domain_rules[@]} -eq 0 && ${#ipcidr_rules[@]} -eq 0 ]]; then
    echo "    ⚠ No valid rules found, skipping"
  fi
done < <(find "$INPUT_DIR" -maxdepth 1 -name '*.list' -print0)

echo "==> Done."
