#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_NAME="local/unsloth-studio-cpu:latest"
CONTAINER_NAME="unsloth-studio-cpu"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="${SCRIPT_DIR}"
LOG_DIR="${PROJECT_DIR}/log"
DOCKER_USE_SUDO=0
ASSUME_YES=0

[[ $# -le 1 ]] || { printf 'Uso: %s [--yes]\n' "${0##*/}" >&2; exit 2; }
[[ $# -eq 0 || "$1" == --yes ]] || { printf 'Uso: %s [--yes]\n' "${0##*/}" >&2; exit 2; }
[[ $# -eq 0 ]] || ASSUME_YES=1
mkdir -p -- "${LOG_DIR}"
LOG_FILE="$(mktemp "${LOG_DIR}/eliminazione-immagine-$(date '+%Y%m%d-%H%M%S')-XXXXXX.log")"
ln -sfn -- "$(basename -- "${LOG_FILE}")" "${LOG_DIR}/ultima-eliminazione-immagine.log"
exec > >(tee -a "${LOG_FILE}") 2>&1
die() { printf 'ERRORE: %s\n' "$*" >&2; exit 1; }
docker_cmd() { if (( DOCKER_USE_SUDO )); then sudo docker "$@"; else docker "$@"; fi; }

command -v docker >/dev/null || die "Docker non è installato."
if docker info >/dev/null 2>&1; then :
elif command -v sudo >/dev/null && sudo docker info >/dev/null 2>&1; then DOCKER_USE_SUDO=1
else die "Docker non è accessibile."
fi
docker_cmd container inspect "${CONTAINER_NAME}" >/dev/null 2>&1 \
    && die "il container ${CONTAINER_NAME} esiste: rimuovilo prima con lo script dedicato."
docker_cmd image inspect "${IMAGE_NAME}" >/dev/null 2>&1 || die "l'immagine ${IMAGE_NAME} non esiste."
docker_cmd image ls --no-trunc --format 'ID: {{.ID}}  Tag: {{.Repository}}:{{.Tag}}  Dimensione: {{.Size}}' \
    --filter "reference=${IMAGE_NAME}"
if (( ! ASSUME_YES )); then
    printf '\nScrivi esattamente ELIMINA IMMAGINE: '
    IFS= read -r confirmation || exit 1
    [[ "${confirmation}" == 'ELIMINA IMMAGINE' ]] || { printf 'Operazione annullata.\n'; exit 0; }
fi
docker_cmd image rm "${IMAGE_NAME}"
docker_cmd image inspect "${IMAGE_NAME}" >/dev/null 2>&1 \
    && die "l'immagine risulta ancora presente."
printf 'Eliminata esclusivamente l’immagine %s.\n' "${IMAGE_NAME}"
