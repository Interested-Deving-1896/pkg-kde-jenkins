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

set -e

run_adt () {
    multi_changes="$export_dir/${source_name}_${epochless_version}_multi.changes"
    adt-run -U "$multi_changes" --output-dir="$export_dir/adt.artifacts" --- lxc -s "adt-$distribution-$arch"
    adt2junit.py -o "$export_dir/adt.xml" "$export_dir/adt.artifacts/log"
}

if [ -z "$arch" ]; then
    # Just a default in case I want to run this without jenkins
    export arch="amd64"
fi
if [ -z "$WORKSPACE" ]; then
    # Just in case we want to run this without jenkins
    export WORKSPACE=$(pwd)
fi
export repo_dir="$WORKSPACE/repo"
export export_dir="$WORKSPACE/build"

echo "Get the information"

cd "$repo_dir"
version=$(dpkg-parsechangelog -S version)
epochless_version=${version##*:}
source_name=$(dpkg-parsechangelog -S source)
source_changes="$export_dir/${source_name}_${epochless_version}_source.changes"
arch_changes="$export_dir/${source_name}_${epochless_version}_$arch.changes"
# TODO: Detect target distribution or use DEP14
distribution=$(dpkg-parsechangelog -S distribution | tr '[:upper:]' '[:lower:]')
if [ "$distribution" = "unreleased" ]; then
    distribution="unstable"
fi

echo "Call pre-test hooks"

cd "$WORKSPACE"
hooks_dir='/srv/pkg-kde-jenkins/hooks/pre-test'
if [ -d "$hooks_dir" ]; then
    run-parts --exit-on-error "$hooks_dir"
fi

echo "Run Lintian"

(lintian -I --pedantic --show-overrides "$source_changes";
 lintian -I --pedantic --show-overrides "$arch_changes") 2>&1 | \
   tee "$export_dir/lintian.log" | lintian2junit.py -o "$export_dir/lintian.xml";

echo "Combine changes file"

cd "$export_dir"

mergechanges -f  "$source_changes" "$arch_changes"
# Fix permissions
find -maxdepth 1 -type f -exec chmod 0644 '{}' '+'

echo "Run autopkgtests"
cd "$repo_dir"
if [ -f debian/tests/control ]; then
    run_adt
fi

echo "Call post-test hooks"

cd "$WORKSPACE"
hooks_dir='/srv/pkg-kde-jenkins/hooks/post-test'
if [ -d "$hooks_dir" ]; then
    run-parts --exit-on-error "$hooks_dir"
fi
