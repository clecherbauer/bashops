#!/usr/bin/env bash
# shellcheck disable=SC2001
# shellcheck disable=SC2034
# shellcheck disable=SC2086
# shellcheck disable=SC2044

set -e

_TRUE_VALUE=0
_FALSE_VALUE=1
_GREEN_BLUE_TEMP_FILE="ingress-blue.yaml"
_BLUE_GREEN_TEMP_FILE="ingress-green.yaml"
_BLUE_GREEN_MODE=service #(service|ingress)
_BLUE_GREEN_PATCHABLE_OBJECT="none"  #(service or ingress name)
_PRODUCTION_INSTANCES="none"
_STAGING_INSTANCES="none"
_REVIEW_DATABASE_CONTAINER="database"

_PROJECT_PREFIX="dummy"
_SECRETS_NAME="$_PROJECT_PREFIX-secrets"

# branch-based _TOPLEVEL_DOMAIN:
# _TOPLEVEL_DOMAIN_MASTER=dummy.ch
# _TOPLEVEL_DOMAIN_XYZ=fool.ch
# if not set it falls back to _TOPLEVEL_DOMAIN
_TOPLEVEL_DOMAIN="dummy.ch"

# branch-based _SUB_DOMAIN_:f
# _SUB_DOMAIN_MASTER=www
# _SUB_DOMAIN_XYZ=test
# if not set it falls back to nothing for production instances and to CI_COMMIT_REF_SLUG in staging instancess
_SUB_DOMAIN_=""

# branch-based _DEPLOYMENT_TOPLEVEL_DOMAIN:
# _DEPLOYMENT_TOPLEVEL_DOMAIN_MASTER=dummy.ch
# _DEPLOYMENT_TOPLEVEL_DOMAIN_XYZ=fool.ch
# if not set it falls back to _DEPLOYMENT_TOPLEVEL_DOMAIN
_DEPLOYMENT_TOPLEVEL_DOMAIN="deployment.dummy.cloud.selbstmade.ch"

_REVIEW_CLUSTER_TOPLEVEL_DOMAIN="dummy.selbstmade.ch"

# ssh user
_REVIEW_CLUSTER_USER="selbstmade"

# branch-based _PRODUCTION_PORT:
# _PRODUCTION_PORT_MASTER="30080"
# _PRODUCTION_PORT_XYZ="30082"
# if not set it falls back to _PRODUCTION_PORT
_PRODUCTION_PORT="30080"

# branch-based _DEPLOYMENT_PORT:
# _DEPLOYMENT_PORT_MASTER="30080"
# _DEPLOYMENT_PORT_XYZ="30082"
# if not set it falls back to _DEPLOYMENT_PORT
_DEPLOYMENT_PORT="30081"

_DOCKER_REGISTRY="registry.gitlab.com"
_CONTAINERS_TO_BUILD="application"
_CONTAINERS_TO_RUN="application"

_STAGING_HTPASSWD_USER="dummy"
_STAGING_HTPASSWD_PASSWORD="dummy"
_TIMEOUT=1000

_PATHS_TO_CHECK="/health"
_CHECK_PROTOCOL="https"

WEB_ROOT=""
_OLD_NAMESPACE=""

#Define used Gitlab-CI Variables if not set
if [ -z "$CI_COMMIT_REF_SLUG" ]; then
    CI_COMMIT_REF_SLUG=""
fi
if [ -z "$CI_COMMIT_SHA" ]; then
    CI_COMMIT_REF_SLUG=""
fi
if [ -z "$CI_SHELL_DEBUG" ]; then
    CI_SHELL_DEBUG=""
fi
if [ -z "$CI_PROJECT_PATH" ]; then
    CI_PROJECT_PATH=""
fi
if [ -z "$VERSION" ]; then
    VERSION=""
fi

#Variables loaded from .env in gitlab-ci-secrets and used during build
_BUILD_VARIABLES_FROM_DOTENV=""

# Variables loaded from Environment with CI_COMMIT_REF_SLUG as postfix
# e.g.: for variable TESTVAR in master define TESTVAR_MASTER in gitlab-ci-secrets an add TESTVAR to _BUILD_VARIABLES_DYNAMIC"
_BUILD_VARIABLES_DYNAMIC=""

function writeDockerBuildEnv {
    exitIfRequiredVariablesAreNotSet "CI_COMMIT_REF_SLUG CI_COMMIT_SHA CI_PROJECT_PATH"
    echo "CI_COMMIT_REF_SLUG=$CI_COMMIT_REF_SLUG" > .docker_build_env
    # shellcheck disable=SC2129
    echo "CI_COMMIT_SHA=$CI_COMMIT_SHA" >> .docker_build_env
    echo "CI_PROJECT_PATH=$CI_PROJECT_PATH" >> .docker_build_env

    TAG="$(git tag -l --points-at HEAD)"

    if [ -n "$TAG" ];
      then
        echo "VERSION=$CI_COMMIT_REF_SLUG-$TAG" >> .docker_build_env
      else
        echo "VERSION=$CI_COMMIT_REF_SLUG-$CI_COMMIT_SHA" >> .docker_build_env
    fi


    if [ -n "$_BUILD_VARIABLES_FROM_DOTENV" ]; then
      DOTENV_VARIABLE_NAME="DOTENV_REVIEW"
      if isProductionInstance || isStagingInstance; then
          DOTENV_VARIABLE_NAME="DOTENV_"$(echo "$CI_COMMIT_REF_SLUG" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
      fi

      exitIfRequiredVariablesAreNotSet "$DOTENV_VARIABLE_NAME"
      for _BUILD_VARIABLE in $_BUILD_VARIABLES_FROM_DOTENV; do
        for _DOTENV_VARIABLE in ${!DOTENV_VARIABLE_NAME}; do
          if [[ $_DOTENV_VARIABLE = "$_BUILD_VARIABLE="* ]]; then
            echo "$_DOTENV_VARIABLE" >> .docker_build_env
          fi
        done
      done
    fi

    if [ -n "$_BUILD_VARIABLES_DYNAMIC" ]; then
      for _BUILD_VARIABLE in $_BUILD_VARIABLES_DYNAMIC; do
        _DYNAMIC_VARIABLE_NAME=$_BUILD_VARIABLE"_"$(echo "$CI_COMMIT_REF_SLUG" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        if [ -n "${!_DYNAMIC_VARIABLE_NAME}" ]; then
          echo "$_BUILD_VARIABLE=${!_DYNAMIC_VARIABLE_NAME}" >> .docker_build_env
        fi
      done
    fi
}


function readVariablesFromGitlab {
    echo ">>> Searching for .docker_build_env"
    while IFS= read -r -d '' FILE
    do
        echo ">>> Reading Docker Environment from $FILE ..."
        # shellcheck disable=SC2046
        export $(grep -E -v '^#' "$FILE" | xargs)
    done <   <(find / -name "*.docker_build_env" -print0)

    if [ -z "$CI_COMMIT_REF_SLUG" ]; then
        export CI_COMMIT_REF_SLUG=local-dev
    fi
}

function getProjectPrefix() {
    echo "$_PROJECT_PREFIX"
}

function getReleaseName() {
    exitIfRequiredVariablesAreNotSet "_PROJECT_PREFIX"
    echo "$_PROJECT_PREFIX-$(getProjectNamespace)"
}

function exitIfRequiredVariablesAreNotSet {
    for REQUIRED_VARIABLE in $1; do
      if [ -z "${!REQUIRED_VARIABLE}" ]; then
        echo "ERROR: Required variable $REQUIRED_VARIABLE is empty or not set!"
        exit 1
      fi
    done
}

function getProjectNamespace() {
    exitIfRequiredVariablesAreNotSet "CI_COMMIT_REF_SLUG CI_COMMIT_SHA"
    echo "$CI_COMMIT_REF_SLUG-$(echo "$CI_COMMIT_SHA" | cut -c1-9)"
}

function initOldNamespaceVariable() {
    exitIfRequiredVariablesAreNotSet "CI_COMMIT_REF_SLUG"
    if [ -z "$_OLD_NAMESPACE" ]; then
        _OLD_NAMESPACE="$(kubectl get namespace | grep "$CI_COMMIT_REF_SLUG" | cut -d ' ' -f1)"
        if [ -z "$_OLD_NAMESPACE" ]; then
            _OLD_NAMESPACE="false"
        fi
        export _OLD_NAMESPACE
    fi
}

function getOldInstanceNamespace() {
    exitIfRequiredVariablesAreNotSet "_OLD_NAMESPACE"
    if [ "$_OLD_NAMESPACE" == "false" ]; then
        echo ""
        return
    fi

    echo "$_OLD_NAMESPACE"
}

function countNamespacesWithCurrentRefSlug() {
    exitIfRequiredVariablesAreNotSet "CI_COMMIT_REF_SLUG"
    kubectl get namespace | grep -c "$CI_COMMIT_REF_SLUG"
}

function getProjectEnvironment() {
    if isReviewInstance; then
        echo "dev"
        return
    fi

    echo "prod"
    return
}

function getProjectProductionDomain() {
    exitIfRequiredVariablesAreNotSet "CI_COMMIT_REF_SLUG _TOPLEVEL_DOMAIN _REVIEW_CLUSTER_TOPLEVEL_DOMAIN"
    _SUB_DOMAIN="$(getDynamicVariable "_SUB_DOMAIN" "$CI_COMMIT_REF_SLUG")"
    _TOPLEVEL_DOMAIN="$_TOPLEVEL_DOMAIN"
    _DYNAMIC_TOPLEVEL_DOMAIN="$(getDynamicVariable "_TOPLEVEL_DOMAIN" "$CI_COMMIT_REF_SLUG")"
    if [ -n "$_DYNAMIC_TOPLEVEL_DOMAIN" ]; then
        _TOPLEVEL_DOMAIN="$_DYNAMIC_TOPLEVEL_DOMAIN"
    fi

    if isProductionInstance || isStagingInstance; then
        if [ -z "$_SUB_DOMAIN" ]; then
            echo "$_TOPLEVEL_DOMAIN"
            return
        fi
        echo "$_SUB_DOMAIN.$_TOPLEVEL_DOMAIN"
        return
    fi

    echo "$CI_COMMIT_REF_SLUG.$_REVIEW_CLUSTER_TOPLEVEL_DOMAIN"
    return
}

function getProjectDeploymentDomain() {
    exitIfRequiredVariablesAreNotSet "CI_COMMIT_REF_SLUG _DEPLOYMENT_TOPLEVEL_DOMAIN"

    if isReviewInstance; then
        getProjectProductionDomain
        return
    else
        _TOPLEVEL_DOMAIN="$_DEPLOYMENT_TOPLEVEL_DOMAIN"
        _DYNAMIC_TOPLEVEL_DOMAIN="$(getDynamicVariable "_DEPLOYMENT_TOPLEVEL_DOMAIN" "$CI_COMMIT_REF_SLUG")"
        if [ -n "$_DYNAMIC_TOPLEVEL_DOMAIN" ]; then
            _TOPLEVEL_DOMAIN="$_DYNAMIC_TOPLEVEL_DOMAIN"
        fi
        echo "$CI_COMMIT_REF_SLUG.$_TOPLEVEL_DOMAIN"
        return
    fi
}

function getProjectProductionPort() {
    getDynamicVariableOrFallback "_PRODUCTION_PORT" "$CI_COMMIT_REF_SLUG"
}

function getProjectDeploymentPort() {
    getDynamicVariableOrFallback "_DEPLOYMENT_PORT" "$CI_COMMIT_REF_SLUG"
}

function isProductionInstance() {
    exitIfRequiredVariablesAreNotSet "CI_COMMIT_REF_SLUG"
    if [[ "$_PRODUCTION_INSTANCES" = *"$CI_COMMIT_REF_SLUG"* ]]; then
        return $_TRUE_VALUE
    fi

    return $_FALSE_VALUE
}

function isStagingInstance() {
    exitIfRequiredVariablesAreNotSet "CI_COMMIT_REF_SLUG"
    if [[ "$_STAGING_INSTANCES" = *"$CI_COMMIT_REF_SLUG"* ]]; then
        return $_TRUE_VALUE
    fi

    return $_FALSE_VALUE
}

function isLocalDevInstance() {
    exitIfRequiredVariablesAreNotSet "CI_COMMIT_REF_SLUG"
    if [ "$CI_COMMIT_REF_SLUG" = "local-dev" ]; then
        return $_TRUE_VALUE
    fi

    return $_FALSE_VALUE
}

function isReviewInstance() {
    if ! isProductionInstance && ! isStagingInstance && ! isLocalDevInstance; then
        return $_TRUE_VALUE
    fi

    return $_FALSE_VALUE
}

function copyFileToFirstBootD {
    FILE_PATH=$1
    ITERATION=$2
    exitIfRequiredVariablesAreNotSet "FILE_PATH ITERATION"
    FILENAME="$(basename "$FILE_PATH")"
    echo ">>> Copy $FILENAME to /usr/local/bin/firstboot.d/ ..."
     if  [ ! -f "$FILE_PATH" ]; then
        echo "$FILE_PATH does not exist!"
        exit 1
     fi

    cp "$FILE_PATH" "/usr/local/bin/firstboot.d/$ITERATION$FILENAME"
}

function modifyWwwDataUser {
    if isLocalDevInstance; then
        echo ">>> Applying moduser.sh as www-data ..."
        overrideUserIdWithIdFromDotEnv www-data
    fi
}

function isNumeric() {
    [[ "$1" =~ ^-?[0-9]+$ ]]
}

function userExists() {
    id "$1" > /dev/null 2>&1
}

function overrideUserIdWithIdFromDotEnv() {
    usage() {
        echo "Set a new user id and group id for a user." \
             "Usage: ${FUNCNAME[1]} username"
        [[ "$1" != "" ]] && echo "- ERROR: $1"
        exit 1
    }
    USERNAME="$1"
    NEWUID=$(grep '^LOCAL_UID=' .env | sed 's/LOCAL_UID=//')
    NEWGID=$(grep '^LOCAL_GID=' .env | sed 's/LOCAL_GID=//')
    userExists "$USERNAME" || usage "User does not exist: '$USERNAME'"
    isNumeric "$NEWUID" || usage "LOCAL_UID should be numeric: '$NEWUID'"
    isNumeric "$NEWGID" || usage "LOCAL_GID should be numeric: '$NEWGID'"
    GROUPNAME=$(id -gn "$USERNAME")
    OLDUID=$(id -u "$USERNAME")
    OLDGID=$(id -g "$USERNAME")
    # inspired by https://muffinresearch.co.uk/linux-changing-uids-and-gids-for-user/
    if [[ "$NEWUID" != "$OLDUID" ]]; then
        echo "Replacing id for $USERNAME: $OLDUID:$OLDGID -> $NEWUID:$NEWGID ..."
        #workarround fo bug: https://github.com/golang/go/issues/13548
        userdel "$USERNAME"
        useradd "$USERNAME" --no-log-init -u "$NEWUID"
        groupmod -g "$NEWGID" "$GROUPNAME"
        find / -not -path "/sys/kernel/*" -ignore_readdir_race -user "$OLDUID" -exec chown -h "$NEWUID" {} \;
        find / -not -path "/sys/kernel/*" -ignore_readdir_race -group "$OLDGID" -exec chgrp -h "$NEWGID" {} \;
        usermod -g "$NEWGID" "$USERNAME"
        echo "Done. $(id "$USERNAME")"
    fi
}

function installSSHKey {
    SOURCE_PATH=$1
    exitIfRequiredVariablesAreNotSet "SOURCE_PATH"
    if ! isLocalDevInstance; then
        echo ">>> Installing ssh-key ..."

        [[ -d /root/.ssh/ ]] || mkdir /root/.ssh/
        mv "$SOURCE_PATH" /root/.ssh/id_rsa
        chmod -R 600 /root/.ssh
        ssh-keygen -y -f /root/.ssh/id_rsa > /root/.ssh/id_rsa.pub
    fi
}

function setPermissions {
    exitIfRequiredVariablesAreNotSet "WEB_ROOT"
    echo ">>> Setting permissions for $WEB_ROOT ..."
    if [ -d "$WEB_ROOT" ]; then
        chown -R www-data:www-data "$WEB_ROOT"
    fi
}

function createNamespace() {
    NAMESPACE_EXISTS=$(kubectl get namespaces --no-headers | grep "$(getProjectNamespace)" --count || true)
    if [ "${NAMESPACE_EXISTS}" -eq "0" ]; then
        echo ">>> creating namespace"
        kubectl create namespace "$(getProjectNamespace)"
    fi
}

function copyRegistryCredentialsIntoCurrentNamespace() {
    SECRET_EXISTS=$(kubectl get secret --no-headers -n "$(getProjectNamespace)" | grep "regcred" --count || true)
    if [ "${SECRET_EXISTS}" -gt "0" ]; then
        echo ">>> deleting registry secret"
        kubectl delete secret regcred -n "$(getProjectNamespace)"
    fi
    echo ">>> copy registry secret"
    kubectl get secret regcred -o yaml | sed "s/default/$(getProjectNamespace)/g" > regcred.yaml
    kubectl -n "$(getProjectNamespace)" create -f regcred.yaml
    rm -Rf regcred.yaml
}

function removeOldInstanceIfExists() {
    exitIfRequiredVariablesAreNotSet "_PROJECT_PREFIX"
    OLD_NAMESPACE="$(getOldInstanceNamespace)"
    if [ -n "$OLD_NAMESPACE" ]; then
        echo ">>> remove old instances"
        removeOldNameSpaces "$OLD_NAMESPACE" "$_PROJECT_PREFIX"
    fi
}

function deploymentAlreadyExists() {
    DEPLOYMENT_EXISTS="$(helm ls --short --all | grep "$(getReleaseName)" --count || true)"
    if [ "${DEPLOYMENT_EXISTS}" -eq "0" ]; then
        return $_FALSE_VALUE
    fi

    return $_TRUE_VALUE
}

function uploadSecretsFromDotEnv() {
    exitIfRequiredVariablesAreNotSet "_SECRETS_NAME"
    SECRET_EXISTS=$(kubectl get secret "$_SECRETS_NAME" -n "$(getProjectNamespace)" --no-headers | wc -l)
    if [ "${SECRET_EXISTS}" -gt "0" ]; then
        kubectl delete secret "$_SECRETS_NAME" -n "$(getProjectNamespace)"
    fi
    kubectl create secret generic "$_SECRETS_NAME" -n "$(getProjectNamespace)" --from-env-file=./.env
}

function rewriteVariableInDotEnv() {
    KEY="$1"
    VALUE="$2"
    exitIfRequiredVariablesAreNotSet "KEY VALUE"
    sed -i "/^$KEY=/c\\$KEY=$VALUE" .env
}

function removeOldNameSpaces() {
    NAMESPACES="$1"
    PROJECT_NAME="$2"
    exitIfRequiredVariablesAreNotSet "NAMESPACES PROJECT_NAME"
    for NAMESPACE in $NAMESPACES
    do
        kubectl delete namespace "$NAMESPACE"
        INSTANCE_EXISTS=$(helm ls --short --all | grep "$NAMESPACE" --count || true)
        if [ "${INSTANCE_EXISTS}" -gt "0" ]; then
            helm delete --purge "$PROJECT_NAME-$NAMESPACE"
        fi
    done
}

function patchBlueGreen() {
    exitIfRequiredVariablesAreNotSet "_BLUE_GREEN_MODE _BLUE_GREEN_PATCHABLE_OBJECT"
    if [ "$_BLUE_GREEN_MODE" == "service" ]; then
        patchServiceBlueGreen "$_BLUE_GREEN_PATCHABLE_OBJECT"
        return
    fi
    if [ "$_BLUE_GREEN_MODE" == "ingress" ]; then
        patchIngressBlueGreen "$_BLUE_GREEN_PATCHABLE_OBJECT"
        return
    fi
}

function patchIngressBlueGreen() {
    INGRESS_NAME="$1"
    exitIfRequiredVariablesAreNotSet "INGRESS_NAME"
    prepareGreenToRedPatch ingress "$INGRESS_NAME"
    prepareBlueToGreenPatch ingress "$INGRESS_NAME"
    patchGreenToRed ingress "$INGRESS_NAME"
    patchBlueToGreen ingress "$INGRESS_NAME"
}

function patchServiceBlueGreen() {
    SERVICE_NAME="$1"
    exitIfRequiredVariablesAreNotSet "SERVICE_NAME"
    prepareGreenToRedPatch service "$SERVICE_NAME"
    prepareBlueToGreenPatch service "$SERVICE_NAME"
    patchGreenToRed service "$SERVICE_NAME"
    patchBlueToGreen service "$SERVICE_NAME"
}

function prepareGreenToRedPatch() {
    OBJECT_TYPE="$1"
    OBJECT_NAME="$2"

    OLD_INSTANCE="$(getOldInstanceNamespace)"
    if [ -n "$OLD_INSTANCE" ]; then
        echo ">>> prepare green to red patch"
        kubectl get "$OBJECT_TYPE" "$OBJECT_NAME" -n "$OLD_INSTANCE" -o yaml > "$_GREEN_BLUE_TEMP_FILE"
        if [ "$OBJECT_TYPE" == "ingress" ]; then
            sed -i "s/$(getProjectProductionDomain)/delete-me.net/g" "$_GREEN_BLUE_TEMP_FILE"
        fi
        if [ "$OBJECT_TYPE" == "service" ]; then
            sed -i "s/$(getProjectProductionPort)/32767/g" "$_GREEN_BLUE_TEMP_FILE"
        fi
    fi
}

function prepareBlueToGreenPatch() {
    OBJECT_TYPE="$1"
    OBJECT_NAME="$2"
    exitIfRequiredVariablesAreNotSet "OBJECT_TYPE OBJECT_NAME _BLUE_GREEN_TEMP_FILE"
    echo ">>> prepare blue to green patch"
    kubectl get "$OBJECT_TYPE" "$OBJECT_NAME" -n "$(getProjectNamespace)" -o yaml > "$_BLUE_GREEN_TEMP_FILE"
    if [ "$OBJECT_TYPE" == "ingress" ]; then
        sed -i "s/$(getProjectDeploymentDomain)/$(getProjectProductionDomain)/g" "$_BLUE_GREEN_TEMP_FILE"
    fi
    if [ "$OBJECT_TYPE" == "service" ]; then
        sed -i "s/$(getProjectDeploymentPort)/$(getProjectProductionPort)/g" "$_BLUE_GREEN_TEMP_FILE"
    fi
}

function patchGreenToRed() {
    OBJECT_TYPE="$1"
    OBJECT_NAME="$2"
    exitIfRequiredVariablesAreNotSet "OBJECT_TYPE OBJECT_NAME _GREEN_BLUE_TEMP_FILE"
    OLD_INSTANCE="$(getOldInstanceNamespace)"
    if [ -n "$OLD_INSTANCE" ]; then
        echo ">>> patch green to red"
        kubectl patch "$OBJECT_TYPE" "$OBJECT_NAME" -n "$OLD_INSTANCE" -p "$(cat $_GREEN_BLUE_TEMP_FILE)"
        rm "$_GREEN_BLUE_TEMP_FILE"
    fi
}

function patchBlueToGreen() {
    OBJECT_TYPE="$1"
    OBJECT_NAME="$2"
    exitIfRequiredVariablesAreNotSet "OBJECT_TYPE OBJECT_NAME _BLUE_GREEN_TEMP_FILE"
    echo ">>> patch blue to gree"
    kubectl patch "$OBJECT_TYPE" "$OBJECT_NAME" -n "$(getProjectNamespace)" -p "$(cat $_BLUE_GREEN_TEMP_FILE)"
    rm "$_BLUE_GREEN_TEMP_FILE"
}

function waitUntilPodsDeployed() {
    exitIfRequiredVariablesAreNotSet "_CONTAINERS_TO_RUN"
    for _CONTAINER in $_CONTAINERS_TO_RUN; do
        waitUntilPodDeployed "$_CONTAINER"
    done
}

function waitUntilPodDeployed() {
    POD_NAME="$1"
    exitIfRequiredVariablesAreNotSet "POD_NAME"
    echo ">>> readyness check"
    kubectl rollout status deployment "$POD_NAME" --namespace "$(getProjectNamespace)"
}

function getHttpResponseCode() {
    URL="$1"
    exitIfRequiredVariablesAreNotSet "URL"
    curl -s --cookie /tmp/secured-area-login --insecure -o /dev/null -w '%{http_code}' "$URL"
}

function authenticateWithFormAuth() {
    PROTOCOL="$1"
    DOMAIN="$2"
    _USER="$3"
    _PASSWORD="$4"
    exitIfRequiredVariablesAreNotSet "PROTOCOL DOMAIN _USER _PASSWORD"
    echo ">>> authenticate form_auth"
    curl -s -d "httpd_username=$_USER&httpd_password=$_PASSWORD" -X POST "$PROTOCOL://$DOMAIN/secured-area-login" --cookie-jar /tmp/secured-area-login --insecure -o /dev/null
}

function checkPathsForPositiveResponse() {
    PROTOCOL="$1"
    exitIfRequiredVariablesAreNotSet "PROTOCOL _PATHS_TO_CHECK"
    for _PATH_TO_CHECK in $_PATHS_TO_CHECK; do
        waitUntilPositiveResponse "$PROTOCOL" "$(getHtpasswdCredentialsAsUrlPrefix)$(getProjectDeploymentDomain)$_PATH_TO_CHECK"
    done
}

function waitUntilPositiveResponse() {
    PROTOCOL="$1"
    DOMAIN="$2"
    exitIfRequiredVariablesAreNotSet "PROTOCOL DOMAIN _TIMEOUT"
    tried_times=0
    echo ">>> waiting for $PROTOCOL://$DOMAIN to return 200"
    while [[ "$(getHttpResponseCode "$PROTOCOL://$DOMAIN")" != "200" ]]; do
        echo -n -e ". "
        sleep 1
        if [ $((tried_times++)) -gt $_TIMEOUT ]; then
          echo ">>> Error! Too many attempts to get 200 from $PROTOCOL://$DOMAIN"
          exit 1
        fi
    done
    echo ""
}

function printDots() {
    AMOUNT=$1
    exitIfRequiredVariablesAreNotSet "AMOUNT"
    DOTS="."
    for (( c=1; c<=AMOUNT; c++ )); do
        DOTS="$DOTS ."
    done
    echo "$DOTS"
}

function getBase64EncodedReviewHtpasswdString() {
    _USER=$1
    PASSWORD=$2
    exitIfRequiredVariablesAreNotSet "_USER PASSWORD"
    echo -n "$(getReviewHtpasswdString "$_USER" "$PASSWORD")" | openssl base64
}

function getReviewHtpasswdString() {
    _USER=$1
    PASSWORD=$2
    exitIfRequiredVariablesAreNotSet "_USER PASSWORD"
    echo "$_USER:$(openssl passwd -apr1 "$PASSWORD")"
}

function getHtpasswdCredentialsAsUrlPrefix() {
    exitIfRequiredVariablesAreNotSet "_STAGING_HTPASSWD_USER _STAGING_HTPASSWD_PASSWORD"
    echo "$_STAGING_HTPASSWD_USER:$_STAGING_HTPASSWD_PASSWORD@"
}

if [ "$CI_SHELL_DEBUG" = "true" ]; then
    set -x
fi

function replaceSymlinksWithItsTarget() {
    for link in $(find "$1" -maxdepth 1 -type l); do
        link_target=$(readlink -f "$link")
        rm -f "$link"
        mkdir "$link"
        echo ">>> copy files from $link_target to $link"
        cp -r "$link_target/." "$link"
    done
}

function convertSecretKeysToArray() {
    exitIfRequiredVariablesAreNotSet "_SECRETS_NAME"
    array="{"
    for key in $(kubectl describe secret $_SECRETS_NAME -n "$(getProjectNamespace)" | sed -e '1,/====/d' | cut -f1 -d":"); do
        array="$array$key,"
    done
    array="$(echo "$array" | sed 's/,\([^,]*\)$/ \1/')}"
    echo "$array"
}

function waitUntilFlagFileExists() {
    POD_NAME="$1"
    FLAGFILE="$2"
    exitIfRequiredVariablesAreNotSet "POD_NAME FLAGFILE"
    tried_times=0
    echo ">>> waiting for $FLAGFILE in $POD_NAME"
    POD="$(kubectl get pods -n "$(getProjectNamespace)" | grep "$POD_NAME" | cut -d " " -f1)"
    while [[ "$(kubectl exec "$POD" -n "$(getProjectNamespace)" cat "$FLAGFILE" 2>/dev/null)" != "1" ]]; do
        echo -n -e ". "
        sleep 1
        if [ $((tried_times++)) -gt 500 ]; then
          echo ">>> Error! Too many attempts to find $FLAGFILE in $POD_NAME"
          exit 1
        fi
    done
    echo ""
}

function establishSSHTunnel() {
    _CONNECTION="$1"
    _PORT="$2"
    exitIfRequiredVariablesAreNotSet "_CONNECTION _PORT"
    ssh -fN -L $_PORT:localhost:$_PORT $_CONNECTION -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no 2>&1
}

function buildAndPushContainerImages() {
    exitIfRequiredVariablesAreNotSet "_CONTAINERS_TO_BUILD _DOCKER_REGISTRY CI_PROJECT_PATH CI_COMMIT_REF_SLUG"
    for _CONTAINER in $_CONTAINERS_TO_BUILD; do
        docker build -f ".deployment/docker/$_CONTAINER/Dockerfile" -t "$_DOCKER_REGISTRY/$CI_PROJECT_PATH/$_CONTAINER:$CI_COMMIT_REF_SLUG" .
        docker push "$_DOCKER_REGISTRY/$CI_PROJECT_PATH/$_CONTAINER:$CI_COMMIT_REF_SLUG"
    done
}

function getDynamicVariable() {
    _PREFIX="$1"
    _POSTFIX="$2"
    VARIABLE_NAME="$_PREFIX"_"$(echo "$_POSTFIX" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"

    echo "${!VARIABLE_NAME}"
}

function getDynamicVariableOrFallback() {
    _FALLBACK_NAME="$1"
    _POSTFIX="$2"
    exitIfRequiredVariablesAreNotSet "$_FALLBACK_NAME"
    VARIABLE_NAME_TEMP="$_FALLBACK_NAME"_"$(echo "$_POSTFIX" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
    if [ -n "${!VARIABLE_NAME_TEMP}" ]; then
        VARIABLE_NAME="$VARIABLE_NAME_TEMP"
    fi

    echo "${!VARIABLE_NAME}"
}

function installHelmChart() {
    exitIfRequiredVariablesAreNotSet "VERSION _SECRETS_NAME"
    echo ">>> installing chart"
    helm install .deployment/kubernetes --name="$(getReleaseName)" --namespace "$(getProjectNamespace)" --wait --debug --timeout 3600 \
      --set "registry=$_DOCKER_REGISTRY" \
      --set "version=0.0.1"\
      --set "image.prefix=$CI_PROJECT_PATH" \
      --set "image.tag=$CI_COMMIT_REF_SLUG" \
      --set "version=$VERSION" \
      --set "environment=$(getProjectEnvironment)" \
      --set "branch=$CI_COMMIT_REF_SLUG" \
      --set "domain.production=$(getProjectProductionDomain)" \
      --set "domain.deployment=$(getProjectDeploymentDomain)" \
      --set "port.production=$(getProjectProductionPort)" \
      --set "port.deployment=$(getProjectDeploymentPort)" \
      --set "secrets=$_SECRETS_NAME" \
      --set "namespace=$(getProjectNamespace)" \
      --set "htpasswd=$(getBase64EncodedReviewHtpasswdString "$_STAGING_HTPASSWD_USER" "$_STAGING_HTPASSWD_PASSWORD")" \
      --set "secretVariableKeys=$(convertSecretKeysToArray)"
}

readVariablesFromGitlab
