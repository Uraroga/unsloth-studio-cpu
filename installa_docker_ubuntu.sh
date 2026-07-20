#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly LOG_DIR="${SCRIPT_DIR}/log"
readonly DOCKER_KEYRING="/etc/apt/keyrings/docker.asc"
readonly DOCKER_REPOSITORY="/etc/apt/sources.list.d/docker.sources"
readonly LEGACY_DOCKER_REPOSITORY="/etc/apt/sources.list.d/docker.list"
readonly INSTALL_CONFIRMATION="INSTALLA DOCKER"
readonly GROUP_CONFIRMATION="AGGIUNGI UTENTE A DOCKER"

PHASE="inizializzazione"
LOG_FILE=""
CURRENT_USER=""
TEMP_KEY_FILE=""
OS_CODENAME=""
LEGACY_REPOSITORY_PRESENT=0

log() {
    printf '\n==> %s\n' "$*"
}

die() {
    printf '\nERRORE: %s\n' "$*" >&2
    exit 1
}

on_error() {
    local exit_code=$?
    local line_number="${BASH_LINENO[0]:-sconosciuta}"
    local failed_command="${BASH_COMMAND:-sconosciuto}"

    trap - ERR
    printf '\nERRORE durante la fase: %s\n' "${PHASE}" >&2
    printf 'Riga: %s\nComando: %s\nCodice di uscita: %s\n' \
        "${line_number}" "${failed_command}" "${exit_code}" >&2
    exit "${exit_code}"
}
trap on_error ERR
trap 'printf "\nOperazione interrotta.\n" >&2; exit 130' INT TERM
trap '[[ -z "${TEMP_KEY_FILE}" ]] || rm -f -- "${TEMP_KEY_FILE}"' EXIT

require_command() {
    local command_name="$1"
    command -v "${command_name}" >/dev/null 2>&1 \
        || die "programma richiesto non trovato: ${command_name}."
}

service_is_active() {
    systemctl is-active --quiet docker
}

docker_works_for_user() {
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

docker_works_with_sudo() {
    command -v docker >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1
}

package_is_installed() {
    local package_name="$1"
    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "${package_name}" 2>/dev/null || true)" == "ii " ]]
}

check_conflicting_packages() {
    local package_name
    local -a conflicting_packages=()
    local -a candidates=(
        docker.io docker-compose docker-compose-v2 docker-doc
        podman-docker containerd runc
    )

    for package_name in "${candidates[@]}"; do
        if package_is_installed "${package_name}"; then
            conflicting_packages+=("${package_name}")
        fi
    done

    if (( ${#conflicting_packages[@]} == 0 )); then
        return 0
    fi

    printf '\nERRORE: sono installati pacchetti potenzialmente incompatibili con Docker CE:\n' >&2
    printf '  - %s\n' "${conflicting_packages[@]}" >&2
    printf '\nQuesti pacchetti possono fornire componenti Docker, containerd o runc in conflitto\n' >&2
    printf 'con le versioni distribuite dal repository ufficiale Docker.\n' >&2
    printf 'Valuta attentamente ed esegui manualmente, se appropriato:\n\n' >&2
    printf '  sudo apt-get remove %s\n' "${conflicting_packages[*]}" >&2
    printf '\nLo script non ha rimosso alcun pacchetto e non ha modificato i repository.\n' >&2
    exit 1
}

legacy_repository_is_official_docker_only() {
    awk '
        /^[[:space:]]*($|#)/ { next }
        {
            official = 0
            if ($1 != "deb" && $1 != "deb-src") {
                exit 1
            }
            for (field = 2; field <= NF; field++) {
                if ($field == "https://download.docker.com/linux/ubuntu" ||
                    $field == "http://download.docker.com/linux/ubuntu") {
                    official = 1
                }
            }
            if (!official) {
                exit 1
            }
            found = 1
        }
        END { if (!found) exit 1 }
    ' "${LEGACY_DOCKER_REPOSITORY}"
}

check_legacy_repository() {
    if [[ ! -e "${LEGACY_DOCKER_REPOSITORY}" ]]; then
        return 0
    fi
    [[ -f "${LEGACY_DOCKER_REPOSITORY}" && -r "${LEGACY_DOCKER_REPOSITORY}" ]] \
        || die "il repository precedente ${LEGACY_DOCKER_REPOSITORY} non è un file regolare leggibile. Non è stato modificato."
    if ! legacy_repository_is_official_docker_only; then
        die "${LEGACY_DOCKER_REPOSITORY} contiene una configurazione vuota, mista o non riconducibile con certezza al repository ufficiale Docker. Non è stato modificato: controllalo manualmente prima di riprovare."
    fi
    LEGACY_REPOSITORY_PRESENT=1
}

ask_to_add_user_to_docker_group() {
    local answer

    if id -nG "${CURRENT_USER}" | tr ' ' '\n' | grep -Fxq docker; then
        log "L'utente ${CURRENT_USER} appartiene già al gruppo docker"
        printf 'Per rendere effettiva un’aggiunta recente potrebbe essere necessario aprire una nuova sessione.\n'
        return 0
    fi

    printf '\nL’appartenenza al gruppo docker consente di controllare il demone Docker e concede\n'
    printf 'privilegi amministrativi sostanzialmente equivalenti a quelli dell’utente root.\n'
    printf 'Per aggiungere %s al gruppo docker, digitare esattamente:\n%s\n> ' \
        "${CURRENT_USER}" "${GROUP_CONFIRMATION}"
    IFS= read -r answer
    if [[ "${answer}" != "${GROUP_CONFIRMATION}" ]]; then
        printf 'Utente non aggiunto al gruppo docker. Docker resterà utilizzabile tramite sudo.\n'
        return 0
    fi

    PHASE="configurazione del gruppo docker"
    if ! getent group docker >/dev/null 2>&1; then
        sudo groupadd docker
    fi
    sudo usermod -aG docker "${CURRENT_USER}"
    log "Utente aggiunto al gruppo docker"
    printf 'Per applicare l’appartenenza al gruppo è necessario scegliere una di queste opzioni:\n'
    printf '  - uscire e rientrare nella sessione;\n'
    printf '  - riavviare il computer;\n'
    printf '  - eseguire manualmente "newgrp docker" per una prova temporanea.\n'
}

PHASE="controllo dei programmi richiesti"
for required_command in awk date dirname getent grep id mkdir mktemp rm tee tr uname; do
    require_command "${required_command}"
done
require_command sudo
require_command apt-get
require_command dpkg
require_command dpkg-query
require_command install
require_command systemctl

PHASE="preparazione del log"
mkdir -p -- "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/installazione-docker-$(date '+%Y%m%d-%H%M%S').log"
if [[ -e "${LOG_FILE}" ]]; then
    LOG_FILE="${LOG_DIR}/installazione-docker-$(date '+%Y%m%d-%H%M%S')-$$.log"
fi
exec > >(tee -a "${LOG_FILE}") 2>&1
printf 'Log: %s\n' "${LOG_FILE}"

PHASE="controllo della piattaforma"
log "Controllo del sistema"
[[ "$(uname -s)" == "Linux" ]] || die "è richiesto Linux."
[[ "$(uname -m)" == "x86_64" ]] || die "è richiesta l’architettura x86_64."
[[ -r /etc/os-release ]] || die "/etc/os-release non è leggibile."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "questo script supporta esclusivamente Ubuntu."
[[ "${VERSION_ID:-}" == "24.04" ]] \
    || die "questo script supporta esclusivamente Ubuntu 24.04 LTS."
[[ "$(dpkg --print-architecture)" == "amd64" ]] \
    || die "l’architettura dei pacchetti deve essere amd64."
OS_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
[[ -n "${OS_CODENAME}" ]] \
    || die "impossibile determinare il nome in codice Ubuntu da /etc/os-release."
[[ "${OS_CODENAME}" == "noble" ]] \
    || die "Ubuntu 24.04 LTS deve usare il nome in codice noble; rilevato: ${OS_CODENAME}."

if [[ "$(id -u)" == "0" ]]; then
    [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]] \
        || die "eseguire lo script come utente normale, non direttamente come root."
    CURRENT_USER="${SUDO_USER}"
else
    CURRENT_USER="$(id -un)"
fi

PHASE="controllo dello stato di Docker"
log "Controllo dell’installazione Docker esistente"
if docker_works_for_user && service_is_active; then
    log "Docker è già installato, il servizio è attivo ed è utilizzabile da ${CURRENT_USER}"
    printf 'Non è stata eseguita alcuna reinstallazione o modifica.\n'
    exit 0
fi

if service_is_active && docker_works_with_sudo; then
    log "Docker è installato e funziona soltanto tramite sudo"
    printf 'Il servizio è attivo, ma l’utente corrente non può usare direttamente il comando docker.\n'
    ask_to_add_user_to_docker_group
    exit 0
fi

docker_cli_present=0
if command -v docker >/dev/null 2>&1; then
    docker_cli_present=1
fi

PHASE="richiesta di conferma"
log "Riepilogo delle operazioni previste"
if (( docker_cli_present )); then
    printf 'Docker risulta presente ma non operativo. Non saranno rimossi o reinstallati pacchetti.\n'
    printf 'Lo script abiliterà e avvierà il servizio Docker esistente.\n'
else
    PHASE="controllo dei pacchetti incompatibili"
    check_conflicting_packages
    PHASE="controllo del repository Docker precedente"
    check_legacy_repository

    PHASE="richiesta di conferma"
    printf '%s\n' \
        '  - aggiornare gli indici APT necessari;' \
        '  - installare ca-certificates e curl se mancanti;' \
        '  - creare /etc/apt/keyrings e installare la chiave ufficiale Docker;' \
        '  - configurare una sola volta il repository APT ufficiale Docker per Ubuntu;' \
        '  - installare Docker Engine, CLI, containerd, Buildx e Compose;' \
        '  - abilitare e avviare il servizio Docker.'
    if (( LEGACY_REPOSITORY_PRESENT )); then
        printf '  - sostituire il precedente docker.list ufficiale con docker.sources in formato Deb822.\n'
    fi
fi
printf '\nNon saranno rimossi pacchetti, immagini, container, volumi o configurazioni esistenti.\n'
printf 'Per procedere, digitare esattamente:\n%s\n> ' "${INSTALL_CONFIRMATION}"
IFS= read -r install_answer
if [[ "${install_answer}" != "${INSTALL_CONFIRMATION}" ]]; then
    printf 'Operazione annullata. Il sistema non è stato modificato.\n'
    exit 0
fi

if (( docker_cli_present )); then
    PHASE="avvio del servizio Docker esistente"
    sudo systemctl enable --now docker
else
    PHASE="installazione dei prerequisiti"
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl

    PHASE="configurazione del repository ufficiale Docker"
    sudo install -m 0755 -d /etc/apt/keyrings
    TEMP_KEY_FILE="$(mktemp /tmp/docker-ubuntu-official-XXXXXX.asc)"
    curl --fail --show-error --silent --location --retry 3 \
        --proto '=https' --tlsv1.2 \
        https://download.docker.com/linux/ubuntu/gpg \
        --output "${TEMP_KEY_FILE}"
    sudo install -m 0644 "${TEMP_KEY_FILE}" "${DOCKER_KEYRING}"
    rm -f -- "${TEMP_KEY_FILE}"
    TEMP_KEY_FILE=""
    printf '%s\n' \
        'Types: deb' \
        'URIs: https://download.docker.com/linux/ubuntu' \
        "Suites: ${OS_CODENAME}" \
        'Components: stable' \
        "Architectures: $(dpkg --print-architecture)" \
        "Signed-By: ${DOCKER_KEYRING}" \
        | sudo tee "${DOCKER_REPOSITORY}" >/dev/null
    if (( LEGACY_REPOSITORY_PRESENT )); then
        sudo rm -f -- "${LEGACY_DOCKER_REPOSITORY}"
    fi

    PHASE="installazione dei pacchetti Docker"
    sudo apt-get update
    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    sudo systemctl enable --now docker
fi

PHASE="verifica finale di Docker"
log "Verifica dell’installazione Docker"
sudo docker version
sudo docker info
sudo systemctl is-active docker
sudo systemctl is-enabled docker

ask_to_add_user_to_docker_group
log "Preparazione di Docker completata"
