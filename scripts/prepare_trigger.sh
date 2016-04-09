#!/bin/sh
# prepare_trigger script
# Copyright © 2016 Maximiliano Curia <maxy@gnuservers.com.ar>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>.


set -e
set -x
set
if [ -n "${WORKSPACE}" ]; then
    WORKSPACE=$(pwd)
fi

if [ ! -d "${WORKSPACE}/repo" ]; then
    # not scm polled, skip
    exit 1
fi

cd "${WORKSPACE}/repo"
# The jenkins plugin won't fetch the tags by default
git fetch --all --tags

expand_tag () {
    # TODO: The upstream tag format should be configurable
    local upstream_tag_format='v%(version)s'
    local version
    if [ $# -lt 1 ]; then
        echo "${upstream_tag_format}"
        return
    fi
    version="$1"
    python -c "print '${upstream_tag_format}' % {'version': '${version}'}"
}

# Check for new upstream releases

# Detect native packages
if grep -q 'native' debian/source/format; then
    exit 4
fi

version=$(dpkg-parsechangelog -S version)
epochless_version=${version##*:}
upstream_version=${epochless_version%%-*}
# TODO: What about dfsg tags?
upstream_tag=$(expand_tag "${upstream_version}")

# ignore the "unstable" (*.*.70 + as well as the rc, alpha and beta tags) releases
release_tag=$(git tag --sort='version:refname' -l "$(expand_tag '*')" | \
    sed -n -r '
/([789][0-9]+|(rc|alpha|beta)[0-9]*)$/d
/^'"${upstream_tag}"'$/,$ {
    /^'"${upstream_tag}"'$/d
    p
}' | tail -1)


if [ -z "${release_tag}" ]; then
    # No new release
    exit 2
fi

if git diff --quiet "${upstream_tag}" "${release_tag}"; then
    # No changes between releases
    exit 3
fi
exit 0
