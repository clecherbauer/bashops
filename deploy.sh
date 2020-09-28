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
source "$(dirname "$(readlink -f "$0")")/../custom_vars.sh"
initOldNamespaceVariable

preInitHook

if ! isReviewInstance && deploymentAlreadyExists; then
    echo "Aborting: Deployment with Releasename  \"$(getReleaseName)\" already exists!"
    exit 1
fi

if isReviewInstance; then
    if maxReviewInstancesReached; then
        echo "Aborting: There are too many Review-Instances!"
        exit 1
    fi
    removeOldInstanceIfExists
fi

createNamespace
copyRegistryCredentialsIntoCurrentNamespace
buildAndPublishSecrets
installHelmChart

if isReviewInstance; then
    waitUntilPodDeployed "$_REVIEW_DATABASE_CONTAINER"
fi
waitUntilPodsDeployed

if isStagingInstance; then
    authenticateWithFormAuth "$_CHECK_PROTOCOL" "$(getProjectDeploymentDomain)" "$_STAGING_HTPASSWD_USER" "$_STAGING_HTPASSWD_PASSWORD"
fi
checkPathsForPositiveResponse "$_CHECK_PROTOCOL"

if ! isReviewInstance; then
    patchBlueGreen
    postBlueGreenHook
    removeOldInstanceIfExists
fi
