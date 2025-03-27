#!/usr/bin/env bash

warnings=$(mktemp -t heroku-buildpack-bun-XXXX)

fail() {
	meta_time "build-time" "${build_start_time}"
	log_meta_data >>"${BUILDPACK_LOG_FILE}"
	exit 1
}

failure_message() {
	local warn

	warn="$(cat "${warnings}")"

	echo ""
	echo "We're sorry this build is failing!"
	echo ""
	if [[ ${warn} != "" ]]; then
		echo "Some possible problems:"
		echo ""
		echo "${warn}"
	else
		echo "If you're stuck, please submit a ticket so we can help:"
		echo "https://help.heroku.com/"
	fi
	echo ""
	echo "Love,"
	echo "Heroku"
	echo ""
}

fail_invalid_package_json() {
	local is_invalid

	is_invalid=$(is_invalid_json_file "${1-}/package.json")

	if "${is_invalid}"; then
		error "Unable to parse package.json"
		mcount 'failures.parse.package-json'
		meta_set "failure" "invalid-package-json"
		header "Build failed"
		failure_message
		fail
	fi
}

fail_dot_heroku() {
	if [[ -f "${1-}/.heroku" ]]; then
		mcount "failures.dot-heroku"
		meta_set "failure" "dot-heroku"
		header "Build failed"
		warn "The directory .heroku could not be created

			It looks like a .heroku file is checked into this project.
			The Bun buildpack uses the hidden directory .heroku to store
			binaries like the bun runtime. You should remove the
			.heroku file or ignore it by adding it to .slugignore
			"
		fail
	fi
}

fail_node_install() {
	local node_engine
	local log_file="${1}"
	local build_dir="${2}"

	if grep -qi 'Could not find Node version corresponding to version requirement' "${log_file}"; then
		node_engine=$(read_json "${build_dir}/package.json" ".engines.node")
		mcount "failures.invalid-node-version"
		meta_set "failure" "invalid-node-version"
		echo ""
		warn "No matching version found for Node: ${node_engine}

       Heroku supports the latest Stable version of Node.js as well as all
       active LTS (Long-Term-Support) versions, however you have specified
       a version in package.json (${node_engine}) that does not correspond to
       any published version of Node.js.

       You should always specify a Node.js version that matches the runtime
       you're developing and testing with. To find your version locally:

       $ node --version
       v6.11.1

       Use the engines section of your package.json to specify the version of
       Node.js to use on Heroku. Drop the 'v' to save only the version number:

       \"engines\": {
         \"node\": \"6.11.1\"
       }
    " https://help.heroku.com/6235QYN4/
		fail
	fi
}

fail_invalid_semver() {
	local log_file="${1}"
	if grep -qi 'Error: Invalid semantic version' "${log_file}"; then
		mcount "failures.invalid-semver-requirement"
		meta_set "failure" "invalid-semver-requirement"
		echo ""
		warn "Invalid semver requirement

					Bun adheres to semver, the semantic versioning convention
					popularized by GitHub.

					http://semver.org/

					However you have specified a version requirement that is not a valid
					semantic version.
				" https://help.heroku.com/0ZIOF3ST
		fail
	fi
}

log_other_failures() {
	local log_file="${1}"

	if grep -qi "sh: 1: .*: not found" "${log_file}"; then
		mcount "failures.dev-dependency-tool-not-installed"
		meta_set "failure" "dev-dependency-tool-not-installed"
		return 0
	fi

	if grep -qi "Failed at the bcrypt@\d.\d.\d install script" "${log_file}"; then
		mcount "failures.bcrypt-permissions-issue"
		meta_set "failure" "bcrypt-permissions-issue"
		return 0
	fi

	if grep -qi "Cannot read property '0' of undefined" "${log_file}"; then
		mcount "failures.npm-property-zero-issue"
		meta_set "failure" "npm-property-zero-issue"
		return 0
	fi

	# "notarget No matching version found for" = npm
	# "error Couldn't find any versions for" = yarn
	if grep -q -e "notarget No matching version found for" -e "error Couldn't find any versions for" "${log_file}"; then
		mcount "failures.bad-version-for-dependency"
		meta_set "failure" "bad-version-for-dependency"
		return 0
	fi

	if grep -qi "CALL_AND_RETRY_LAST Allocation failed" "${log_file}"; then
		mcount "failures.build-out-of-memory-error"
		meta_set "failure" "build-out-of-memory-error"
		return 0
	fi

	if grep -qi "enoent ENOENT: no such file or directory" "${log_file}"; then
		mcount "failures.npm-enoent"
		meta_set "failure" "npm-enoent"
		return 0
	fi

	if grep -qi "ERROR in [^ ]* from UglifyJs" "${log_file}"; then
		mcount "failures.uglifyjs"
		meta_set "failure" "uglifyjs"
		return 0
	fi

	if grep -qi "Host key verification failed" "${log_file}"; then
		mcount "failures.private-git-dependency-without-auth"
		meta_set "failure" "private-git-dependency-without-auth"
		return 0
	fi

	# same as the next test, but isolate bcyrpt specifically
	if grep -qi "Failed at the bcrypt@\d\.\d\.\d install" "${log_file}"; then
		mcount "failures.bcrypt-failed-to-build"
		meta_set "failure" "bcrypt-failed-to-build"
		return 0
	fi

	if grep -qi "Failed at the [^ ]* install script" "${log_file}"; then
		mcount "failures.dependency-failed-to-build"
		meta_set "failure" "dependency-failed-to-build"
		return 0
	fi

	if grep -qi "Line \d*:  '.*' is not defined" "${log_file}"; then
		mcount "failures.undefined-variable-lint"
		meta_set "failure" "undefined-variable-lint"
		return 0
	fi

	if grep -qiE -e 'npm (ERR!|error) code E404' -e 'error An unexpected error occurred: .* Request failed "404 Not Found"' "${log_file}"; then
		mcount "failures.module-404"
		meta_set "failure" "module-404"

		if grep -qi "flatmap-stream" "${log_file}"; then
			mcount "flatmap-stream-404"
			meta_set "failure" "flatmap-stream-404"
			warn "The flatmap-stream module has been removed from the npm registry

       On November 26th (2018), npm was notified of a malicious package that had made its
       way into event-stream, a popular npm package. After triaging the malware,
       npm responded by removing flatmap-stream and event-stream@3.3.6 from the Registry
       and taking ownership of the event-stream package to prevent further abuse.
      " https://help.heroku.com/4OM7X18J
			fail
		fi

		return 0
	fi

	if grep -qi "sh: 1: cd: can't cd to" "${log_file}"; then
		mcount "failures.cd-command-fail"
		meta_set "failure" "cd-command-fail"
		return 0
	fi

	# Webpack Errors

	if grep -qi "Module not found: Error: Can't resolve" "${log_file}"; then
		mcount "failures.webpack.module-not-found"
		meta_set "failure" "webpack-module-not-found"
		return 0
	fi

	if grep -qi "sass-loader/lib/loader.js:3:14" "${log_file}"; then
		mcount "failures.webpack.sass-loader-error"
		meta_set "failure" "webpack-sass-loader-error"
		return 0
	fi

	# Typescript errors

	if grep -qi "Property '.*' does not exist on type '.*'" "${log_file}"; then
		mcount "failures.typescript.missing-property"
		meta_set "failure" "typescript-missing-property"
		return 0
	fi

	if grep -qi "Property '.*' is private and only accessible within class '.*'" "${log_file}"; then
		mcount "failures.typescript.private-property"
		meta_set "failure" "typescript-private-property"
		return 0
	fi

	if grep -qi "error TS2307: Cannot find module '.*'" "${log_file}"; then
		mcount "failures.typescript.missing-module"
		meta_set "failure" "typescript-missing-module"
		return 0
	fi

	if grep -qi "error TS2688: Cannot find type definition file for '.*'" "${log_file}"; then
		mcount "failures.typescript.missing-type-definition"
		meta_set "failure" "typescript-missing-type-definition"
		return 0
	fi

	# [^/C] means that the error is not for a file expected to be within the project
	# Ex: Error: Cannot find module 'chalk'
	if grep -q "Error: Cannot find module '[^/C\.]" "${log_file}"; then
		mcount "failures.missing-module.npm"
		meta_set "failure" "missing-module-npm"
		return 0
	fi

	# / means that the error is for a file expected within the local project
	# Ex: Error: Cannot find module '/tmp/build_{hash}/...'
	if grep -q "Error: Cannot find module '/" "${log_file}"; then
		mcount "failures.missing-module.local-absolute"
		meta_set "failure" "missing-module-local-absolute"
		return 0
	fi

	# /. means that the error is for a file that's a relative require
	# Ex: Error: Cannot find module './lib/utils'
	if grep -q "Error: Cannot find module '\." "${log_file}"; then
		mcount "failures.missing-module.local-relative"
		meta_set "failure" "missing-module-local-relative"
		return 0
	fi

	# [^/C] means that the error is not for a file expected to be found on a C: drive
	# Ex: Error: Cannot find module 'C:\Users...'
	if grep -q "Error: Cannot find module 'C:" "${log_file}"; then
		mcount "failures.missing-module.local-windows"
		meta_set "failure" "missing-module-local-windows"
		return 0
	fi

	# matches the subsequent lines of a stacktrace
	if grep -q 'at [^ ]* \([^ ]*:\d*\d*\)' "${log_file}"; then
		mcount "failures.unknown-stacktrace"
		meta_set "failure" "unknown-stacktrace"
		return 0
	fi

	# If we've made it this far it's not an error we've added detection for yet
	meta_set "failure" "unknown"
	mcount "failures.unknown"
}

warning() {
	local tip=${1-}
	local url=${2:-https://devcenter.heroku.com/articles/nodejs-support}
	{
		echo "- ${tip}"
		echo "  ${url}"
		echo ""
	} >>"${warnings}"
}

warn() {
	local tip=${1-}
	local url=${2:-https://devcenter.heroku.com/articles/nodejs-support}
	echo " !     ${tip}" || true
	echo "       ${url}" || true
	echo ""
}

warn_prebuilt_modules() {
	local build_dir=${1-}
	if [[ -e "${build_dir}/node_modules" ]]; then
		warning "node_modules checked into source control" "https://devcenter.heroku.com/articles/node-best-practices#only-git-the-important-bits"
		mcount 'warnings.modules.prebuilt'
		meta_set "checked-in-node-modules" "true"
	else
		meta_set "checked-in-node-modules" "false"
	fi
}

warn_missing_package_json() {
	local build_dir=${1-}
	if ! [[ -e "${build_dir}/package.json" ]]; then
		warning "No package.json found"
		mcount 'warnings.no-package'
	fi
}

warn_missing_devdeps() {
	local dev_deps
	local log_file="${1}"
	local build_dir="${2}"

	if grep -qi 'cannot find module' "${log_file}"; then
		warning "A module may be missing from 'dependencies' in package.json" "https://devcenter.heroku.com/articles/troubleshooting-node-deploys#ensure-you-aren-t-relying-on-untracked-dependencies"
		mcount 'warnings.modules.missing'
		if [[ ${NPM_CONFIG_PRODUCTION} == "true" ]]; then
			dev_deps=$(read_json "${build_dir}/package.json" ".devDependencies")
			if [[ ${dev_deps} != "" ]]; then
				warning "This module may be specified in 'devDependencies' instead of 'dependencies'" "https://devcenter.heroku.com/articles/nodejs-support#devdependencies"
				mcount 'warnings.modules.devdeps'
			fi
		fi
	fi
}

warn_no_start() {
	local start_script
	local build_dir="${1}"

	if ! [[ -e "${build_dir}/Procfile" ]]; then
		start_script=$(read_json "${build_dir}/package.json" ".scripts.start")
		if [[ ${start_script} == "" ]]; then
			if ! [[ -e "${build_dir}/server.js" ]]; then
				warn "This app may not specify any way to start a bun process" "https://devcenter.heroku.com/articles/nodejs-support#default-web-process-type"
				mcount 'warnings.unstartable'
			fi
		fi
	fi
}

warn_unmet_dep() {
	local log_file="${1}"

	if grep -qi 'unmet dependency' "${log_file}" || grep -qi 'unmet peer dependency' "${log_file}"; then
		warn "Unmet dependencies don't fail bun install but may cause runtime issues" "https://github.com/npm/npm/issues/7494"
		mcount 'warnings.modules.unmet'
	fi
}
