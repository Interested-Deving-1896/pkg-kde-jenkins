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
upstream_dir="$(pwd)/upstream"

echo "Clean build directory"
rm -rf "${export_dir}"

echo "Add a snapshot changelog entry"
cd "${repo_dir}"
source_name=$(dpkg-parsechangelog -S source)
# TODO: Detect native packages
version=$(dpkg-parsechangelog -S version)
epochless_version=${version##*:}
upstream_version=${epochless_version%%-*}
# TODO: What about dfsg tags?
upstream_tag=$(expand_tag "${upstream_version}")

DCH="gbp dch"
DCH_ARGS="--verbose --snapshot --upstream-tag='$(expand_tag)' --commit"

# ignore the "unstable" (*.*.80 + as well as the rc, alpha and beta tags) releases
release_tag=$(git tag --sort='version:refname' -l "$(expand_tag '*')" | \
    sed -n -r '
/([89][0-9]+|(rc|alpha|beta)[0-9]*)$/d
/^'"${upstream_tag}"'$/,$ {
    /^'"${upstream_tag}"'$/d
    p
}' | tail -1)

if [ -n "${release_tag}" ]; then
    if ! git diff --quiet "${upstream_tag}" "${release_tag}"; then
        new_upstream_release="$(tag_to_version ${release_tag})"
        new_version="${new_upstream_release}-1"
        if [ "${version%%:*}" != "${version}" ]; then
            new_version="${version%%:*}:${new_version}"
        fi
        DCH_ARGS="${DCH_ARGS} --new-version=${new_version}"
        upstream_tag="${release_tag}"
    fi
fi

${DCH} ${DCH_ARGS}

echo "Prepare upstream worktree"

if [ -d "${upstream_dir}" ]; then
    rm -rf "${upstream_dir}"
    git worktree prune
fi
git worktree add "${upstream_dir}" "${upstream_tag}"

echo "Call prepare hooks"

hooks_dir='/srv/pkg-kde-jenkins/hooks/prepare'
if [ -d "${hooks_dir}" ]; then
    run-parts --exit-on-error "${hooks_dir}"
fi

echo "Prepare source package"
cd "${repo_dir}"
gbp buildpackage --git-verbose --git-upstream-tag="$(expand_tag)" \
    --git-export-dir="${export_dir}" --git-overlay -S -us -uc

version=$(dpkg-parsechangelog -S version)
epochless_version=${version##*:}
cd "${export_dir}"
dput -u local "${source_name}_${epochless_version}_source.changes"
