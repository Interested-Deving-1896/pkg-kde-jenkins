#!/bin/sh

set -x
set -e

cd "${WORKSPACE}"

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

remote_ref="refs/remotes/debian/master"

cd repo
# Check if there is local branch
if [ -z "$(git branch -l)" ]; then
    git checkout --track -b master refs/remotes/debian/master
    exit 0
fi

# The Git Client plugin fails to produce the trigger
git fetch --all --tags
git rev-list --left-right --count HEAD.."${remote_ref}" | \
    read ahead behind

if [ ${behind} -gt 0 ]; then
    git rebase "${remote_ref}"
    exit 0
fi

# Check for new upstream releases

# TODO: Detect native packages
version=$(dpkg-parsechangelog -S version)
epochless_version=${version##*:}
upstream_version=${epochless_version%%-*}
# TODO: What about dfsg tags?
upstream_tag=$(expand_tag "${upstream_version}")
upstream_commit=$(git rev-parse "${upstream_tag}")
if [ -z "${upstream_commit}" ]; then
    echo "Missing upstream tag for version ${upstream_version}" > /dev/stderr
    exit 1
fi

# ignore the "unstable" (*.*.80 or up) releases
release_tag=$(git tag --sort='version:refname' \
    --contains "${upstream_commit}" -l "$(expand_tag '*')" | \
    egrep -v '[89][0-9]+$' | fgrep -v "${upstream_tag}" | tail -1)

if [ -z "${release_tag}" ]; then
    # No new release
    exit 2
fi

if git diff --quiet "${upstream_tag}" "${release_tag}"; then
    # No changes between releases
    exit 3
fi
exit 0
