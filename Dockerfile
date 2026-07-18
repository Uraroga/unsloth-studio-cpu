FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG HOST_UID=1000
ARG HOST_GID=1000

ENV TZ=Europe/Rome \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    UNSLOTH_STUDIO_HOME=/opt/unsloth-studio \
    UNSLOTH_NO_TORCH=1 \
    UNSLOTH_SKIP_AUTOSTART=1 \
    UNSLOTH_PYTHON=3.13 \
    UNSLOTH_CPU_THREADS=4 \
    OMP_NUM_THREADS=4 \
    OPENBLAS_NUM_THREADS=4 \
    MKL_NUM_THREADS=4 \
    NUMEXPR_NUM_THREADS=4 \
    HF_HOME=/home/unsloth/.cache/huggingface \
    PATH=/opt/unsloth-studio/unsloth_studio/bin:/home/unsloth/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        ffmpeg \
        git \
        iproute2 \
        jq \
        libcurl4-openssl-dev \
        libgomp1 \
        libopenblas-dev \
        libssl-dev \
        lsof \
        pciutils \
        pkg-config \
        procps \
        python3 \
        sqlite3 \
        unzip \
        wget \
        zip \
    && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    if group_entry="$(getent group "${HOST_GID}")"; then \
        existing_group="${group_entry%%:*}"; \
        if [ "${existing_group}" != unsloth ]; then \
            if getent group unsloth >/dev/null; then \
                echo "Il gruppo unsloth esiste già con un GID diverso da ${HOST_GID}." >&2; \
                exit 1; \
            fi; \
            groupmod --new-name unsloth "${existing_group}"; \
        fi; \
    elif getent group unsloth >/dev/null; then \
        groupmod --gid "${HOST_GID}" unsloth; \
    else \
        groupadd --gid "${HOST_GID}" unsloth; \
    fi; \
    if user_entry="$(getent passwd "${HOST_UID}")"; then \
        existing_user="${user_entry%%:*}"; \
        if [ "${existing_user}" != unsloth ]; then \
            if getent passwd unsloth >/dev/null; then \
                echo "L'utente unsloth esiste già con un UID diverso da ${HOST_UID}." >&2; \
                exit 1; \
            fi; \
            usermod --login unsloth "${existing_user}"; \
        fi; \
        user_entry="$(getent passwd unsloth)"; \
        old_fields="${user_entry#*:*:*:*:*:}"; \
        old_home="${old_fields%%:*}"; \
        if [ "${old_home}" != /home/unsloth ]; then \
            if [ -d "${old_home}" ]; then \
                usermod --home /home/unsloth --move-home unsloth; \
            else \
                usermod --home /home/unsloth unsloth; \
            fi; \
        fi; \
        usermod --gid "${HOST_GID}" --shell /bin/bash unsloth; \
    elif getent passwd unsloth >/dev/null; then \
        user_entry="$(getent passwd unsloth)"; \
        old_fields="${user_entry#*:*:*:*:*:}"; \
        old_home="${old_fields%%:*}"; \
        if [ "${old_home}" = /home/unsloth ]; then \
            usermod \
                --uid "${HOST_UID}" \
                --gid "${HOST_GID}" \
                --shell /bin/bash \
                unsloth; \
        else \
            usermod \
                --uid "${HOST_UID}" \
                --gid "${HOST_GID}" \
                --home /home/unsloth \
                --move-home \
                --shell /bin/bash \
                unsloth; \
        fi; \
    else \
        useradd \
            --uid "${HOST_UID}" \
            --gid "${HOST_GID}" \
            --home-dir /home/unsloth \
            --create-home \
            --shell /bin/bash \
            unsloth; \
    fi; \
    mkdir -p \
        /home/unsloth \
        /home/unsloth/.cache/huggingface \
        /opt/unsloth-studio \
        /workspace; \
    chown -R "${HOST_UID}:${HOST_GID}" \
        /home/unsloth \
        /opt/unsloth-studio \
        /workspace

COPY build/unsloth-install.sh /tmp/unsloth-install.sh
RUN chown "${HOST_UID}:${HOST_GID}" /tmp/unsloth-install.sh

USER unsloth
WORKDIR /home/unsloth

# --no-torch realizza l'installazione ufficiale GGUF-only:
# evita CUDA e PyTorch su una CPU x86_64 compatibile priva di GPU dedicata.
RUN UNSLOTH_STUDIO_HOME=/opt/unsloth-studio \
    UNSLOTH_NO_TORCH=1 \
    UNSLOTH_SKIP_AUTOSTART=1 \
    UNSLOTH_PYTHON=3.13 \
    OMP_NUM_THREADS=4 \
    MAKEFLAGS=-j4 \
    /tmp/unsloth-install.sh --no-torch --python 3.13 --verbose \
    && test -x /opt/unsloth-studio/unsloth_studio/bin/unsloth \
    && unsloth --version \
    && rm -f /tmp/unsloth-install.sh

WORKDIR /workspace

EXPOSE 8888

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=5 \
    CMD curl -fsS http://127.0.0.1:8888/api/health >/dev/null || exit 1

CMD ["unsloth", "studio", "-H", "0.0.0.0", "-p", "8888"]
