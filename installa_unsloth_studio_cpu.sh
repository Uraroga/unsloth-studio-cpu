#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="${SCRIPT_DIR}"
BUILD_DIR="${PROJECT_DIR}/build"
LOG_DIR="${PROJECT_DIR}/log"
INSTALLER_FILE="${BUILD_DIR}/unsloth-install.sh"
INSTALLER_URL="https://unsloth.ai/install.sh"
IMAGE_NAME="local/unsloth-studio-cpu:latest"
DOCKER_USE_SUDO=0

mkdir -p -- "${LOG_DIR}" "${BUILD_DIR}" "${PROJECT_DIR}/dati/workspace/modelli" "${PROJECT_DIR}/dati/huggingface"
LOG_FILE="$(mktemp "${LOG_DIR}/installazione-$(date '+%Y%m%d-%H%M%S')-XXXXXX.log")"
exec > >(tee -a "${LOG_FILE}") 2>&1

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERRORE: %s\n' "$*" >&2; exit 1; }
docker_cmd() { if (( DOCKER_USE_SUDO )); then sudo docker "$@"; else docker "$@"; fi; }
trap 'printf "\nInstallazione interrotta alla riga %s.\n" "${BASH_LINENO[0]:-?}" >&2' ERR

log "Controllo sistema"
[[ "$(uname -s)" == Linux ]] || die "è richiesto Linux."
[[ "$(uname -m)" == x86_64 ]] || die "è richiesta l'architettura x86_64."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die "questo script supporta Ubuntu."
[[ "${VERSION_ID:-}" == 24.04 ]] || die "configurazione verificata soltanto su Ubuntu 24.04 LTS."
[[ -f "${PROJECT_DIR}/Dockerfile" ]] || die "Dockerfile non trovato."
command -v curl >/dev/null || die "curl non è installato."

if ! command -v docker >/dev/null; then
    die "Docker non è installato. Installalo dalla documentazione ufficiale Docker e riesegui lo script."
fi
if docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=0
elif command -v sudo >/dev/null && sudo docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=1
else
    die "Docker non è accessibile; verifica servizio e permessi."
fi

log "Acquisisco l'installer ufficiale usato dal Dockerfile"
tmp_installer="$(mktemp "${BUILD_DIR}/.unsloth-install-XXXXXX")"
trap 'rm -f -- "${tmp_installer:-}"' EXIT
curl --fail --show-error --location --retry 3 --proto '=https' --tlsv1.2 \
    "${INSTALLER_URL}" --output "${tmp_installer}"
head -n 5 "${tmp_installer}" | grep -qE '^#!/bin/(ba)?sh|^#!/usr/bin/env (ba)?sh' \
    || die "il download non è uno script shell valido."
chmod 0755 "${tmp_installer}"
mv -f -- "${tmp_installer}" "${INSTALLER_FILE}"
trap - EXIT

log "Costruisco ${IMAGE_NAME} dal Dockerfile tracciato"
docker_cmd build --pull --progress=plain \
    --build-arg "HOST_UID=$(id -u)" --build-arg "HOST_GID=$(id -g)" \
    --tag "${IMAGE_NAME}" "${PROJECT_DIR}"

[[ "$(docker_cmd image inspect --format '{{.Os}}/{{.Architecture}}' "${IMAGE_NAME}")" == linux/amd64 ]] \
    || die "l'immagine prodotta non è linux/amd64."
log "Immagine costruita: ${IMAGE_NAME}"
printf 'Nessun container o modello è stato creato o scaricato dallo script.\n'
