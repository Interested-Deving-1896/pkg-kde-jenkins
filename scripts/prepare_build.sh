#!/bin/sh
# prepare_build, the main builder of the prepare jobs
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

set -x
set -e

# TODO: The upstream tag format should be configurable
# + Add it to the environment vars in the job
if [ -z "$UPSTREAM_VCS_TAG" ]; then
    UPSTREAM_VCS_TAG='v%(version)s'
fi

expand_tag () {
    local version
    if [ $# -lt 1 ]; then
        echo "$UPSTREAM_VCS_TAG"
        return
    fi
    version="$1"
    python -c "print '$UPSTREAM_VCS_TAG' % {'version': '$version'}"
}
tag_to_version () {
    echo "$1" | sed 's/^v//;s|^upstream/||;y/%_/:~/'
}
version_to_tag () {
    echo "$1" | tr ':~' '%_'
}


prepare_branches () {
    echo "Check for missing branches"
    if ! git show-ref --verify --quiet refs/remotes/local/master; then
        git push --set-upstream local master
    fi
    if ! git show-ref --verify --quiet refs/remotes/local/pristine-tar; then
        git checkout --orphan pristine-tar
        git rm --ignore-unmatch -rf .
        git commit --allow-empty -m 'pristine-tar branch'
        git push --set-upstream local pristine-tar
    fi
    if ! git show-ref --verify --quiet refs/remotes/local/gbp_upstream; then
        git checkout --orphan gbp_upstream
        git rm --ignore-unmatch -rf .
        git commit --allow-empty -m 'upstream branch'
        git push --set-upstream local gbp_upstream
    fi
    git remote set-branches --add local master
    git remote set-branches --add local pristine-tar
    git remote set-branches --add local gbp_upstream
    git fetch --all

    echo "Merge debian and local"
    git checkout -B master debian/master
    git merge refs/remotes/local/master
    git branch --set-upstream-to=local/master

    echo "Update pristine-tar and upstream"
    git checkout -B pristine-tar refs/remotes/local/pristine-tar
    git branch --set-upstream-to=local/pristine-tar

    git checkout -B gbp_upstream refs/remotes/local/gbp_upstream
    git branch --set-upstream-to=local/gbp_upstream

    echo "Config remote"
    if ! git config --get-all remote.local.push | grep -q 'refs/heads/master';
    then
        git config --add remote.local.push refs/heads/master
    fi
    if ! git config --get-all remote.local.push | grep -q 'refs/heads/pristine-tar';
    then
        git config --add remote.local.push refs/heads/pristine-tar
    fi
    if ! git config --get-all remote.local.push | grep -q 'refs/heads/gbp_upstream';
    then
        git config --add remote.local.push refs/heads/gbp_upstream
    fi
    echo "Back to master branch"
    git checkout master
}

export_dir="$(pwd)/build"
repo_dir="$(pwd)/repo"
upstream_dir="$(pwd)/upstream"
if [ -z "$WORKSPACE" ]; then
    # Just in case we want to run this without jenkins
    WORKSPACE=$(pwd)
fi

cd "$repo_dir"

prepare_branches

if ! [ -d "$export_dir" ]; then
    mkdir "$export_dir"
fi

echo "Add a snapshot changelog entry"
source_name=$(dpkg-parsechangelog -S source)
# TODO: Detect native packages and skip the upstream dance
version=$(dpkg-parsechangelog -S version)
epochless_version=${version##*:}
upstream_version=${epochless_version%%-*}
# TODO: What about dfsg changes
upstream_vcs_tag=$(expand_tag "$(version_to_tag "$upstream_version")")
upstream_tag="upstream/$(version_to_tag "$upstream_version")"
# TODO: Detect target distribution or use DEP14
distribution=$(dpkg-parsechangelog -S distribution | tr '[:upper:]' '[:lower:]')
if [ "$distribution" = "unreleased" ]; then
    distribution="unstable"
fi

DCH="gbp dch"
DCH_ARGS="--verbose --snapshot --commit"

# ignore the "unstable" (*.*.70 + as well as the rc, alpha and beta tags) releases
release_tag=$(git tag --sort='version:refname' -l "$(expand_tag '*')" | \
    sed -n -r '
/([789][0-9]+|(rc|alpha|beta)[0-9]*)$/d
/^'"$upstream_vcs_tag"'$/,$ {
    /^'"$upstream_vcs_tag"'$/d
    p
}' | tail -1)

if [ -n "$release_tag" ]; then
    if ! git diff --quiet "$upstream_vcs_tag" "$release_tag"; then
        new_upstream_release="$(tag_to_version $release_tag)"
        new_version="$new_upstream_release-1"
        if [ "${version%%:*}" != "$version" ]; then
            new_version="${version%%:*}:$new_version"
        fi
        # TODO: This also needs to take into account dsfg versions
        DCH_ARGS="$DCH_ARGS --new-version=$new_version"

        upstream_vcs_tag="$release_tag"
        new_upstream_version="$(tag_to_version "$release_tag")"
        upstream_tag="upstream/$(version_to_tag "$new_upstream_version")"
    fi
fi

if gbp buildpackage --git-verbose --git-tag-only; then
    echo "Added missing tag"
fi

tag_version=$(echo "$version" | tr ':~' '%_')
debian_tag="debian/$tag_version"

# TODO:
# if new upstream release, use gbp import-orig to fetch the new tarball
# else check it the upstream_tag is present and use uscan if not.
if [ -n "$new_upstream_release" ]; then
    gbp import-orig --uscan --pristine-tar \
        --upstream-vcs-tag="$UPSTREAM_VCS_TAG" \
        --upstream-branch=gbp_upstream \
        --no-merge --no-interactive
elif ! git show-ref --verify --quiet "refs/tags/$upstream_tag"; then
    uscan --destdir ../build --dehs --download-current-version > "$export_dir/uscan.log"
    downloaded_tarball=$(sed -n -r '
/<target-path>/ {
    s|</?target-path>||g
    p
}' "$export_dir/uscan.log")
    gbp import-orig --pristine-tar \
        --upstream-vcs-tag="$UPSTREAM_VCS_TAG" \
        --upstream-branch=gbp_upstream \
        --no-merge --no-interactive "$downloaded_tarball"
fi

echo "Prepare upstream worktree"

if [ -d "${upstream_dir}" ]; then
    rm -rf "${upstream_dir}"
    git worktree prune
fi
git worktree add "$upstream_dir" "$upstream_tag"

echo "Call prepare hooks"

cd "$WORKSPACE"
export UPSTREAM_TAG="${upstream_tag}"
export UPSTREAM_TAG_TEMPLATE="upstream/{version}"

hooks_dir='/srv/pkg-kde-jenkins/hooks/prepare'
if [ -d "${hooks_dir}" ]; then
    run-parts --exit-on-error --verbose "${hooks_dir}"
fi

GBP_ARGS="--git-verbose"

cd "${repo_dir}"
if [ -n "$new_upstream_release" ] || \
    [ "$(git rev-list --left-right --count HEAD...$debian_tag)" != "0	0" ];
then
    echo "Add a new changelog entry"
    ${DCH} ${DCH_ARGS}
    GBP_ARGS="$GBP_ARGS --git-tag"
fi

echo "Prepare source package"
cd "${repo_dir}"
# FIXME: Force changes distribution to unstable, probably a job parameter
distribution="unstable"
gbp buildpackage \
    --git-export-dir="${export_dir}" --git-dist="${distribution}" \
    --git-overlay --git-no-sign-tags ${GBP_ARGS} \
    -S -us -uc --changes-option="-DDistribution=${distribution}"

# Push
git push --follow-tags

# Upload source package locally
version=$(dpkg-parsechangelog -S version)
epochless_version=${version##*:}
cd "${export_dir}"
# Fix permissions, else dput tries to do it remotely, which fails if the file
# is already processed
# find -maxdepth 1 -type f -exec chmod 0644 '{}' '+'
# dput -u local "${source_name}_${epochless_version}_source.changes"
dupload -t local --nomail "${source_name}_${epochless_version}_source.changes"
