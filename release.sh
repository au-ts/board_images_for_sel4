#!/bin/bash

set -ex

if [ "$#" -ne 1 ]; then
    echo "usage: ./release.sh VERSION"
    exit 1
fi

VERSION=$1

nix build .

git tag $VERSION

git push origin tag $VERSION

gh release create $VERSION result/*.tar.gz
