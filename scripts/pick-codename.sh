#!/bin/bash
# Pick a random dessert codename for NovumOS release from Wiktionary API
set -euo pipefail

API="https://en.wiktionary.org/w/api.php"
CATEGORIES=("Category:en:Desserts" "Category:en:Cakes and pastries" "Category:en:Ice cream")

for dep in curl jq; do
    if ! command -v "$dep" &>/dev/null; then
        echo "Error: $dep is required but not installed."
        exit 1
    fi
done

names=()
for cat in "${CATEGORIES[@]}"; do
    cmcont=""
    while :; do
        params="action=query&list=categorymembers&cmtitle=$(printf '%s' "$cat" | jq -sRr @uri)&cmlimit=max&format=json"
        if [ -n "$cmcont" ]; then
            params+="&cmcontinue=$(printf '%s' "$cmcont" | jq -sRr @uri)"
        fi
        resp=$(curl -s "$API?$params")
        while IFS=$'\t' read -r ns title; do
            [ "$ns" = "0" ] && names+=("$title")
        done < <(echo "$resp" | jq -r '.query.categorymembers[] | [.ns, .title] | @tsv')
        cmcont=$(echo "$resp" | jq -r '.continue.cmcontinue // empty')
        [ -z "$cmcont" ] && break
    done
done

if [ ${#names[@]} -eq 0 ]; then
    echo "Error: no desserts found from Wiktionary API"
    exit 1
fi

codename=${names[$RANDOM % ${#names[@]}]}
echo "NovumOS $codename"