#!/usr/bin/env bash

create_signature() {
	echo "v2; ${STACK}; $(bun --version); ${PREBUILD}"
}

save_signature() {
	local cache_dir="${1}"
	create_signature > "${cache_dir}/bun/signature"
}

load_signature() {
	local cache_dir="${1}"
	if test -f "${cache_dir}/bun/signature"; then
		cat "${cache_dir}/bun/signature"
	else
		echo ""
	fi
}

get_cache_status() {
	local cache_dir="${1}"
	if ! ${NODE_MODULES_CACHE:-true}; then
		echo "disabled"
	elif ! test -d "${cache_dir}/bun/"; then
		echo "not-found"
	elif [[ "$(create_signature)" != "$(load_signature "${cache_dir}")" ]]; then
		echo "new-signature"
	else
		echo "valid"
	fi
}

get_cache_directories() {
	local build_dir="${1}"
	local dirs1 dirs2
	dirs1=$(read_json "${build_dir}/package.json" ".cacheDirectories | .[]?")
	dirs2=$(read_json "${build_dir}/package.json" ".cache_directories | .[]?")

	if [[ -n "${dirs1}" ]]; then
		echo "${dirs1}"
	else
		echo "${dirs2}"
	fi
}

restore_default_cache_directories() {
	local build_dir="${1:-}"
	local cache_dir="${2:-}"
	local bun_cache_dir="${3:-}"

	if [[ -d "${cache_dir}/bun/cache/bun" ]]; then
		rm -rf "${bun_cache_dir}"
		mv "${cache_dir}/bun/cache/bun" "${bun_cache_dir}"
		echo "- bun cache"
		meta_set "bun_cache" "true"
	else
		echo "- bun cache (not cached - skipping)"

		if [[ -e "${build_dir}/node_modules" ]]; then
			echo "- node_modules is checked into source control and cannot be cached"
		elif [[ -e "${cache_dir}/bun/cache/node_modules" ]]; then
			echo "- node_modules"
			mkdir -p "$(dirname "${build_dir}/node_modules")"
			mv "${cache_dir}/bun/cache/node_modules" "${build_dir}/node_modules"
		else
			echo "- node_modules (not cached - skipping)"
		fi
	fi
}

restore_custom_cache_directories() {
	local cache_directories
	local build_dir="${1:-}"
	local cache_dir="${2:-}"
	mapfile -t cache_directories <<< "${3}"

	echo "Loading ${#cache_directories[@]} from cacheDirectories (package.json):"

	for cachepath in "${cache_directories[@]}"; do
		if [[ -e "${build_dir}/${cachepath}" ]]; then
			echo "- ${cachepath} (exists - skipping)"
		else
			if [[ -e "${cache_dir}/bun/cache/${cachepath}" ]]; then
				echo "- ${cachepath}"
				mkdir -p "$(dirname "${build_dir}/${cachepath}")"
				mv "${cache_dir}/bun/cache/${cachepath}" "${build_dir}/${cachepath}"
			else
				echo "- ${cachepath} (not cached - skipping)"
			fi
		fi
	done
}

clear_cache() {
	local cache_dir="${1}"
	rm -rf "${cache_dir}/bun"
	mkdir -p "${cache_dir}/bun"
	mkdir -p "${cache_dir}/bun/cache"
}

save_default_cache_directories() {
	local build_dir="${1:-}"
	local cache_dir="${2:-}"
	local bun_cache_dir="${3:-}"

	if [[ -d "${bun_cache_dir}" ]]; then
		mv "${bun_cache_dir}" "${cache_dir}/bun/cache/bun"
		echo "- bun cache"
	else
		echo "- bun cache (nothing to cache)"

		if [[ -e "${build_dir}/node_modules" ]]; then
			echo "- node_modules"
			mkdir -p "${cache_dir}/bun/cache/node_modules"
			cp -a "${build_dir}/node_modules" "$(dirname "${cache_dir}/bun/cache/node_modules")"
		else
			mcount "cache.no-node-modules"
			echo "- node_modules (nothing to cache)"
		fi
	fi

	meta_set "bun-custom-cache-dirs" "false"
}

save_custom_cache_directories() {
	local cache_directories
	local build_dir="${1:-}"
	local cache_dir="${2:-}"
	mapfile -t cache_directories <<< "${3}"

	echo "Saving ${#cache_directories[@]} cacheDirectories (package.json):"

	for cachepath in "${cache_directories[@]}"; do
		if [[ -e "${build_dir}/${cachepath}" ]]; then
			echo "- ${cachepath}"
			mkdir -p "${cache_dir}/bun/cache/${cachepath}"
			cp -a "${build_dir}/${cachepath}" "$(dirname "${cache_dir}/bun/cache/${cachepath}")"
		else
			echo "- ${cachepath} (nothing to cache)"
		fi
	done

	meta_set "bun-custom-cache-dirs" "true"
}

is_int() {
	case ${1#[-+]} in
		'' | *[!0-9]*) return 1;;
		*) return 0;;
	esac
}
