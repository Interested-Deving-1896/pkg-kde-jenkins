#!/bin/sh

set -e

delete="false"
no_act="false"

for i in "$@"; do
    case "$i" in
        --delete|-d)
            delete="true"
            shift
            ;;
        --no-act)
            no_act="true"
            shift
            ;;
        *)
            break
            ;;
    esac
done

if ${delete}; then
    if [[ ! -e out ]]; then
        mkdir out
    fi
    find out -printf '%P\n' | \
        xargs /usr/bin/jenkins-job-builder --conf jjb.ini delete
fi

python3 jjb-builder.py -o jobs/projects.yaml \
    --local-vcs "ssh://freak.gnuservers.com.ar/git" \
    --basedir ~/debian \
    @framework.paths @plasma.paths @applications.paths @extras.paths

./test.sh

if ! ${no_act}; then
    jenkins-job-builder --conf jjb.ini update -r jobs
fi
