#!/usr/bin/env bash

set -ex

scriptdir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
base_image=${1}; shift
image_name=${1}; shift

# needed to build wheels that use native code
py_run_deps=(build-essential libc6-dev libffi-dev)

py_build_deps=(libreadline-dev libncursesw5-dev libssl-dev libsqlite3-dev tk-dev libgdbm-dev libbz2-dev zlib1g-dev)

pyversions=(3.8.18 3.9.18 3.10.13 3.11.5 3.12.0rc1)

c=$(buildah from "${base_image}")

buildcmd() {
    buildah run --network host "${c}" -- "$@"
}

buildah config --workingdir /root "${c}"

buildcmd apt-get update --quiet=2

buildcmd apt-get install --yes --quiet=2 git

buildcmd apt-get install --yes --quiet=2 "${py_run_deps[@]}" "${py_build_deps[@]}"

for pyver in "${pyversions[@]}"; do
    # shellcheck disable=SC2001
    # strip off any beta or rc suffix to get version directory
    verdir=$(echo "${pyver}" | sed -e 's/^\([[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*\).*$/\1/')
    wget --quiet --output-document - "https://www.python.org/ftp/python/${verdir}/Python-${pyver}.tgz" | tar --extract --gzip
    buildah run --network host --volume "${scriptdir}:/scriptdir" --volume "$(pwd)/Python-${pyver}:/${pyver}" "${c}" -- /scriptdir/pybuild.sh "/${pyver}"
    rm -rf "Python-${pyver}"
done

buildcmd sh -c "rm -rf /usr/local/bin/python3.?m*"
buildcmd sh -c "rm -rf /usr/local/bin/python3.??m*"

buildcmd pip3.11 install hatch hatch-fancy-pypi-readme
buildcmd mkdir /hatch
buildah copy "${c}" "${scriptdir}/hatch-config.toml" /hatch/config.toml
buildah config --env HATCH_CONFIG=/hatch/config.toml "${c}"

buildcmd pip3.11 install tox
buildcmd mkdir /tox
buildah copy "${c}" "${scriptdir}/tox-config.ini" /tox/config.ini
buildah config --env TOX_USER_CONFIG_FILE=/tox/config.ini "${c}"

buildcmd apt-get remove --yes --purge "${py_build_deps[@]}"
buildcmd apt-get autoremove --yes --purge
buildcmd apt-get clean autoclean
buildcmd sh -c "rm -rf /var/lib/apt/lists/*"
buildcmd rm -rf /root/.cache

if buildah images --quiet "${image_name}"; then
    buildah rmi "${image_name}"
fi
buildah commit --squash --rm "${c}" "${image_name}"
