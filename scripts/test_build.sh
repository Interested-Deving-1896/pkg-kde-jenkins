#!/bin/sh
# single braces reference to the template vars, use double braces to space
# them
set -e

run_adt () {
    multi_changes="$export_dir/${source_name}_${epochless_version}_multi.changes"
    adt-run -U "$multi_changes" --output-dir="$export_dir/adt.artifacts" --- lxc -s "adt-$distribution-$arch"
    adt2junit.py -o "$export_dir/adt.xml" "$export_dir/adt.artifacts/log"
}

if [ -z "$arch" ]; then
    # Just a default in case I want to run this without jenkins
    arch="amd64"
fi
export_dir="$(pwd)/build"
repo_dir="$(pwd)/repo"

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

cd "$export_dir"

echo "Call post-test hooks"

hooks_dir='/srv/pkg-kde-jenkins/hooks/post-test'
if [ -d "$hooks_dir" ]; then
    run-parts --exit-on-error "$hooks_dir"
fi
