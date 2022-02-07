#!/usr/bin/env bash
# shellcheck disable=SC1090
# shellcheck disable=SC2034
# shellcheck disable=SC1091
set -e

source "$(dirname "$(readlink -f "$0")")/functions.sh"
source "$(dirname "$(readlink -f "$0")")/../bashops.sh"

echo "$SSH_KEY_CONTAINER" > id_rsa
buildAndPushContainerImage "$1"