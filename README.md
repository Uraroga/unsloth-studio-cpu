# Unsloth Studio CPU Docker

Configurazione Docker indipendente e non ufficiale per eseguire Unsloth Studio su una macchina senza GPU. Il progetto ufficiale è [unslothai/unsloth](https://github.com/unslothai/unsloth).

Questa configurazione serve per inferenza e chat con modelli GGUF, incluso il tool calling quando supportato dal modello e da Studio. Non è pensata per addestramento o fine-tuning su CPU: le prestazioni sono molto inferiori a quelle di una GPU e modelli grandi possono richiedere molta RAM.

## Avvio rapido

Questo progetto è una configurazione indipendente, non ufficiale e CPU-only per Unsloth Studio.

È pensato per **Ubuntu 24.04 LTS**. Docker deve essere già installato e funzionante. Non è necessaria una GPU.

Il progetto non contiene modelli GGUF. Per usare la chat locale dovrai procurarti legalmente un modello compatibile.

Apri il terminale ed esegui i comandi uno dopo l'altro.

### 1. Scarica il progetto

Crea la cartella `Progetti`, se non esiste, e scarica il repository:

```bash
mkdir -p ~/Progetti
cd ~/Progetti
git clone https://github.com/Uraroga/unsloth-studio-cpu.git
cd unsloth-studio-cpu
```

Il comando `mkdir -p` crea la cartella soltanto se non è già presente.

### 2. Costruisci l'immagine Docker

```bash
./installa_unsloth_studio_cpu.sh
```

La costruzione può richiedere parecchio tempo.

Lo script scarica e installa nell'immagine Docker i componenti necessari. Non installa Docker e non scarica modelli GGUF.

Attendi che il comando termini e che ritorni il prompt del terminale senza errori.

### 3. Aggiungi un modello GGUF

Copia un modello GGUF nella cartella:

```text
dati/workspace/modelli/
```

Esempio:

```bash
cp /percorso/del/modello.gguf dati/workspace/modelli/
```

Usa soltanto modelli ottenuti legalmente. I modelli non devono essere aggiunti al repository Git.

Unsloth Studio può essere avviato anche senza modello, ma per utilizzare la chat locale serve un modello GGUF compatibile.

### 4. Avvia Unsloth Studio

```bash
./avvia_unsloth_studio_cpu.sh
```

### 5. Leggi la password iniziale

```bash
./leggi_password_unsloth_studio_cpu.sh
```

Non pubblicare e non condividere la password.

### 6. Apri l'interfaccia

Apri nel browser dello stesso computer:

```text
http://127.0.0.1:8888
```

### 7. Seleziona il modello

Nell'interfaccia di Unsloth Studio, i modelli sono disponibili nel percorso:

```text
/home/unsloth/modelli
```

### In pratica

1. clona il progetto;
2. costruisci l'immagine Docker;
3. copia un modello GGUF nella cartella dei modelli;
4. avvia Unsloth Studio;
5. leggi la password;
6. apri l'interfaccia nel browser.

## Requisiti

- Ubuntu 24.04 LTS (piattaforma verificata);
- CPU x86_64; test previsto su Intel Core i5-4590 con 4 thread;
- almeno 16 GiB di RAM, consigliati 32 GiB;
- spazio libero per immagine, cache e modelli;
- Docker Engine.

Gli script sono scritti per `bash` e usano normali programmi disponibili su Ubuntu, tra cui `curl`, `tar`, `awk`, `find` e `tee`. Lo script di avvio controlla la porta con `ss` oppure, se `ss` non è disponibile, con `lsof`. Docker viene usato direttamente quando l'utente ha i permessi; altrimenti gli script provano `sudo docker` e il terminale può chiedere la password. Lo script di test controlla i propri programmi richiesti prima di iniziare la build.

Non servono GPU, runtime NVIDIA o modalità privilegiata. La build usa Python 3.13 tramite l'installer ufficiale e la modalità `--no-torch`. L'installer di Unsloth e alcune sue dipendenze sono risolti al momento della build: finché il progetto ufficiale non offre un artefatto stabile completamente bloccabile, una ricostruzione futura può installare versioni diverse.

## Installazione

```bash
git clone https://github.com/Uraroga/unsloth-studio-cpu.git
cd unsloth-studio-cpu
./installa_unsloth_studio_cpu.sh
```

Lo script costruisce `local/unsloth-studio-cpu:latest`; non scarica modelli e non crea container.

Durante l'installazione, `installa_unsloth_studio_cpu.sh` scarica l'installer ufficiale di Unsloth in `build/unsloth-install.sh`. Il Dockerfile copia e usa quel file per installare Studio nell'immagine. La directory `build/` è generata localmente ed è intenzionalmente esclusa da Git: dopo un clone nuovo bisogna quindi usare lo script di installazione. Un semplice `docker build` eseguito prima dello script può fallire perché `build/unsloth-install.sh` non esiste ancora.

Il progetto è ricostruibile attraverso lo script, ma la scelta attuale non garantisce immagini identiche byte per byte nel tempo. Ubuntu 24.04 non è fissata tramite digest, i pacchetti APT non sono bloccati a versioni esatte, l'installer ufficiale viene scaricato al momento e le versioni risolte di Unsloth e llama.cpp possono cambiare.

## Test Docker isolato

Prima di usare l'installazione principale è possibile eseguire:

```bash
./testa_build_unsloth_studio_cpu.sh
```

Lo script costruisce l'immagine temporanea `local/unsloth-studio-cpu:test` e usa un container temporaneo separato sulla porta `127.0.0.1:18888`. Workspace, cache e cartella modelli del test sono vuoti e isolati sotto `build/test-docker`: non vengono usati dati o modelli reali. Lo script controlla build, healthcheck, API, utente interno, porta, mount e assenza di file modello. Al termine, anche in caso di errore quando possibile, elimina soltanto il container, l'immagine e le directory temporanee contrassegnate per il test.

Prima di procedere richiede di scrivere esattamente:

```text
ESEGUI TEST DOCKER
```

## Modelli e avvio

Metti manualmente un modello autorizzato, per esempio `modello.gguf`, in:

```text
dati/workspace/modelli/modello.gguf
```

Non sono inclusi modelli e questo progetto non fornisce collegamenti a copie non autorizzate. Avvia con:

```bash
./avvia_unsloth_studio_cpu.sh
```

Apri <http://127.0.0.1:8888>. La porta è associata soltanto a localhost. In Studio la directory dei modelli è `/home/unsloth/modelli`; gli stessi file sono visibili anche in `/workspace/modelli`.

Per leggere una sola volta la password iniziale, quando ancora disponibile:

```bash
./leggi_password_unsloth_studio_cpu.sh
```

La password non viene salvata nei log del progetto.

## Persistenza e rimozione

- `dati/workspace` viene montata in `/workspace`;
- `dati/workspace/modelli` viene montata anche in `/home/unsloth/modelli`;
- `dati/huggingface` viene montata nella cache Hugging Face dell'utente `unsloth`;
- `log` contiene soltanto i log degli script locali.

Workspace, modelli e cache Hugging Face sono quindi conservati sul PC. Database, account, impostazioni e chat di Unsloth Studio non hanno ancora un mount dedicato verificato: non bisogna considerarli persistenti senza una verifica. Distruggendo il container, tutti i dati interni che non si trovano nelle directory montate possono essere persi.

Queste directory sono ignorate da Git. Per fermare ed eliminare esclusivamente il container:

```bash
./ferma_distruggi_unsloth_studio_cpu.sh
```

Conferma con `DISTRUGGI`. Dati, cache, modelli, log e immagine restano intatti. Per eliminare separatamente la sola immagine, dopo aver rimosso il container:

```bash
./elimina_immagine_unsloth_studio_cpu.sh
```

Conferma con `ELIMINA IMMAGINE`. È disponibile `--yes` per automazione consapevole.

## File del progetto e file locali

- `VERSION` contiene la versione del progetto.
- `CHANGELOG.md` descrive le modifiche delle versioni pubblicate.
- `.github/workflows/validate.yml` esegue su push e pull request il controllo del Dockerfile, `bash -n` e ShellCheck.
- `build/` contiene installer e directory temporanee generate localmente.
- `dati/` contiene workspace, modelli e cache persistenti.
- `log/` contiene i log prodotti dagli script.
- `IMMAGINE.txt` e `docker-image-inspect.json`, quando presenti, sono riepiloghi locali e non sono necessari per ricostruire il progetto.

Le directory `build/`, `dati/` e `log/`, i modelli, le cache, i database e le credenziali non vengono pubblicati nel repository Git.

## Risoluzione dei problemi

- Consulta `log/` e `docker logs unsloth-studio-cpu` senza condividere password o token.
- Verifica lo stato con `docker inspect --format '{{.State.Health.Status}}' unsloth-studio-cpu`.
- Controlla che la porta 8888 non sia occupata e che Docker sia avviato.
- Se cambi UID/GID o Dockerfile, rimuovi il solo container e ricostruisci l'immagine con lo script di installazione.
- Una ricostruzione completa non elimina automaticamente cache o dati persistenti.

## Licenze e riconoscimenti

Il codice di questo repository è distribuito secondo GNU AGPL v3; vedi [LICENSE](LICENSE). Le dipendenze mantengono le loro licenze, riepilogate in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Grazie ai progetti [Unsloth](https://github.com/unslothai/unsloth) e [llama.cpp](https://github.com/ggml-org/llama.cpp).
