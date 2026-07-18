#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_NAME="local/unsloth-studio-cpu:latest"
CONTAINER_NAME="unsloth-studio-cpu"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="${SCRIPT_DIR}"
LOG_DIR="${PROJECT_DIR}/log"
WORKSPACE_DIR="${PROJECT_DIR}/dati/workspace"
HUGGINGFACE_DIR="${PROJECT_DIR}/dati/huggingface"
MODELS_DIR="${WORKSPACE_DIR}/modelli"
CONTAINER_MODELS_DIR="/home/unsloth/modelli"
LOG_FILE=""
DOCKER_USE_SUDO=0
DOCKER_READY=0
WAIT_SECONDS=180

mkdir -p -- "${LOG_DIR}"
LOG_FILE="$(mktemp "${LOG_DIR}/avvio-$(date '+%Y%m%d-%H%M%S')-XXXXXX.log")"
ln -sfn -- "$(basename -- "${LOG_FILE}")" "${LOG_DIR}/ultimo-avvio.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf '\nERRORE: %s\n' "$*" >&2
    show_container_logs
    exit 1
}

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

mounts_are_correct() {
    local expected_mounts
    local actual_mounts

    expected_mounts="$(printf '%s\n' \
        "bind|${WORKSPACE_DIR}|/workspace" \
        "bind|${HUGGINGFACE_DIR}|/home/unsloth/.cache/huggingface" \
        "bind|${MODELS_DIR}|${CONTAINER_MODELS_DIR}" \
        | sort)"
    actual_mounts="$(docker_cmd container inspect \
        --format '{{range .Mounts}}{{printf "%s|%s|%s\n" .Type .Source .Destination}}{{end}}' \
        "${CONTAINER_NAME}" | sort)"
    [[ "${actual_mounts}" == "${expected_mounts}" ]]
}

show_container_logs() {
    if [[ "${DOCKER_READY}" == "1" ]] && container_exists; then
        printf '\nUltime 100 righe dei log Docker:\n' >&2
        docker_cmd logs --tail 100 "${CONTAINER_NAME}" >&2 || true
    fi
}

on_error() {
    local exit_code=$?
    local line_number="${BASH_LINENO[0]:-sconosciuta}"
    trap - ERR
    set +e
    printf '\nAvvio interrotto alla riga %s, codice %s.\n' \
        "${line_number}" "${exit_code}" >&2
    show_container_logs
    exit "${exit_code}"
}
trap on_error ERR

port_8888_in_use() {
    if command -v ss >/dev/null 2>&1; then
        ss -H -ltn | awk '$4 ~ /(^|:)8888$/ { found=1 } END { exit !found }'
    elif command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:8888 -sTCP:LISTEN >/dev/null 2>&1
    else
        die "impossibile verificare la porta 8888: servono ss oppure lsof."
    fi
}

log "Controllo Docker e immagine"
command -v docker >/dev/null 2>&1 || die "Docker non è installato."
command -v curl >/dev/null 2>&1 || die "curl non è installato."

if docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=0
elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=1
else
    die "il demone Docker non è accessibile né direttamente né tramite sudo."
fi
DOCKER_READY=1

docker_cmd image inspect "${IMAGE_NAME}" >/dev/null 2>&1 \
    || die "l'immagine ${IMAGE_NAME} non è presente."

log "Preparo le directory persistenti"
mkdir -p -- \
    "${WORKSPACE_DIR}" \
    "${HUGGINGFACE_DIR}" \
    "${MODELS_DIR}"
WORKSPACE_DIR="$(cd -- "${WORKSPACE_DIR}" && pwd -P)"
HUGGINGFACE_DIR="$(cd -- "${HUGGINGFACE_DIR}" && pwd -P)"
MODELS_DIR="$(cd -- "${MODELS_DIR}" && pwd -P)"

if container_exists; then
    expected_image_id="$(docker_cmd image inspect --format '{{.Id}}' "${IMAGE_NAME}")"
    container_image_id="$(docker_cmd container inspect --format '{{.Image}}' "${CONTAINER_NAME}")"
    if [[ "${container_image_id}" != "${expected_image_id}" ]]; then
        die "il container ${CONTAINER_NAME} esiste ma usa un'immagine differente; non è stato modificato."
    fi
    port_binding="$(docker_cmd container inspect \
        --format '{{json (index .HostConfig.PortBindings "8888/tcp")}}' \
        "${CONTAINER_NAME}")"
    if [[ "${port_binding}" != '[{"HostIp":"127.0.0.1","HostPort":"8888"}]' ]]; then
        die "il container esistente non pubblica esclusivamente 127.0.0.1:8888; non è stato modificato."
    fi
    if ! mounts_are_correct; then
        die "il container esistente non ha esattamente i tre bind mount previsti; non è stato modificato. Usa prima ferma_distruggi_unsloth_studio_cpu.sh e successivamente avvia_unsloth_studio_cpu.sh."
    fi

    if [[ "$(docker_cmd container inspect --format '{{.State.Running}}' "${CONTAINER_NAME}")" == "true" ]]; then
        log "Il container ${CONTAINER_NAME} è già attivo"
    else
        port_8888_in_use \
            && die "la porta 127.0.0.1:8888 è già occupata; il container non è stato avviato."
        log "Avvio il container esistente ${CONTAINER_NAME}"
        docker_cmd start "${CONTAINER_NAME}" >/dev/null
    fi
else
    port_8888_in_use \
        && die "la porta 127.0.0.1:8888 è già occupata; il container non è stato creato."
    log "Creo e avvio il container ${CONTAINER_NAME}"
    docker_cmd run -d \
        --name "${CONTAINER_NAME}" \
        --init \
        --shm-size=2g \
        --publish 127.0.0.1:8888:8888 \
        --mount "type=bind,source=${WORKSPACE_DIR},target=/workspace" \
        --mount "type=bind,source=${HUGGINGFACE_DIR},target=/home/unsloth/.cache/huggingface" \
        --mount "type=bind,source=${MODELS_DIR},target=${CONTAINER_MODELS_DIR}" \
        "${IMAGE_NAME}" >/dev/null
fi

log "Attendo lo stato healthy e la risposta sulla porta 8888"
deadline=$((SECONDS + WAIT_SECONDS))
ready=0
while (( SECONDS < deadline )); do
    running="$(docker_cmd container inspect --format '{{.State.Running}}' "${CONTAINER_NAME}")"
    health="$(docker_cmd container inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${CONTAINER_NAME}")"

    if [[ "${running}" != "true" ]]; then
        die "il container si è arrestato durante l'avvio."
    fi
    if [[ "${health}" == "unhealthy" ]]; then
        die "il healthcheck Docker segnala che il container non è healthy."
    fi
    if [[ "${health}" == "healthy" ]] \
        && curl --fail --silent --show-error --max-time 3 \
            http://127.0.0.1:8888/api/health >/dev/null; then
        ready=1
        break
    fi
    sleep 3
done

if [[ "${ready}" != "1" ]]; then
    die "Unsloth Studio non ha risposto entro ${WAIT_SECONDS} secondi."
fi

log "Verifico la cartella dei modelli GGUF"
mounts_are_correct \
    || die "i bind mount del container non corrispondono alle tre directory persistenti previste."
docker_cmd exec "${CONTAINER_NAME}" sh -c \
    'test -d /home/unsloth/modelli && test -r /home/unsloth/modelli' \
    || die "${CONTAINER_MODELS_DIR} non esiste o non è leggibile dall'utente interno."
host_gguf_count="$(find "${MODELS_DIR}" -type f -iname '*.gguf' -printf '.' | wc -c | tr -d '[:space:]')"
container_gguf_count="$(docker_cmd exec "${CONTAINER_NAME}" sh -c \
    'find /home/unsloth/modelli -type f -iname "*.gguf" -readable -printf "." | wc -c' \
    | tr -d '[:space:]')"
if [[ "${container_gguf_count}" != "${host_gguf_count}" ]]; then
    die "non tutti i file GGUF presenti sul PC sono leggibili in ${CONTAINER_MODELS_DIR}."
fi

log "Stato del container"
docker_cmd ps --filter "name=^/${CONTAINER_NAME}$" \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

printf '\nUnsloth Studio:\nhttp://127.0.0.1:8888\n'
printf '\nCartella modelli sul PC:\n%s\n' "${MODELS_DIR}"
printf '\nCartella modelli in Unsloth Studio:\n%s\n' "${CONTAINER_MODELS_DIR}"
