#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'
# call GitHub API
# 	find repos with names: asdf-plugin-* TODO
# 	find repos with topics: asdf, asdf-plugin
# output repos to plugins/<tool>.csv list with the following information
#	repo, license, build status, security policy, last updated (UTC)

tmp_download_dir=$(mktemp -d -t -p . 'asdf_plugins_XXXXXX')
tmp_plugin_search_result="repos.json"
all_plugins_output_csv_filename="all-plugins.csv"
trap 'rm -rf "${tmp_download_dir}"' EXIT

# https://help.github.com/en/github/searching-for-information-on-github/searching-for-repositories
# topics = asdf-plugin asdf
# archived = false
# forks are automatically ignored
github_api_token="Authorization: token b9792c19f793d2372fdfaf4e5b87f003e6576a0f" #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1
github_page_size="30"
github_checks_header="Accept: application/vnd.github.antiope-preview+json"
github_repos_header="Accept: application/vnd.github.mercy-preview+json"
github_repos_search="search/repositories?per_page=${github_page_size}&q=topic:asdf-plugin+topic:asdf+archived:false"

skip_list=("asdf-vm/asdf-plugins" "asdf-vm/asdf-plugin-template")

csv_header="full_name,owner_name,repo_name,url,license,build_status,security_policy,last_updated_at"

# sed can be replaced with grep -Eo
last_page_number=$(curl -s -I -H "${github_repos_header}" "https://api.github.com/${github_repos_search}" | grep '^link:' | sed -e 's/^link:.*page=//g' -e 's/>.*$//g')

function github_security_policy() {
	local org_repo="$1"
	security_uppercase=$(curl -s -I -H "${github_repos_header}" -H "${github_api_token}" "https://api.github.com/repos/${org_repo}/contents/SECURITY.md" | grep "status:")
	security_lowercase=$(curl -s -I -H "${github_repos_header}" -H "${github_api_token}" "https://api.github.com/repos/${org_repo}/contents/security.md" | grep "status:")
	if [[ "$security_uppercase" =~ "status: 200 OK" ]] || [[ "$security_lowercase" =~ "status: 200 OK" ]]; then
		echo "y"
	else
		echo "x"
	fi
}

# check-runs conclusion states: success, failure, neutral, cancelled, skipped, timed_out, action_required
# if NOT success or doesn't exist, then consider failed.
# https://developer.github.com/v3/checks/runs/#list-check-runs-in-a-check-suite
# https://developer.github.com/v3/repos/statuses/#get-the-combined-status-for-a-specific-reference
function github_build_status() {
	local org_repo="$1"
	local default_branch_name="$2"
	local repo_checks_filename="$tmp_download_dir/${org_repo/\//\_}_checks.json"
	local repo_statuses_filename="$tmp_download_dir/${org_repo/\//\_}_statuses.json"

	curl -s -H "${github_checks_header}" -H "${github_api_token}" \
		"https://api.github.com/repos/${org_repo}/commits/${default_branch_name}/check-runs" >"$repo_checks_filename"
	curl -s -H "${github_checks_header}" -H "${github_api_token}" \
		"https://api.github.com/repos/${org_repo}/commits/${default_branch_name}/status" >"$repo_statuses_filename"

	checks_not_success_count=$(yq r "$repo_checks_filename" "check_runs.*.conclusion" | grep --extended-regexp --ignore-case --count "^failure|neutral|cancelled|skipped|timed_out|action_required$")
	checks_success_count=$(yq r "$repo_checks_filename" "check_runs.*.conclusion" | grep --extended-regexp --ignore-case --count "^success$")
	statuses_not_success_count=$(yq r "$repo_statuses_filename" "statuses.[*].state" | grep --extended-regexp --ignore-case --count "^error|failure|pending$")
	statuses_success_count=$(yq r "$repo_statuses_filename" "statuses.[*].state" | grep --extended-regexp --ignore-case --count "^success$")

	if ([[ $checks_success_count -ge 1 ]] || [[ $statuses_success_count -ge 1 ]]) &&
		[[ $checks_not_success_count -eq 0 ]] && [[ $statuses_not_success_count -eq 0 ]]; then
		# build status success if either checks or status have a success and neither has not successes (failures/neutrals/pendings etc)
		echo "y"
	else
		# this includes in-progress/pending builds. This is just an indicator people should check the codebase.
		echo "x"
	fi
}

function github_search() {
	local page_number="$1"
	curl -s -H "$github_repos_header" -H "${github_api_token}" "https://api.github.com/${github_repos_search}&page=${page_number}"
}

github_search "" >"${tmp_download_dir}/repos.json"
if [[ -n "$last_page_number" ]]; then
	# pagination
	for ((i = 2; i <= "$last_page_number"; i++)); do
		printf "%s:\t%s\n" "fetching page" "$i"
		github_search "$i" >"${tmp_download_dir}/repos${i}.json"
		yq m -a -i -j -P "${tmp_download_dir}/${tmp_plugin_search_result}" "${tmp_download_dir}/repos${i}.json"
		rm -rf "${tmp_download_dir}/repos${i}.json"
	done
fi

total_count=$(yq r "${tmp_download_dir}/${tmp_plugin_search_result}" 'total_count')
items_length=$(yq r --length "${tmp_download_dir}/${tmp_plugin_search_result}" 'items')
printf "%s:%s\n" "[DEBUG] items length" "${items_length}"
printf "%s:%s\n" "[DEBUG] total count" "${total_count}"

if [[ "$total_count" -ne "$items_length" ]]; then
	printf "[ERROR] REST response total_count does not equal merged items array length"
	exit 1
fi

incomplete_results=$(yq r "${tmp_download_dir}/${tmp_plugin_search_result}" 'incomplete_results')
if [[ "$incomplete_results" == "true" ]]; then
	printf "[ERROR] REST response was incomplete"
	exit 1
fi

mkdir -p "plugins"
echo "$csv_header" >"plugins/${all_plugins_output_csv_filename}"
for ((i = 0; i < ${total_count}; i++)); do
	full_name=$(yq r "${tmp_download_dir}/${tmp_plugin_search_result}" "items.[${i}].full_name")
	printf "%s:\t%s\n" "processing #" "${i}"
	if [[ "${skip_list[@]}" =~ "${full_name}" ]]; then
		printf "%s %s\n" "[DEBUG] skipping" "$full_name"
		continue
	fi

	repo_name=$(yq r "${tmp_download_dir}/${tmp_plugin_search_result}" "items.[${i}].name")
	owner_name="${full_name%\/$repo_name}"
	plugin_output_csv_filename="${repo_name#asdf\-}.csv"

	clone_url=$(yq r "${tmp_download_dir}/${tmp_plugin_search_result}" "items[${i}].clone_url")
	git_url=$(yq r "${tmp_download_dir}/${tmp_plugin_search_result}" "items[${i}].git_url")
	ssh_url=$(yq r "${tmp_download_dir}/${tmp_plugin_search_result}" "items[${i}].ssh_url")
	default_branch_name=$(yq r "${tmp_download_dir}/${tmp_plugin_search_result}" "items[${i}].default_branch")
	license=$(yq r "${tmp_download_dir}/${tmp_plugin_search_result}" "items[${i}].license.name")
	build_status=$(github_build_status "$full_name" "$default_branch_name")
	security_policy=$(github_security_policy "$full_name")
	last_updated_at=$(yq r "${tmp_download_dir}/${tmp_plugin_search_result}" "items[${i}].updated_at")
	csv_row=$(printf "%s,%s,%s,%s,%s,%s,%s,%s" "$full_name" "$owner_name" "$repo_name" "$clone_url" "$license" "$build_status" "$security_policy" "$last_updated_at")
	echo "$csv_row" >>"plugins/${all_plugins_output_csv_filename}"
	echo "$csv_row" >>"plugins/${plugin_output_csv_filename}"
	# toml_data=$(printf "%s\\n%s = \"%s\"\\n%s = \"%s\"\\n%s = \"%s\"\\n%s = \"%s\"\\n%s = \"%s\"\\n%s = \"%s\"\\n%s = \"%s\"\\n%s = \"%s\"\\n" "[$repo_name.$owner_name]" "full_name" "$full_name" "owner_name" "$owner_name" "repo_name" "$repo_name" "repository" "$clone_url" "license" "$license" "build_status" "$build_status" "security_policy" "$security_policy" "last_updated_at" "$last_updated_at")
	# echo "$toml_data" >>"plugins/${repo_name#asdf\-}.toml"
done

# TODO:
#	- edge-cases: support prefix + suffix named repos. EG: tox-asdf
#	- gitlab repo support. Currently plugins are sourced from gitlab.
#	- find repos by name? asdf-plugin-* not just GitHub topics
