#!/usr/bin/env bash

set -ex

scriptdir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
base_image=${1}; shift
image_name=${1}; shift

pyversions=(3.8 3.9 3.10 3.11 3.12)

c=$(buildah from "${base_image}")

buildcmd() {
    buildah run --network host "${c}" -- "$@"
}

buildah config --workingdir /root "${c}"

buildcmd apt-get update --quiet=2

buildcmd apt-get install --yes --quiet=2 git python3

uv_version=$(curl -sL https://api.github.com/repos/astral-sh/uv/releases/latest | jq -r ".tag_name")

curl -sL https://github.com/astral-sh/uv/releases/download/"${uv_version}"/uv-x86_64-unknown-linux-gnu.tar.gz | tar --extract --gzip --strip-components=1
buildah copy "${c}" uv /usr/bin/uv
buildah copy "${c}" "${scriptdir}/uv-config.toml" /uv.toml
buildah config --env UV_CONFIG_FILE=/uv.toml "${c}"

buildcmd uv venv --python python3.11 --no-cache /hatch

buildcmd uv pip install --python /hatch/bin/python3.11 --no-cache hatch hatchling hatch-vcs hatch-fancy-pypi-readme

buildah copy "${c}" "${scriptdir}/hatch-config.toml" /hatch/config.toml
buildah config --env HATCH_CONFIG=/hatch/config.toml "${c}"
buildah config --env HATCH_ENV_TYPE_VIRTUAL_UV_PATH=/usr/bin/uv "${c}"

# Hatch will add the installed Python distributions as PATH
# entries in .profile, but that's not necessary since the PATH
# variable for the entire image will include them
buildcmd cp /root/.profile /root/.profile.save
buildcmd /hatch/bin/hatch python install "${pyversions[@]}"
buildcmd cp /root/.profile.save /root/.profile

new_path=/usr/sbin:/usr/bin:/sbin:/bin:/hatch/bin

for pyversion in "${pyversions[@]}"
do
    new_path="${new_path}:/hatch/python/${pyversion}/python/bin"
done

buildah config --env PATH="${new_path}" "${c}"

buildcmd apt-get clean autoclean
buildcmd sh -c "rm -rf /var/lib/apt/lists/*"

if buildah images --quiet "${image_name}"; then
    buildah rmi "${image_name}"
fi
buildah commit --squash --rm "${c}" "${image_name}"
