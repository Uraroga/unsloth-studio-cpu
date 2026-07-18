#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_NAME="local/unsloth-studio-cpu:latest"
CONTAINER_NAME="unsloth-studio-cpu"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="${SCRIPT_DIR}"
LOG_DIR="${PROJECT_DIR}/log"
LOG_FILE=""
DOCKER_USE_SUDO=0
PHASE="inizializzazione"
ASSUME_YES=0

log() {
    printf '\n==> %s\n' "$*"
}

report_error() {
    local exit_code="$1"
    local line_number="$2"
    local failed_command="$3"

    printf '\nERRORE durante la fase: %s\n' "${PHASE}" >&2
    printf 'Riga: %s\n' "${line_number}" >&2
    printf 'Comando: %s\n' "${failed_command}" >&2
    printf 'Codice di uscita: %s\n' "${exit_code}" >&2
}

die() {
    local message="$1"
    printf '\nERRORE: %s\n' "${message}" >&2
    report_error 1 "${BASH_LINENO[0]:-sconosciuta}" "${BASH_COMMAND:-errore gestito}"
    exit 1
}

on_error() {
    local exit_code=$?
    local failed_command="${BASH_COMMAND:-sconosciuto}"
    local line_number="${BASH_LINENO[0]:-sconosciuta}"
    trap - ERR
    report_error "${exit_code}" "${line_number}" "${failed_command}"
    exit "${exit_code}"
}
trap on_error ERR

docker_cmd() {
    if [[ "${DOCKER_USE_SUDO}" == "0" ]]; then
        docker "$@"
    else
        sudo docker "$@"
    fi
}

container_exists() {
    docker_cmd container inspect "${CONTAINER_NAME}" >/dev/null 2>&1
}

usage() {
    printf 'Uso: %s [--yes]\n' "$(basename -- "$0")"
}

if (( $# > 1 )); then
    usage >&2
    exit 2
fi
if (( $# == 1 )); then
    if [[ "$1" == "--yes" ]]; then
        ASSUME_YES=1
    else
        usage >&2
        exit 2
    fi
fi

PHASE="preparazione del log"
mkdir -p -- "${LOG_DIR}"
LOG_FILE="$(mktemp "${LOG_DIR}/distruzione-$(date '+%Y%m%d-%H%M%S')-XXXXXX.log")"
ln -sfn -- "$(basename -- "${LOG_FILE}")" "${LOG_DIR}/ultima-distruzione.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

PHASE="controllo di Docker"
log "Controllo Docker"
command -v docker >/dev/null 2>&1 || die "Docker non è installato."

if docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=0
elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=1
else
    die "il demone Docker non è accessibile né direttamente né tramite sudo."
fi

PHASE="ricerca del container"
if ! container_exists; then
    log "Il container ${CONTAINER_NAME} non esiste"
    printf 'Non c’è nulla da fermare o eliminare.\n'
    exit 0
fi

PHASE="verifica dell'appartenenza del container"
container_image="$(docker_cmd container inspect --format '{{.Config.Image}}' "${CONTAINER_NAME}")"
if [[ "${container_image}" != "${IMAGE_NAME}" ]]; then
    die "il container ${CONTAINER_NAME} usa l'immagine ${container_image}, non ${IMAGE_NAME}; non è stato modificato."
fi

container_status="$(docker_cmd container inspect --format '{{.State.Status}}' "${CONTAINER_NAME}")"
container_running="$(docker_cmd container inspect --format '{{.State.Running}}' "${CONTAINER_NAME}")"

printf '\nContainer da fermare ed eliminare:\n'
printf '  Nome:     %s\n' "${CONTAINER_NAME}"
printf '  Immagine: %s\n' "${container_image}"
printf '  Stato:    %s\n' "${container_status}"
printf '\nATTENZIONE: i dati interni al container che non sono montati saranno persi.\n'
printf 'Le directory persistenti non saranno cancellate:\n'
printf '  %s\n' "${PROJECT_DIR}/dati/workspace"
printf '  %s\n' "${PROJECT_DIR}/dati/huggingface"
printf 'L’immagine %s non sarà cancellata.\n' "${IMAGE_NAME}"

if [[ "${ASSUME_YES}" != "1" ]]; then
    printf '\nPer confermare, scrivi esattamente DISTRUGGI: '
    if ! IFS= read -r confirmation; then
        printf '\nOperazione annullata: nessuna conferma ricevuta.\n'
        exit 0
    fi
    if [[ "${confirmation}" != "DISTRUGGI" ]]; then
        printf 'Operazione annullata. Il container non è stato modificato.\n'
        exit 0
    fi
else
    log "Conferma interattiva saltata tramite --yes"
fi

if [[ "${container_running}" == "true" ]]; then
    PHASE="arresto ordinato del container"
    log "Arresto ordinato del container, timeout 30 secondi"
    if docker_cmd stop --time 30 "${CONTAINER_NAME}" >/dev/null; then
        PHASE="eliminazione del container arrestato"
        log "Elimino il container arrestato"
        docker_cmd container rm "${CONTAINER_NAME}" >/dev/null
    else
        printf '\nAVVISO: l’arresto ordinato è fallito; procedo con la rimozione forzata del solo container %s.\n' \
            "${CONTAINER_NAME}" >&2
        PHASE="rimozione forzata dopo arresto fallito"
        docker_cmd container rm --force "${CONTAINER_NAME}" >/dev/null
    fi
else
    PHASE="eliminazione del container già fermo"
    log "Il container è già fermo; lo elimino senza eseguire docker stop"
    docker_cmd container rm "${CONTAINER_NAME}" >/dev/null
fi

PHASE="verifica finale"
if container_exists; then
    die "il container ${CONTAINER_NAME} risulta ancora presente."
fi
docker_cmd image inspect "${IMAGE_NAME}" >/dev/null 2>&1 \
    || die "il container è stato eliminato, ma l'immagine ${IMAGE_NAME} non risulta più presente."

log "Operazione completata"
printf 'Il container %s è stato eliminato.\n' "${CONTAINER_NAME}"
printf 'L’immagine %s è ancora presente.\n' "${IMAGE_NAME}"
printf 'Dati persistenti e modelli non sono stati cancellati.\n'
