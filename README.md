# 🔋 Battery Health Checker

Un'app leggera per Windows che mostra lo stato di salute della batteria del tuo laptop con un'interfaccia moderna in stile iOS — nessuna installazione, nessuna dipendenza esterna.

A lightweight Windows app that shows your laptop's battery health with a modern, iOS-style interface — no installation, no external dependencies.

![Platform](https://img.shields.io/badge/platform-Windows-blue) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)

---

## 🇮🇹 Italiano

### Cosa fa

- Mostra la **salute della batteria** (capacità attuale vs capacità di fabbrica) con un gauge circolare animato
- Visualizza **usura**, **cicli di ricarica**, **capacità attuale/originale**
- Mostra il **livello di carica attuale** e se il laptop è in ricarica
- **Rileva automaticamente** produttore e modello del PC (ASUS, Lenovo, HP, Dell, qualsiasi marca)
- Tema **scuro/chiaro** con switch animato stile iOS
- Interfaccia senza bordi, con card arrotondata e animazioni fluide

### Come funziona

Lo script usa `powercfg /batteryreport`, un comando **nativo di Windows** (non specifico per nessuna marca), che genera un report HTML leggendo i dati direttamente dal firmware della batteria (standard ACPI). Da quel report vengono estratti capacità di progetto, capacità massima attuale e cicli di ricarica.

Perché funziona identico su qualsiasi PC: non stai leggendo un tool proprietario, ma l'output di un componente del sistema operativo stesso — l'unico requisito è "Windows con batteria", non il produttore.

Il report temporaneo viene **eliminato automaticamente** alla chiusura dell'app.

### Requisiti

- Windows 10/11
- PowerShell 5.1 o superiore (preinstallato su Windows)
- Un dispositivo con batteria (non funziona su desktop fissi)

### Come usarlo

**Opzione 1 — Eseguibile già pronto (consigliato)**
Scarica `BatteryHealth.exe` dalla sezione [Releases](../../releases) e avvialo con doppio click.

> ⚠️ Essendo un eseguibile non firmato digitalmente, Windows Defender/SmartScreen potrebbe mostrare un avviso al primo avvio ("Windows ha protetto il tuo PC"). È un comportamento normale per eseguibili compilati da script open source non firmati — clicca su "Ulteriori informazioni" → "Esegui comunque". Il codice sorgente è interamente pubblico in questo repository, puoi verificarlo tu stesso.

**Opzione 2 — Eseguire lo script direttamente**
1. Scarica `Battery_Health_Checker.ps1` e `battery-icon.ico` (stessa cartella)
2. Apri PowerShell nella cartella e lancia:
   ```powershell
   Unblock-File -Path .\Battery_Health_Checker.ps1
   powershell -ExecutionPolicy Bypass -File .\Battery_Health_Checker.ps1
   ```

### Compilare il tuo .exe

Il repository include un workflow **GitHub Actions** che compila automaticamente l'eseguibile ad ogni nuovo tag di versione, usando [ps2exe](https://github.com/MScholtes/PS2EXE):

```bash
git tag v1.x
git push origin v1.x
```

La build gira su un runner Windows reale di GitHub e allega `BatteryHealth.exe` alla Release automaticamente — non serve installare nulla in locale.

### Struttura del progetto

```
Battery_Health_Checker.ps1     → script principale (UI + logica)
battery-icon.ico               → icona dell'app
.github/workflows/build-exe.yml → build automatica dell'exe
```

---

## 🇬🇧 English

### What it does

- Shows **battery health** (current vs factory capacity) with an animated circular gauge
- Displays **wear level**, **charge cycles**, **current/original capacity**
- Shows **current charge level** and whether the laptop is plugged in
- **Auto-detects** PC manufacturer and model (ASUS, Lenovo, HP, Dell, any brand)
- **Dark/light theme** with an animated iOS-style switch
- Borderless interface with a rounded card and smooth animations

### How it works

The script uses `powercfg /batteryreport`, a **native Windows command** (not vendor-specific), which generates an HTML report reading data directly from the battery firmware (ACPI standard). The report is parsed for design capacity, current full-charge capacity, and cycle count.

Why it behaves identically on any PC: you're not reading a proprietary vendor tool, you're reading output from the operating system itself — the only requirement is "Windows with a battery", not the manufacturer.

The temporary report file is **automatically deleted** when the app closes.

### Requirements

- Windows 10/11
- PowerShell 5.1 or later (pre-installed on Windows)
- A device with a battery (won't work on desktop PCs)

### Usage

**Option 1 — Prebuilt executable (recommended)**
Download `BatteryHealth.exe` from the [Releases](../../releases) section and double-click to run.

> ⚠️ Since it's an unsigned executable, Windows Defender/SmartScreen may show a warning on first launch ("Windows protected your PC"). This is expected for compiled executables from unsigned open-source scripts — click "More info" → "Run anyway". The full source code is public in this repository so you can verify it yourself.

**Option 2 — Run the script directly**
1. Download `Battery_Health_Checker.ps1` and `battery-icon.ico` (same folder)
2. Open PowerShell in that folder and run:
   ```powershell
   Unblock-File -Path .\Battery_Health_Checker.ps1
   powershell -ExecutionPolicy Bypass -File .\Battery_Health_Checker.ps1
   ```

### Building your own .exe

This repository includes a **GitHub Actions** workflow that automatically compiles the executable on every new version tag, using [ps2exe](https://github.com/MScholtes/PS2EXE):

```bash
git tag v1.x
git push origin v1.x
```

The build runs on a real Windows GitHub runner and automatically attaches `BatteryHealth.exe` to the Release — no local setup required.

### Project structure

```
Battery_Health_Checker.ps1     → main script (UI + logic)
battery-icon.ico               → app icon
.github/workflows/build-exe.yml → automatic exe build
```

---

## Licenza / License

_Non ancora specificata — aggiungi un file `LICENSE` se vuoi rendere esplicite le condizioni d'uso._
_Not yet specified — add a `LICENSE` file if you want to make usage terms explicit._