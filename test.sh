#!/bin/sh

if [[ ! -e out ]]; then
    mkdir out
fi
rm -f out/*

jenkins-job-builder --conf jjb.ini -r jobs -o out
