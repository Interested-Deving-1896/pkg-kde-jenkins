#!/bin/sh

if [ -z "$WORKSPACE" ]; then
    export WORKSPACE="$(pwd)"
fi
export_dir="$WORKSPACE/build"

echo "Clean build directory"

rm -rf "$export_dir"
rm -rf "$WORKSPACE"/arch=*
