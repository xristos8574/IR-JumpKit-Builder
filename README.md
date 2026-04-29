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
    - [winpmem](#winpmem)
    - [avml](#avml)
    - [LiME](#lime)
    - [EZ Tools Suite](#ez-tools-suite)
    - [Velociraptor](#velociraptor)
    - [Disk Imaging Guide](#disk-imaging-guide)
  - [03 · Network](#03--network)
    - [Wireshark / tshark](#wireshark--tshark)
  - [04 · Malware Analysis](#04--malware-analysis)
    - [ProcMon](#procmon)
    - [Autoruns](#autoruns)
    - [YARA](#yara)
    - [Loki](#loki)
    - [HitmanPro](#hitmanpro)
    - [RootkitRevealer](#rootkitrevealer)
    - [Malwarebytes](#malwarebytes)
    - [AdwCleaner](#adwcleaner)
  - [05 · Log Analysis](#05--log-analysis)
    - [Chainsaw](#chainsaw)
    - [Hayabusa](#hayabusa)
  - [06 · Utilities](#06--utilities)
    - [CyberChef](#cyberchef)
    - [7-Zip](#7-zip)
    - [PuTTY / PSCP](#putty--pscp)
    - [HashMyFiles](#hashmyfiles)
    - [jq](#jq)
- [Order of Operations](#order-of-operations)
- [Evidence Folder](#evidence-folder)

---

## What is the IR JumpKit Builder?

The IR JumpKit Builder (`Build-IRJumpkit.ps1`) is a **single PowerShell script** that builds an entire Incident Response USB toolkit from scratch. When you run it against a USB drive (or any target folder), it:

1. Runs pre-flight checks (admin rights, internet, disk space)
2. Creates a clean, numbered folder structure
3. Downloads the latest version of every tool directly from authoritative sources (GitHub releases, vendor CDNs, Sysinternals)
4. Embeds ready-to-run IR scripts for Windows and Linux — no internet needed on the incident scene
5. Writes quick-start notes, cheatsheets, and an IOC template
6. Generates a full HTML + text build report with SHA-256 hashes of everything downloaded

The result is a **self-documenting, auditable USB kit** with everything you need from memory acquisition to log analysis, from initial triage to host isolation — all pre-staged and ready to run.

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

Several tools in this kit — particularly **YARA rules**, **Sigma detection files** (used by Hayabusa/Chainsaw), and **memory acquisition binaries** — describe or interact with malicious behaviour patterns. Your antivirus **may flag or quarantine individual files** during or after the build. This is a **false positive** and is expected behaviour.

The tools themselves are clean and sourced directly from their official maintainers. You are encouraged to review every download URL in the script and verify hashes against the build report. To avoid interruptions during the build, temporarily exclude the target folder:

```powershell
Add-MpPreference -ExclusionPath "E:\IR-Jumpkit"
# Remove after build:
Remove-MpPreference -ExclusionPath "E:\IR-Jumpkit"
```

### Transparency & Review

This project is fully open and **self-auditable**. The builder is a single `.ps1` file — every download URL, every embedded script, and every file written to disk is visible in plain text. You are encouraged to read it before running it. All downloads come from:

- Official GitHub releases (GitHub API — no hardcoded version pins)
- Sysinternals / Microsoft CDN
- Sophos (HitmanPro) and Malwarebytes (AdwCleaner) via BleepingComputer's download infrastructure
- Official vendor sites (Wireshark, PuTTY, NirSoft)

The build report includes SHA-256 hashes for every downloaded file for chain-of-custody purposes.

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

**Requirements:** Windows, PowerShell 5.1+, internet connection, run as Administrator.

```powershell
# 1. Open PowerShell as Administrator

# 2. Set execution policy for this session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 3. Run the builder pointing at your USB drive
.\Build-IRJumpkit.ps1 -TargetPath "E:\"

# Or build to a local folder for testing
.\Build-IRJumpkit.ps1 -TargetPath "D:\IR-Jumpkit-Test"
```

The builder will display live progress for every download and write a full HTML build report to `00_START_HERE\BUILD_REPORT.html` when done.

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
│   │   ├── triage_collect.ps1       ← Run FIRST on any live Windows host
│   │   ├── collect_artifacts.ps1    ← Full non-volatile collection
│   │   ├── isolate_host.ps1         ← Firewall isolation
│   │   └── hash_files.ps1           ← Chain-of-custody hashing
│   ├── linux/
│   │   ├── collect_artifacts.sh
│   │   ├── isolate_host.sh
│   │   └── hash_files.sh
│   └── SCRIPTS_README.md
│
├── 02_Forensics/
│   ├── memory/
│   │   ├── winpmem.exe              ← Windows memory acquisition
│   │   ├── avml                     ← Linux memory acquisition
│   │   └── LiME/                    ← Linux kernel module (compile on target)
│   ├── artefacts/
│   │   ├── EZTools/                 ← Eric Zimmerman Tools (full suite)
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
│   ├── Loki/                        ← IOC + YARA scanner
│   ├── HitmanPro/                   ← Second-opinion cloud scanner (Sophos)
│   ├── RootkitRevealer/             ← Rootkit detection
│   ├── Malwarebytes/                ← Malware removal
│   └── AdwCleaner/                  ← Adware / PUP removal
│
├── 05_Logs/
│   ├── Chainsaw/                    ← Windows event log hunter
│   └── Hayabusa/                    ← DFIR timeline generator
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

#### triage\_collect.ps1

**Platform:** Windows | **Run as:** Administrator | **Location:** `01_Triage\windows\triage_collect.ps1`

**Purpose:** Fast volatile data collector — run this **first** on any live Windows host. Completes in ~90 seconds. Captures everything that disappears on reboot: running processes, network connections, sessions, persistence keys, WMI subscriptions, loaded DLLs, unsigned modules, clipboard, PowerShell history, Defender exclusions.

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

**Platform:** Windows | **Location:** `02_Forensics\memory\winpmem.exe`

**Purpose:** Dumps physical memory from a live Windows system. Run this **before anything else** — memory is volatile and overwritten constantly.

```powershell
# Acquire memory to USB (always point output at the USB)
.\winpmem.exe E:\07_Evidence\HOST01_mem.raw

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

#### EZ Tools Suite

**Platform:** Windows | **Location:** `02_Forensics\artefacts\EZTools\`

**Purpose:** Eric Zimmerman's comprehensive suite of Windows artefact parsers. Covers registry hives, event logs, prefetch, LNK files, shellbags, jump lists, and much more. Industry standard for Windows DFIR.

Key tools in the suite:

| Tool | What it parses |
|---|---|
| `MFTECmd.exe` | NTFS Master File Table |
| `PECmd.exe` | Prefetch files |
| `LECmd.exe` | LNK (shortcut) files |
| `JLECmd.exe` | Jump lists |
| `SBECmd.exe` | Shellbags |
| `RECmd.exe` | Registry hives |
| `EvtxECmd.exe` | Windows event logs (EVTX → CSV/JSON) |
| `RBCmd.exe` | Recycle bin |
| `AppCompatCacheParser.exe` | Shimcache |
| `AmcacheParser.exe` | Amcache.hve |

```powershell
# Parse prefetch files from evidence folder
.\PECmd.exe -d E:\07_Evidence\HOST01\nonvolatile\prefetch\ --csv E:\07_Evidence\HOST01\parsed\

# Parse exported registry hive
.\RECmd.exe -f E:\07_Evidence\HOST01\nonvolatile\registry\SOFTWARE.hiv --csv E:\07_Evidence\HOST01\parsed\

# Parse EVTX event logs
.\EvtxECmd.exe -d E:\07_Evidence\HOST01\nonvolatile\eventlogs\ --csv E:\07_Evidence\HOST01\parsed\ --csvf evtx_parsed.csv
```

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

#### Loki

**Platform:** Windows | **Location:** `04_Malware\Loki\`

**Purpose:** IOC and YARA scanner that checks files against a database of known-malicious hashes, filenames, YARA rules, and C2 indicators. The `--update` flag pulls the latest IOC database.

```powershell
# Scan the suspect host's C drive (run from USB)
.\loki.exe --path C:\ --log E:\07_Evidence\HOST01_loki.log

# Update IOC database before scanning (requires internet)
.\loki.exe --update

# Scan only specific directory, exclude noise
.\loki.exe --path C:\Users\ --log E:\07_Evidence\loki_users.log --noprocscan
```

**Expected output:** Colour-coded log with `ALERT` (high confidence IOC match), `WARNING` (suspicious), and `NOTICE` (interesting) findings. ALERT = immediate investigation.

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

#### Hayabusa

**Platform:** Windows | **Location:** `05_Logs\Hayabusa\`

**Purpose:** Windows event log DFIR timeline generator with a large built-in Sigma ruleset. Produces a human-readable or machine-parseable timeline from EVTX files, highlighting attacker TTPs mapped to MITRE ATT&CK.

```powershell
# Generate timeline from exported event logs (CSV output)
.\hayabusa.exe csv-timeline -d E:\07_Evidence\HOST01\nonvolatile\eventlogs\ -o E:\07_Evidence\HOST01_hayabusa_timeline.csv

# Quick triage — summary of findings only
.\hayabusa.exe logon-summary -d E:\07_Evidence\HOST01\nonvolatile\eventlogs\

# Live system scan (run on the suspect host)
.\hayabusa.exe csv-timeline -l -o E:\07_Evidence\HOST01_hayabusa_live.csv
```

> ℹ️ AV may flag Sigma rule `.yml` files inside the `rules/` folder. This is expected — the rules describe malicious behaviour patterns for detection, not for execution.

**Expected output:** Timeline CSV with columns for timestamp, computer, channel, event ID, Sigma rule name, severity, and MITRE ATT&CK technique. Open in Excel or Timeline Explorer (from EZ Tools) for analysis.

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
| **1** | 🔴 **Capture memory first** — it is the most volatile artefact | `winpmem.exe` / `avml` |
| **2** | Run quick volatile triage | `triage_collect.ps1` / `collect_artifacts.sh` |
| **3** | Capture live network traffic | `tshark.exe` / `tcpdump` |
| **4** | Scan for active threats (without removing) | `Loki`, `ProcMon`, `Autoruns` |
| **5** | Isolate the host from the network | `isolate_host.ps1` / `isolate_host.sh` |
| **6** | Full non-volatile artefact collection | `collect_artifacts.ps1` |
| **7** | Disk imaging | FTK Imager / dcfldd — see `02_Forensics\imaging\IMAGING_TOOLS.md` |
| **8** | Hash all collected evidence | `hash_files.ps1` / `hash_files.sh` |
| **9** | Deep analysis (off-scene, on analyst machine) | EZ Tools, Chainsaw, Hayabusa, YARA |
| **10** | Remediation (only after full collection) | Malwarebytes, AdwCleaner, HitmanPro |

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

*Built with ❤️ for the blue team. Connect with the author on [LinkedIn](https://dk.linkedin.com/in/chris857).*
