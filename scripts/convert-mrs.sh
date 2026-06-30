#!/usr/bin/env bash
set -euo pipefail

INPUT_DIR="${1:?Usage: $0 <input_dir> <output_dir>}"
OUTPUT_DIR="${2:?Usage: $0 <input_dir> <output_dir>}"

mkdir -p "$OUTPUT_DIR"

echo "==> Scanning $INPUT_DIR for .list files..."

while IFS= read -r -d '' list_file; do
  base_name=$(basename "$list_file" .list)
  mrs_file="$OUTPUT_DIR/${base_name}.mrs"
  temp_yaml=$(mktemp)

  echo "  → Processing: $list_file"

  domain_count=0
  ipcidr_count=0
  rules=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    IFS=',' read -r rule_type value rest <<< "$line"

    case "$rule_type" in
      DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD|DOMAIN-REGEX)
        domain_count=$((domain_count + 1))
        rules+=("$line")
        ;;
      IP-CIDR|IP-CIDR6)
        cidr="${value%%,*}"
        ipcidr_count=$((ipcidr_count + 1))
        rules+=("$rule_type,$cidr")
        ;;
      *)
        echo "    ⚠ Skipping unsupported rule: $line"
        ;;
    esac
  done < "$list_file"

  if [[ ${#rules[@]} -eq 0 ]]; then
    echo "    ⚠ No valid rules found, skipping"
    rm -f "$temp_yaml"
    continue
  fi

  printf 'rules:\n' > "$temp_yaml"
  for rule in "${rules[@]}"; do
    printf '  - %s\n' "$rule" >> "$temp_yaml"
  done

  if [[ $domain_count -gt 0 && $ipcidr_count -eq 0 ]]; then
    echo "    → Converting to MRS (domain behavior)"
    mihomo convert-ruleset domain yaml "$temp_yaml" "$mrs_file"
  elif [[ $ipcidr_count -gt 0 && $domain_count -eq 0 ]]; then
    echo "    → Converting to MRS (ipcidr behavior)"
    mihomo convert-ruleset ipcidr yaml "$temp_yaml" "$mrs_file"
  else
    echo "    → Converting to MRS (classical behavior, mixed)"
    mihomo convert-ruleset classical yaml "$temp_yaml" "$mrs_file"
  fi

  echo "    ✓ Generated: $mrs_file ($(du -h "$mrs_file" | cut -f1))"

  rm -f "$temp_yaml"
done < <(find "$INPUT_DIR" -maxdepth 1 -name '*.list' -print0)

echo "==> Done."
