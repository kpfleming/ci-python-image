#!/usr/bin/env bash

set -ex

scriptdir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
base_image=${1}; shift
image_name=${1}; shift

pyversions=(3.9 3.10 3.11 3.12 3.13 3.14)

c=$(buildah from "${base_image}")

buildcmd() {
    buildah run --network host "${c}" -- "$@"
}

buildah config --workingdir /root "${c}"

buildcmd apt-get update --quiet=2

buildcmd apt-get install --yes --quiet=2 git python3

uv_version=$(curl -sL https://api.github.com/repos/astral-sh/uv/releases/latest | jq -r ".tag_name")

curl -sL https://github.com/astral-sh/uv/releases/download/"${uv_version}"/uv-aarch64-unknown-linux-gnu.tar.gz | tar --extract --gzip --strip-components=1
buildah copy "${c}" uv /usr/bin/uv
buildah copy "${c}" "${scriptdir}/uv-config.toml" /uv.toml
buildah config --env UV_CONFIG_FILE=/uv.toml "${c}"

buildcmd uv python install "${pyversions[@]}" --preview

buildcmd uv tool install --python python3.13 --no-cache hatch --with hatchling --with hatch-vcs --with hatch-fancy-pypi-readme

buildcmd mkdir /hatch
buildah copy "${c}" "${scriptdir}/hatch-config.toml" /hatch/config.toml
buildah config --env HATCH_CONFIG=/hatch/config.toml "${c}"
buildah config --env HATCH_ENV_TYPE_VIRTUAL_UV_PATH=/usr/bin/uv "${c}"

new_path=/root/.local/bin:/usr/sbin:/usr/bin:/sbin:/bin

buildah config --env PATH="${new_path}" "${c}"

buildcmd apt-get clean autoclean
buildcmd sh -c "rm -rf /var/lib/apt/lists/*"

if buildah images --quiet "${image_name}"; then
    buildah rmi "${image_name}"
fi
buildah commit --squash --rm "${c}" "${image_name}"
