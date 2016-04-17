#!/bin/bash
# build_build, the main builder part of the build jobs
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

# Just a default in case I want to run this without jenkins
: ${arch="amd64"}
: ${WORKSPACE=$(pwd)}
: ${DISTRIBUTION="unreleased"}
: ${JOB_NAME=$(basename "$WORKSPACE")}
export arch WORKSPACE DISTRIBUTION JOB_NAME

export EXPORT_DIR="$WORKSPACE/build"

if [ "$DISTRIBUTION" = "unreleased" ]; then
    TARGET_DISTRIBUTION="unstable"
else
    TARGET_DISTRIBUTION="$DISTRIBUTION"
fi

export SOURCE_NAME="${JOB_NAME%_*}"

# Clean up old repository
rm -rf "${WORKSPACE}/repo"

packages_for_this_arch () {
    arch="$1"
    dsc_file="$2"

    pkg_arches=$(dscextract "$dsc_file" debian/control | awk '
/^Architecture:/ {
    in_arch=1
    $1=""
}
!/^Architecture/ && !/^\s/ {
    in_arch=0
}
in_arch {
    for (i=1; i <= NF; i++) {
        if ($i) print $i
    }
}' | sort -u)
    for pkg_arch in $pkg_arches; do
        if dpkg-architecture -a"$arch" -i"$pkg_arch"; then
            return 0
        fi
        # We assume we want to build the arch all in amd64
        if [ "$pkg_arch" = "all" ] && [ "$arch" = "amd64" ]; then
            return 0
        fi
    done
    return 1
}

echo "Get the build information"
cd "$EXPORT_DIR"
dsc_file="$(ls ${SOURCE_NAME}_*.dsc)"

# TODO: Hide this in a config file
local_repository='deb [trusted=yes] http://freak.gnuservers.com.ar/~maxy/debian/ '"$TARGET_DISTRIBUTION"' main'

echo "Check it this package is available in the current arch"

if ! packages_for_this_arch "$arch" "$dsc_file"; then
    # Skip this build
    exit 0
fi

echo "Call pre-build hooks"

cd "$WORKSPACE"
hooks_dir='/srv/pkg-kde-jenkins/hooks/pre-build'
if [ -d "$hooks_dir" ]; then
    run-parts --exit-on-error --verbose "$hooks_dir"
fi

echo "Build it"
cd "$EXPORT_DIR"
chroot="$TARGET_DISTRIBUTION-$arch-sbuild"

declare -a SBUILD_ARGS
SBUILD_ARGS=("--dist=$TARGET_DISTRIBUTION" "--arch=$arch" --chroot="$chroot"
             "--verbose")
if [ "$arch" = "amd64" ]; then
    SBUILD_ARGS+="--arch-all"
fi
if [ "$DISTRIBUTION" != "unstable" ]; then
    SBUILD_ARGS+="--extra-repository=$local_repository"
fi

sbuild "$SBUILD_ARGS[@]" "$dsc_file"

echo "Call post-build hooks"

cd "$WORKSPACE"
hooks_dir='/srv/pkg-kde-jenkins/hooks/post-build'
if [ -d "$hooks_dir" ]; then
    run-parts --exit-on-error --verbose "$hooks_dir"
fi

echo "Local upload"
cd "$EXPORT_DIR"

# Fix permissions
find -maxdepth 1 -type f -exec chmod 0644 '{}' '+'
changes_file="$(ls ${SOURCE_NAME}_*_${arch}.changes)"
dput -u local "$changes_file"

# Remove build symlink due to a bug in the clone scm plugin
buildlog_link=$(find -type l -name '*.build')
buildlog_real=$(readlink "$buildlog_link")
rm "$buildlog_link"
mv "$buildlog_real" "$buildlog_link"
