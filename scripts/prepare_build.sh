#!/bin/bash
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

# TODO: get the new upstream release with uscan if there is no upstream git
# TODO: build against experimental, do we need to merge experimental into
# unstable? or into local?

set -x
set -e

# Set default values for the common variables if not set
: ${WORKSPACE=$(pwd)}
: ${EXPORT_DIR="$WORKSPACE/build"}
: ${REPO_DIR="$WORKSPACE/repo"}
: ${UPSTREAM_DIR="$WORKSPACE/upstream"}
: ${DISTRIBUTION="unreleased"}
export WORKSPACE EXPORT_DIR REPO_DIR UPSTREAM_DIR DISTRIBUTION

# Split the logic behind the DISTRIBUTION once
case "$DISTRIBUTION" in
    unreleased)
        LOCAL_BRANCH='master'
        TARGET_DISTRIBUTION='unstable'
        UPLOAD_HOST='local'
        FORCE_BUILD=
        PROCESS_NUR='true'
        ;;
    *)
        LOCAL_BRANCH="$DISTRIBUTION"
        TARGET_DISTRIBUTION="$DISTRIBUTION"
        UPLOAD_HOST=
        FORCE_BUILD='true'
        PROCESS_NUR=
        ;;
esac

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
    for branch in master "$LOCAL_BRANCH"; do
        if ! git show-ref --verify --quiet refs/remotes/local/"$branch"; then
            git push --set-upstream local master:"$branch"
        fi
    done
    for branch in pristine-tar gbp_upstream; do
        if ! git show-ref --verify --quiet refs/remotes/local/"$branch"; then
            git checkout --orphan "$branch"
            git rm --ignore-unmatch -rf .
            git commit --allow-empty -m "$branch branch"
            git push --set-upstream local "$branch"
        fi
    done
    # If there is no fetch entry configured for the remote setting it fails,
    # but adding it does the job.
    if ! git remote set-branches local master; then
        git remote set-branches --add local master
    fi
    for branch in "$LOCAL_BRANCH" pristine-tar gbp_upstream; do
        if [ "$branch" != "master" ]; then
            git remote set-branches --add local "$branch"
        fi
    done
    git fetch --all

    echo "Merge debian and local"
    if gif show-ref --verify --quiet refs/remotes/debian/"$LOCAL_BRANCH"; then
        git checkout -B master refs/remotes/debian/"$LOCAL_BRANCH"
    else
        git checkout -B master refs/remotes/debian/master
    fi
    git merge --no-edit refs/remotes/local/master
    for ref in refs/remotes/local/"$LOCAL_BRANCH"
               refs/remotes/debian/unstable
               refs/remotes/local/unstable; do
        if git show-ref --verify --quiet "$ref"; then
            git merge --no-edit "$ref"
        fi
    done
    git branch --set-upstream-to=local/"$LOCAL_BRANCH"

    echo "Update pristine-tar and upstream"
    if git show-ref --verify --quiet refs/remotes/debian/pristine-tar; then
        git checkout -B pristine-tar refs/remotes/debian/pristine-tar
        git merge --no-edit refs/remotes/local/pristine-tar
    else
        git checkout -B pristine-tar refs/remotes/local/pristine-tar
    fi
    git branch --set-upstream-to=local/pristine-tar

    if git show-ref --verify --quiet refs/remotes/debian/upstream; then
        git checkout -B gbp_upstream refs/remotes/debian/upstream
        git merge --no-edit refs/remotes/local/gbp_upstream
    else
        git checkout -B gbp_upstream refs/remotes/local/gbp_upstream
    fi
    git branch --set-upstream-to=local/gbp_upstream

    echo "Config remote"
    if git config --get-all remote.local.push | grep -q 'refs/heads'; then
        git config --unset-all remote.local.push
    fi
    git config --add remote.local.push refs/heads/master:refs/heads/"$LOCAL_BRANCH"
    git config --add remote.local.push refs/heads/pristine-tar
    git config --add remote.local.push refs/heads/gbp_upstream

    echo "Back to master branch"
    git checkout master
}

cd "$REPO_DIR"

prepare_branches

if ! [ -d "$EXPORT_DIR" ]; then
    mkdir "$EXPORT_DIR"
fi

UPSTREAM_VCS_TAG=$(python3 -c '
import configparser
c = configparser.ConfigParser()
c.read("debian/gbp.conf")
print(c.get("import-orig", "upstream-vcs-tag", fallback="v%(version)s"))
')
export UPSTREAM_VCS_TAG

declare -a IMPORT_ORIG_ARGS
# We merge the upstream release (if needed) after calling the hooks
IMPORT_ORIG_ARGS=("--pristine-tar" "--upstream-branch=gbp_upstream"
                  "--no-interactive" "--no-merge")
if git remote | grep -q 'upstream'; then
    IMPORT_ORIG_ARGS+=("--upstream-vcs-tag=$UPSTREAM_VCS_TAG")
fi

MERGE_UPSTREAM=$(python3 -c '
import configparser
c = configparser.ConfigParser()
c.read("debian/gbp.conf")
print(c.getboolean("import-orig", "merge", fallback=""))
')
export MERGE_UPSTREAM

source_name=$(dpkg-parsechangelog -S source)
current_distribution=$(dpkg-parsechangelog -S distribution | tr '[:upper:]' '[:lower:]')
# TODO: Detect native packages and skip the upstream dance
version=$(dpkg-parsechangelog -S version)
epochless_version=${version##*:}
upstream_version=${epochless_version%%-*}
# TODO: What about dfsg changes
upstream_vcs_tag=$(expand_tag "$(version_to_tag "$upstream_version")")
upstream_tag="upstream/$(version_to_tag "$upstream_version")"
current_upstream_tag="$upstream_tag"

DCH="gbp dch"
declare -a DCH_ARGS
DCH_ARGS=("--verbose" "--commit" "--multimaint-merge"
          "--upstream-branch=gbp_upstream")
DCH_ARGS+=("--snapshot")

if [ "kgamma5" = "${JOB_NAME%_*}" ]; then
    versions="[5-9]*"
else
    versions="*"
fi

# ignore the "unstable" (*.*.70 + as well as the rc, alpha and beta tags) releases
release_tag=$(git tag --sort='version:refname' -l "$(expand_tag "$versions")" | \
    sed -n -r '
/([789][0-9]+|(rc|alpha|beta)[0-9]*)$/d
/^'"$upstream_vcs_tag"'$/,$ {
    /^'"$upstream_vcs_tag"'$/d
    p
}' | tail -1)

# Only process new upstream releases in the unreleased jobs
if [ -n "$PROCESS_NUR" ] && [ -n "$release_tag" ]; then
    if ! git diff --quiet "$upstream_vcs_tag" "$release_tag"; then
        new_upstream_release="$(tag_to_version $release_tag)"
        new_version="$new_upstream_release-1"
        if [ "${version%%:*}" != "$version" ]; then
            new_version="${version%%:*}:$new_version"
        fi
        # TODO: This also needs to take into account dsfg versions
        DCH_ARGS+=("--new-version=$new_version")

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

# check it the upstream_tag is present and use uscan if not.
if ! git show-ref --verify --quiet "refs/tags/$current_upstream_tag"; then
    uscan --destdir ../build --dehs --download-current-version > "$EXPORT_DIR/uscan.log"
    downloaded_tarball=$(sed -n -r '
/<target-path>/ {
    s|</?target-path>||g
    p
}' "$EXPORT_DIR/uscan.log")
    gbp import-orig "${IMPORT_ORIG_ARGS[@]}" "$downloaded_tarball"
fi
# if new upstream release, use gbp import-orig to fetch the new tarball
if [ -n "$new_upstream_release" ] && \
    ! git show-ref --verify --quiet "refs/tags/$upstream_tag"; then
    gbp import-orig "${IMPORT_ORIG_ARGS[@]}" --uscan
fi
# Push new upstream tags, if any
git push --follow-tags

echo "Prepare upstream worktree"

if [ -d "$UPSTREAM_DIR" ]; then
    rm -rf "$UPSTREAM_DIR"
    git worktree prune
fi
git worktree add "$UPSTREAM_DIR" "$upstream_tag"

echo "Call prepare hooks"

cd "$WORKSPACE"
export UPSTREAM_TAG="$upstream_tag"
export UPSTREAM_TAG_TEMPLATE="upstream/{version}"

hooks_dir='/srv/pkg-kde-jenkins/hooks/prepare'
if [ -d "$hooks_dir" ]; then
    run-parts --exit-on-error --verbose "$hooks_dir"
fi

declare -a GBP_ARGS
GBP_ARGS=("--git-verbose" "--git-export-dir=$EXPORT_DIR"
          "--git-dist=$TARGET_DISTRIBUTION" "--git-overlay"
          "--git-no-sign-tags")

cd "$REPO_DIR"
changes=""
if [ -n "$new_upstream_release" ] || \
    [ "$(git rev-list --left-right --count HEAD...$debian_tag)" != "0	0" ];
then
    changes='true'
    echo "Add a new changelog entry"
    ${DCH} "${DCH_ARGS[@]}"
fi

if [ -n "$MERGE_UPSTREAM" ]; then
    git merge --no-edit "refs/tags/$upstream_tag"
fi

if [ -n "$changes" ]; then
    echo "Add the tag so the next call to gbp dch has something to compare with"
    gbp buildpackage --git-verbose --git-tag-only
fi

# Push new changelog entry
git push --follow-tags

echo "Prepare source package"
gbp buildpackage "${GBP_ARGS[@]}" \
    -S -us -uc --changes-option="-DDistribution=$TARGET_DISTRIBUTION"

# Push
git push --follow-tags

# Upload source package locally
version=$(dpkg-parsechangelog -S version)
epochless_version=${version##*:}
cd "$EXPORT_DIR"
# Fix permissions, else dput tries to do it remotely, which fails if the file
# is already processed
find -maxdepth 1 -type f -exec chmod 0644 '{}' '+'

# Avoid triggering the build if there are no changes pending
if [ -n "$FORCE_BUILD" ] || [ -n "$changes" ]; then
    if [ -n "$UPLOAD_HOST" ]; then
        # dput -u local "${source_name}_${epochless_version}_source.changes"
        dupload -t "$UPLOAD_HOST" --nomail "${source_name}_${epochless_version}_source.changes"
    fi

    touch "$EXPORT_DIR/trigger_build"
fi
