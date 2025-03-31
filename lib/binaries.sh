#!/usr/bin/env bash

install_bun() (
	local version="${1-}"
	local dir="${2:?}"

	export BUN_INSTALL="${dir}"
	if [[ -n ${version} ]]; then
		curl -fsSL --retry-connrefused --retry 3 https://bun.sh/install | bash -s "bun-v${version}"
	else
		curl -fsSL --retry-connrefused --retry 3 https://bun.sh/install | bash
	fi
)

suppress_output() {
	local TMP_COMMAND_OUTPUT
	TMP_COMMAND_OUTPUT=$(mktemp)
	trap "rm -rf '${TMP_COMMAND_OUTPUT}' >/dev/null" RETURN

	"$@" >"${TMP_COMMAND_OUTPUT}" 2>&1 || {
		local exit_code="$?"
		cat "${TMP_COMMAND_OUTPUT}"
		return "${exit_code}"
	}
	return 0
}
