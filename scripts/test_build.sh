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
    multi_changes="$(ls "$EXPORT_DIR/$SOURCE_NAME"_*_multi.changes)"
    adt-run -U "$multi_changes" --output-dir="$EXPORT_DIR/adt.artifacts" --- lxc -s "adt-$DISTRIBUTION-$arch"
    /srv/pkg-kde-jenkins/scripts/adt2junit.py -o "$EXPORT_DIR/adt.xml" "$EXPORT_DIR/adt.artifacts/log"
}

# Just a default in case I want to run this without jenkins
: ${arch="amd64"}
: ${WORKSPACE=$(pwd)}
: ${DISTRIBUTION="unreleased"}
: ${JOB_NAME=$(basename "$WORKSPACE")}
export arch WORKSPACE DISTRIBUTION JOB_NAME

export EXPORT_DIR="$WORKSPACE/build"

if [ "$DISTRIBUTION" = "unreleased" ]; then
    DISTRIBUTION="unstable"
fi

export SOURCE_NAME="${JOB_NAME%_*}"

echo "Get the information"

source_changes=$(ls "$EXPORT_DIR/$SOURCE_NAME"_*_source.changes)
arch_changes=$(ls "$EXPORT_DIR/$SOURCE_NAME"_*_"$arch".changes)
export CHANGES_FILE="$arch_changes"

echo "Run Lintian"

(lintian -I --pedantic --show-overrides "$source_changes";
 lintian -I --pedantic --show-overrides "$arch_changes") 2>&1 | \
   tee "$EXPORT_DIR/lintian.log" | \
   /srv/pkg-kde-jenkins/scripts/lintian2junit.py -o "$EXPORT_DIR/lintian.xml";

echo "Combine changes file"

cd "$EXPORT_DIR"

mergechanges -f  "$source_changes" "$arch_changes"
# Fix permissions
find -maxdepth 1 -type f -exec chmod 0644 '{}' '+'

echo "Run autopkgtests"
dsc_file="$(ls "$EXPORT_DIR/$SOURCE_NAME"_*.dsc)"
if dscextract "$dsc_file" debian/tests/control > /dev/null; then
    run_adt
fi

echo "Call test hooks"

cd "$WORKSPACE"
hooks_dir='/srv/pkg-kde-jenkins/hooks/test'
if [ -d "$hooks_dir" ]; then
    run-parts --exit-on-error "$hooks_dir"
fi
