#!/usr/bin/env bash
set -Eeuo pipefail

readonly IMAGE_MAIN="local/unsloth-studio-cpu:latest"
readonly CONTAINER_MAIN="unsloth-studio-cpu"
readonly IMAGE_TEST="local/unsloth-studio-cpu:test"
readonly CONTAINER_TEST="unsloth-studio-cpu-test"
readonly HOST_PORT="18888"
readonly CONTAINER_PORT="8888"
readonly WAIT_SECONDS=180
readonly MAX_EMBEDDED_WEIGHT_BYTES=$((50 * 1024 * 1024))

NO_CACHE=0
if (( $# > 1 )); then
    printf 'Uso: %s [--no-cache]\n' "${0##*/}" >&2
    exit 2
fi
if (( $# == 1 )); then
    if [[ "$1" == "--no-cache" ]]; then
        NO_CACHE=1
    else
        printf 'Uso: %s [--no-cache]\n' "${0##*/}" >&2
        exit 2
    fi
fi

if (( NO_CACHE )); then
    BUILD_MODE="build completa senza cache"
    BUILD_CACHE_ARGS=(--no-cache --pull)
else
    BUILD_MODE="build con cache"
    BUILD_CACHE_ARGS=(--pull)
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROJECT_DIR="${SCRIPT_DIR}"
readonly TEST_DIR="${PROJECT_DIR}/build/test-docker"
readonly TEST_WORKSPACE="${TEST_DIR}/workspace"
readonly TEST_MODELS="${TEST_WORKSPACE}/modelli"
readonly TEST_HUGGINGFACE="${TEST_DIR}/huggingface"
readonly LOG_DIR="${PROJECT_DIR}/log"
RUN_ID="test-docker-$(date '+%Y%m%d-%H%M%S')-$$"
readonly RUN_ID
readonly OWNERSHIP_LABEL="local.unsloth-studio.test-run=${RUN_ID}"

DOCKER_USE_SUDO=0
DOCKER_READY=0
CONTAINER_CREATED=0
BUILD_STARTED=0
TEST_DIR_CREATED=0
PHASE="inizializzazione"
LOG_FILE=""
BUILD_RESULT="non eseguita"
HEALTH_RESULT="non verificato"
API_RESPONSE="non verificata"
INTERNAL_USER="non verificato"
MOUNTS_RESULT="non verificati"
PORT_RESULT="non verificata"
MODELS_RESULT="non verificata"

log() {
    printf '\n==> %s\n' "$*"
}

docker_cmd() {
    if (( DOCKER_USE_SUDO )); then
        sudo docker "$@"
    else
        docker "$@"
    fi
}

container_test_exists() {
    docker_cmd container inspect "${CONTAINER_TEST}" >/dev/null 2>&1
}

image_test_exists() {
    docker_cmd image inspect "${IMAGE_TEST}" >/dev/null 2>&1
}

show_mount_table() {
    printf '\nMount rilevati nel container temporaneo:\n' >&2
    printf '%-10s %-60s %-45s %s\n' \
        'TYPE' 'SOURCE' 'DESTINATION' 'RW' >&2
    docker_cmd container inspect \
        --format '{{range .Mounts}}{{printf "%-10s %-60s %-45s %t\n" .Type .Source .Destination .RW}}{{end}}' \
        "${CONTAINER_TEST}" >&2 || true
}

canonical_directory() {
    local directory="$1"
    (cd -- "${directory}" 2>/dev/null && pwd -P)
}

verify_bind_mount() {
    local destination="$1"
    local expected_source="$2"
    local mount_rows
    local mount_count
    local found_type="non trovato"
    local found_source="non trovata"
    local found_destination="non trovata"
    local found_rw="non trovato"
    local canonical_expected
    local canonical_found

    printf '\nVerifica mount:\n'
    printf '  Destinazione:    %s\n' "${destination}"
    printf '  Sorgente attesa: %s\n' "${expected_source}"

    mount_rows="$(docker_cmd container inspect \
        --format "{{range .Mounts}}{{if eq .Destination \"${destination}\"}}{{printf \"%s|%s|%s|%t\\n\" .Type .Source .Destination .RW}}{{end}}{{end}}" \
        "${CONTAINER_TEST}")"
    mount_count="$(printf '%s\n' "${mount_rows}" | awk 'NF { count++ } END { print count+0 }')"

    if [[ "${mount_count}" != "1" ]]; then
        printf '  Sorgente trovata: %s\n' "${found_source}"
        printf '  Tipo trovato:     %s\n' "${found_type}"
        printf '  Risultato:         ERRORE, trovati %s mount per la destinazione\n' \
            "${mount_count}" >&2
        show_mount_table
        return 1
    fi

    IFS='|' read -r found_type found_source found_destination found_rw <<< "${mount_rows}"
    printf '  Sorgente trovata: %s\n' "${found_source}"
    printf '  Tipo trovato:     %s\n' "${found_type}"

    canonical_expected="$(canonical_directory "${expected_source}")" || {
        printf '  Risultato:         ERRORE, sorgente attesa non canonicalizzabile\n' >&2
        show_mount_table
        return 1
    }
    canonical_found="$(canonical_directory "${found_source}")" || {
        printf '  Risultato:         ERRORE, sorgente trovata non canonicalizzabile\n' >&2
        show_mount_table
        return 1
    }

    if [[ "${found_type}" != "bind" \
        || "${canonical_found}" != "${canonical_expected}" \
        || "${found_destination}" != "${destination}" \
        || "${found_rw}" != "true" ]]; then
        printf '  Risultato:         ERRORE (Type, Source, Destination o RW non corrisponde)\n' >&2
        show_mount_table
        return 1
    fi

    printf '  Risultato:         OK, bind mount scrivibile verificato\n'
}

verify_no_unexpected_bind_mounts() {
    local bind_mounts
    local unexpected_bind_mounts

    bind_mounts="$(docker_cmd container inspect \
        --format '{{range .Mounts}}{{if eq .Type "bind"}}{{printf "%s|%s|%t\n" .Source .Destination .RW}}{{end}}{{end}}' \
        "${CONTAINER_TEST}")"
    unexpected_bind_mounts="$(printf '%s\n' "${bind_mounts}" | awk -F '|' \
        '$2 != "/workspace" &&
         $2 != "/home/unsloth/.cache/huggingface" &&
         $2 != "/home/unsloth/modelli" && NF { print }')"

    if [[ -n "${unexpected_bind_mounts}" ]]; then
        printf '\nBind mount aggiuntivi inattesi (Source|Destination|RW):\n%s\n' \
            "${unexpected_bind_mounts}" >&2
        show_mount_table
        return 1
    fi

    printf '\nBind mount aggiuntivi: nessuno.\n'
}

show_test_logs() {
    if (( DOCKER_READY )) && container_test_exists; then
        printf '\nUltime 100 righe dei log del container temporaneo:\n' >&2
        docker_cmd logs --tail 100 "${CONTAINER_TEST}" >&2 || true
    fi
}

safe_remove_test_dir() {
    local expected="${PROJECT_DIR}/build/test-docker"

    if [[ "${TEST_DIR}" != "${expected}" ]] || [[ "${TEST_DIR}" == / ]] || [[ -z "${TEST_DIR}" ]]; then
        printf 'ERRORE: percorso temporaneo non valido; directory non rimossa: %s\n' "${TEST_DIR}" >&2
        return 1
    fi
    if [[ -e "${TEST_DIR}" ]]; then
        rm -rf -- "${TEST_DIR}"
        printf 'Directory temporanea eliminata: %s\n' "${TEST_DIR}"
    fi
}

cleanup() {
    local original_status="$1"
    local cleanup_status=0
    local actual_label=""

    trap - ERR EXIT INT TERM
    set +e
    PHASE="pulizia degli elementi temporanei"
    printf '\n==> Pulizia controllata\n'

    if (( DOCKER_READY )) && (( CONTAINER_CREATED )) && container_test_exists; then
        actual_label="$(docker_cmd container inspect \
            --format '{{index .Config.Labels "local.unsloth-studio.test-run"}}' \
            "${CONTAINER_TEST}" 2>/dev/null)"
        if [[ "${actual_label}" == "${RUN_ID}" ]]; then
            docker_cmd container rm --force "${CONTAINER_TEST}" >/dev/null
            printf 'Container temporaneo eliminato: %s\n' "${CONTAINER_TEST}"
        else
            printf 'ERRORE: il container temporaneo non ha il contrassegno atteso; non è stato eliminato.\n' >&2
            cleanup_status=1
        fi
    fi

    if (( DOCKER_READY )) && (( BUILD_STARTED )) && image_test_exists; then
        actual_label="$(docker_cmd image inspect \
            --format '{{index .Config.Labels "local.unsloth-studio.test-run"}}' \
            "${IMAGE_TEST}" 2>/dev/null)"
        if [[ "${actual_label}" == "${RUN_ID}" ]]; then
            docker_cmd image rm "${IMAGE_TEST}" >/dev/null
            printf 'Immagine temporanea eliminata: %s\n' "${IMAGE_TEST}"
        else
            printf "ERRORE: l'immagine temporanea non ha il contrassegno atteso; non è stata eliminata.\n" >&2
            cleanup_status=1
        fi
    fi

    if (( TEST_DIR_CREATED )); then
        safe_remove_test_dir || cleanup_status=1
    fi

    if (( original_status == 0 && cleanup_status != 0 )); then
        return "${cleanup_status}"
    fi
    return "${original_status}"
}

on_error() {
    local exit_code=$?
    local failed_command="${BASH_COMMAND:-sconosciuto}"
    local line_number="${BASH_LINENO[0]:-sconosciuta}"

    trap - ERR
    set +e
    printf '\nERRORE durante la fase: %s\n' "${PHASE}" >&2
    printf 'Riga: %s\n' "${line_number}" >&2
    printf 'Comando: %s\n' "${failed_command}" >&2
    printf 'Codice di uscita: %s\n' "${exit_code}" >&2
    show_test_logs
    exit "${exit_code}"
}

trap on_error ERR
trap 'exit 130' INT TERM
trap 'cleanup $?' EXIT

PHASE="controllo dei programmi richiesti"
for required_command in \
    awk basename curl date dirname find id ln mkdir rm sleep sort tar tee touch; do
    if ! command -v "${required_command}" >/dev/null 2>&1; then
        printf 'Programma richiesto non trovato: %s. Installa il programma e riprova.\n' \
            "${required_command}" >&2
        exit 1
    fi
done

PHASE="preparazione del log"
mkdir -p -- "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/test-docker-$(date '+%Y%m%d-%H%M%S').log"
if [[ -e "${LOG_FILE}" ]]; then
    LOG_FILE="${LOG_DIR}/test-docker-$(date '+%Y%m%d-%H%M%S')-$$.log"
fi
touch -- "${LOG_FILE}"
ln -sfn -- "$(basename -- "${LOG_FILE}")" "${LOG_DIR}/ultimo-test-docker.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

PHASE="controlli di sicurezza"
log "Controlli di sicurezza"
[[ -f "${PROJECT_DIR}/Dockerfile" ]] || { printf 'Dockerfile non trovato: %s\n' "${PROJECT_DIR}/Dockerfile" >&2; exit 1; }
[[ "${IMAGE_TEST}" == "local/unsloth-studio-cpu:test" ]]
[[ "${CONTAINER_TEST}" == "unsloth-studio-cpu-test" ]]
[[ "${CONTAINER_TEST}" != "${CONTAINER_MAIN}" ]]
[[ "${IMAGE_TEST}" != "${IMAGE_MAIN}" ]]
[[ "${HOST_PORT}" == "18888" && "${HOST_PORT}" != "8888" ]]
[[ "${TEST_DIR}" == "${PROJECT_DIR}/build/test-docker" ]]
command -v docker >/dev/null 2>&1 || { printf 'Docker non è installato.\n' >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { printf 'curl non è installato.\n' >&2; exit 1; }

if docker info >/dev/null 2>&1; then
    DOCKER_USE_SUDO=0
else
    command -v sudo >/dev/null 2>&1 || { printf 'Docker non è accessibile e sudo non è disponibile.\n' >&2; exit 1; }
    printf 'Docker richiede privilegi; sudo può chiedere la password nel terminale.\n'
    sudo docker info >/dev/null
    DOCKER_USE_SUDO=1
fi
DOCKER_READY=1

if container_test_exists; then
    printf 'Il container %s esiste già: nessun elemento è stato modificato.\n' "${CONTAINER_TEST}" >&2
    exit 1
fi
if image_test_exists; then
    printf "L'immagine %s esiste già: non sarà sovrascritta o eliminata.\n" "${IMAGE_TEST}" >&2
    exit 1
fi
if [[ -e "${TEST_DIR}" ]]; then
    printf 'La directory temporanea %s esiste già: non sarà modificata.\n' "${TEST_DIR}" >&2
    exit 1
fi

MAIN_IMAGE_ID_BEFORE="$(docker_cmd image inspect --format '{{.Id}}' "${IMAGE_MAIN}" 2>/dev/null || printf 'assente')"
MAIN_CONTAINER_ID_BEFORE="$(docker_cmd container inspect --format '{{.Id}}' "${CONTAINER_MAIN}" 2>/dev/null || printf 'assente')"
MAIN_CONTAINER_STATE_BEFORE="$(docker_cmd container inspect --format '{{.State.Status}}' "${CONTAINER_MAIN}" 2>/dev/null || printf 'assente')"

printf '\nIl test creerà e poi eliminerà soltanto:\n'
printf '  immagine:  %s\n' "${IMAGE_TEST}"
printf '  container: %s\n' "${CONTAINER_TEST}"
printf '  directory: %s\n' "${TEST_DIR}"
printf '  modalità:  %s\n' "${BUILD_MODE}"
printf 'Scrivi esattamente ESEGUI TEST DOCKER: '
IFS= read -r confirmation || exit 1
if [[ "${confirmation}" != "ESEGUI TEST DOCKER" ]]; then
    printf 'Operazione annullata.\n'
    exit 0
fi

PHASE="creazione delle directory temporanee vuote"
mkdir -p -- "${TEST_MODELS}" "${TEST_HUGGINGFACE}"
TEST_DIR_CREATED=1
[[ -z "$(find "${TEST_DIR}" -type f -print -quit)" ]]

PHASE="build dell'immagine temporanea"
log "Build di ${IMAGE_TEST}"
BUILD_STARTED=1
docker_cmd build "${BUILD_CACHE_ARGS[@]}" --progress=plain \
    --build-arg "HOST_UID=$(id -u)" \
    --build-arg "HOST_GID=$(id -g)" \
    --label "${OWNERSHIP_LABEL}" \
    --tag "${IMAGE_TEST}" \
    "${PROJECT_DIR}"
BUILD_RESULT="completata"
printf 'Risultato build: %s (%s)\n' "${BUILD_RESULT}" "$(docker_cmd image inspect --format '{{.Id}}' "${IMAGE_TEST}")"

PHASE="creazione del container temporaneo senza mount"
docker_cmd create \
    --name "${CONTAINER_TEST}" \
    --label "${OWNERSHIP_LABEL}" \
    "${IMAGE_TEST}" >/dev/null
CONTAINER_CREATED=1

PHASE="verifica dei file nell'immagine originale"
IMAGE_ARCHIVE="${TEST_DIR}/image-rootfs.tar"
docker_cmd export "${CONTAINER_TEST}" > "${IMAGE_ARCHIVE}"

set +e
tar --list --verbose --numeric-owner --file "${IMAGE_ARCHIVE}" | awk \
    -v limit="${MAX_EMBEDDED_WEIGHT_BYTES}" '
function normalized_path(    p, i) {
    p=$6
    for (i=7; i<=NF; i++) p=p " " $i
    sub(/^\.\//, "", p)
    p="/" p
    if (p != "/") sub(/\/+$/, "", p)
    return p
}
function lower(value) {
    return tolower(value)
}
function mib(bytes) {
    return sprintf("%.2f MiB", bytes / 1048576)
}
BEGIN {
    danger=0
    printf "File runtime e possibili pesi presenti nella immagine originale:\n"
}
{
    path=normalized_path()
    size=$3+0
    path_lower=lower(path)
    is_directory=(substr($1, 1, 1) == "d")

    invalid_structural_type=(!is_directory &&
        (path_lower == "/workspace" ||
         path_lower == "/workspace/modelli" ||
         path_lower == "/home/unsloth/modelli"))
    in_user_directory=(path_lower ~ /^\/workspace\/modelli\// ||
        path_lower ~ /^\/home\/unsloth\/modelli\//)
    unexpected_workspace_entry=(path_lower ~ /^\/workspace\// &&
        !(path_lower == "/workspace/modelli" && is_directory) &&
        path_lower !~ /^\/workspace\/modelli\//)
    if (invalid_structural_type || in_user_directory || unexpected_workspace_entry) {
        printf "%s | %s | possibile modello incorporato: directory utente non vuota\n", path, mib(size)
        danger=1
        next
    }

    if (path_lower ~ /\.pth$/) {
        printf "%s | %s | file Python .pth non classificato come modello\n", path, mib(size)
        next
    }

    if (path_lower !~ /\.(gguf|safetensors|pt|onnx|bin)$/) next

    if (size > limit) {
        printf "%s | %s | possibile modello incorporato\n", path, mib(size)
        danger=1
    } else if (path_lower ~ /^\/opt\/unsloth-studio\/llama\.cpp\/models\/ggml-vocab-[^/]*\.gguf$/) {
        printf "%s | %s | file runtime consentito\n", path, mib(size)
    } else {
        printf "%s | %s | piccolo file di test consentito\n", path, mib(size)
    }
}
END {
    if (danger) exit 42
}'
image_scan_status=$?
set -e

if (( image_scan_status == 42 )); then
    printf "Trovato almeno un possibile modello incorporato o un file nella directory utente dell'immagine.\n" >&2
    exit 1
elif (( image_scan_status != 0 )); then
    printf "Impossibile analizzare il filesystem esportato dell'immagine, codice %s.\n" \
        "${image_scan_status}" >&2
    exit "${image_scan_status}"
fi
rm -f -- "${IMAGE_ARCHIVE}"
docker_cmd container rm "${CONTAINER_TEST}" >/dev/null
CONTAINER_CREATED=0

PHASE="creazione del container temporaneo con mount isolati"
docker_cmd create \
    --name "${CONTAINER_TEST}" \
    --label "${OWNERSHIP_LABEL}" \
    --init \
    --shm-size=2g \
    --publish "127.0.0.1:${HOST_PORT}:${CONTAINER_PORT}" \
    --mount "type=bind,source=${TEST_WORKSPACE},target=/workspace" \
    --mount "type=bind,source=${TEST_HUGGINGFACE},target=/home/unsloth/.cache/huggingface" \
    --mount "type=bind,source=${TEST_MODELS},target=/home/unsloth/modelli" \
    "${IMAGE_TEST}" >/dev/null
CONTAINER_CREATED=1

PHASE="avvio del container temporaneo"
docker_cmd start "${CONTAINER_TEST}" >/dev/null

PHASE="attesa dell'healthcheck"
log "Attesa dell'healthcheck, massimo ${WAIT_SECONDS} secondi"
deadline=$((SECONDS + WAIT_SECONDS))
while (( SECONDS < deadline )); do
    running="$(docker_cmd container inspect --format '{{.State.Running}}' "${CONTAINER_TEST}")"
    health="$(docker_cmd container inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${CONTAINER_TEST}")"
    [[ "${running}" == "true" ]] || { printf 'Il container temporaneo si è arrestato.\n' >&2; exit 1; }
    [[ "${health}" != "unhealthy" ]] || { printf 'Healthcheck unhealthy.\n' >&2; exit 1; }
    if [[ "${health}" == "healthy" ]]; then
        HEALTH_RESULT="healthy"
        break
    fi
    sleep 3
done
[[ "${HEALTH_RESULT}" == "healthy" ]] || { printf 'Healthcheck non healthy entro %s secondi.\n' "${WAIT_SECONDS}" >&2; exit 1; }

PHASE="verifica dell'API"
API_RESPONSE="$(curl --fail --silent --show-error --max-time 5 "http://127.0.0.1:${HOST_PORT}/api/health")"

PHASE="verifiche del container"
docker_cmd exec "${CONTAINER_TEST}" sh -c \
    'test -d /workspace && test -d /workspace/modelli && test -d /home/unsloth/modelli'
INTERNAL_USER="$(docker_cmd container inspect --format '{{.Config.User}}' "${CONTAINER_TEST}")"
[[ -n "${INTERNAL_USER}" && "${INTERNAL_USER}" != "0" && "${INTERNAL_USER}" != "root" ]]
[[ "$(docker_cmd container inspect --format '{{.HostConfig.Privileged}}' "${CONTAINER_TEST}")" == "false" ]]
gpu_requests="$(docker_cmd container inspect --format '{{json .HostConfig.DeviceRequests}}' "${CONTAINER_TEST}")"
[[ "${gpu_requests}" == "null" || "${gpu_requests}" == "[]" ]]

PORT_RESULT="$(docker_cmd container inspect --format '{{json (index .HostConfig.PortBindings "8888/tcp")}}' "${CONTAINER_TEST}")"
[[ "${PORT_RESULT}" == '[{"HostIp":"127.0.0.1","HostPort":"18888"}]' ]]

verify_bind_mount "/workspace" "${TEST_WORKSPACE}"
verify_bind_mount "/home/unsloth/.cache/huggingface" "${TEST_HUGGINGFACE}"
verify_bind_mount "/home/unsloth/modelli" "${TEST_MODELS}"
verify_no_unexpected_bind_mounts
MOUNTS_RESULT="verificati: esclusivamente directory temporanee"

mounted_model_files="$(docker_cmd exec "${CONTAINER_TEST}" find \
    /workspace/modelli /home/unsloth/modelli -type f \
    \( -iname '*.gguf' -o -iname '*.safetensors' -o -iname '*.pt' \
       -o -iname '*.pth' -o -iname '*.onnx' -o -iname '*.bin' \) \
    -printf '%p | %s byte | possibile modello incorporato\n' 2>/dev/null)"
if [[ -n "${mounted_model_files}" ]]; then
    printf 'File modello trovati nelle directory temporanee che devono essere vuote:\n%s\n' \
        "${mounted_model_files}" >&2
    exit 1
fi
MODELS_RESULT="nessun peso oltre 50 MiB nell'immagine e nessun modello nelle directory temporanee"

PHASE="verifica dell'installazione principale"
MAIN_IMAGE_ID_AFTER="$(docker_cmd image inspect --format '{{.Id}}' "${IMAGE_MAIN}" 2>/dev/null || printf 'assente')"
MAIN_CONTAINER_ID_AFTER="$(docker_cmd container inspect --format '{{.Id}}' "${CONTAINER_MAIN}" 2>/dev/null || printf 'assente')"
MAIN_CONTAINER_STATE_AFTER="$(docker_cmd container inspect --format '{{.State.Status}}' "${CONTAINER_MAIN}" 2>/dev/null || printf 'assente')"
[[ "${MAIN_IMAGE_ID_AFTER}" == "${MAIN_IMAGE_ID_BEFORE}" ]]
[[ "${MAIN_CONTAINER_ID_AFTER}" == "${MAIN_CONTAINER_ID_BEFORE}" ]]
[[ "${MAIN_CONTAINER_STATE_AFTER}" == "${MAIN_CONTAINER_STATE_BEFORE}" ]]

PHASE="riepilogo finale"
log "Risultato del test"
printf 'Risultato build: %s\n' "${BUILD_RESULT}"
printf 'Healthcheck: %s\n' "${HEALTH_RESULT}"
printf 'Risposta /api/health: %s\n' "${API_RESPONSE}"
printf 'Utente interno: %s (non root)\n' "${INTERNAL_USER}"
printf 'Mount: %s\n' "${MOUNTS_RESULT}"
printf 'Associazione porta: %s\n' "${PORT_RESULT}"
printf 'Modelli: %s\n' "${MODELS_RESULT}"
printf 'Container temporaneo: %s, stato %s\n' \
    "${CONTAINER_TEST}" "$(docker_cmd container inspect --format '{{.State.Status}}' "${CONTAINER_TEST}")"
printf 'Immagine e container principali verificati e non modificati.\n'
printf 'La pulizia degli elementi temporanei viene eseguita ora dal trap EXIT.\n'
