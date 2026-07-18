#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER_NAME="unsloth-studio-cpu"
DOCKER_USE_SUDO=0
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="${SCRIPT_DIR}"

die() {
    printf 'ERRORE: %s\n' "$*" >&2
    exit 1
}

docker_cmd() {
    if [[ "${DOCKER_USE_SUDO}" -eq 1 ]]; then
        sudo docker "$@"
    else
        docker "$@"
    fi
}

command -v docker >/dev/null 2>&1 \
    || die "Docker non è installato."

if docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=0
elif command -v sudo >/dev/null 2>&1; then
    sudo -v
    sudo docker info >/dev/null 2>&1 \
        || die "il servizio Docker non è accessibile."
    DOCKER_USE_SUDO=1
else
    die "Docker richiede privilegi, ma sudo non è disponibile."
fi

docker_cmd container inspect "${CONTAINER_NAME}" >/dev/null 2>&1 \
    || die "il container ${CONTAINER_NAME} non esiste."

running="$(docker_cmd container inspect \
    --format '{{.State.Running}}' \
    "${CONTAINER_NAME}")"

[[ "${running}" == "true" ]] \
    || die "il container ${CONTAINER_NAME} non è in esecuzione."

password_output="$(
    docker_cmd exec "${CONTAINER_NAME}" sh -lc '
        password_file="$(
            find /opt/unsloth-studio /home/unsloth \
                -type f \
                -name .bootstrap_password \
                -print -quit 2>/dev/null
        )"

        if [ -z "${password_file}" ]; then
            exit 44
        fi

        cat "${password_file}"
    '
)" || {
    exit_code=$?
    if [[ "${exit_code}" -eq 44 ]]; then
        die "il file .bootstrap_password non è stato trovato. La password potrebbe essere già stata cambiata."
    fi
    die "non è stato possibile leggere la password dal container."
}

password="${password_output}"

[[ -n "${password}" ]] \
    || die "la password iniziale disponibile è vuota."

printf '\nPassword temporanea di Unsloth Studio:\n%s\n\n' "${password}"
printf 'Non condividere questa password. Dopo aver impostato la nuova password, questa potrebbe non essere più valida.\n'
