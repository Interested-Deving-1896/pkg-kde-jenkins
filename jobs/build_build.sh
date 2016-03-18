#!/bin/sh
# single braces reference to the template vars, use double braces to espace
# them
set -x
set -e

export_dir="$(pwd)/build"
repo_dir="$(pwd)/repo"

echo "Get the build information"
cd "$repo_dir"
source_name=$(dpkg-parsechangelog -S source)
version=$(dpkg-parsechangelog -S version)
epochless_version=${{version##*:}}

distribution=$(dpkg-parsechangelog -S distribution | tr '[:upper:]' '[:lower:]')
arch='{arch}'

echo "Call pre-build hooks"
cd "$repo_dir"

hooks_dir='/srv/pkg-kde-jenkins/hooks/pre-build'
if [ -d "$hooks_dir" ]; then
    run-parts --exit-on-error "$hooks_dir"
fi

echo "Build it"
cd "$export_dir"
dsc_file="${{source_name}}_${{epochless_version}}.dsc"
chroot="$distribution-$arch-sbuild"

SBUILD_ARGS="--verbose"
if [ "$arch" = "amd64" ]; then
    SBUILD_ARGS="$SBUILD_ARGS --arch-all"
fi
sbuild --dist="$distribution" --arch="$arch" --chroot="$chroot" $SBUILD_ARGS \
    "$dsc_file"

echo "Call post-build hooks"
cd "$repo_dir"

hooks_dir='/srv/pkg-kde-jenkins/hooks/post-build'
if [ -d "$hooks_dir" ]; then
    run-parts --exit-on-error "$hooks_dir"
fi

echo "Local upload"
cd "$export_dir"

# Fix permissions
find -maxdepth 1 -type f -exec chmod 0644 '{{}}' '+'
changes_file="${{source_name}}_${{epochless_version}}_${{arch}}.changes"
dput -u local "$changes_file"
