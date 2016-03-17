#!/bin/sh

python3 jjb-builder.py -o jobs/projects.yaml @framework.paths

find out -printf '%P\n' | \
    xargs /usr/bin/jenkins-job-builder --conf jjb.ini delete
jenkins-job-builder --conf jjb.ini update -r jobs
