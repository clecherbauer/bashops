#!/bin/bash
set -e

trap "exit" INT

base_functions="cleanup help init setup update"
declare -A plugins
available_init_plugins=""
available_update_plugins=""
available_cleanup_plugins=""
for plugin_path in $(find . -name 'dev.plugin.sh'); do
  plugin_name="$(source $plugin_path; plugin_name)"
  plugins[$plugin_name]="$plugin_path"
  if [[ "$(source $plugin_path; declare -F | grep 'init' | wc -l)" > 0 ]]; then
    available_init_plugins="$available_init_plugins $plugin_name"
  fi
  if [[ "$(source $plugin_path; declare -F | grep 'update' | wc -l)" > 0 ]]; then
    available_update_plugins="$available_update_plugins $plugin_name"
  fi
  if [[ "$(source $plugin_path; declare -F | grep 'cleanup' | wc -l)" > 0 ]]; then
    available_cleanup_plugins="$available_cleanup_plugins $plugin_name"
  fi
done

function update_pre_hook() {
  return
}

function update_post_hook() {
  return
}

function cleanup_pre_hook() {
  return
}

function cleanup_post_hook() {
  return
}

function setup_pre_hook() {
  return
}

function setup_post_hook() {
  return
}

function init_pre_hook() {
  return
}

function init_post_hook() {
  return
}

function setup() {
    _confirm && _setup
}

_setup() {
  setup_pre_hook
  curl -s https://raw.githubusercontent.com/clecherbauer/docker-setup/master/setup.sh | bash
  setup_post_hook
}

function init() {
    available_functions="all help $available_init_plugins"
    function help() {
        echo ""
        echo "Usage: $0 update [argument]"
        echo ""
        echo "Available arguments:"
        for arg in $available_functions; do
          echo "$arg"
        done
    }

    if [[ "$1" == "" || "$1" == "all" ]]; then
      init_pre_hook
      for available_init_plugin in $available_init_plugins; do
        for key in "${!plugins[@]}"; do
          if [[ "$available_init_plugin" == "$key" ]]; then
            source "${plugins[$key]}"
            cd $(dirname $(readlink -f "${plugins[$key]}")) || exit;
            init
            cd ..
          fi
        done
      done
      init_post_hook
      return
    fi

    if [[ "$available_init_plugins" == *"$1"* ]]; then
        for key in "${!plugins[@]}"; do
          if [[ "$1" == "$key" ]]; then
            init_pre_hook
            source "${plugins[$key]}"
            cd $(dirname $(readlink -f "${plugins[$key]}")) || exit;
            init
            init_post_hook
          fi
        done
        return
    fi

    if [[ "$available_functions" != *"$1"* ]]; then
        echo "Error: unknown argument $1"
        help
        exit 1
    fi

    $1
}

function update() {
    available_functions="all help $available_update_plugins"
    function help() {
        echo ""
        echo "Usage: $0 update [argument]"
        echo ""
        echo "Available arguments:"
        for arg in $available_functions; do
          echo "$arg"
        done
    }

    if [[ "$1" == "" || "$1" == "all" ]]; then
      update_pre_hook
      for available_update_plugin in $available_update_plugins; do
        for key in "${!plugins[@]}"; do
          if [[ "$available_update_plugin" == "$key" ]]; then
            source "${plugins[$key]}"
            cd $(dirname $(readlink -f "${plugins[$key]}")) || exit;
            update
            cd ..
          fi
        done
      done
      update_post_hook
      return
    fi

    if [[ "$available_update_plugins" == *"$1"* ]]; then
        for key in "${!plugins[@]}"; do
          if [[ "$1" == "$key" ]]; then
            update_pre_hook
            source "${plugins[$key]}"
            cd $(dirname $(readlink -f "${plugins[$key]}")) || exit;
            update
            update_post_hook
          fi
        done
        return
    fi

    if [[ "$available_functions" != *"$1"* ]]; then
        echo "Error: unknown argument $1"
        help
        exit 1
    fi

    $1
}

function cleanup() {
    _confirm && _cleanup
}

function _cleanup() {
    available_functions="all help $available_cleanup_plugins"
    function help() {
        echo ""
        echo "Usage: $0 cleanup [argument]"
        echo ""
        echo "Available arguments:"
        for arg in $available_functions; do
          echo "$arg"
        done
    }

    if [[ "$1" == "" || "$1" == "all" ]]; then
      cleanup_pre_hook
      for available_cleanup_plugin in $available_cleanup_plugins; do
        for key in "${!plugins[@]}"; do
          if [[ "$available_cleanup_plugin" == "$key" ]]; then
            (
              source "${plugins[$key]}"
              cd $(dirname $(readlink -f "${plugins[$key]}")) || exit;
              update
              cd ..
            )
          fi
        done
      done
      cleanup_post_hook
      return
    fi

    if [[ "$available_cleanup_plugins" == *"$1"* ]]; then
        for key in "${!plugins[@]}"; do
          if [[ "$1" == "$key" ]]; then
            cleanup_pre_hook
            source "${plugins[$key]}"
            cd $(dirname $(readlink -f "${plugins[$key]}")) || exit;
            cleanup
            cleanup_post_hook
          fi
        done
    fi

    if [[ "$available_functions" != *"$1"* ]]; then
        echo "Error: unknown argument $1"
        help
        exit 1
    fi

    $1
}

function help() {
    echo ""
    echo "Usage: $0 [argument]"
    echo ""
    echo "Available arguments:"
    echo "setup           installs system dependencies"
    echo "init            inits the project"
    echo "update          updates all project dependencies"
    echo "cleanup         resets the project and all submodules"
    echo "help            displays this"
}

function _confirm() {
    read -r -p "Are you sure? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            false
            ;;
    esac
}

function run() {
  if [[ "$1" == "" ]]; then
      echo "$0 requires at least 1 argument!"
      help
      exit 1
  fi

  if [[ "$base_functions" != *"$1"* ]]; then
      echo "Error: unknown argument $1"
      help
      exit 1
  fi

  "$1" "$2" "$3" "$4"
}