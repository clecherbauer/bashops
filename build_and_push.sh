#!/usr/bin/env bash
# shellcheck disable=SC1090
# shellcheck disable=SC2034
# shellcheck disable=SC1091
set -e

source "$(dirname "$(readlink -f "$0")")/functions.sh"
source "$(dirname "$(readlink -f "$0")")/../custom_vars.sh"

buildAndPushContainerImages