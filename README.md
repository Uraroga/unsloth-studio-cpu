# Unsloth Studio CPU Docker

Configurazione Docker indipendente e non ufficiale per eseguire Unsloth Studio **solo su CPU**, senza GPU. Il progetto ufficiale è [unslothai/unsloth](https://github.com/unslothai/unsloth).

Questa configurazione è pensata per inferenza e chat con modelli GGUF, compreso il tool calling quando supportato dal modello e da Studio. Non è pensata per addestramento o fine-tuning su CPU: le prestazioni sono molto inferiori a quelle di una GPU e i modelli grandi possono richiedere molta RAM.

## Requisiti

- Ubuntu 24.04 LTS su architettura x86_64;
- CPU; la configurazione usa 4 thread e non richiede GPU, runtime NVIDIA o modalità privilegiata;
- almeno 16 GiB di RAM, consigliati 32 GiB;
- spazio libero per immagine, cache e modelli;
- Docker Engine già installato, avviato e accessibile;
- `bash`, `curl` e gli altri normali programmi di Ubuntu usati dagli script.

Gli script provano prima `docker` con l'utente corrente e, quando previsto, riprovano con `sudo docker`: il terminale può quindi chiedere la password dell'utente. Il progetto non include e non scarica modelli GGUF.

## Ordine consigliato per una nuova prova

> **Importante:** non eseguire necessariamente tutti i comandi uno dopo l'altro. Leggi ogni messaggio, controlla l'esito e inserisci le conferme testuali soltanto dopo aver verificato cosa verrà creato o eliminato.

Dopo un nuovo clone, l'ordine logico consigliato è:

1. entrare nella cartella del progetto;
2. controllare la sintassi degli script Bash;
3. eseguire il test Docker isolato;
4. se il test termina correttamente, costruire l'immagine principale;
5. avviare Unsloth Studio;
6. leggere la password iniziale;
7. aprire l'interfaccia nel browser;
8. fermare e distruggere il container quando non serve più;
9. eliminare separatamente l'immagine Docker soltanto se realmente necessario.

Comandi completi:

```bash
cd /home/sergio/Progetti/unsloth-studio-cpu

find . -type f -name "*.sh" -exec bash -n {} \; &&
echo "OK: sintassi degli script corretta"

./testa_build_unsloth_studio_cpu.sh
./installa_unsloth_studio_cpu.sh
./avvia_unsloth_studio_cpu.sh
./leggi_password_unsloth_studio_cpu.sh
./ferma_distruggi_unsloth_studio_cpu.sh
./elimina_immagine_unsloth_studio_cpu.sh
```

Il percorso del comando `cd` è quello richiesto per questa installazione di esempio. Se hai clonato il repository altrove, usa il percorso reale.

### Limite attuale su un clone pulito

Il Dockerfile copia `build/unsloth-install.sh`, ma questo file è generato localmente ed escluso da Git. Lo script di test **non lo scarica**; è `installa_unsloth_studio_cpu.sh` a scaricarlo, e subito dopo costruisce anche l'immagine principale. Di conseguenza, con il codice attuale, il test isolato al punto 3 può completare la build soltanto se `build/unsloth-install.sh` è già presente. Su un clone completamente pulito fallirà durante la build per il file mancante.

Questo significa che l'ordine ideale “test isolato, poi immagine principale” non è interamente realizzabile al primo clone senza preparare quel file con un'operazione non fornita da uno script separato. Non copiare manualmente un installer non verificato: usa lo script di installazione sapendo che costruirà già `local/unsloth-studio-cpu:latest`, quindi esegui il test isolato come verifica separata.

## Le quattro operazioni da non confondere

| Operazione | Cosa riguarda | Cosa non riguarda |
| --- | --- | --- |
| Test Docker isolato | Immagine `local/unsloth-studio-cpu:test`, container `unsloth-studio-cpu-test`, porta `127.0.0.1:18888` e directory vuote sotto `build/test-docker` | Non monta `dati/`, non usa modelli reali e verifica di non modificare immagine e container principali |
| Installazione principale | Scarica l'installer ufficiale e costruisce `local/unsloth-studio-cpu:latest` | Non crea il container principale e non scarica modelli GGUF |
| Arresto e distruzione | Ferma e rimuove soltanto il container `unsloth-studio-cpu` | Non elimina immagine, cartelle persistenti, modelli, cache o log |
| Eliminazione immagine | Rimuove separatamente `local/unsloth-studio-cpu:latest` | Non rimuove dati persistenti; rifiuta di procedere se il container principale esiste |

Le cartelle locali `dati/workspace`, `dati/workspace/modelli` e `dati/huggingface` sono indipendenti dalla vita del container. Eliminare il container non equivale a cancellarle.

## Quale script devo usare?

| Necessità                              | Script |
| -------------------------------------- | ------ |
| Verificare il progetto in modo isolato | `testa_build_unsloth_studio_cpu.sh` |
| Costruire l'immagine principale        | `installa_unsloth_studio_cpu.sh` |
| Avviare Unsloth Studio                 | `avvia_unsloth_studio_cpu.sh` |
| Leggere la password iniziale           | `leggi_password_unsloth_studio_cpu.sh` |
| Fermare ed eliminare il container      | `ferma_distruggi_unsloth_studio_cpu.sh` |
| Eliminare anche l'immagine Docker      | `elimina_immagine_unsloth_studio_cpu.sh` |

## Controllo della sintassi Bash

Eseguilo prima di avviare gli script:

```bash
find . -type f -name "*.sh" -exec bash -n {} \; &&
echo "OK: sintassi degli script corretta"
```

Il messaggio `OK` appare soltanto se `bash -n` non rileva errori di sintassi. Il controllo non costruisce immagini, non crea container e non esegue le operazioni contenute negli script.

## Test Docker isolato

### `testa_build_unsloth_studio_cpu.sh`

Serve a costruire e collaudare una copia temporanea del progetto senza montare workspace, cache o modelli reali. Va eseguito prima di affidarsi all'installazione principale, tenendo presente il limite del file `build/unsloth-install.sh` spiegato sopra.

```bash
./testa_build_unsloth_studio_cpu.sh
```

Per forzare una build completa senza cache:

```bash
./testa_build_unsloth_studio_cpu.sh --no-cache
```

Prima di iniziare controlla gli argomenti, la presenza dei programmi richiesti, del Dockerfile e di Docker; convalida i nomi e i percorsi riservati al test; rifiuta di sovrascrivere un'immagine, un container o una directory temporanea già esistenti. Registra inoltre identificativo e stato dell'immagine e del container principali per verificare alla fine che non siano cambiati.

Mostra gli elementi temporanei previsti e richiede esattamente:

```text
ESEGUI TEST DOCKER
```

Se la conferma è diversa, annulla senza avviare la build. Dopo la conferma crea directory vuote sotto `build/test-docker`, l'immagine `local/unsloth-studio-cpu:test` e il container `unsloth-studio-cpu-test`. Pubblica la porta interna `8888` esclusivamente come `127.0.0.1:18888`.

Durante l'esecuzione la build può essere lunga e produrre molto testo. Lo script analizza il filesystem dell'immagine per individuare modelli incorporati o file inattesi, poi verifica healthcheck, risposta di `/api/health`, utente interno non root, assenza di modalità privilegiata e richieste GPU, porta, tre bind mount scrivibili e assenza di file modello nelle directory temporanee. Attende al massimo 180 secondi lo stato `healthy`.

Il log locale è `log/test-docker-AAAAMMGG-HHMMSS.log`; `log/ultimo-test-docker.log` punta all'ultimo. In caso di errore mostra anche le ultime 100 righe dei log Docker, quando il container esiste.

All'uscita tenta una pulizia controllata basata su un contrassegno univoco: elimina soltanto container e immagine temporanei creati da quella esecuzione e `build/test-docker`. Non elimina il log e non modifica `dati/`, modelli reali, immagine principale o container principale. Il test è riuscito quando compare il riepilogo con build completata, healthcheck `healthy`, verifiche superate e il comando restituisce il prompt con codice zero; subito dopo devono comparire i messaggi di pulizia degli elementi temporanei.

## Installazione principale

### `installa_unsloth_studio_cpu.sh`

Serve a preparare l'installer usato dal Dockerfile e a costruire l'immagine principale. Eseguilo dopo le verifiche preliminari, oppure per ricostruire l'immagine.

```bash
./installa_unsloth_studio_cpu.sh
```

Lo script controlla Linux, architettura x86_64, Ubuntu 24.04 LTS, Dockerfile, `curl`, Docker e relativi permessi. Crea, se mancanti, `build/`, `log/`, `dati/workspace/modelli` e `dati/huggingface`; scarica tramite HTTPS `https://unsloth.ai/install.sh`, verifica che inizi come script shell, lo salva come `build/unsloth-install.sh` e lo rende eseguibile.

Costruisce quindi `local/unsloth-studio-cpu:latest` passando UID e GID dell'utente. Il Dockerfile parte da Ubuntu 24.04, installa Unsloth Studio in `/opt/unsloth-studio` con Python 3.13 e opzione `--no-torch`, verifica il comando `unsloth --version`, espone internamente la porta `8888` e definisce il healthcheck su `/api/health`. La build può scaricare molti pacchetti e richiedere parecchio tempo.

Non è richiesta una conferma testuale. Il log è `log/installazione-AAAAMMGG-HHMMSS-XXXXXX.log`; non viene creato un collegamento “ultimo log”. Lo script conserva l'installer scaricato, le directory locali e l'immagine costruita; non elimina dati, non scarica modelli GGUF e non crea container. Una nuova build può aggiornare il tag `latest` secondo il normale comportamento di Docker.

L'operazione è conclusa correttamente quando stampa `Immagine costruita: local/unsloth-studio-cpu:latest`, conferma che nessun container o modello è stato creato o scaricato e termina con codice zero. Verifica inoltre che l'immagine prodotta sia `linux/amd64`.

## Modelli e dati persistenti

Metti manualmente un modello GGUF ottenuto legalmente in:

```text
dati/workspace/modelli/
```

Esempio:

```bash
cp /percorso/del/modello.gguf dati/workspace/modelli/
```

## Download manuale del modello consigliato

Il download dall'interfaccia di Unsloth Studio può essere usato normalmente. Se però rimane fermo, mostra una velocità pari a `0 B/s` oppure non avanza per diversi minuti, puoi interromperlo e scaricare manualmente il file GGUF. Questa è una procedura alternativa, non significa che il download dall'interfaccia sia sempre guasto.

Per una prima prova di questo progetto su un computer con CPU datata e 16 oppure 32 GB di RAM, il modello consigliato è `unsloth/gemma-4-E2B-it-GGUF`, nella quantizzazione `UD-Q4_K_XL`. Il file esatto è `gemma-4-E2B-it-UD-Q4_K_XL.gguf`.

Il container può essere fermo durante il download. Scarica il modello **sul computer**, nella cartella persistente del progetto, non dentro il container. La posizione completa è:

```text
/home/sergio/Progetti/unsloth-studio-cpu/dati/workspace/modelli
```

Per prima cosa entra nella cartella corretta:

```bash
cd /home/sergio/Progetti/unsloth-studio-cpu

mkdir -p dati/workspace/modelli
cd dati/workspace/modelli
```

Scarica direttamente il file verificato dal repository ufficiale su Hugging Face con `wget`:

```bash
wget -c \
  -O gemma-4-E2B-it-UD-Q4_K_XL.gguf \
  "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-UD-Q4_K_XL.gguf"
```

L'opzione `-c` permette a `wget` di provare a riprendere un download parziale con lo stesso nome. Se `wget` non è disponibile, usa il comando equivalente con `curl`:

```bash
curl --fail --location --continue-at - \
  --output gemma-4-E2B-it-UD-Q4_K_XL.gguf \
  "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-UD-Q4_K_XL.gguf"
```

Non avviare Studio usando un file ancora incompleto. Attendi che il comando termini senza errori e restituisca il prompt. Verifica quindi l'integrità del file confrontando il checksum SHA-256 pubblicato nella pagina ufficiale:

```bash
echo "b8906b8c5e05e57b657646bbc657bd35814a269b2c20f0a2579047fafa1a67dd  gemma-4-E2B-it-UD-Q4_K_XL.gguf" \
  | sha256sum --check
```

Se il download è completo e integro, il risultato deve essere:

```text
gemma-4-E2B-it-UD-Q4_K_XL.gguf: OK
```

Se compare `FAILED`, non usare il file: il download è incompleto o non corrisponde al file verificato. Riprendi il download con lo stesso comando oppure elimina soltanto quel file incompleto e scaricalo nuovamente.

Quando il container principale viene creato o avviato, lo script `avvia_unsloth_studio_cpu.sh` monta questa directory in:

```text
/home/unsloth/modelli
```

Se il container era fermo, avvialo normalmente dalla cartella del progetto:

```bash
cd /home/sergio/Progetti/unsloth-studio-cpu
./avvia_unsloth_studio_cpu.sh
```

Lo script di avvio verifica che i file GGUF presenti sul computer siano leggibili nel container. Al termine mostra sia la cartella sul computer sia `/home/unsloth/modelli`. A quel punto apri o aggiorna l'interfaccia di Unsloth Studio e seleziona il modello dalla directory montata.

I mount usati dal container principale sono:

| Cartella sul PC | Percorso nel container | Contenuto |
| --- | --- | --- |
| `dati/workspace` | `/workspace` | workspace persistente |
| `dati/huggingface` | `/home/unsloth/.cache/huggingface` | cache Hugging Face persistente |
| `dati/workspace/modelli` | `/home/unsloth/modelli` | modelli, visibili anche sotto `/workspace/modelli` |

Database, account, impostazioni e chat di Unsloth Studio non hanno un mount dedicato verificato. Se rimangono soltanto nel filesystem interno del container, possono andare persi quando il container viene eliminato.

## Avvio di Unsloth Studio

### `avvia_unsloth_studio_cpu.sh`

Serve a creare e avviare il container principale, oppure a riavviarlo se esiste già ed è fermo. Va eseguito dopo la costruzione dell'immagine.

```bash
./avvia_unsloth_studio_cpu.sh
```

Controlla `docker`, `curl`, accesso al demone e presenza di `local/unsloth-studio-cpu:latest`. Crea le tre directory persistenti. Se il container esiste, verifica che usi esattamente l'immagine prevista, la porta prevista e i tre mount previsti; in caso contrario non lo modifica. Se deve avviarlo, controlla con `ss` o `lsof` che la porta 8888 non sia già occupata.

Quando necessario crea `unsloth-studio-cpu` con `--init`, memoria condivisa di 2 GiB, i tre bind mount e associazione `127.0.0.1:8888:8888`. Non richiede conferme testuali. Non elimina alcun dato, container o immagine.

Attende fino a 180 secondi che il container resti in esecuzione, diventi `healthy` e risponda su `http://127.0.0.1:8888/api/health`. Verifica poi i mount, la leggibilità della directory dei modelli e che tutti i file GGUF presenti sul PC siano leggibili nel container.

Il log locale è `log/avvio-AAAAMMGG-HHMMSS-XXXXXX.log`; `log/ultimo-avvio.log` punta all'ultimo. I log dell'applicazione sono inoltre disponibili tramite `docker logs unsloth-studio-cpu`; in caso di errore lo script ne mostra fino a 100 righe.

L'avvio è riuscito quando viene mostrata la tabella del container e compaiono indirizzo `http://127.0.0.1:8888`, cartella modelli sul PC e `/home/unsloth/modelli`, senza errori finali.

## Password iniziale

### `leggi_password_unsloth_studio_cpu.sh`

Serve a mostrare la password temporanea iniziale. Eseguilo dopo che il container principale è stato avviato.

```bash
./leggi_password_unsloth_studio_cpu.sh
```

Controlla Docker e i permessi, verifica che `unsloth-studio-cpu` esista e sia in esecuzione, quindi cerca il primo file `.bootstrap_password` sotto `/opt/unsloth-studio` o `/home/unsloth` e ne mostra il contenuto. Non usa porte, non crea o elimina file, directory, container, immagini o dati e non richiede conferme testuali.

Questo script non salva un log locale: la password appare soltanto nel terminale. Non condividerla. Se il file non viene trovato, la password potrebbe essere già stata cambiata; se l'operazione riesce compaiono `Password temporanea di Unsloth Studio:` e un valore non vuoto.

Apri quindi, sullo stesso computer:

```text
http://127.0.0.1:8888
```

## Arresto e distruzione del container

### `ferma_distruggi_unsloth_studio_cpu.sh`

Serve a fermare e rimuovere **soltanto** il container principale quando non serve più o quando deve essere ricreato.

```bash
./ferma_distruggi_unsloth_studio_cpu.sh
```

Controlla Docker, cerca `unsloth-studio-cpu` e verifica che sia associato al nome immagine `local/unsloth-studio-cpu:latest`; se il container non esiste termina correttamente senza eliminare nulla. Mostra nome, immagine, stato e cartelle che resteranno.

Richiede esattamente:

```text
DISTRUGGI
```

Una risposta diversa annulla l'operazione. L'opzione `--yes` salta consapevolmente la conferma. Se il container è attivo prova un arresto ordinato con timeout di 30 secondi, poi lo rimuove; se l'arresto fallisce forza la rimozione del solo container. Se è già fermo lo rimuove direttamente. Non usa porte.

Vengono persi soltanto i dati rimasti all'interno del container e non montati. Lo script non cancella `dati/workspace`, `dati/workspace/modelli`, `dati/huggingface`, i log o l'immagine. Il log è `log/distruzione-AAAAMMGG-HHMMSS-XXXXXX.log`; `log/ultima-distruzione.log` punta all'ultimo.

L'operazione è riuscita quando verifica che il container non esista più, che l'immagine esista ancora e stampa `Operazione completata`, insieme alla conferma che dati persistenti e modelli non sono stati cancellati.

## Eliminazione separata dell'immagine

### `elimina_immagine_unsloth_studio_cpu.sh`

Serve a rimuovere l'immagine principale per recuperare spazio. Eseguilo soltanto se non serve più e dopo aver rimosso il container principale.

```bash
./elimina_immagine_unsloth_studio_cpu.sh
```

Controlla argomenti, Docker e permessi; rifiuta di procedere se `unsloth-studio-cpu` esiste o se `local/unsloth-studio-cpu:latest` non esiste. Mostra identificativo, tag e dimensione dell'immagine, poi richiede esattamente:

```text
ELIMINA IMMAGINE
```

Una risposta diversa annulla. L'opzione `--yes` salta la conferma. Lo script esegue la rimozione dell'immagine e verifica che non sia più ispezionabile; non usa porte, non elimina container, dati persistenti, modelli, cache o log.

Il log è `log/eliminazione-immagine-AAAAMMGG-HHMMSS-XXXXXX.log`; `log/ultima-eliminazione-immagine.log` punta all'ultimo. L'operazione è riuscita quando stampa `Eliminata esclusivamente l'immagine local/unsloth-studio-cpu:latest.` e termina con codice zero.

## File locali e Git

- `build/` contiene l'installer scaricato e le directory temporanee del test;
- `dati/` contiene workspace, modelli e cache persistenti;
- `log/` contiene i log degli script locali;
- `IMMAGINE.txt` e `docker-image-inspect.json`, quando presenti, sono riepiloghi locali;
- `VERSION` contiene la versione del progetto e `CHANGELOG.md` ne descrive le modifiche;
- `.github/workflows/validate.yml` controlla Dockerfile, sintassi Bash e ShellCheck su Ubuntu 24.04.

Queste directory e i file sensibili o voluminosi sono esclusi da Git secondo `.gitignore` e `.dockerignore`. Non pubblicare password, token, database o modelli.

## Verifica finale e risoluzione dei problemi

Comandi utili:

```bash
docker ps -a --filter "name=unsloth-studio-cpu"
docker images "local/unsloth-studio-cpu"
docker logs unsloth-studio-cpu
docker inspect --format '{{.State.Health.Status}}' unsloth-studio-cpu
```

- `docker ps -a` mostra se il container principale esiste e il suo stato;
- `docker images` mostra i tag `latest` e, se una pulizia del test non è riuscita, eventualmente `test`;
- `docker logs` mostra i log prodotti dentro il container;
- `docker inspect` deve restituire `healthy` quando Studio è pronto.

Se i comandi Docker richiedono privilegi, anteponi `sudo`. Controlla anche i file sotto `log/`, che la porta `127.0.0.1:8888` sia libera e che Docker sia avviato. Una ricostruzione o la rimozione del container non elimina automaticamente dati persistenti e cache.

## Licenze e riconoscimenti

Il codice di questo repository è distribuito secondo GNU AGPL v3; vedi [LICENSE](LICENSE). Le dipendenze conservano le proprie licenze, riepilogate in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Grazie ai progetti [Unsloth](https://github.com/unslothai/unsloth) e [llama.cpp](https://github.com/ggml-org/llama.cpp).
