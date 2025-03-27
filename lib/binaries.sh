#!/usr/bin/env bash

install_bun() (
	local version="${1-}"
	local dir="${2:?}"

	export BUN_INSTALL="${dir}"
	if [[ -n "${version}" ]]; then
		curl -fsSL --retry-connrefused --retry 3 https://bun.sh/install | bash -s "bun-v${version}"
	else
		curl -fsSL --retry-connrefused --retry 3 https://bun.sh/install | bash
	fi
)

install_nodejs() {
	local version="${1-}"
	local dir="${2:?}"
	local code resolve_result

	if [[ -z "${version}" ]]; then
		version="22.x"
	fi

	if [[ -n "${NODE_BINARY_URL}" ]]; then
		url="${NODE_BINARY_URL}"
		echo "Downloading and installing node from ${url}"
	else
		echo "Resolving node version ${version}..."
		resolve_result=$(resolve node "${version}" || echo "failed")

		read -r number url < <(echo "${resolve_result}")

		if [[ "${resolve_result}" == "failed" ]]; then
			fail_bin_install node "${version}"
		fi

		echo "Downloading and installing node ${number}..."

		if [[ "${number}" == "22.5.0" ]]; then
			warn_about_node_version_22_5_0
		fi
	fi

	code=$(curl "${url}" -L --silent --fail --retry 5 --retry-max-time 15 --retry-connrefused --connect-timeout 5 -o /tmp/node.tar.gz --write-out "%{http_code}")

	if [[  "${code}" != "200"  ]]; then
		echo "Unable to download node: ${code}" && false
	fi
	rm -rf "${dir:?}"/*
	tar xzf /tmp/node.tar.gz --strip-components 1 -C "${dir}"
	chmod +x "${dir}"/bin/*
}

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
