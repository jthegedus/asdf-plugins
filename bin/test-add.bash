#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# while IFS=, read -r full_name name url license build_status security_policy last_updated; do

# while IFS=, read -r full_name name url license build_status security_policy last_updated; do
# printf "%s\t%s\t%s\t%s\t%s\n" "${url}" "${license}" "${build_status}" "${security_policy}" "${last_updated}"
# awk '{ printf "%-20s %-20s %-20s %-20s %-20s\n", $url, $license, $build_status, $security_policy $last_updated}'
# done <"plugins/all-plugins.csv"

# cat "plugins/all-plugins.csv" | awk '
# 		BEGIN { FS="," };
# 		{ if (FNR == 1) printf "%-60s %-20s\n", toupper($3), toupper($4) }
# 		{ if (FNR > 1) printf "%-60s %-20s\n", $3, $4 }
# 	'

# cat "plugins/all-plugins.csv" | awk '
# 		BEGIN { FS="," };
# 		{ if (FNR == 1) printf "%-3s %-3s %-60s %-20s %-20s\n", "BLD", "SEC", toupper($3), toupper($4), toupper($7) }
# 		{ if (FNR > 1) printf "%-3s %-3s %-60s %-20s %-20s\n", $5, $6, $3, $4, $7 }
# 	'

# for a in ./old-plugins/*; do
# 	echo "$a" >>all_repos.txt
# 	cat $a >>all_repos.txt
# done

# Parsing .toml in Bash
# parse_toml() {
# 	local filename="$1"
# 	local key="$2"
# 	grep "$key" "$filename" | awk -F'=' '{print $2}' | sed 's/ //' | sed 's/"//g'
# }
# parse_toml "./old-plugins/1password.toml" "repository"
