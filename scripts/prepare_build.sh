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

set -x
set -e

: ${WORKSPACE=$(pwd)}
: ${EXPORT_DIR="$WORKSPACE/build"}
: ${REPO_DIR="$WORKSPACE/repo"}
: ${UPSTREAM_DIR="$WORKSPACE/upstream"}
: ${DISTRIBUTION="unreleased"}
export WORKSPACE EXPORT_DIR REPO_DIR UPSTREAM_DIR DISTRIBUTION

target_distribution="$DISTRIBUTION"
if [ "$DISTRIBUTION" = "unreleased" ]; then
    target_distribution="unstable"
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
    if [ "$DISTRIBUTION" != 'unreleased' ]; then
        if ! git show-ref --verify --quiet refs/remotes/local/"$DISTRIBUTION"; then
            git push --set-upstream local master:"$DISTRIBUTION"
        fi
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
    # If there is no fetch entry configured for the remote setting it fails,
    # but adding it does the job.
    if ! git remote set-branches local master; then
        git remote set-branches --add local master
    fi
    if [ "$DISTRIBUTION" != "unreleased" ]; then
        git remote set-branches --add local "$DISTRIBUTION"
    fi
    git remote set-branches --add local pristine-tar
    git remote set-branches --add local gbp_upstream
    git fetch --all

    echo "Merge debian and local"
    case "$DISTRIBUTION" in
        unreleased)
            git checkout -B master refs/remotes/debian/master
            git merge --no-edit refs/remotes/local/master
            if git show-ref --verify --quiet refs/remotes/debian/unstable; then
                git merge --no-edit refs/remotes/debian/unstable
            fi
            if git show-ref --verify --quiet refs/remotes/local/unstable; then
                git merge --no-edit refs/remotes/local/unstable
            fi
            git branch --set-upstream-to=local/master
            ;;
        unstable)
            if git show-ref --verify --quiet refs/remotes/debian/unstable; then
                git checkout -B master refs/remotes/debian/unstable
            else
                git checkout -B master refs/remotes/debian/master
            fi
            git merge --no-edit refs/remotes/local/master
            git merge --no-edit refs/remotes/local/unstable
            git branch --set-upstream-to=local/unstable
            ;;
        *)
            if git show-ref --verify --quiet refs/remotes/debian/"$DISTRIBUTION"; then
                git checkout -B master refs/remotes/debian/"$DISTRIBUTION"
            else
                git checkout -B master refs/remotes/debian/master
            fi
            git merge --no-edit refs/remotes/local/master
            git merge --no-edit refs/remotes/local/"$DISTRIBUTION"
            if git show-ref --verify --quiet refs/remotes/local/unstable; then
                git merge --no-edit refs/remotes/local/unstable
            fi
            git branch --set-upstream-to=local/"$DISTRIBUTION"
            ;;
    esac

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
    if [ "$DISTRIBUTION" = "unreleased" ]; then
        git config --add remote.local.push refs/heads/master
    else
        git config --add remote.local.push refs/heads/master:refs/heads/"$DISTRIBUTION"
    fi
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
if [ "$DISTRIBUTION" = "unreleased" ] && [ -n "$release_tag" ]; then
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
          "--git-dist=$target_distribution" "--git-overlay"
          "--git-no-sign-tags")

cd "$REPO_DIR"
changes=""
if [ -n "$new_upstream_release" ] || \
    [ "$DISTRIBUTION" != "$current_distribution" ] || \
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
    -S -us -uc --changes-option="-DDistribution=$target_distribution"

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
if [ -n "$changes" ]; then
    if [ "$DISTRIBUTION" != "unstable" ]; then
        # dput -u local "${source_name}_${epochless_version}_source.changes"
        dupload -t local --nomail "${source_name}_${epochless_version}_source.changes"
    fi

    touch "$EXPORT_DIR/trigger_build"
fi
