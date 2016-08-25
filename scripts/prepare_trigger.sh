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

if [ -z "$WORKSPACE" ]; then
    if [ -d "workspace/$JOB_NAME" ]; then
        cd "workspace/$JOB_NAME"
        WORKSPACE=$(pwd)
    else
        exit 1
    fi
fi

if [ ! -d "$WORKSPACE/repo" ]; then
    # not scm polled, skip
    exit 1
fi

cd "${WORKSPACE}/repo"
# The jenkins plugin won't fetch the tags by default
git fetch --all --tags

UPSTREAM_VCS_TAG=$(python3 -c '
import configparser
c = configparser.ConfigParser()
c.read("debian/gbp.conf")
print(c.get("import-orig", "upstream-vcs-tag", fallback="v%(version)s"))
')
export UPSTREAM_VCS_TAG

expand_tag () {
    local VERSION
    if [ $# -lt 1 ]; then
        echo "$UPSTREAM_VCS_TAG"
        return
    fi
    VERSION="$1"
    python -c "print '$UPSTREAM_VCS_TAG' % {'version': '$VERSION'}"
}

# Check for new upstream releases
check_upstream_vcs() {
    # TODO: What about dfsg tags?
    UPSTREAM_TAG=$(expand_tag "${UPSTREAM_VERSION}")

    if [ "kgamma5" = "${JOB_NAME%_*}" ]; then
        VERSIONS="[5-9]*"
    else
        VERSIONS="*"
    fi
    # ignore the "unstable" (*.*.70 + as well as the rc, alpha and beta tags) releases
    RELEASE_TAG=$(git tag --sort='version:refname' -l "$(expand_tag "$VERSIONS")" | \
        sed -n -r '
    /^'"${upstream_tag}"'$/,$ {
        /^'"${upstream_tag}"'$/d
        /([789][0-9]+|(rc|alpha|beta)[0-9]*)$/d
        p
    }' | tail -1)


    if [ -z "${RELEASE_TAG}" ]; then
        # No new release
        exit 2
    fi

    if git diff --quiet "${upstream_tag}" "${RELEASE_TAG}"; then
        # No changes between releases
        exit 3
    fi
    exit 0
}

check_uscan() {
    NEW_UPSTREAM_VERSION=$(uscan --report-status --dehs | sed -n -r '
/<upstream-version>/ {
    s|</?upstream-version>||g
    p
}')

    if dpkg --compare-versions "$NEW_UPSTREAM_VERSION" gt "$UPSTREAM_VERSION";
    then
        exit 0
    fi
    exit 1
}

# Detect native packages
if grep -q 'native' debian/source/format; then
    exit 4
fi

VERSION=$(dpkg-parsechangelog -S version)
EPOCHLESS_VERSION=${VERSION##*:}
UPSTREAM_VERSION=${EPOCHLESS_VERSION%%-*}

if ! (git remote | grep -q 'upstream'); then
    # No upstream remote
    # TODO: use uscan
    check_uscan
fi

check_upstream_vcs

