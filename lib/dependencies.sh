#!/usr/bin/env bash

measure_size() {
	(du -s node_modules 2>/dev/null || echo 0) | awk '{print $1}'
}

list_dependencies() {
	local build_dir="${1}"

	cd "${build_dir}" || return
	(bun pm ls | tail -n +2 || true) 2>/dev/null
}

run_if_present() {
	local build_dir="${1-}"
	local script_name="${2-}"
	local has_script_name

	has_script_name=$(has_script "${build_dir}/package.json" "${script_name}")

	if [[ ${has_script_name} == "true" ]]; then
		echo "Running ${script_name}"
		monitor "${script_name}-script" bun run --bun --if-present "${script_name}"
	fi
}

run_build_if_present() {
	local build_dir="${1-}"
	local script_name="${2-}"
	local has_script_name
	local script

	has_script_name=$(has_script "${build_dir}/package.json" "${script_name}")
	script=$(read_json "${build_dir}/package.json" ".scripts[\"${script_name}\"]")

	if [[ ${script} == "ng build" ]]; then
		warn '"ng build" detected as build script. We recommend you use `ng build --prod`.'
	fi

	if [[ ${has_script_name} == "true" ]]; then
		echo "Running ${script_name}"
		monitor "${script_name}-script" bun run --bun --if-present "${script_name}"
	fi
}

run_prebuild_script() {
	local build_dir="${1-}"
	local has_heroku_prebuild_script

	has_heroku_prebuild_script=$(has_script "${build_dir}/package.json" "heroku-prebuild")

	if [[ ${has_heroku_prebuild_script} == "true" ]]; then
		mcount "script.heroku-prebuild"
		header "Prebuild"
		run_if_present "${build_dir}" 'heroku-prebuild'
	fi
}

run_build_script() {
	local build_dir="${1-}"
	local has_build_script has_heroku_build_script

	has_build_script=$(has_script "${build_dir}/package.json" "build")
	has_heroku_build_script=$(has_script "${build_dir}/package.json" "heroku-postbuild")
	if [[ ${has_heroku_build_script} == "true" ]] && [[ ${has_build_script} == "true" ]]; then
		echo 'Detected both "build" and "heroku-postbuild" scripts'
		mcount "scripts.heroku-postbuild-and-build"
		run_if_present "${build_dir}" 'heroku-postbuild'
	elif [[ ${has_heroku_build_script} == "true" ]]; then
		mcount "scripts.heroku-postbuild"
		run_if_present "${build_dir}" 'heroku-postbuild'
	elif [[ ${has_build_script} == "true" ]]; then
		mcount "scripts.build"
		run_build_if_present "${build_dir}" 'build'
	fi
}

run_cleanup_script() {
	local build_dir="${1-}"
	local has_heroku_cleanup_script

	has_heroku_cleanup_script=$(has_script "${build_dir}/package.json" "heroku-cleanup")

	if [[ ${has_heroku_cleanup_script} == "true" ]]; then
		mcount "script.heroku-cleanup"
		header "Cleanup"
		run_if_present "${build_dir}" 'heroku-cleanup'
	fi
}

log_build_scripts() {
	local build_dir="${1-}"

	meta_set "build-script" "$(read_json "${build_dir}/package.json" '.scripts["build"]')"
	meta_set "postinstall-script" "$(read_json "${build_dir}/package.json" '.scripts["postinstall"]')"
	meta_set "heroku-prebuild-script" "$(read_json "${build_dir}/package.json" '.scripts["heroku-prebuild"]')"
	meta_set "heroku-postbuild-script" "$(read_json "${build_dir}/package.json" '.scripts["heroku-postbuild"]')"
}

bun_install() {
	local build_dir="${1-}"

	cd "${build_dir}" || return
	echo "Running 'bun install'"
	monitor "bun-install" bun install --frozen-lockfile 2>&1
}

bun_prune_devdependencies() {
	local build_dir="${1-}"

	cd "${build_dir}" || return

	if [[ ${BUN_ENV} != "production" ]]; then
		echo "Skipping because BUN_ENV is not 'production'"
		meta_set "skipped-prune" "true"
		return 0
	elif [[ ${BUN_SKIP_PRUNING} == "true" ]]; then
		echo "Skipping because BUN_SKIP_PRUNING is '${BUN_SKIP_PRUNING}'"
		meta_set "skipped-prune" "true"
		return 0
	fi

	monitor "bun-prune" bun install -p --frozen-lockfile --ignore-scripts 2>&1
	meta_set "skipped-prune" "false"
}
