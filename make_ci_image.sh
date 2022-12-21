#!/usr/bin/env bash

set -ex

scriptdir=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
distro="${1}"

py_deps=(build-essential libreadline-dev libncursesw5-dev libssl-dev libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev zlib1g-dev)

pyversions=(3.8.16 3.9.16 3.10.9 3.11.1)

c=$(buildah from "debian:${distro}")

buildcmd() {
    buildah run --network host "${c}" -- "$@"
}

buildah config --workingdir /root "${c}"

buildcmd apt-get update --quiet=2

buildcmd apt-get install --yes --quiet=2 git

buildcmd apt-get install --yes --quiet=2 "${py_deps[@]}"

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

buildcmd pip3.10 install hatch
buildcmd mkdir /root/hatch

buildcmd pip3.10 install tox
buildcmd mkdir /root/tox

buildcmd apt-get remove --yes --purge "${py_deps[@]}"
buildcmd apt-get autoremove --yes --purge
buildcmd apt-get clean autoclean
buildcmd sh -c "rm -rf /var/lib/apt/lists/*"
buildcmd rm -rf /root/.cache

# shellcheck disable=SC2154 # image_name set in external environment
if buildah images --quiet "${image_name}"; then
    buildah rmi "${image_name}"
fi
buildah commit --squash --rm "${c}" "${image_name}"
