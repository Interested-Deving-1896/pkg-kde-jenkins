#!/bin/sh
# test_build, the main builder part of the test jobs
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

# set -e

run_adt () {
    multi_changes="$(ls "$export_dir/${SOURCE_NAME}"_*_multi.changes)"
    adt-run -U "$multi_changes" --output-dir="$export_dir/adt.artifacts" --- lxc -s "adt-$distribution-$arch"
    /srv/pkg-kde-jenkins/scripts/adt2junit.py -o "$export_dir/adt.xml" "$export_dir/adt.artifacts/log"
}

if [ -z "$arch" ]; then
    # Just a default in case I want to run this without jenkins
    export arch="amd64"
fi
if [ -z "$WORKSPACE" ]; then
    # Just in case we want to run this without jenkins
    export WORKSPACE=$(pwd)
fi
export_dir="$WORKSPACE/build"
export EXPORT_DIR="$export_dir"

echo "Get the information"

if [ -x "$JOB_NAME" ]; then
    export JOB_NAME="$(basename "$WORKSPACE")"
fi
export SOURCE_NAME="${JOB_NAME%_*}"
source_changes=$(ls "$export_dir/${SOURCE_NAME}"_*_source.changes)
arch_changes=$(ls "$export_dir/${SOURCE_NAME}"_*_"$arch".changes)
export CHANGES_FILE="$arch_changes"

# TODO: Detect target distribution or use DEP14
distribution=$(dpkg-parsechangelog -S distribution | tr '[:upper:]' '[:lower:]')
if [ "$distribution" = "unreleased" ]; then
    distribution="unstable"
fi

echo "Run Lintian"

(lintian -I --pedantic --show-overrides "$source_changes";
 lintian -I --pedantic --show-overrides "$arch_changes") 2>&1 | \
   tee "$export_dir/lintian.log" | \
   /srv/pkg-kde-jenkins/scripts/lintian2junit.py -o "$export_dir/lintian.xml";

echo "Combine changes file"

cd "$export_dir"

mergechanges -f  "$source_changes" "$arch_changes"
# Fix permissions
find -maxdepth 1 -type f -exec chmod 0644 '{}' '+'

echo "Run autopkgtests"
dsc_file="$(ls "${export_dir}/${SOURCE_NAME}"_*.dsc)"
if dscextract "$dsc_file" debian/tests/control > /dev/null; then
    run_adt
fi

echo "Call test hooks"

cd "$WORKSPACE"
hooks_dir='/srv/pkg-kde-jenkins/hooks/test'
if [ -d "$hooks_dir" ]; then
    run-parts --exit-on-error "$hooks_dir"
fi
