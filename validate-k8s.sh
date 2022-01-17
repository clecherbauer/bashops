#!/usr/bin/env bash
# shellcheck disable=SC1090
# shellcheck disable=SC2034
# shellcheck disable=SC1091
set -e

_REVIEW_DATABASE_CONTAINER=""
_STAGING_HTPASSWD_USER=""
_STAGING_HTPASSWD_PASSWORD=""
_CHECK_PROTOCOL=""

source "$(dirname "$(readlink -f "$0")")/functions.sh"
source "$(dirname "$(readlink -f "$0")")/../bashops.sh"
initOldNamespaceVariable

preInitHook

createDotEnv
convertDotEnvKeysToArray
validateHelmChart
