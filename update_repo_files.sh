#!/usr/bin/env bash
# Script to update all the files from the build
# that are checked into the repository (png files, right now)

# bash "strict mode"
set -euo pipefail
IFS=$'\n\t'

# Rebuild everything
npx bazelisk build "...:all"

# cd to the script directory so we can find the built png files
cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")"

# Update the contents of the imgs directory
cp bazel-bin/uml/*.png imgs
