# 🔴 IR JumpKit Builder 🕵️

> **One script. One USB. Every tool you need (probably👀) before an IR case.**

A self-contained PowerShell builder that downloads, organises, and embeds a complete **Incident Response USB toolkit** in a single run. Plug it into a Windows machine, run the builder once, and walk into the incident with a fully loaded kit in your pocket. ⚙️

**Developed by [Christos Xenofontos](https://dk.linkedin.com/in/chris857)**
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Christos%20Xenofontos-blue?logo=linkedin)](https://dk.linkedin.com/in/chris857)

---

## Table of Contents

- [What is the IR JumpKit Builder?](#what-is-the-ir-jumpkit-builder)
- [Who is this for?](#who-is-this-for)
- [⚠️ Disclaimers](#️-disclaimers)
- [Quick Start](#quick-start)
- [Builder Options](#builder-options)
- [USB Structure](#usb-structure)
- [Tool Reference](#tool-reference)
  - [01 · Triage Scripts](#01--triage-scripts)
    - [triage\_collect.ps1](#triage_collectps1)
    - [collect\_artifacts.ps1](#collect_artifactsps1)
    - [isolate\_host.ps1](#isolate_hostps1)
    - [hash\_files.ps1](#hash_filesps1)
    - [collect\_artifacts.sh](#collect_artifactssh)
    - [isolate\_host.sh](#isolate_hostsh)
    - [hash\_files.sh](#hash_filessh)
  - [02 · Forensics](#02--forensics)
    - [winpmem (full + mini variants)](#winpmem)
    - [avml](#avml)
    - [LiME](#lime)
    - [Velociraptor](#velociraptor)
    - [Disk Imaging Guide](#disk-imaging-guide)
  - [03 · Network](#03--network)
    - [Wireshark / tshark](#wireshark--tshark)
  - [04 · Malware Analysis](#04--malware-analysis)
    - [ProcMon](#procmon)
    - [Autoruns](#autoruns)
    - [YARA](#yara)
    - [HitmanPro](#hitmanpro)
    - [RootkitRevealer](#rootkitrevealer)
    - [Malwarebytes](#malwarebytes)
    - [AdwCleaner](#adwcleaner)
  - [05 · Log Analysis](#05--log-analysis)
    - [Chainsaw](#chainsaw)
  - [06 · Utilities](#06--utilities)
    - [CyberChef](#cyberchef)
    - [7-Zip](#7-zip)
    - [PuTTY / PSCP](#putty--pscp)
    - [HashMyFiles](#hashmyfiles)
    - [jq](#jq)
- [Order of Operations](#order-of-operations)
- [Evidence Folder](#evidence-folder)
- [Standalone Scripts (Repository)](#standalone-scripts-repository)
- [Build Report](#build-report)

---

## What is the IR JumpKit Builder?

The IR JumpKit Builder (`Build-IRJumpkit.ps1`) is a **single PowerShell script** that builds an entire Incident Response USB toolkit from scratch. When you run it against a USB drive (or any target folder), it:

1. Runs pre-flight checks (rights, internet, disk space)
2. Creates a clean, numbered folder structure
3. Downloads the latest version of every tool directly from authoritative sources (GitHub releases, vendor CDNs, Sysinternals)
4. Embeds ready-to-run IR scripts for Windows and Linux, no internet needed on the incident scene
5. Writes quick-start notes, cheatsheets, and an IOC template
6. Generates a full HTML + text build report with SHA-256 hashes and signatures of everything downloaded

The result is a **self-documenting, auditable USB kit** with everything you need from memory acquisition to log analysis, from initial triage to host isolation, all pre-staged and ready to run.

---

## Who is this for?

- **Incident Responders** who need a reliable, portable toolkit that's always up to date
- **SOC Analysts** called out to investigate a potentially compromised host
- **Security Engineers** who want a reproducible, script-built kit with a known-good hash manifest
- **Blue Team practitioners** building out an IR capability from scratch
- **Students and practitioners** learning practical DFIR tooling

You don't need to manually hunt down tools, remember versions, or maintain a shared drive. Run the builder, get the USB. Simple.

---

## ⚠️ Disclaimers

### Antivirus Detections

Several tools in this kit, particularly **YARA rules**, **Sigma detection files**, and some **memory acquisition binaries**, describe or interact with malicious behaviour patterns. Your antivirus **may flag or quarantine individual files** during or after the build. This is a **false positive** and is expected behaviour. The script executes 2 PE files (Wireshark, and 7Zip) **IF and only IF** the user selects Yes n the beginning of the installation.

The tools themselves are clean and sourced directly from their official maintainers. You are encouraged to review every download URL in the script and verify hashes against the build report. To avoid interruptions during the build, temporarily exclude the target folder:

```powershell
Add-MpPreference -ExclusionPath "E:\IR-Jumpkit"
# Remove after build:
Remove-MpPreference -ExclusionPath "E:\IR-Jumpkit"
```

### Transparency & Review

This project is fully open and **self-auditable**. The builder is a single `.ps1` file, every download URL, every embedded script, and every file written to disk is visible in plain text. You are encouraged to read it before running it. All downloads come from:

- Official GitHub releases (GitHub API — no hardcoded version pins)
- Sysinternals / Microsoft CDN
- Sophos (HitmanPro) and Malwarebytes (AdwCleaner) via BleepingComputer's download infrastructure
- Official vendor sites (Wireshark, PuTTY, NirSoft)

The build report includes SHA-256 hashes for every downloaded file for chain-of-custody purposes, and highlight signed files.

### Defensive Use Only

This toolkit is intended **strictly for defensive, authorised incident response and security operations**. All tools included are industry-standard DFIR utilities used by professional responders worldwide.

**You are responsible for ensuring you have proper authorisation before running any tool on any system.** Running these tools on systems you do not own or have explicit written permission to analyse may be illegal in your jurisdiction.

### Supply Chain Disclaimer

While every effort has been made to source tools from their official, authoritative maintainers, the author **cannot guarantee the integrity of third-party software** at the time of download. If a tool's upstream repository, vendor CDN, or distribution channel is compromised (supply chain attack), the downloaded binary may be affected.

**Mitigations built in:**
- All downloads come from HTTPS sources
- SHA-256 hashes are recorded in the build report for post-build verification
- GitHub API is used for all GitHub-hosted tools (fetches the verified latest release)

The author and contributors **accept no liability** for any damage, data loss, or legal consequences arising from the use of this toolkit or any tool included within it.

---

## Quick Start

**Requirements:** Windows, PowerShell 5.1+, internet connection.

> **Administrator rights are optional.** The builder runs fine as a standard user — you still get every tool except Wireshark. Wireshark cannot be portably extracted without running its installer, which requires Administrator. Run as Administrator if you want Wireshark staged on the USB.

| Scenario | What you get |
|---|---|
| Run as **Administrator** → answer **Yes** to installer consent | Full kit — 7-Zip + Wireshark included |
| Run as **Standard User** → answer **Yes** | Everything except Wireshark — 7-Zip installs to USB path |
| Answer **No** to installer consent (any elevation) | Everything except Wireshark — both installers downloaded but not run |

```powershell
# 1. Open PowerShell (as Administrator if you want Wireshark)

# 2. Set execution policy for this session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 3. Run the builder pointing at your USB drive
.\Build-IRJumpkit.ps1 -TargetPath "E:\"

# Or build to a local folder for testing
.\Build-IRJumpkit.ps1 -TargetPath "D:\IR-Jumpkit-Test"
```

The builder will prompt you once about installer consent before anything runs, then display live progress for every download. A full HTML build report is written to `00_START_HERE\BUILD_REPORT.html` when done.

---

## Builder Options

| Flag | Description |
|---|---|
| `-TargetPath "E:\"` | **Required.** Target drive or folder |
| `-Force` | Re-download all tools even if already present |
| `-Offline` | Skip all downloads — only create folder structure and write embedded scripts |
| `-SkipTools "X","Y"` | Skip specific tools by name (e.g. `"Wireshark","Hayabusa"`) |

**Re-running after a partial failure** (e.g. a download timed out) is safe — any file already present is skipped automatically. Only missing files are re-downloaded.

---

## USB Structure

After a successful build, your USB will look like this. **Click any tool name to jump to its usage section.**

```
IR-Jumpkit/
│
├── 00_START_HERE/
│   ├── README.md
│   ├── CHAIN_OF_CUSTODY.md
│   └── BUILD_REPORT.html
│
├── 01_Triage/
│   ├── windows/
│   │   ├── prevent_lock.bat         ← Run FIRST: disable sleep/screen lock
│   │   ├── triage_collect.ps1       ← Run second: fast volatile triage
│   │   ├── collect_artifacts.ps1    ← Full non-volatile collection
│   │   ├── isolate_host.ps1         ← Firewall isolation
│   │   ├── hash_files.ps1           ← Chain-of-custody hashing
│   │   └── restore_lock.bat         ← Run LAST: restore sleep settings
│   ├── linux/
│   │   ├── collect_artifacts.sh
│   │   ├── isolate_host.sh
│   │   └── hash_files.sh
│   └── SCRIPTS_README.md
│
├── 02_Forensics/
│   ├── memory/
│   │   ├── go-winpmem_amd64_*_signed.exe  ← Full build (The authors of the tool state they can't sign it even though the release name says signed)
│   │   ├── winpmem_mini_x64.exe           ← Mini signed variant (64-bit, lightweight)
│   │   ├── winpmem_mini_x86.exe           ← Mini signed variant (32-bit)
│   │   ├── avml                           ← Linux memory acquisition
│   │   └── LiME/                          ← Linux kernel module (compile on target)
│   ├── artefacts/
│   │   └── Velociraptor/            ← Velociraptor agent
│   └── imaging/
│       └── IMAGING_TOOLS.md         ← FTK Imager / dcfldd guide
│
├── 03_Network/
│   ├── Wireshark/
│   │   ├── wireshark.exe
│   │   └── tshark.exe               ← CLI capture tool
│   └── pcap_filters/
│       └── bpf_cheatsheet.md
│
├── 04_Malware/
│   ├── ProcMon/                     ← Real-time process/file/registry monitor
│   ├── Autoruns/                    ← Persistence scanner
│   ├── yara/
│   │   ├── bin/                     ← YARA engine
│   │   └── rules/                   ← Neo23x0 signature-base rules
│   ├── HitmanPro/                   ← Second-opinion cloud scanner (Sophos)
│   ├── RootkitRevealer/             ← Rootkit detection
│   ├── Malwarebytes/                ← Malware removal
│   └── AdwCleaner/                  ← Adware / PUP removal
│
├── 05_Logs/
│   └── Chainsaw/                    ← Windows event log hunter
│
├── 06_Utils/
│   ├── CyberChef/                   ← Offline decode/transform
│   ├── 7zip/
│   ├── putty/                       ← SSH + SCP
│   ├── HashMyFiles/                 ← GUI file hasher
│   └── jq/                          ← JSON processor
│
├── 07_Evidence/                     ← ★ WRITE ALL EVIDENCE HERE ★
├── 08_Runbooks/
└── 09_Reference/
    └── IOC_template.csv
```

---

## Tool Reference

---

### 01 · Triage Scripts

All scripts are written by the builder and live inside `01_Triage\`. They are designed to be run **directly from the USB** — output always goes to `07_Evidence\` on the USB, never to the suspect host's disk.

---

#### prevent\_lock.bat / restore\_lock.bat

**Platform:** Windows | **Run as:** Administrator | **Location:** `01_Triage\windows\`

**Purpose:** Prevents the suspect machine from sleeping or locking its screen during acquisition — a common cause of interrupted evidence collection, especially when imaging or capturing memory. Uses `powercfg` to silence all power timeouts (monitor, standby, hibernate) and disables the screensaver. Works on both AC and battery.

```bat
:: Run BEFORE any collection (right-click > Run as administrator)
prevent_lock.bat

:: Run AFTER all collection is complete
restore_lock.bat
```

No GUI popups, no third-party tools — silent, native Windows commands only. `restore_lock.bat` resets to Windows Balanced plan defaults (15/10 min monitor, 30/15 min standby).

---

#### triage\_collect.ps1

**Platform:** Windows | **Run as:** Administrator | **Location:** `01_Triage\windows\triage_collect.ps1`

**Purpose:** Fast volatile data collector — run this **first** on any live Windows host. Completes in ~90–120 seconds. Captures everything that disappears on reboot: running processes, network connections, sessions, persistence keys, WMI subscriptions, loaded DLLs, unsigned modules, clipboard, PowerShell history, Defender exclusions, and browser history across all user profiles.

```powershell
# Basic run (output auto-named to 07_Evidence\)
powershell -ExecutionPolicy Bypass -File .\triage_collect.ps1

# Specify output path explicitly
powershell -ExecutionPolicy Bypass -File .\triage_collect.ps1 -OutputPath "E:\07_Evidence\2024-01-01_HOST01"

# Skip hashing (faster, less rigorous)
powershell -ExecutionPolicy Bypass -File .\triage_collect.ps1 -SkipHash
```

**Expected output:** A timestamped folder in `07_Evidence\` containing:
- `01_processes\` — process list, tree, hashes, suspicious command lines, missing-EXE detection
- `02_network\` — netstat, established connections mapped to PIDs, DNS cache, ARP, routing
- `03_users_sessions\` — logged-on users, recent logons (4624), failed logons (4625)
- `04_services_drivers\` — running services, new service installs (event 7045), drivers
- `05_persistence\` — Run keys, scheduled tasks, startup folders, WMI subscriptions, IFEO, LSA packages
- `06_dlls_modules\` — DLLs per process, unsigned module detection
- `07_system\` — env vars, clipboard, hotfixes, Defender exclusions, BitLocker status
- `08_browser_history\` — Chrome, Edge, Brave, Opera, Firefox, IE history for all user profiles (raw SQLite + quick URL scan)
- `_hashes.csv` — SHA-256 manifest of all output files

---

#### collect\_artifacts.ps1

**Platform:** Windows | **Run as:** Administrator | **Location:** `01_Triage\windows\collect_artifacts.ps1`

**Purpose:** Full non-volatile artefact collection. Run after `triage_collect.ps1` (or after memory acquisition). Takes 5–15 minutes depending on the host. Exports event logs, registry hives, prefetch files, scheduled task XML, recent files, and installed software.

```powershell
# Run with default output path
powershell -ExecutionPolicy Bypass -File .\collect_artifacts.ps1

# Specify output path
powershell -ExecutionPolicy Bypass -File .\collect_artifacts.ps1 -OutputPath "E:\07_Evidence\HOST01_artifacts"
```

**Expected output:** Structured folder containing:
- `volatile\` — processes, network state, users, services (snapshot at run time)
- `nonvolatile\eventlogs\` — exported `.evtx` files (Security, System, Application, PowerShell, Sysmon, WMI, TerminalServices)
- `nonvolatile\registry\` — exported hives (SYSTEM, SOFTWARE, SAM, SECURITY, NTUSER)
- `nonvolatile\prefetch\` — all `.pf` prefetch files
- `nonvolatile\scheduled_tasks\` — task list + raw XML files from `C:\Windows\System32\Tasks`
- `nonvolatile\persistence\` — Run keys, startup folders, WMI subscriptions
- `nonvolatile\recent_files\` — recently accessed docs, recently modified System32 files
- `hashes\manifest.csv` — full SHA-256 manifest

---

#### isolate\_host.ps1

**Platform:** Windows | **Run as:** Administrator | **Location:** `01_Triage\windows\isolate_host.ps1`

**Purpose:** Cuts a Windows host off from the network while preserving your analyst's access. Run **only after memory acquisition is complete** — isolation kills active network connections.

```powershell
# Isolate — allow only analyst IP 10.0.0.50
powershell -ExecutionPolicy Bypass -File .\isolate_host.ps1 -AnalystIP 10.0.0.50

# Restore original firewall rules
powershell -ExecutionPolicy Bypass -File .\isolate_host.ps1 -AnalystIP 10.0.0.50 -Undo
```

**What it does:**
1. Exports current firewall rules to a `.wfw` backup file
2. Sets all profiles to block inbound + outbound by default
3. Adds allow rules for your analyst IP (bidirectional) and loopback
4. Logs the isolation action with timestamp

> ⚠️ **Ensure you have physical or out-of-band access to the host before running.** Running `-Undo` restores the original rules from the backup.

---

#### hash\_files.ps1

**Platform:** Windows | **Location:** `01_Triage\windows\hash_files.ps1`

**Purpose:** Hashes a file or entire directory recursively with SHA-256 + MD5. Outputs a CSV manifest for chain-of-custody documentation.

```powershell
# Hash a single file
powershell -ExecutionPolicy Bypass -File .\hash_files.ps1 -Target "C:\suspicious_binary.exe"

# Hash an entire evidence folder
powershell -ExecutionPolicy Bypass -File .\hash_files.ps1 -Target "E:\07_Evidence\HOST01_artifacts"

# Use SHA-512 and specify output file
powershell -ExecutionPolicy Bypass -File .\hash_files.ps1 -Target "E:\07_Evidence" -Algorithm SHA512 -OutputCSV "E:\07_Evidence\custody_hashes.csv"
```

**Expected output:** CSV with columns: `FilePath, FileName, SizeBytes, SHA256, MD5, CollectedAt, Hostname`

---

#### collect\_artifacts.sh

**Platform:** Linux | **Run as:** root | **Location:** `01_Triage\linux\collect_artifacts.sh`

**Purpose:** Full Linux triage collection — equivalent to the Windows collector. Captures volatile data (processes, network, users, memory indicators) and non-volatile data (logs, cron, persistence, filesystem anomalies).

```bash
# Basic run
sudo bash collect_artifacts.sh

# Specify output directory (recommend pointing at the USB mount)
sudo bash collect_artifacts.sh /mnt/usb/07_Evidence/$(hostname)_triage
```

**Expected output:** Structured folder with `volatile/`, `nonvolatile/`, and `hashes/manifest.sha256`. Includes detection of deleted EXEs, anonymous RWX mappings, SUID/SGID files, hidden files, SSH authorized_keys, bash history, LD_PRELOAD entries, and recently modified files.

---

#### isolate\_host.sh

**Platform:** Linux | **Run as:** root | **Location:** `01_Triage\linux\isolate_host.sh`

**Purpose:** Applies strict `iptables` rules to isolate a Linux host while preserving the analyst's access channel. Also isolates IPv6.

```bash
# Isolate — allow only analyst IP 10.0.0.50
sudo bash isolate_host.sh 10.0.0.50

# Restore previous iptables rules
sudo bash isolate_host.sh 10.0.0.50 --undo
```

---

#### hash\_files.sh

**Platform:** Linux | **Location:** `01_Triage\linux\hash_files.sh`

**Purpose:** SHA-256 + MD5 hashing for a file or directory. Outputs a CSV manifest.

```bash
# Hash a file
bash hash_files.sh /path/to/suspicious_binary

# Hash an evidence directory
bash hash_files.sh /mnt/usb/07_Evidence/ custody_hashes.csv
```

---

### 02 · Forensics

---

#### winpmem

**Platform:** Windows | **Location:** `02_Forensics\memory\`

The builder downloads **three variants** of winpmem, all sourced from the [Velocidex/WinPmem](https://github.com/Velocidex/WinPmem) GitHub releases:

| File | Use case |
|---|---|
| `go-winpmem_amd64_*_signed.exe` | **Recommended.** Full signed build — use on any modern 64-bit Windows host |
| `winpmem_mini_x64.exe` | Lightweight signed variant for constrained environments (64-bit) |
| `winpmem_mini_x86.exe` | Lightweight signed variant for 32-bit systems or older hardware |

**Purpose:** Dumps physical memory from a live Windows system. Run this **before anything else** — memory is volatile and overwritten constantly. All variants are Authenticode-signed (visible in the Signed column of the build report).

```powershell
# Recommended: full signed build — acquire memory to USB
.\go-winpmem_amd64_*_signed.exe E:\07_Evidence\HOST01_mem.raw

# Lightweight variant (smaller binary, faster load)
.\winpmem_mini_x64.exe E:\07_Evidence\HOST01_mem.raw

# 32-bit target host
.\winpmem_mini_x86.exe E:\07_Evidence\HOST01_mem.raw

# Hash immediately after acquisition
certutil -hashfile E:\07_Evidence\HOST01_mem.raw SHA256
```

**Expected output:** Raw memory image (`.raw`) — typically the full RAM size of the target (e.g. 16 GB). Can be analysed with Volatility 3 or Rekall after collection.

> ⚠️ Memory acquisition requires ~1× the host's RAM in free USB space.

---

#### avml

**Platform:** Linux | **Location:** `02_Forensics\memory\avml`

**Purpose:** Static binary (no dependencies, no compilation) for acquiring Linux physical memory. Microsoft-maintained, runs on any Linux system.

```bash
# Acquire memory to USB
sudo ./avml /mnt/usb/07_Evidence/$(hostname)_mem.lime

# Hash immediately
sha256sum /mnt/usb/07_Evidence/$(hostname)_mem.lime | tee /mnt/usb/07_Evidence/$(hostname)_mem.lime.sha256
```

---

#### LiME

**Platform:** Linux (kernel module) | **Location:** `02_Forensics\memory\LiME\`

**Purpose:** Linux Memory Extractor — a loadable kernel module for full physical memory acquisition. More thorough than avml in some scenarios but requires compilation on the **target machine** (kernel version must match).

```bash
# Compile on the TARGET machine (requires kernel headers)
sudo apt install linux-headers-$(uname -r) build-essential
cd LiME/src
make

# Acquire memory
sudo insmod lime.ko "path=/mnt/usb/07_Evidence/mem.lime format=lime"
sha256sum /mnt/usb/07_Evidence/mem.lime | tee /mnt/usb/07_Evidence/mem.lime.sha256

# Unload module
sudo rmmod lime
```

> See `02_Forensics\memory\LiME\COMPILE.txt` for full instructions.

---

#### Velociraptor

**Platform:** Windows | **Location:** `02_Forensics\artefacts\Velociraptor\velociraptor.exe`

**Purpose:** Powerful DFIR platform for live remote triage, artefact collection, and hunting across fleets. In standalone mode, it can be used as a powerful local collection tool with VQL queries.

```powershell
# Collect common triage artefacts (standalone GUI)
.\velociraptor.exe gui

# Run a specific VQL collection from CLI
.\velociraptor.exe artifacts collect Windows.System.Pslist --output E:\07_Evidence\HOST01\velociraptor\

# Collect Windows.KapeFiles.Targets (KAPE-compatible collection)
.\velociraptor.exe artifacts collect Windows.KapeFiles.Targets --args "Device=C:" --output E:\07_Evidence\
```

---

#### Disk Imaging Guide

**Location:** `02_Forensics\imaging\IMAGING_TOOLS.md`

Disk imaging tools (FTK Imager, dcfldd, dd, Guymager) cannot be automatically downloaded due to licensing or installer-only distribution. See `IMAGING_TOOLS.md` for download links, usage examples, and platform-specific guidance.

---

### 03 · Network

---

#### Wireshark / tshark

**Platform:** Windows | **Location:** `03_Network\Wireshark\`

**Purpose:** Packet capture and protocol analysis. `tshark.exe` (the CLI version) is the primary tool for capturing traffic from a suspect host directly to the USB.

```powershell
# List available interfaces
.\tshark.exe -D

# Capture all traffic on interface 1, save to USB
.\tshark.exe -i 1 -w E:\07_Evidence\HOST01_capture.pcap

# Capture for exactly 5 minutes
.\tshark.exe -i 1 -w E:\07_Evidence\capture.pcap -a duration:300

# Capture excluding your analyst machine IP
.\tshark.exe -i 1 -f "not host 10.0.0.50" -w E:\07_Evidence\capture.pcap

# Capture only suspicious C2 ports
.\tshark.exe -i 1 -f "dst port 4444 or dst port 1337 or dst port 8080" -w E:\07_Evidence\c2_traffic.pcap

# Post-capture: extract all unique external IPs (on analyst machine)
.\tshark.exe -r capture.pcap -T fields -e ip.dst | sort | uniq -c | sort -rn
```

> See `03_Network\pcap_filters\bpf_cheatsheet.md` for a full BPF filter reference.

---

### 04 · Malware Analysis

---

#### ProcMon

**Platform:** Windows | **Location:** `04_Malware\ProcMon\`

**Purpose:** Sysinternals Process Monitor — real-time monitoring of all filesystem, registry, network, and process activity on the system. Indispensable for watching what a suspicious process is doing.

```powershell
# Launch GUI (interactive monitoring)
.\Procmon.exe

# Launch and capture to a log file (run for 60 seconds, then save)
.\Procmon.exe /BackingFile E:\07_Evidence\HOST01_procmon.pml /Runtime 60 /Quiet /Minimized

# Convert .pml log to CSV for analysis
.\Procmon.exe /OpenLog E:\07_Evidence\HOST01_procmon.pml /SaveAs E:\07_Evidence\HOST01_procmon.csv
```

**Expected output:** `.pml` log (native format, reopenable in ProcMon) or `.csv` export. Filter by process name or PID to focus on suspicious activity.

---

#### Autoruns

**Platform:** Windows | **Location:** `04_Malware\Autoruns\`

**Purpose:** The most comprehensive persistence scanner available. Shows every program configured to run at startup across 30+ persistence locations — registry, scheduled tasks, services, drivers, browser extensions, WMI, and more. Unsigned entries and those not on VirusTotal are highlighted.

```powershell
# Launch GUI
.\Autoruns.exe

# CLI scan and save results to CSV
.\Autorunsc.exe -a * -c -h -s -o E:\07_Evidence\HOST01_autoruns.csv

# Scan and check VirusTotal (requires internet on analyst machine)
.\Autorunsc.exe -a * -c -h -s -v -o E:\07_Evidence\HOST01_autoruns_vt.csv
```

**Expected output:** List of all persistence entries. Focus on entries with no publisher, unsigned status, or unknown hashes — these are your leads.

---

#### YARA

**Platform:** Windows | **Location:** `04_Malware\yara\`

**Purpose:** Pattern-matching engine for malware identification. Scans files or memory against a library of rules (the kit includes Neo23x0's signature-base — ~4,000+ rules covering APT malware, generic malware families, exploit tools, and credential dumpers).

```powershell
# Scan a suspicious file against all rules
.\yara\bin\yara64.exe -r .\yara\rules\signature-base\yara\ suspicious_file.exe

# Scan an entire directory
.\yara\bin\yara64.exe -r .\yara\rules\signature-base\yara\ C:\Users\

# Scan and output only matching files
.\yara\bin\yara64.exe -r .\yara\rules\signature-base\yara\ C:\Temp\ 2>nul
```

**Expected output:** Matched rules with file path. A hit on `APT_*` or `MAL_*` rules warrants immediate escalation.

---

#### HitmanPro

**Platform:** Windows | **Location:** `04_Malware\HitmanPro\`

**Purpose:** Second-opinion cloud-assisted scanner from Sophos. Scans in under 5 minutes using definitions from multiple AV vendors simultaneously. Use it to validate findings or rule out active infection after initial triage.

```powershell
# Run GUI scan (64-bit systems)
.\hitmanpro_x64.exe

# Run GUI scan (32-bit systems)
.\hitmanpro.exe

# Silent scan with log output
.\hitmanpro_x64.exe /quiet /log:E:\07_Evidence\HOST01_hitmanpro.log
```

> ⚠️ Requires internet access on first run to pull cloud scan signatures. Use it as a **second opinion** after primary triage — not as a first step.

---

#### RootkitRevealer

**Platform:** Windows | **Location:** `04_Malware\RootkitRevealer\`

**Purpose:** Sysinternals rootkit detector that scans for registry and filesystem API discrepancies — the fingerprint of a rootkit hiding objects from the OS. Compares what the kernel reports vs. what the raw disk shows.

```powershell
# Launch GUI scan
.\RootkitRevealer.exe

# Scan and save results to log
.\RootkitRevealer.exe /a E:\07_Evidence\HOST01_rootkit_scan.log
```

**Expected output:** List of discrepancies between API and raw views. Any `Hidden from Windows API` entry is a strong rootkit indicator.

---

#### Malwarebytes

**Platform:** Windows | **Location:** `04_Malware\Malwarebytes\MBSetup.exe`

**Purpose:** Industry-leading malware removal tool. Use for cleaning confirmed infections after forensic acquisition is complete — run it after you've collected evidence, not before.

```powershell
# Launch installer / on-demand scanner
.\MBSetup.exe
```

> ⚠️ **Run after evidence collection.** Malwarebytes will remediate (delete/quarantine) findings — this modifies the host and can destroy forensic artefacts. Always complete memory acquisition and artefact collection first.

---

#### AdwCleaner

**Platform:** Windows | **Location:** `04_Malware\AdwCleaner\adwcleaner.exe`

**Purpose:** Malwarebytes tool specialising in adware, browser hijackers, toolbars, and PUPs (Potentially Unwanted Programs). Portable — no installation required.

```powershell
# Launch GUI (interactive scan + clean)
.\adwcleaner.exe

# Silent scan only — no removal, save log
.\adwcleaner.exe /eula /scan

# Silent clean and reboot
.\adwcleaner.exe /eula /clean /noreboot
```

**Expected output:** Report at `C:\AdwCleaner\Logs\` listing detected items by category (adware, PUPs, hijackers).

---

### 05 · Log Analysis

---

#### Chainsaw

**Platform:** Windows | **Location:** `05_Logs\Chainsaw\`

**Purpose:** Fast Windows event log hunter from WithSecure. Runs Sigma detection rules against EVTX files and produces a timeline of suspicious activity in seconds. Great for rapid triage of exported event logs.

```powershell
# Hunt against exported EVTX logs using built-in Sigma rules
.\chainsaw.exe hunt E:\07_Evidence\HOST01\nonvolatile\eventlogs\ --sigma .\rules\ --mapping .\mappings\sigma-event-logs-all.yml --output E:\07_Evidence\HOST01_chainsaw.csv

# Hunt a single EVTX file
.\chainsaw.exe hunt E:\07_Evidence\Security.evtx --sigma .\rules\ --mapping .\mappings\sigma-event-logs-all.yml

# Search for a specific string across all logs
.\chainsaw.exe search "mimikatz" E:\07_Evidence\HOST01\nonvolatile\eventlogs\
```

**Expected output:** CSV/JSON timeline with matched Sigma rules, severity, and event details. Focus on `critical` and `high` severity matches.

---

### 06 · Utilities

---

#### CyberChef

**Platform:** Any browser | **Location:** `06_Utils\CyberChef\`

**Purpose:** The "Swiss Army Knife" for data analysis — decode, deobfuscate, convert, hash, and transform data entirely in your browser with no internet required. Useful for analysing Base64-encoded payloads, obfuscated scripts, suspicious strings, and network indicators.

```
# Open in any browser — completely offline
Open: 06_Utils\CyberChef\CyberChef.html
```

Common uses: Base64 decode → `From Base64`, deobfuscate PowerShell → `Generic Code Beautify`, extract IPs from log → `Extract IP addresses`, compute hash → `SHA256`.

---

#### 7-Zip

**Location:** `06_Utils\7zip\7z.exe`

**Purpose:** Portable archive utility. Used internally by the builder and available for manual extraction of compressed evidence or tool archives.

```powershell
# Extract an archive
.\7z.exe x archive.zip -oC:\output\

# Create a compressed evidence archive
.\7z.exe a E:\07_Evidence\HOST01_evidence.7z E:\07_Evidence\HOST01\ -p   # -p prompts for password
```

---

#### PuTTY / PSCP

**Location:** `06_Utils\putty\`

**Purpose:** SSH client and SCP file transfer tool. Use PSCP to exfiltrate evidence to a remote collection server over SSH.

```powershell
# Connect to a remote host
.\putty.exe user@10.0.0.100

# Copy an evidence folder to remote collection server
.\pscp.exe -r E:\07_Evidence\HOST01\ analyst@10.0.0.100:/cases/2024-01-01/HOST01/
```

---

#### HashMyFiles

**Location:** `06_Utils\HashMyFiles\`

**Purpose:** GUI tool for hashing files with MD5, SHA-1, SHA-256, SHA-512. Useful for quick ad-hoc hashing and VirusTotal lookups of suspicious files.

```powershell
# Launch GUI
.\HashMyFiles.exe

# Command-line hash a file
.\HashMyFiles.exe /file "C:\suspicious.exe" /stext E:\07_Evidence\suspicious_hashes.txt
```

---

#### jq

**Location:** `06_Utils\jq\`

**Purpose:** Lightweight JSON processor. Useful for parsing JSON output from tools like Velociraptor, or filtering large JSON log files.

```powershell
# Windows
.\jq-windows.exe ".[] | select(.severity == \"high\")" hayabusa_output.json

# Linux
./jq-linux '.[] | .process_name' velociraptor_output.json | sort | uniq -c | sort -rn
```

---

## Order of Operations

Follow this sequence on a live host to preserve evidence integrity:

| Step | Action | Tool |
|---|---|---|
| **0** | Prevent screen lock during acquisition | `prevent_lock.bat` (run as Admin) |
| **1** | 🔴 **Capture memory first** — it is the most volatile artefact | `winpmem.exe` / `avml` |
| **2** | Run quick volatile triage | `triage_collect.ps1` / `collect_artifacts.sh` |
| **3** | Capture live network traffic | `tshark.exe` / `tcpdump` |
| **4** | Scan for active threats (without removing) | `ProcMon`, `Autoruns`, `YARA` |
| **5** | Isolate the host from the network | `isolate_host.ps1` / `isolate_host.sh` |
| **6** | Full non-volatile artefact collection | `collect_artifacts.ps1` |
| **7** | Disk imaging | FTK Imager / dcfldd — see `02_Forensics\imaging\IMAGING_TOOLS.md` |
| **8** | Hash all collected evidence | `hash_files.ps1` / `hash_files.sh` |
| **9** | Restore sleep settings | `restore_lock.bat` (run as Admin) |
| **10** | Deep analysis (off-scene, on analyst machine) | Chainsaw, YARA, Velociraptor |
| **11** | Remediation (only after full collection) | Malwarebytes, AdwCleaner, HitmanPro |

> 🔑 **Golden rule:** Never write evidence to the suspect host's own disk. All output goes to `07_Evidence\` on the USB.

---

## Evidence Folder

`07_Evidence\` is intentionally left empty by the builder. This is where **all output from every tool** should be directed during an incident.

Recommended naming convention for evidence subfolders:
```
07_Evidence\
├── 2024-01-15_HOST01_triage\       ← volatile triage output
├── 2024-01-15_HOST01_artifacts\    ← full collection output
├── 2024-01-15_HOST01_mem.raw       ← memory image
├── 2024-01-15_HOST01_capture.pcap  ← network capture
└── 2024-01-15_HOST01_chainsaw.csv  ← log analysis output
```

---

## Standalone Scripts (Repository)

The IR scripts embedded inside the builder are also available as standalone files in this repository under `scripts/`. This lets you review, modify, or version-control them independently — and makes it easy to push them to your own fork without running the builder first.

```
scripts/
├── windows/
│   ├── triage_collect.ps1       ← Fast volatile triage (run first on live Windows host)
│   ├── collect_artifacts.ps1    ← Full non-volatile artefact collection
│   ├── isolate_host.ps1         ← Firewall-based host isolation
│   └── hash_files.ps1           ← SHA-256 + MD5 chain-of-custody hasher
└── linux/
    ├── collect_artifacts.sh     ← Full Linux triage + non-volatile collection
    ├── isolate_host.sh          ← iptables-based host isolation (IPv4 + IPv6)
    └── hash_files.sh            ← SHA-256 + MD5 hasher for Linux

Note: prevent_lock.bat and restore_lock.bat are generated by the builder into
01_Triage\windows\ on the USB — they are not standalone source scripts.
```

These files are **identical** to the versions embedded in the builder — they are extracted directly from the same here-strings. When the builder runs, it writes these same scripts into `01_Triage\windows\` and `01_Triage\linux\` on the USB.

### How the scripts behave

All scripts are designed to be run **directly from the USB**. They share two key behaviours:

1. **Output goes to the USB, never to the suspect host's disk.** Each script computes a default output path of `$PSScriptRoot\..\..\07_Evidence\` (two levels up from its folder in `01_Triage\windows\` or `01_Triage\linux\`), pointing at `07_Evidence\` on the USB. You can override this with the `-OutputPath` parameter.

2. **They do not install anything.** All scripts are self-contained — no dependencies, no modules, no internet access required on the incident scene.

See the [01 · Triage Scripts](#01--triage-scripts) section above for full usage documentation and expected output for each script.

---

## Build Report

After every build, the builder writes two report files to `00_START_HERE\`:

| File | Format | Purpose |
|---|---|---|
| `BUILD_REPORT.html` | HTML (browser) | Full colour-coded report — open in any browser |
| `BUILD_REPORT.txt` | Plain text | Plain-text copy for documentation, archiving, or no-GUI environments |

### What the report contains

Each downloaded file gets a row with:

| Column | Description |
|---|---|
| **Tool** | Tool name as shown in the builder |
| **Status** | `OK` (green), `FAIL` (red), or `SKIP` (grey — file already present, not re-downloaded) |
| **Version** | Version string resolved from the GitHub API (where applicable) |
| **File** | Filename saved to the USB |
| **SHA-256** | Hash of the downloaded file — use this for chain-of-custody verification |
| **Signed** | Authenticode signature status for PE files (`.exe`, `.dll`, `.sys`, `.msi`) |

### Signed column

The **Signed** column shows the result of `Get-AuthenticodeSignature` on each downloaded PE file. The format is:

```
Signed · <Signer CN> · <Algorithm>
```

For example:
- `Signed · Microsoft Corporation · sha256RSA`
- `Signed · Sophos Limited · sha256RSA`
- `Not signed`
- `Invalid (hash mismatch)`

A `FAIL` status in the build report means the file could not be downloaded (network error, API failure, or URL changed). Re-run the builder with no flags to retry only missing files — any file that downloaded successfully is skipped automatically.

---

*Built with ❤️ for the blue team. Connect with the author on [LinkedIn](https://dk.linkedin.com/in/chris857).*
