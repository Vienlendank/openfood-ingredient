#!/usr/bin/env bash
# Usage: ./find_ingredient.sh -i "<ingredient>" -d /path/to/folder
# Input: products.csv (TSV) must exist inside the folder.
# Output: product_name<TAB>code for matches, then a final count line.

set -euo pipefail # safer Bash: fail on errors/unset vars/pipelines
# Allow up to 1 GB per field

export CSVKIT_FIELD_SIZE_LIMIT=$((1024 * 1024 * 1024))

INGREDIENT=""; DATA_DIR=""; CSV=""

usage() {
  echo "Usage: $0 -i \"<ingredient>\" -d /path/to/folder"
  echo " -i ingredient to search (case-insensitive)"
  echo " -d folder containing products.csv (tab-separated)"
  echo " -h show help"
}

# Parse flags (getopts)
while getopts ":i:d:h" opt; do
  case "$opt" in
    i) INGREDIENT="$OPTARG" ;;
    d) DATA_DIR="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

#test one
[ -z "${INGREDIENT:-}" ] && { echo "ERROR: -i <ingredient> is required" >&2; usage; exit 1; }
[ -z "${DATA_DIR:-}" ] && { echo "ERROR: -d /path/to/folder is required" >&2; usage; exit 1; }

CSV="$DATA_DIR/products.csv"
[ -s "$CSV" ] || { echo "ERROR: $CSV not found or empty." >&2; exit 1; }

# Check csvkit tools
for cmd in csvcut csvgrep csvformat; do
   command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not found. Please install csvkit." >&2; exit
       1; }
done

# Check column presence
has_col() {
  csvcut -t -n "$CSV" | awk -F': ' '{print $2}' | grep -Fxq "$1"
}

HAVE_PN=0
HAVE_CODE=0
has_col "product_name" && HAVE_PN=1
has_col "code" && HAVE_CODE=1

# Build SQL to substitute placeholders if needed
if [ "$HAVE_PN" -eq 1 ] && [ "$HAVE_CODE" -eq 1 ]; then
  SQL='select coalesce("product_name","<no-name>") as product_name,
              coalesce("code","<no-code>") as code from stdin'
elif [ "$HAVE_PN" -eq 1 ]; then
  SQL='select coalesce("product_name","<no-name>") as product_name,
              "<no-code>" as code from stdin'
elif [ "$HAVE_CODE" -eq 1 ]; then
  SQL='select "<no-name>" as product_name,
              coalesce("code","<no-code>") as code from stdin'
else
  SQL='select "<no-name>" as product_name,
              "<no-code>" as code from stdin'
fi


# Pipeline:
tmp_matches="$(mktemp)"
csvcut -t -c ingredients_text,product_name,code "$CSV" \
| csvgrep -t -c ingredients_text -r "(?i)${INGREDIENT}" \
| csvcut -c product_name,code \
| csvformat -T \
| tail -n +2 \
| tee "$tmp_matches"


count="$(wc -l < "$tmp_matches" | tr -d ' ')"
echo "----"
echo "Found ${count} product(s) containing: \"${INGREDIENT}\""

# cleanup
rm -f "$tmp_matches"