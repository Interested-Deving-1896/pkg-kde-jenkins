#!/bin/sh

if [[ ! -e out ]]; then
    mkdir out
fi
rm -f out/*

python3-jenkins-jobs --conf jjb.ini test -r jobs -o out
