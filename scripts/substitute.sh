#!/usr/bin/env bash
# 讀入 template.json + field-map.json，逐欄位用 jq 替換成假資料，輸出成一份新的 JSON。
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $(basename "$0") <template.json> <output.json>" >&2
  exit 1
fi

template_path="$1"
output_path="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POOL_DIR="$PROJECT_ROOT/data/fake-pools"
FIELD_MAP="$PROJECT_ROOT/data/field-map.json"

# 離線部署環境可能沒裝 jq，優先用系統的 jq，找不到就退回 vendor/ 裡帶的靜態二進制檔。
if command -v jq >/dev/null 2>&1; then
  JQ="jq"
elif [[ -x "$PROJECT_ROOT/vendor/jq-linux-amd64" ]]; then
  JQ="$PROJECT_ROOT/vendor/jq-linux-amd64"
else
  echo "Error: jq not found on PATH and no vendored binary at vendor/jq-linux-amd64" >&2
  exit 1
fi

random_line() {
  shuf -n 1 "$1"
}

random_digits() {
  local n="$1" s=""
  for ((k = 0; k < n; k++)); do
    s+="$((RANDOM % 10))"
  done
  printf '%s' "$s"
}

# addresses.tsv 的欄位（district/city/street/postal_code）必須來自同一列，
# 否則行政區會跟郵遞區號兜不起來，所以在迴圈開始前只抽一次列。
# 注意：不能把這個抽籤包成用 $(...) 呼叫的 function 再讓多個欄位各自呼叫，
# 那樣每次呼叫都在各自的 subshell 裡重新 shuf，等於每個欄位都抽到不同列。
ADDR_ROW="$(random_line "$POOL_DIR/addresses.tsv")"
ADDR_DISTRICT="$(cut -f1 <<< "$ADDR_ROW")"
ADDR_CITY="$(cut -f2 <<< "$ADDR_ROW")"
ADDR_STREET="$(cut -f3 <<< "$ADDR_ROW")"
ADDR_POSTAL="$(cut -f4 <<< "$ADDR_ROW")"
ADDR_HOUSE_NO=$(( (RANDOM % 300) + 1 ))
ADDR_FLOOR=$(( (RANDOM % 15) + 1 ))
ADDR_TEXT="${ADDR_DISTRICT}${ADDR_CITY}${ADDR_STREET}${ADDR_HOUSE_NO}號${ADDR_FLOOR}樓"

# 身分證第二碼是性別碼（1 男 / 2 女），跟 Patient.gender 必須對得起來，
# 所以兩者要來自同一次抽籤，不能各自獨立產生。
ALPHABET="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
ID_LETTER="${ALPHABET:$((RANDOM % 26)):1}"
GENDER_DIGIT=$(( (RANDOM % 2) + 1 ))
NATIONAL_ID="${ID_LETTER}${GENDER_DIGIT}$(random_digits 8)"
if [[ "$GENDER_DIGIT" == "1" ]]; then
  GENDER_VALUE="male"
else
  GENDER_VALUE="female"
fi

resolve_value() {
  local type="$1"
  case "$type" in
    name) random_line "$POOL_DIR/names.txt" ;;
    family_name) random_line "$POOL_DIR/family-names.txt" ;;
    given_name) random_line "$POOL_DIR/given-names.txt" ;;
    phone) random_line "$POOL_DIR/phones.txt" ;;
    national_id) printf '%s' "$NATIONAL_ID" ;;
    gender) printf '%s' "$GENDER_VALUE" ;;
    address_text) printf '%s' "$ADDR_TEXT" ;;
    address_line) printf '%s' "$ADDR_STREET" ;;
    address_city) printf '%s' "$ADDR_CITY" ;;
    address_district) printf '%s' "$ADDR_DISTRICT" ;;
    address_postal_code) printf '%s' "$ADDR_POSTAL" ;;
    relationship_code) random_line "$POOL_DIR/relationship-codes.txt" ;;
    *)
      echo "Error: unknown field-map type '$type'" >&2
      exit 1
      ;;
  esac
}

json="$(cat "$template_path")"

field_count=$("$JQ" 'length' "$FIELD_MAP")
for ((i = 0; i < field_count; i++)); do
  path=$("$JQ" -r ".[$i].path" "$FIELD_MAP")
  type=$("$JQ" -r ".[$i].type" "$FIELD_MAP")
  value="$(resolve_value "$type")"
  json="$("$JQ" --arg v "$value" "${path} = \$v" <<< "$json")"
done

printf '%s\n' "$json" > "$output_path"
