#!/bin/bash -e

DOCKER_VERSION="19.03"
DOCKER_SCRIPT_URL="https://releases.rancher.com/install-docker/$DOCKER_VERSION.sh"

curl -LJ --progress-bar $DOCKER_SCRIPT_URL | sh

