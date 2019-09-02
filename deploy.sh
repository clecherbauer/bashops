#!/usr/bin/env bash
# shellcheck disable=SC1090
# shellcheck disable=SC2034
set -e

_REVIEW_DATABASE_CONTAINER=""
_STAGING_HTPASSWD_USER=""
_STAGING_HTPASSWD_PASSWORD=""

source "$(dirname "$(readlink -f "$0")")/functions.sh"
source "$(dirname "$(readlink -f "$0")")/../custom_vars.sh"
initOldNamespaceVariable

if ! isReviewInstance && deploymentAlreadyExists; then
    echo "Aborting: Deployment with Releasename  \"$(getReleaseName)\" already exists!"
    exit 1
fi

if isReviewInstance; then
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
    authenticateWithFormAuth https "$(getProjectDeploymentDomain)" "$_STAGING_HTPASSWD_USER" "$_STAGING_HTPASSWD_PASSWORD"
fi
checkPathsForPositiveResponse https

if ! isReviewInstance; then
    patchBlueGreen
    removeOldInstanceIfExists
fi
