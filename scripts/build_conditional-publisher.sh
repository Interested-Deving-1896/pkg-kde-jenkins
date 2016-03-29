#!/bin/sh
set
set -e
if [ -z "$arch" ]; then
    # Make it easier to test the script even without jenkins
    arch="amd64"
fi
[ "$arch" = "amd64" ]
