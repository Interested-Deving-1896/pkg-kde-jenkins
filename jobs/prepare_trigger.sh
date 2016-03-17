#!/bin/sh

set -x
set -e

if [ ! -d "${WORKSPACE}/repo" ]; then
    # not scm polled, skip
    exit 1
fi

cd "${WORKSPACE}/repo"

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
    exit 1
fi

version=$(dpkg-parsechangelog -S version)
epochless_version=${version##*:}
upstream_version=${epochless_version%%-*}
# TODO: What about dfsg tags?
upstream_tag=$(expand_tag "${upstream_version}")

# ignore the "unstable" (*.*.80 or up) releases
release_tag=$(git tag --sort='version:refname' -l "$(expand_tag '*')" | \
    egrep -v '([89][0-9]+|(rc|alpha|beta)[0-9]*)$' | \
    sed -n "/${upstream_tag}/+1,\$p" | \
    tail -1)

if [ -z "${release_tag}" ]; then
    # No new release
    exit 2
fi

if git diff --quiet "${upstream_tag}" "${release_tag}"; then
    # No changes between releases
    exit 3
fi
exit 0
