#!/bin/sh

set -e

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
tag_to_version () {
    echo ${1#v}
}

export_dir="$(pwd)/build"
repo_dir="$(pwd)/repo"

echo "Clean build directory"
rm -rf "${export_dir}"

echo "Add a snapshot changelog entry"
cd "${repo_dir}"
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
DCH="gbp dch"
DCH_ARGS="--verbose --snapshot --upstream-tag='$(expand_tag)' --commit"

# ignore the "unstable" (*.*.80 or up) releases
release_tag=$(git tag --sort='version:refname' \
    --contains "${upstream_commit}" -l "$(expand_tag '*')" | \
    egrep -v '([89][0-9]+|(rc|alpha|beta)[0-9]*)$' | fgrep -v "${upstream_tag}" | tail -1)

if [ -n "${release_tag}" ]; then
    if ! git diff --quiet "${upstream_tag}" "${release_tag}"; then
        new_upstream_release="$(tag_to_version ${release_tag})"
        new_version="${new_upstream_release}-1"
        if [ "${version%%:*}" != "${version}" ]; then
            new_version="${version%%:*}:${new_version}"
        fi
        DCH_ARGS="${DCH_ARGS} --new-version='${new_version}'"

    fi
fi

${DCH} ${DCH_ARGS}

echo "Call prepare hooks"

hooks_dir='/srv/pkg-kde-jenkins/hooks/prepare'
if [ -d "${hooks_dir}" ]; then
    run-parts --exit-on-error "${hooks_dir}"
fi

echo "Prepare source package"
cd "${repo_dir}"
gbp buildpackage --git-verbose --git-upstream-tag="$(expand_tag)" \
    --git-export-dir="${export_dir}" --git-overlay -S -us -uc
