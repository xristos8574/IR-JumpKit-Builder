#Requires -RunAsAdministrator
<#
.SYNOPSIS
    IR Jumpkit Builder v2.1 -- Self-contained. One file. Run once, get a full USB kit.

.DESCRIPTION
    Downloads, installs, and organises a complete Incident Response USB toolkit.
    ALL IR scripts are embedded inside this file -- no other files are needed.
    Run this script from anywhere (Desktop, Downloads, etc).

    Steps:
      1. Pre-flight checks (admin, PS version, git, .NET, Python, space, AV warning)
      2. Creates full USB directory structure
      3. Downloads all tools with live per-file progress bars
      4. Installs Wireshark silently -> copies folder -> uninstalls
      5. Writes all embedded IR scripts to 01_Triage\
      6. Writes reference documents and cheatsheets
      7. Generates HTML + plain-text build report

.PARAMETER TargetPath
    Target drive or folder. Example: "E:\" or "D:\IR-Jumpkit"

.PARAMETER SkipTools
    Comma-separated tool names to skip. Example: -SkipTools "Hayabusa","YARA"

.PARAMETER Offline
    Skip all downloads. Only creates structure and writes embedded scripts.

.PARAMETER Force
    Re-download tools even if they already exist at the target path.

.EXAMPLE
    .\Build-IRJumpkit.ps1 -TargetPath "E:\"
    .\Build-IRJumpkit.ps1 -TargetPath "E:\" -Force
    .\Build-IRJumpkit.ps1 -TargetPath "E:\" -Offline
    .\Build-IRJumpkit.ps1 -TargetPath "E:\" -SkipTools "Wireshark","Hayabusa"
#>

param(
    [Parameter(Mandatory=$true)][string]$TargetPath,
    [string[]]$SkipTools = @(),
    [switch]$Offline,
    [switch]$Force
)

Set-StrictMode -Off
$ErrorActionPreference  = "Continue" # Changed so we can actually see terminating errors
$ProgressPreference     = "SilentlyContinue"

# MUST HAVE: Force PowerShell to use TLS 1.2, otherwise GitHub drops the connection
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$BuildStart             = Get-Date
$BuilderVersion         = "2.1.0"
$Root                   = Join-Path $TargetPath "IR-Jumpkit"
$TempDir                = Join-Path $env:TEMP "IRKit_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

$Script:Results   = [System.Collections.Generic.List[PSObject]]::new()
$Script:Warnings  = [System.Collections.Generic.List[string]]::new()
$Script:HardFails = [System.Collections.Generic.List[string]]::new()

# ============================================================
#  OUTPUT HELPERS
# ============================================================
function Write-Step { param([string]$Msg)
    Write-Host ""
    Write-Host "  +-------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "  |  $Msg" -ForegroundColor Cyan
    Write-Host "  +-------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Log { param([string]$Status, [string]$Name, [string]$Detail="")
    $col = switch ($Status) {
        "OK"      { "Green"   }
        "WARN"    { "Yellow"  }
        "FAIL"    { "Red"     }
        "SKIP"    { "Gray"    }
        "COMPILE" { "Magenta" }
        "INFO"    { "Cyan"    }
        default   { "White"   }
    }
    $icon = switch ($Status) { "OK" {"[OK]"} "WARN" {"[!!]"} "FAIL" {"[XX]"} "SKIP" {"[--]"} "COMPILE" {"[cc]"} default {"[..]"} }
    Write-Host ("  [{0,-7}] {1}  {2}" -f $Status, $icon, $Name) -ForegroundColor $col
    if ($Detail) { Write-Host "             $Detail" -ForegroundColor DarkGray }
}

function Add-Result { param([string]$Cat, [string]$Name, [string]$Status,
                             [string]$Detail="", [string]$Path="", [string]$Hash="", [string]$Ver="")
    Write-Log $Status $Name $Detail
    $Script:Results.Add([PSCustomObject]@{
        Category=$Cat; Name=$Name; Status=$Status
        Detail=$Detail; Path=$Path; Hash=$Hash; Version=$Ver
        Time=(Get-Date -Format "HH:mm:ss")
    })
}

function Get-SHA256 { param([string]$Path)
    if (Test-Path $Path) { return (Get-FileHash $Path -Algorithm SHA256 -EA SilentlyContinue).Hash }
    return ""
}

function Should-Skip { param([string]$Name)
    return ($SkipTools -contains $Name)
}

# ============================================================
#  DOWNLOAD WITH LIVE PROGRESS
# ============================================================
function Invoke-Download {
    param([string]$Uri, [string]$Dest, [string]$Label, [string]$Cat)

    if (!$Force -and (Test-Path $Dest)) {
        Add-Result $Cat $Label "SKIP" "Already exists -- use -Force to re-download" $Dest (Get-SHA256 $Dest)
        return $true
    }

    # Safety check so we don't pass null URLs
    if ([string]::IsNullOrWhiteSpace($Uri)) {
        Add-Result $Cat $Label "FAIL" "Download URL is empty or null (GitHub API issue?)"
        return $false
    }

    $destDir = Split-Path $Dest -Parent
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    try {
        Write-Host "  [....] Downloading $Label..." -ForegroundColor DarkYellow
        Invoke-WebRequest -Uri $Uri -OutFile $Dest -UseBasicParsing -ErrorAction Stop
        
        $hash = Get-SHA256 $Dest
        Add-Result $Cat $Label "OK" "Downloaded from $Uri" $Dest $hash
        return $true
    }
    catch {
        Write-Host "  [WARN] Download failed: $_" -ForegroundColor Red
        Add-Result $Cat $Label "FAIL" "Download failed: $_"
        return $false
    }
}

function Expand-Auto { param([string]$Archive, [string]$Dest)
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    $ext = [IO.Path]::GetExtension($Archive).ToLower()
    try {
        if ($ext -eq ".zip") {
            Expand-Archive -Path $Archive -DestinationPath $Dest -Force
        } else {
            $sz = Get-Command "7z.exe" -EA SilentlyContinue
            if (!$sz) { $sz = Get-ChildItem "$Root\06_Utils\7zip" -Filter "7z.exe" -Recurse -EA SilentlyContinue | Select-Object -First 1 }
            if ($sz)  { & $sz.Source x $Archive "-o$Dest" -y 2>$null | Out-Null }
            else { Write-Host "  [WARN] Cannot extract $([IO.Path]::GetFileName($Archive)) -- 7-Zip not available" -ForegroundColor Yellow }
        }
    } catch { Write-Host "  [WARN] Extraction failed: $_" -ForegroundColor Yellow }
}

function Get-GitHubLatest { param([string]$Repo, [string]$Pattern)
    try {
        $r = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" `
             -Headers @{"User-Agent"="IR-Jumpkit-Builder"} -EA Stop
        $a = $r.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
        if ($a) { return @{ Version=$r.tag_name; Url=$a.browser_download_url; FileName=$a.name } }
    } catch {}
    return $null
}

# ============================================================
#  STEP 1  PRE-FLIGHT
# ============================================================
Clear-Host
Write-Host ""
Write-Host "  +==============================================================+" -ForegroundColor Cyan
Write-Host "  |           IR JUMPKIT BUILDER  v$BuilderVersion                        |" -ForegroundColor Cyan
Write-Host "  +==============================================================+" -ForegroundColor DarkCyan
Write-Host "  |  Target   : $TargetPath" -ForegroundColor White
Write-Host "  |  Root     : $Root" -ForegroundColor White
Write-Host "  |  Offline  : $Offline" -ForegroundColor White
Write-Host "  |  Started  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "  +==============================================================+" -ForegroundColor DarkCyan

Write-Step "STEP 1 -- Pre-flight Checks"

# Administrator
if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Add-Result "Pre-flight" "Run As Administrator" "OK"
} else {
    Add-Result "Pre-flight" "Run As Administrator" "FAIL" "Re-launch PowerShell as Administrator"
    $Script:HardFails.Add("Must run as Administrator")
}

# PowerShell version
$psv = $PSVersionTable.PSVersion
if ($psv.Major -ge 5) { Add-Result "Pre-flight" "PowerShell $($psv.ToString())" "OK" "Minimum: 5.1" }
else {
    Add-Result "Pre-flight" "PowerShell $($psv.ToString())" "FAIL" "Need 5.1+. Get: https://aka.ms/powershell"
    $Script:HardFails.Add("PowerShell 5.1+ required")
}

# Execution policy
$pol = Get-ExecutionPolicy
if ($pol -in "Bypass","Unrestricted","RemoteSigned") { Add-Result "Pre-flight" "Execution Policy ($pol)" "OK" }
else {
    Add-Result "Pre-flight" "Execution Policy ($pol)" "WARN" "Run: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass"
    $Script:Warnings.Add("Execution policy is $pol -- scripts may not run from USB")
}

# Git
$git = Get-Command git -EA SilentlyContinue
if ($git) { Add-Result "Pre-flight" "Git" "OK" (git --version 2>$null) $git.Source }
else {
    Add-Result "Pre-flight" "Git" "WARN" "Not found -- git clone disabled. Get: https://git-scm.com/download/win"
    $Script:Warnings.Add("Git not found -- some repos will use direct download fallback")
}

# .NET SDK
$dotnet = Get-Command dotnet -EA SilentlyContinue
if ($dotnet) { Add-Result "Pre-flight" ".NET SDK $((dotnet --version 2>$null))" "OK" ".NET available for compilation" }
else {
    Add-Result "Pre-flight" ".NET SDK" "WARN" "Not found. Get: https://dotnet.microsoft.com/download"
    $Script:Warnings.Add(".NET SDK not found -- compilation tasks will be skipped")
}
$hasDotnet = $null -ne $dotnet

# Python
$py = Get-Command python -EA SilentlyContinue
if (!$py) { $py = Get-Command python3 -EA SilentlyContinue }
if ($py) { Add-Result "Pre-flight" "Python ($((& $py.Source --version 2>&1)))" "OK" $py.Source }
else {
    Add-Result "Pre-flight" "Python 3" "WARN" "Not found -- Volatility pip install will be skipped. Get: https://python.org"
    $Script:Warnings.Add("Python 3 not found -- Volatility deps won't auto-install")
}
$hasPython = $null -ne $py

# 7-Zip
$sz = Get-Command 7z -EA SilentlyContinue
if (!$sz) { $sz = Get-Command "7z.exe" -EA SilentlyContinue }
if ($sz) { Add-Result "Pre-flight" "7-Zip" "OK" $sz.Source }
else {
    Add-Result "Pre-flight" "7-Zip" "WARN" "Not in PATH -- portable 7-Zip will be downloaded first"
    $Script:Warnings.Add("7-Zip not in PATH -- will download portable version as first step")
}

# Internet
if (!$Offline) {
    try {
        $null = Invoke-WebRequest "https://api.github.com" -UseBasicParsing -TimeoutSec 8 -EA Stop
        Add-Result "Pre-flight" "Internet Connectivity" "OK" "GitHub API reachable"
    } catch {
        Add-Result "Pre-flight" "Internet Connectivity" "FAIL" "Cannot reach GitHub. Use -Offline if no internet."
        $Script:HardFails.Add("No internet connectivity")
    }
} else {
    Add-Result "Pre-flight" "Internet Connectivity" "SKIP" "Offline mode"
}

# Free space
try {
    $drv = Split-Path -Qualifier (Resolve-Path $TargetPath -EA SilentlyContinue)
    $disk = Get-PSDrive -Name $drv.TrimEnd(':') -EA SilentlyContinue
    $freeGB = [math]::Round($disk.Free/1GB, 1)
    if ($freeGB -ge 8) { Add-Result "Pre-flight" "Free Space ($freeGB GB)" "OK" "Min recommended: 8 GB" }
    else {
        Add-Result "Pre-flight" "Free Space ($freeGB GB)" "WARN" "Low -- recommend 32 GB USB"
        $Script:Warnings.Add("Low free space: $freeGB GB")
    }
} catch { Add-Result "Pre-flight" "Free Space" "WARN" "Could not determine free space" }

# AV Notice
Write-Host ""
Write-Host "  [NOTE] Antivirus Notice:" -ForegroundColor Yellow
Write-Host "  Some YARA rules and Sigma detection files describe malicious behavior." -ForegroundColor DarkYellow
Write-Host "  Your AV may quarantine individual rule .yml/.yar files -- this is expected." -ForegroundColor DarkYellow
Write-Host "  The tools themselves are safe. Temporarily exclude the target folder" -ForegroundColor DarkYellow
Write-Host "  from real-time scanning during the build if needed:" -ForegroundColor DarkYellow
Write-Host "  Add-MpPreference -ExclusionPath '$Root'" -ForegroundColor Gray
Write-Host ""

# Abort on hard fails
if ($Script:HardFails.Count -gt 0) {
    Write-Host "  +=============================================+" -ForegroundColor Red
    Write-Host "  |  PRE-FLIGHT FAILED -- cannot continue      |" -ForegroundColor Red
    Write-Host "  +=============================================+" -ForegroundColor Red
    $Script:HardFails | ForEach-Object { Write-Host "  [XX] $_" -ForegroundColor Red }
    exit 1
}

if ($Script:Warnings.Count -gt 0) {
    Write-Host "  Pre-flight passed with $($Script:Warnings.Count) warning(s):" -ForegroundColor Yellow
    $Script:Warnings | ForEach-Object { Write-Host "    [!!] $_" -ForegroundColor DarkYellow }
}

# ============================================================
#  STEP 2  DIRECTORY STRUCTURE
# ============================================================
Write-Step "STEP 2 -- Building Directory Structure"

$FolderMap = [ordered]@{
    "00_START_HERE"                       = "Quick-start, chain of custody, incident log"
    "01_Triage\windows"                   = "Windows triage tools"
    "01_Triage\linux"                     = "Linux triage tools"
    "01_Triage\macos"                     = "macOS triage tools"
    "02_Forensics\imaging"                = "Disk imaging (FTK Imager, dcfldd)"
    "02_Forensics\memory"                 = "Memory acquisition (winpmem, avml, LiME)"
    "02_Forensics\artefacts\EZTools"      = "Eric Zimmerman Tools suite"
    "02_Forensics\artefacts\Velociraptor" = "Velociraptor DFIR platform"
    "03_Network\Wireshark"                = "Wireshark + tshark portable"
    "03_Network\pcap_filters"             = "BPF filter cheatsheets"
    "04_Malware\ProcMon"                   = "Process Monitor - real-time file/registry/process activity"
    "04_Malware\Autoruns"                 = "Autoruns (persistence scanner)"
    "04_Malware\yara\bin"                 = "YARA engine"
    "04_Malware\yara\rules"               = "YARA community rules"
    "04_Malware\Loki"                     = "Loki IOC and YARA scanner"
    "04_Malware\HitmanPro"                = "HitmanPro second-opinion malware scanner (Sophos)"
    "04_Malware\RootkitRevealer"          = "RootkitRevealer - registry/filesystem rootkit detector"
    "04_Malware\Malwarebytes"             = "Malwarebytes Anti-Malware"
    "04_Malware\AdwCleaner"               = "AdwCleaner - adware and PUP remover (Malwarebytes)"
    "05_Logs\Chainsaw"                    = "Chainsaw Windows event log hunter"
    "05_Logs\Hayabusa"                    = "Hayabusa DFIR timeline"
    "06_Utils\CyberChef"                  = "CyberChef offline"
    "06_Utils\7zip"                       = "7-Zip portable"
    "06_Utils\putty"                      = "PuTTY + PSCP"
    "06_Utils\HashMyFiles"                = "HashMyFiles"
    "06_Utils\jq"                         = "jq JSON processor"
    "07_Evidence"                         = "WRITE EVIDENCE HERE"
    "08_Runbooks"                         = "Incident runbooks"
    "09_Reference"                        = "Cheatsheets, event IDs, IOC templates"
}

foreach ($folder in $FolderMap.Keys) {
    $fp = Join-Path $Root $folder
    New-Item -ItemType Directory -Force -Path $fp | Out-Null
    Add-Result "Structure" $folder "OK" $FolderMap[$folder] $fp
}

# ============================================================
#  STEP 3  DOWNLOADS
# ============================================================
Write-Step "STEP 3 -- Downloading Tools"

if ($Offline) {
    Write-Host "  Offline mode -- skipping all downloads." -ForegroundColor Yellow
    Add-Result "Downloads" "All tools" "SKIP" "Offline mode"
} else {

# ---- 7-Zip portable (must be first -- needed for later extractions) ----------
if (!(Should-Skip "7zip")) {
    $szExe = Join-Path $Root "06_Utils\7zip\7z.exe"
    if (!(Test-Path $szExe) -or $Force) {
        $info = Get-GitHubLatest "ip7z/7zip" "7z\d+-x64\.exe"
        if (!$info) {
            Add-Result "Utils" "7-Zip" "FAIL" "GitHub API returned no release. Install 7-Zip manually from https://7-zip.org then re-run."
            $Script:Warnings.Add("7-Zip download failed -- install manually from https://7-zip.org and re-run")
        } else {
            $inst = Join-Path $TempDir $info.FileName
            if (Invoke-Download $info.Url $inst "7-Zip installer" "Utils") {
                $szDir = Join-Path $Root "06_Utils\7zip"
                Start-Process -FilePath $inst -ArgumentList "/S /D=$szDir" -Wait -NoNewWindow
                if (Test-Path $szExe) {
                    Add-Result "Utils" "7-Zip (installed)" "OK" "Extracted to $szDir" $szExe (Get-SHA256 $szExe) $info.Version
                    $env:Path = "$szDir;$env:Path"
                } else { Add-Result "Utils" "7-Zip (install)" "FAIL" "Installer ran but 7z.exe not found" }
            }
        }
    } else { Add-Result "Utils" "7-Zip" "SKIP" "Already present" $szExe }
}

# ---- winpmem (Windows memory acquisition) ------------------------------------
if (!(Should-Skip "winpmem")) {
    $dest = Join-Path $Root "02_Forensics\memory\winpmem.exe"
    $info = Get-GitHubLatest "Velocidex/WinPmem" "winpmem.*\.exe$"
    if ($info) { Invoke-Download $info.Url $dest "winpmem" "Memory" | Out-Null }
    else { Add-Result "Memory" "winpmem" "FAIL" "Could not resolve GitHub release" }
}

# ---- avml (Linux memory acquisition -- static binary) ------------------------
if (!(Should-Skip "avml")) {
    $dest = Join-Path $Root "02_Forensics\memory\avml"
    $info = Get-GitHubLatest "microsoft/avml" "avml$"
    if ($info) { Invoke-Download $info.Url $dest "avml (Linux)" "Memory" | Out-Null }
    else { Add-Result "Memory" "avml" "FAIL" "Could not resolve GitHub release" }
}

# ---- LiME (Linux kernel module -- clone source, compile on target) -----------
if (!(Should-Skip "LiME")) {
    $limeDir = Join-Path $Root "02_Forensics\memory\LiME"
    if ($git -and (!(Test-Path "$limeDir\src") -or $Force)) {
        try {
            if (Test-Path $limeDir) { Remove-Item $limeDir -Recurse -Force }
            git clone --depth=1 "https://github.com/504ensicsLabs/LiME.git" $limeDir 2>$null
            Add-Result "Memory" "LiME (source cloned)" "COMPILE" "Must compile on target Linux system. See COMPILE.txt." $limeDir
@"
# LiME -- Compile on the TARGET Linux machine (must match running kernel)
# -----------------------------------------------------------------------
# Install build dependencies:
sudo apt-get install -y linux-headers-`$(uname -r) build-essential   # Debian/Ubuntu
# or
sudo yum install -y kernel-devel kernel-headers gcc make              # RHEL/CentOS

# Compile:
cd LiME/src
make

# Acquire memory:
sudo insmod lime.ko "path=/mnt/usb/mem.lime format=lime"

# Hash immediately:
sha256sum /mnt/usb/mem.lime | tee /mnt/usb/mem.lime.sha256

# Unload:
sudo rmmod lime
"@ | Out-File (Join-Path $limeDir "COMPILE.txt") -Encoding ASCII
        } catch { Add-Result "Memory" "LiME" "FAIL" "git clone failed: $_" }
    } elseif (!$git) {
        Add-Result "Memory" "LiME" "SKIP" "Git not available -- clone manually: https://github.com/504ensicsLabs/LiME"
    } else { Add-Result "Memory" "LiME" "SKIP" "Already present. Use -Force to re-clone." $limeDir }
}

# ---- Eric Zimmerman Tools (EZ Tools) ----------------------------------------
if (!(Should-Skip "EZTools")) {
    $ezDir    = Join-Path $Root "02_Forensics\artefacts\EZTools"
    $ezScript = Join-Path $TempDir "Get-ZimmermanTools.ps1"
    if (Invoke-Download "https://raw.githubusercontent.com/EricZimmerman/Get-ZimmermanTools/master/Get-ZimmermanTools.ps1" `
        $ezScript "EZ Tools installer script" "Forensics") {
        Write-Host "  [BUILD] Running Get-ZimmermanTools.ps1 ..." -ForegroundColor DarkYellow
        & powershell.exe -ExecutionPolicy Bypass -File $ezScript -Dest $ezDir -NetVersion 4 2>$null
        $ezCount = (Get-ChildItem $ezDir -Recurse -File -EA SilentlyContinue).Count
        if ($ezCount -gt 0) { Add-Result "Forensics" "EZ Tools Suite ($ezCount files)" "OK" "Downloaded to $ezDir" $ezDir }
        else { Add-Result "Forensics" "EZ Tools Suite" "FAIL" "Installer ran but no files found in $ezDir" }
    }
}

# ---- Velociraptor standalone -------------------------------------------------
if (!(Should-Skip "Velociraptor")) {
    $dest = Join-Path $Root "02_Forensics\artefacts\Velociraptor\velociraptor.exe"
    $info = Get-GitHubLatest "Velocidex/velociraptor" "windows-amd64\.exe$"
    if ($info) { Invoke-Download $info.Url $dest "Velociraptor" "Forensics" | Out-Null }
    else { Add-Result "Forensics" "Velociraptor" "FAIL" "Could not resolve GitHub release" }
}

# ---- Wireshark: detect existing -> copy, or silent install -> copy -> uninstall
if (!(Should-Skip "Wireshark")) {
    $wsTarget = Join-Path $Root "03_Network\Wireshark"
    $wsFound  = $false

    # Check if already installed
    $wsReg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Wireshark" -EA SilentlyContinue
    if (!$wsReg) { $wsReg = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Wireshark" -EA SilentlyContinue }

    if ($wsReg -and $wsReg.InstallLocation -and (Test-Path $wsReg.InstallLocation)) {
        $wsPath = $wsReg.InstallLocation.TrimEnd('\')
        Write-Host "  [INFO] Wireshark already installed at $wsPath -- copying to USB..." -ForegroundColor Cyan
        Copy-Item -Path "$wsPath\*" -Destination $wsTarget -Recurse -Force
        $tshark = Join-Path $wsTarget "tshark.exe"
        if (Test-Path $tshark) {
            Add-Result "Network" "Wireshark + tshark (copied from existing install)" "OK" "Copied from $wsPath" $tshark (Get-SHA256 $tshark) $wsReg.DisplayVersion
            $wsFound = $true
        }
    }

    if (!$wsFound) {
        # Download installer, install silently, copy, uninstall
        $wsInstaller = Join-Path $TempDir "Wireshark-installer.exe"
        if (Invoke-Download "https://www.wireshark.org/download/win64/Wireshark-latest-x64.exe" $wsInstaller "Wireshark installer" "Network") {
            Write-Host "  [BUILD] Installing Wireshark silently..." -ForegroundColor DarkYellow
            $wsInstallDir = Join-Path $env:ProgramFiles "Wireshark"
            Start-Process -FilePath $wsInstaller -ArgumentList "/S /desktopicon=no /quicklaunchicon=no" -Wait -NoNewWindow

            Start-Sleep -Seconds 15   # give installer a moment to finish file writes

            if (Test-Path $wsInstallDir) {
                Write-Host "  [BUILD] Copying Wireshark folder to USB..." -ForegroundColor DarkYellow
                Copy-Item -Path "$wsInstallDir\*" -Destination $wsTarget -Recurse -Force
                $tshark = Join-Path $wsTarget "tshark.exe"
                if (Test-Path $tshark) {
                    Add-Result "Network" "Wireshark + tshark (installed->copied)" "OK" "Installed silently, copied, will uninstall" $tshark (Get-SHA256 $tshark)
                    $wsFound = $true
                }
                # Uninstall
                Write-Host "  [BUILD] Uninstalling Wireshark from this machine..." -ForegroundColor DarkYellow
                $wsUninstall = Join-Path $wsInstallDir "uninstall.exe"
                if (Test-Path $wsUninstall) {
                    Start-Process -FilePath $wsUninstall -ArgumentList "/S" -Wait -NoNewWindow
                    Add-Result "Network" "Wireshark (uninstalled from build machine)" "OK" "Build machine is clean"
                }
            } else {
                Add-Result "Network" "Wireshark" "FAIL" "Installer ran but $wsInstallDir not found"
            }
        }
    }

    # Write tshark/tcpdump quick-start note
@"
# Wireshark + tshark -- USB Quick-Start
#
# Run tshark.exe directly from this USB folder:
#   tshark.exe -D                                      # list interfaces
#   tshark.exe -i 1 -w D:\07_Evidence\capture.pcap    # capture on interface 1
#   tshark.exe -i 1 -w capture.pcap -a duration:300   # capture for 5 minutes
#
# Filter examples:
#   tshark.exe -i 1 -f "not host 10.0.0.50" -w capture.pcap   # exclude analyst IP
#   tshark.exe -i 1 -f "port 53" -w dns.pcap                  # DNS only
#   tshark.exe -i 1 -f "dst port 4444" -w suspicious.pcap     # suspicious C2 port
#
# On Linux/macOS use tcpdump (built-in):
#   sudo tcpdump -i any -w /mnt/usb/capture.pcap
#   sudo tcpdump -i eth0 -f "not host 10.0.0.50" -w capture.pcap
#
# On macOS:
#   sudo tcpdump -i en0 -w /Volumes/USB/capture.pcap
"@ | Out-File (Join-Path $Root "03_Network\Wireshark\TSHARK_QUICKSTART.txt") -Encoding ASCII
}

# ---- ProcMon (Process Monitor -- Sysinternals) --------------------------------
if (!(Should-Skip "ProcMon")) {
    $dest = Join-Path $Root "04_Malware\ProcMon"
    $zip  = Join-Path $TempDir "ProcessMonitor.zip"
    if (Invoke-Download "https://download.sysinternals.com/files/ProcessMonitor.zip" $zip "Process Monitor" "Malware") {
        Expand-Auto $zip $dest
        Add-Result "Malware" "ProcMon (extracted)" "OK" "Real-time file, registry and process activity monitor. Extracted to $dest" $dest
    }
}

# ---- Autoruns ----------------------------------------------------------------
if (!(Should-Skip "Autoruns")) {
    $dest = Join-Path $Root "04_Malware\Autoruns"
    $zip  = Join-Path $TempDir "Autoruns.zip"
    if (Invoke-Download "https://download.sysinternals.com/files/Autoruns.zip" $zip "Autoruns" "Malware") {
        Expand-Auto $zip $dest
        Add-Result "Malware" "Autoruns (extracted)" "OK" "Extracted to $dest" $dest
    }
}


# ---- YARA + rules ------------------------------------------------------------
if (!(Should-Skip "YARA")) {
    $yaraDir = Join-Path $Root "04_Malware\yara"
    $info    = Get-GitHubLatest "VirusTotal/yara" "yara-v.*-win64\.zip$"
    if ($info) {
        $zip = Join-Path $TempDir $info.FileName
        if (Invoke-Download $info.Url $zip "YARA engine (Windows)" "Malware") {
            Expand-Auto $zip "$yaraDir\bin"
            Add-Result "Malware" "YARA (extracted)" "OK" "Bin at $yaraDir\bin" "" "" $info.Version
        }
    }
    # Rules: Neo23x0/signature-base (Florian Roth community rules)
    $rulesDir = "$yaraDir\rules\signature-base"
    if ($git -and (!(Test-Path "$rulesDir\.git") -or $Force)) {
        Write-Host "  [BUILD] Cloning YARA signature-base rules..." -ForegroundColor DarkYellow
        if (Test-Path $rulesDir) { Remove-Item $rulesDir -Recurse -Force }
        git clone --depth=1 "https://github.com/Neo23x0/signature-base.git" $rulesDir 2>$null
        Add-Result "Malware" "YARA rules (Neo23x0/signature-base)" "OK" "Cloned to $rulesDir" $rulesDir
    } elseif (!$git) {
        Add-Result "Malware" "YARA rules" "SKIP" "Git not available"
    } else { Add-Result "Malware" "YARA rules" "SKIP" "Already cloned. Use -Force to refresh." }
}


# ---- Loki IOC Scanner (open-source, YARA + IOC + hash based) ----------------
if (!(Should-Skip "Loki")) {
    $lokiDir = Join-Path $Root "04_Malware\Loki"
    $info    = Get-GitHubLatest "Neo23x0/Loki" "loki_.*\.zip$"
    if ($info) {
        $zip = Join-Path $TempDir $info.FileName
        if (Invoke-Download $info.Url $zip "Loki IOC scanner" "Malware") {
            Expand-Auto $zip $lokiDir
            Add-Result "Malware" "Loki IOC Scanner (extracted)" "OK" "Run loki.exe on suspect host. Auto-updates IOC DB on first run." $lokiDir "" $info.Version
        }
    } else { Add-Result "Malware" "Loki IOC Scanner" "FAIL" "Could not resolve GitHub release" }
}

# ---- HitmanPro (Sophos -- second-opinion scanner) ----------------------------
if (!(Should-Skip "HitmanPro")) {
    $hmDir = Join-Path $Root "04_Malware\HitmanPro"
    Invoke-Download "https://www.bleepingcomputer.com/download/hitmanpro/dl/176/" (Join-Path $hmDir "hitmanpro_x64.exe") "HitmanPro 64-bit" "Malware" | Out-Null
    Invoke-Download "https://www.bleepingcomputer.com/download/hitmanpro/dl/175/" (Join-Path $hmDir "hitmanpro.exe")      "HitmanPro 32-bit" "Malware" | Out-Null
@"
# HitmanPro -- Quick Start (Sophos second-opinion scanner)
#
# Run directly -- no installation required:
#   hitmanpro_x64.exe   (64-bit systems)
#   hitmanpro.exe       (32-bit systems)
#
# For a silent scan with log output:
#   hitmanpro_x64.exe /quiet /log:E:\07_Evidence\hitmanpro_scan.log
#
# Note: Requires internet on first run to fetch latest cloud scan signatures.
#       Use it as a second opinion AFTER primary triage -- do not use as first step.
"@ | Out-File (Join-Path $hmDir "HITMANPRO_QUICKSTART.txt") -Encoding ASCII
}

# ---- RootkitRevealer (Sysinternals) ------------------------------------------
if (!(Should-Skip "RootkitRevealer")) {
    $dest = Join-Path $Root "04_Malware\RootkitRevealer"
    $zip  = Join-Path $TempDir "RootkitRevealer.zip"
    if (Invoke-Download "https://download.sysinternals.com/files/RootkitRevealer.zip" $zip "RootkitRevealer" "Malware") {
        Expand-Auto $zip $dest
        Add-Result "Malware" "RootkitRevealer (extracted)" "OK" "Scans registry and filesystem for rootkit discrepancies. Extracted to $dest" $dest
    }
}

# ---- Malwarebytes Anti-Malware -----------------------------------------------
if (!(Should-Skip "Malwarebytes")) {
    $dest = Join-Path $Root "04_Malware\Malwarebytes\MBSetup.exe"
    Invoke-Download "https://downloads.malwarebytes.com/file/mb-windows" $dest "Malwarebytes Anti-Malware" "Malware" | Out-Null
@"
# Malwarebytes -- Quick Start
#
# Run the installer directly from the USB:
#   MBSetup.exe
#
# For a scan without full install (trial/on-demand):
#   Launch MBSetup.exe -> choose "Scan" without activating premium features.
#
# Note: Installs to the target host temporarily. Uninstall after scan if needed.
"@ | Out-File (Join-Path $Root "04_Malware\Malwarebytes\MALWAREBYTES_QUICKSTART.txt") -Encoding ASCII
}

# ---- AdwCleaner (Malwarebytes) -----------------------------------------------
if (!(Should-Skip "AdwCleaner")) {
    $dest = Join-Path $Root "04_Malware\AdwCleaner\adwcleaner.exe"
    Invoke-Download "https://www.bleepingcomputer.com/download/adwcleaner/dl/382/" $dest "AdwCleaner" "Malware" | Out-Null
@"
# AdwCleaner -- Quick Start (Malwarebytes adware/PUP remover)
#
# Run directly -- no installation required:
#   adwcleaner.exe
#
# For a silent scan (no removal, results saved to log):
#   adwcleaner.exe /eula /clean /noreboot
#
# View results log at: C:\AdwCleaner\Logs\
"@ | Out-File (Join-Path $Root "04_Malware\AdwCleaner\ADWCLEANER_QUICKSTART.txt") -Encoding ASCII
}

# ---- Chainsaw ----------------------------------------------------------------
if (!(Should-Skip "Chainsaw")) {
    $dest = Join-Path $Root "05_Logs\Chainsaw"
    $info = Get-GitHubLatest "WithSecureLabs/chainsaw" "chainsaw_x86_64-pc-windows-msvc\.zip$"
    if ($info) {
        $zip = Join-Path $TempDir $info.FileName
        if (Invoke-Download $info.Url $zip "Chainsaw" "Logs") {
            Expand-Auto $zip $dest
            Add-Result "Logs" "Chainsaw (extracted)" "OK" "Extracted to $dest" $dest "" $info.Version
        }
    } else { Add-Result "Logs" "Chainsaw" "FAIL" "Could not resolve GitHub release" }
}

# ---- Hayabusa ----------------------------------------------------------------
if (!(Should-Skip "Hayabusa")) {
    $dest = Join-Path $Root "05_Logs\Hayabusa"
    $info = Get-GitHubLatest "Yamato-Security/hayabusa" "hayabusa-.*-win-x64\.zip$"
    if ($info) {
        $zip = Join-Path $TempDir $info.FileName
        if (Invoke-Download $info.Url $zip "Hayabusa" "Logs") {
            Expand-Auto $zip $dest
            Add-Result "Logs" "Hayabusa (extracted)" "OK" "Extracted to $dest. AV may flag Sigma rule YMLs -- this is expected." $dest "" $info.Version
        }
    } else { Add-Result "Logs" "Hayabusa" "FAIL" "Could not resolve GitHub release" }
}

# ---- CyberChef offline -------------------------------------------------------
if (!(Should-Skip "CyberChef")) {
    $dest = Join-Path $Root "06_Utils\CyberChef"
    $info = Get-GitHubLatest "gchq/CyberChef" "CyberChef_v.*\.zip$"
    if ($info) {
        $zip = Join-Path $TempDir $info.FileName
        if (Invoke-Download $info.Url $zip "CyberChef (offline)" "Utils") {
            Expand-Auto $zip $dest
            Add-Result "Utils" "CyberChef (extracted)" "OK" "Open CyberChef.html in any browser -- no internet needed" $dest "" $info.Version
        }
    } else { Add-Result "Utils" "CyberChef" "FAIL" "Could not resolve GitHub release" }
}

# ---- jq ----------------------------------------------------------------------
if (!(Should-Skip "jq")) {
    $info    = Get-GitHubLatest "jqlang/jq" "jq-windows-amd64\.exe$"
    $infoLin = Get-GitHubLatest "jqlang/jq" "jq-linux-amd64$"
    if ($info)    { Invoke-Download $info.Url    (Join-Path $Root "06_Utils\jq\jq-windows.exe") "jq (Windows)" "Utils" | Out-Null }
    if ($infoLin) { Invoke-Download $infoLin.Url (Join-Path $Root "06_Utils\jq\jq-linux")       "jq (Linux)"   "Utils" | Out-Null }
}

# ---- PuTTY -------------------------------------------------------------------
if (!(Should-Skip "PuTTY")) {
    Invoke-Download "https://the.earth.li/~sgtatham/putty/latest/w64/putty.exe" (Join-Path $Root "06_Utils\putty\putty.exe") "PuTTY" "Utils" | Out-Null
    Invoke-Download "https://the.earth.li/~sgtatham/putty/latest/w64/pscp.exe"  (Join-Path $Root "06_Utils\putty\pscp.exe")  "PSCP"  "Utils" | Out-Null
}

# ---- HashMyFiles -------------------------------------------------------------
if (!(Should-Skip "HashMyFiles")) {
    $dest = Join-Path $Root "06_Utils\HashMyFiles"
    $zip  = Join-Path $TempDir "HashMyFiles.zip"
    if (Invoke-Download "https://www.nirsoft.net/utils/hashmyfiles-x64.zip" $zip "HashMyFiles" "Utils") {
        Expand-Auto $zip $dest
        Add-Result "Utils" "HashMyFiles (extracted)" "OK" "Extracted to $dest" $dest
    }
}

} # end if not Offline

# ============================================================
#  STEP 4  WRITE EMBEDDED SCRIPTS
# ============================================================
Write-Step "STEP 4 -- Writing Embedded IR Scripts"

function Write-Script { param([string]$Dest, [string]$Content, [string]$Name)
    $dir = Split-Path $Dest -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    # Write with UTF-8 BOM so PowerShell 5.1 reads correctly
    $utf8bom = New-Object System.Text.UTF8Encoding $true
    [IO.File]::WriteAllText($Dest, $Content, $utf8bom)
    $hash = Get-SHA256 $Dest
    Add-Result "Scripts" $Name "OK" "Written to $Dest" $Dest $hash
}

function Write-ShellScript { param([string]$Dest, [string]$Content, [string]$Name)
    $dir = Split-Path $Dest -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    # Shell scripts: UTF-8 without BOM, LF line endings
    $lf = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    [IO.File]::WriteAllBytes($Dest, [Text.Encoding]::UTF8.GetBytes($lf))
    Add-Result "Scripts" $Name "OK" "Written to $Dest" $Dest (Get-SHA256 $Dest)
}


# -- Windows: triage_collect.ps1 --
$tcScript = @'
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    IR Jumpkit - triage_collect.ps1
    Fast volatile triage: run this FIRST on a live Windows host.

.DESCRIPTION
    Lightweight, fast-running volatile data collector. Completes in ~90 seconds.
    Captures data that disappears on reboot:
      - Running processes (tree, cmdlines, hashes, unsigned modules)
      - Network connections mapped to owning processes
      - Active sessions, recent logons/failures
      - Services, drivers
      - Persistence (Run keys, tasks, WMI subscriptions, LSA packages, IFEO)
      - Loaded DLLs per process, unsigned module detection
      - Clipboard, PS history, Defender exclusions, env vars

    Run collect_artifacts.ps1 afterwards for full non-volatile collection
    (event logs, registry hives, prefetch, scheduled task XML).

.PARAMETER OutputPath
    Where to write output. Defaults to USB\07_Evidence\<timestamp>_<host>_Triage.
    Always point this at the USB - never write to the suspect host's disk.

.PARAMETER SkipHash
    Skip SHA-256 hashing of output files. Faster, less rigorous.

.EXAMPLE
    .\triage_collect.ps1
    .\triage_collect.ps1 -OutputPath "E:\07_Evidence\2024-01-01_Incident"
    .\triage_collect.ps1 -SkipHash
#>

param(
    [string]$OutputPath = "$PSScriptRoot\..\..\07_Evidence\$(Get-Date -Format 'yyyy-MM-dd_HHmmss')_$(hostname)_Triage",
    [switch]$SkipHash
)

$ErrorActionPreference = "SilentlyContinue"
$StartTime  = Get-Date
$Hostname   = $env:COMPUTERNAME
$Analyst    = $env:USERNAME

# --- Directory setup ----------------------------------------------------------
foreach ($d in @("01_processes","02_network","03_users_sessions",
                 "04_services_drivers","05_persistence","06_dlls_modules","07_system")) {
    New-Item -ItemType Directory -Force -Path "$OutputPath\$d" | Out-Null
}

$Log = "$OutputPath\_triage.log"

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts][$Level] $Msg"
    $col  = switch ($Level) { "WARN" {"Yellow"} "CRIT" {"Red"} "OK" {"Green"} default {"Cyan"} }
    Write-Host "  $line" -ForegroundColor $col
    Add-Content -Path $Log -Value $line
}

function Out-Triage {
    param([string]$Rel, [scriptblock]$Cmd)
    try   { & $Cmd 2>$null | Out-File "$OutputPath\$Rel" -Encoding UTF8 -Force; Write-Log "OK   $Rel" "OK" }
    catch { Write-Log "FAIL $Rel - $_" "WARN" }
}

# --- Banner -------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor Red
Write-Host "  |      IR JUMPKIT  -  Windows Quick Triage             |" -ForegroundColor Red
Write-Host "  +======================================================+" -ForegroundColor DarkRed
Write-Host "  |  Host    : $Hostname" -ForegroundColor White
Write-Host "  |  Analyst : $Analyst" -ForegroundColor White
Write-Host "  |  Time    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') (local)" -ForegroundColor White
Write-Host "  |  UTC     : $(Get-Date -AsUTC -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "  |  Output  : $OutputPath" -ForegroundColor White
Write-Host "  +======================================================+" -ForegroundColor Red
Write-Host ""
Write-Log "=== TRIAGE START === Host:$Hostname Analyst:$Analyst ==="

# --- 00  System snapshot ------------------------------------------------------
Write-Log "[ 00 ] System snapshot"
Out-Triage "00_snapshot.txt" {
    $os  = Get-WmiObject Win32_OperatingSystem
    $cs  = Get-WmiObject Win32_ComputerSystem
    "Host            : $env:COMPUTERNAME"
    "Analyst         : $env:USERNAME"
    "Script Time     : $(Get-Date)"
    "UTC Time        : $(Get-Date -AsUTC)"
    "Local TZ        : $((Get-TimeZone).DisplayName)"
    "NTP Source      : $(w32tm /query /source 2>$null)"
    "OS              : $($os.Caption)"
    "OS Build        : $($os.BuildNumber)"
    "Architecture    : $env:PROCESSOR_ARCHITECTURE"
    "Last Boot       : $($os.LastBootUpTime)"
    "Uptime          : $((Get-Date) - [Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime))"
    "Physical RAM    : $([math]::Round($cs.TotalPhysicalMemory/1GB,2)) GB"
    "Domain          : $env:USERDOMAIN"
    "Logon Server    : $env:LOGONSERVER"
    ""
    "=== Drives ==="
    Get-PSDrive -PSProvider FileSystem |
        Select-Object Name,
            @{N="UsedGB"; E={[math]::Round($_.Used/1GB,1)}},
            @{N="FreeGB"; E={[math]::Round($_.Free/1GB,1)}} |
        Format-Table -AutoSize
}

# --- 01  Processes ------------------------------------------------------------
Write-Log "[ 01 ] Processes"

Out-Triage "01_processes\process_list.txt" {
    Get-WmiObject Win32_Process | Sort-Object ProcessId |
        Select-Object ProcessId, ParentProcessId, Name,
            @{N="Owner";      E={$_.GetOwner().User}},
            @{N="Created";    E={$_.ConvertToDateTime($_.CreationDate)}},
            ExecutablePath, CommandLine |
        Format-Table -AutoSize -Wrap
}

Out-Triage "01_processes\process_tree.txt" {
    $all    = Get-WmiObject Win32_Process
    $lookup = @{}; $all | ForEach-Object { $lookup[$_.ProcessId] = $_ }
    function Draw-Tree($pid, $indent="") {
        $p = $lookup[$pid]; if (!$p) { return }
        "  $indent[$($p.ProcessId)] $($p.Name)  -  $($p.CommandLine)"
        $all | Where-Object { $_.ParentProcessId -eq $pid -and $_.ProcessId -ne $pid } |
            ForEach-Object { Draw-Tree $_.ProcessId ("  " + $indent) }
    }
    $all | Where-Object { !$lookup.ContainsKey($_.ParentProcessId) -or $_.ParentProcessId -eq 0 } |
        ForEach-Object { Draw-Tree $_.ProcessId }
}

Out-Triage "01_processes\process_hashes.txt" {
    "SHA256 | PID | Name | Path"
    "-"*100
    Get-WmiObject Win32_Process |
        Where-Object { $_.ExecutablePath -and (Test-Path $_.ExecutablePath) } |
        ForEach-Object {
            $h = (Get-FileHash $_.ExecutablePath -Algorithm SHA256 -EA SilentlyContinue).Hash
            "$h | $($_.ProcessId) | $($_.Name) | $($_.ExecutablePath)"
        }
}

Out-Triage "01_processes\suspicious_cmdlines.txt" {
    $watchlist = "powershell","cmd","wscript","cscript","mshta","rundll32","regsvr32",
                 "msiexec","certutil","bitsadmin","wmic","psexec","nc","ncat","netcat",
                 "mimikatz","procdump","lsass","pwdump","fgdump"
    Get-WmiObject Win32_Process |
        Where-Object { $watchlist -contains ($_.Name -replace '\.exe$','').ToLower() } |
        Select-Object ProcessId, Name, CommandLine, ExecutablePath |
        Format-Table -AutoSize -Wrap
}

Out-Triage "01_processes\missing_exe.txt" {
    "Processes whose executable path does not exist on disk (hollowing / deleted binary indicator)"
    "-"*80
    Get-WmiObject Win32_Process |
        Where-Object { $_.ExecutablePath -and !(Test-Path $_.ExecutablePath) } |
        Select-Object ProcessId, Name, ExecutablePath, CommandLine |
        Format-Table -AutoSize -Wrap
}

# --- 02  Network --------------------------------------------------------------
Write-Log "[ 02 ] Network"

Out-Triage "02_network\connections_with_process.txt" {
    Get-NetTCPConnection | Where-Object { $_.State -ne "TimeWait" } |
        ForEach-Object {
            $p = Get-Process -Id $_.OwningProcess -EA SilentlyContinue
            [PSCustomObject]@{
                State       = $_.State
                LocalAddr   = "$($_.LocalAddress):$($_.LocalPort)"
                RemoteAddr  = "$($_.RemoteAddress):$($_.RemotePort)"
                PID         = $_.OwningProcess
                ProcessName = if ($p) { $p.Name }     else { "?" }
                ProcessPath = if ($p) { $p.MainModule.FileName } else { "?" }
            }
        } | Sort-Object State | Format-Table -AutoSize
}

Out-Triage "02_network\netstat_ano.txt"          { netstat -ano }
Out-Triage "02_network\netstat_anob.txt"         { netstat -anob }
Out-Triage "02_network\established.txt"          { netstat -ano | Select-String "ESTABLISHED" }
Out-Triage "02_network\listening.txt"            { netstat -ano | Select-String "LISTENING" }
Out-Triage "02_network\dns_cache.txt"            { ipconfig /displaydns }
Out-Triage "02_network\arp_cache.txt"            { arp -a }
Out-Triage "02_network\routing_table.txt"        { route print }
Out-Triage "02_network\ipconfig.txt"             { ipconfig /all }
Out-Triage "02_network\hosts_file.txt"           { Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" }
Out-Triage "02_network\smb_sessions.txt"         { net session }
Out-Triage "02_network\smb_shares.txt"           { net share }
Out-Triage "02_network\firewall_state.txt"       { netsh advfirewall show allprofiles state }
Out-Triage "02_network\proxy_settings.txt" {
    Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" |
        Select-Object ProxyEnable, ProxyServer, ProxyOverride, AutoConfigURL
}

# --- 03  Users & Sessions -----------------------------------------------------
Write-Log "[ 03 ] Users & Sessions"
Out-Triage "03_users_sessions\logged_on.txt"     { query user 2>$null }
Out-Triage "03_users_sessions\whoami_all.txt"    { whoami /all }
Out-Triage "03_users_sessions\local_admins.txt"  { net localgroup administrators }
Out-Triage "03_users_sessions\local_users.txt"   { Get-LocalUser | Format-Table -AutoSize }
Out-Triage "03_users_sessions\rdp_sessions.txt"  { qwinsta 2>$null }
Out-Triage "03_users_sessions\ps_history.txt" {
    $h = (Get-PSReadLineOption -EA SilentlyContinue).HistorySavePath
    if ($h -and (Test-Path $h)) { Get-Content $h } else { "PSReadLine history unavailable" }
}
Out-Triage "03_users_sessions\recent_logons.txt" {
    Get-WinEvent -LogName Security -MaxEvents 500 -EA SilentlyContinue |
        Where-Object Id -eq 4624 |
        ForEach-Object {
            [PSCustomObject]@{
                Time      = $_.TimeCreated
                User      = $_.Properties[5].Value
                Domain    = $_.Properties[6].Value
                LogonType = $_.Properties[8].Value
                SourceIP  = $_.Properties[18].Value
            }
        } | Format-Table -AutoSize
}
Out-Triage "03_users_sessions\failed_logons.txt" {
    Get-WinEvent -LogName Security -MaxEvents 200 -EA SilentlyContinue |
        Where-Object Id -eq 4625 |
        ForEach-Object {
            [PSCustomObject]@{
                Time     = $_.TimeCreated
                User     = $_.Properties[5].Value
                SourceIP = $_.Properties[19].Value
                Reason   = $_.Properties[9].Value
            }
        } | Format-Table -AutoSize
}

# --- 04  Services & Drivers ---------------------------------------------------
Write-Log "[ 04 ] Services & Drivers"
Out-Triage "04_services_drivers\running_services.txt" {
    Get-WmiObject Win32_Service | Where-Object State -eq Running |
        Select-Object ProcessId, Name, DisplayName, PathName, StartName | Format-Table -AutoSize
}
Out-Triage "04_services_drivers\all_services.txt" {
    Get-WmiObject Win32_Service |
        Select-Object Name, State, StartMode, PathName, StartName | Format-Table -AutoSize
}
Out-Triage "04_services_drivers\new_services_7045.txt" {
    Get-WinEvent -LogName System -MaxEvents 2000 -EA SilentlyContinue |
        Where-Object Id -eq 7045 | Select-Object TimeCreated, Message | Format-List
}
Out-Triage "04_services_drivers\drivers.txt" {
    Get-WmiObject Win32_SystemDriver |
        Select-Object Name, State, PathName | Format-Table -AutoSize
}

# --- 05  Persistence ----------------------------------------------------------
Write-Log "[ 05 ] Persistence"

Out-Triage "05_persistence\run_keys.txt" {
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($k in $keys) {
        "=== $k ==="; Get-ItemProperty $k 2>$null | Format-List; ""
    }
}

Out-Triage "05_persistence\scheduled_tasks.txt" {
    Get-ScheduledTask | Where-Object State -ne Disabled |
        Select-Object TaskName, TaskPath, State,
            @{N="Action"; E={($_.Actions | ForEach-Object {"$($_.Execute) $($_.Arguments)"}) -join " | "}} |
        Format-Table -AutoSize -Wrap
}

Out-Triage "05_persistence\startup_folders.txt" {
    "=== User Startup ===";   Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -Force
    "=== Common Startup ==="; Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" -Force
}

Out-Triage "05_persistence\wmi_subscriptions.txt" {
    "=== EventFilter ===";    Get-WMIObject -NS root\subscription -Class __EventFilter     2>$null | Format-List
    "=== EventConsumer ===";  Get-WMIObject -NS root\subscription -Class __EventConsumer   2>$null | Format-List
    "=== Binding ===";        Get-WMIObject -NS root\subscription -Class __FilterToConsumerBinding 2>$null | Format-List
}

Out-Triage "05_persistence\image_file_execution_options.txt" {
    "IFEO Debugger entries (used for persistence / process hijacking):"
    Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options" 2>$null |
        ForEach-Object {
            $v = Get-ItemProperty $_.PSPath -EA SilentlyContinue
            if ($v.Debugger) { "  [$($_.PSChildName)]  Debugger = $($v.Debugger)" }
        }
}

Out-Triage "05_persistence\lsa_packages.txt" {
    $lsa = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -EA SilentlyContinue
    "Authentication Packages : $($lsa.'Authentication Packages')"
    "Security Packages       : $($lsa.'Security Packages')"
    "Notification Packages   : $($lsa.'Notification Packages')"
}

# --- 06  DLLs & Unsigned Modules ---------------------------------------------
Write-Log "[ 06 ] DLLs & Unsigned Modules"

Out-Triage "06_dlls_modules\dlls_per_process.txt" {
    Get-Process | ForEach-Object {
        "=== PID $($_.Id)  $($_.Name)  [$($_.Path)] ==="
        $_.Modules 2>$null | Select-Object -ExpandProperty FileName | ForEach-Object { "  $_" }
        ""
    }
}

Out-Triage "06_dlls_modules\unsigned_modules.txt" {
    "Modules without a valid Authenticode signature:"
    "-"*80
    Get-Process | ForEach-Object {
        $proc = $_
        $_.Modules 2>$null | ForEach-Object {
            $sig = Get-AuthenticodeSignature $_.FileName -EA SilentlyContinue
            if ($sig -and $sig.Status -ne "Valid") {
                "PID $($proc.Id) | $($proc.Name) | $($sig.Status) | $($_.FileName)"
            }
        }
    }
}

# --- 07  System State ---------------------------------------------------------
Write-Log "[ 07 ] System state"
Out-Triage "07_system\environment_variables.txt"  { Get-ChildItem Env: | Format-Table -AutoSize }
Out-Triage "07_system\clipboard.txt" {
    Add-Type -AssemblyName System.Windows.Forms
    $cb = [System.Windows.Forms.Clipboard]::GetText()
    if ($cb) { $cb } else { "(clipboard empty)" }
}
Out-Triage "07_system\hotfixes.txt" {
    Get-HotFix | Sort-Object InstalledOn -Descending | Format-Table -AutoSize
}
Out-Triage "07_system\defender_exclusions.txt" {
    Get-MpPreference 2>$null | Select-Object ExclusionPath, ExclusionProcess, ExclusionExtension | Format-List
}
Out-Triage "07_system\bitlocker_status.txt"        { manage-bde -status 2>$null }
Out-Triage "07_system\installed_software.txt" {
    Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Sort-Object InstallDate -Descending | Format-Table -AutoSize
}

# --- Hash manifest ------------------------------------------------------------
if (-not $SkipHash) {
    Write-Log "[ 08 ] Hashing output files"
    $manifest = "$OutputPath\_hashes.csv"
    "FilePath,SHA256,SizeKB" | Out-File $manifest -Encoding UTF8
    Get-ChildItem -Path $OutputPath -Recurse -File |
        Where-Object Name -notlike "_hashes*" |
        ForEach-Object {
            $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
            "$($_.FullName),$h,$([math]::Round($_.Length/1KB,1))"
        } | Add-Content $manifest
    Write-Log "Hash manifest written: _hashes.csv" "OK"
}

# --- Summary ------------------------------------------------------------------
$Duration  = (Get-Date) - $StartTime
$FileCount = (Get-ChildItem $OutputPath -Recurse -File).Count
$SizeMB    = [math]::Round((Get-ChildItem $OutputPath -Recurse | Measure-Object Length -Sum).Sum/1MB,1)

Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host "  |            TRIAGE COMPLETE                           |" -ForegroundColor Green
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host "  |  Host      : $Hostname" -ForegroundColor Green
Write-Host "  |  Duration  : $($Duration.ToString('mm\:ss')) (mm:ss)" -ForegroundColor Green
Write-Host "  |  Files     : $FileCount" -ForegroundColor Green
Write-Host "  |  Total     : $SizeMB MB" -ForegroundColor Green
Write-Host "  |  Output    : $OutputPath" -ForegroundColor Green
Write-Host "  +======================================================+" -ForegroundColor Yellow
Write-Host "  |  NEXT: winpmem.exe > collect_artifacts.ps1 > isolate |" -ForegroundColor Yellow
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host ""

Write-Log "=== TRIAGE DONE === Files:$FileCount Size:${SizeMB}MB Duration:$($Duration.ToString('mm\:ss')) ==="

'@
Write-Script (Join-Path $Root '01_Triage\windows\triage_collect.ps1') $tcScript 'triage_collect.ps1'

# -- Windows: collect_artifacts.ps1 --
$caScript = @'
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    IR Jumpkit - Windows Triage Artifact Collector
.DESCRIPTION
    Collects volatile and non-volatile artefacts from a live Windows system.
    Run from the USB. Output goes to a timestamped folder on the USB or a
    network share. DO NOT run directly on the suspect host's C:\ drive.
.USAGE
    .\collect_artifacts.ps1 [-OutputPath "D:\07_Evidence\2024-01-01_Incident"]
.NOTES
    Author : IR Jumpkit
    Version: 1.2
    Requires: PowerShell 5.1+, Run As Administrator
#>

param(
    [string]$OutputPath = "$PSScriptRoot\..\..\07_Evidence\$(Get-Date -Format 'yyyy-MM-dd_HHmmss')_Triage"
)

# --- Initialise ----------------------------------------------------------------
$ErrorActionPreference = "SilentlyContinue"
$StartTime = Get-Date
$Hostname  = $env:COMPUTERNAME

New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$Dirs = @(
    "volatile\processes",
    "volatile\network",
    "volatile\users",
    "volatile\services",
    "nonvolatile\eventlogs",
    "nonvolatile\registry",
    "nonvolatile\prefetch",
    "nonvolatile\scheduled_tasks",
    "nonvolatile\persistence",
    "nonvolatile\recent_files",
    "hashes"
)
foreach ($d in $Dirs) { New-Item -ItemType Directory -Force -Path "$OutputPath\$d" | Out-Null }

$LogFile = "$OutputPath\collection.log"

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Save-Output {
    param([string]$Path, [scriptblock]$Command)
    try {
        & $Command | Out-File -FilePath $Path -Encoding UTF8
        Write-Log "Saved: $Path"
    } catch {
        Write-Log "FAILED: $Path - $_" "WARN"
    }
}

Write-Log "=== IR Jumpkit Windows Triage === Host: $Hostname ==="
Write-Log "Output directory: $OutputPath"
Write-Log "Collector started at: $StartTime"

# --- SYSTEM INFO ---------------------------------------------------------------
Write-Log "--- System Information ---"
Save-Output "$OutputPath\system_info.txt" { systeminfo }
Save-Output "$OutputPath\system_time.txt" {
    "System Time  : $(Get-Date)"
    "UTC Time     : $(Get-Date -AsUTC)"
    "Timezone     : $((Get-TimeZone).DisplayName)"
    "NTP Source   : $(w32tm /query /source 2>$null)"
}

# --- VOLATILE - PROCESSES ------------------------------------------------------
Write-Log "--- Volatile: Processes ---"
Save-Output "$OutputPath\volatile\processes\process_list.txt" {
    Get-Process | Select-Object Id, Name, CPU, WorkingSet, Path, StartTime,
        @{N="ParentPID";E={(Get-WmiObject Win32_Process -Filter "ProcessId=$($_.Id)").ParentProcessId}},
        @{N="CommandLine";E={(Get-WmiObject Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine}} |
        Format-Table -AutoSize
}
Save-Output "$OutputPath\volatile\processes\process_tree.txt" {
    Get-WmiObject Win32_Process | Select-Object ProcessId, Name, ParentProcessId, CommandLine, ExecutablePath |
        Sort-Object ParentProcessId | Format-Table -AutoSize
}
Save-Output "$OutputPath\volatile\processes\dlls_per_process.txt" {
    Get-Process | ForEach-Object {
        "PID $($_.Id) - $($_.Name)"
        $_.Modules | Select-Object -ExpandProperty FileName | ForEach-Object { "  $_" }
    }
}

# --- VOLATILE - NETWORK --------------------------------------------------------
Write-Log "--- Volatile: Network ---"
Save-Output "$OutputPath\volatile\network\netstat.txt"          { netstat -ano }
Save-Output "$OutputPath\volatile\network\netstat_b.txt"        { netstat -anob }
Save-Output "$OutputPath\volatile\network\arp_cache.txt"        { arp -a }
Save-Output "$OutputPath\volatile\network\dns_cache.txt"        { ipconfig /displaydns }
Save-Output "$OutputPath\volatile\network\routing_table.txt"    { route print }
Save-Output "$OutputPath\volatile\network\ipconfig_all.txt"     { ipconfig /all }
Save-Output "$OutputPath\volatile\network\hosts_file.txt"       { Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" }
Save-Output "$OutputPath\volatile\network\firewall_rules.txt"   { netsh advfirewall firewall show rule name=all }
Save-Output "$OutputPath\volatile\network\smb_shares.txt"       { net share }
Save-Output "$OutputPath\volatile\network\smb_sessions.txt"     { net session }
Save-Output "$OutputPath\volatile\network\wifi_profiles.txt"    { netsh wlan show profiles }

# --- VOLATILE - USERS & SESSIONS ----------------------------------------------
Write-Log "--- Volatile: Users & Sessions ---"
Save-Output "$OutputPath\volatile\users\logged_on_users.txt"    { query user }
Save-Output "$OutputPath\volatile\users\local_accounts.txt"     { Get-LocalUser | Format-Table -AutoSize }
Save-Output "$OutputPath\volatile\users\local_groups.txt"       { Get-LocalGroup | Format-Table -AutoSize }
Save-Output "$OutputPath\volatile\users\admins.txt"             { net localgroup administrators }
Save-Output "$OutputPath\volatile\users\open_sessions.txt"      { net sessions }
Save-Output "$OutputPath\volatile\users\recent_logons.txt" {
    Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4624]]" -MaxEvents 200 |
        Select-Object TimeCreated, @{N="User";E={$_.Properties[5].Value}},
        @{N="LogonType";E={$_.Properties[8].Value}},
        @{N="SourceIP";E={$_.Properties[18].Value}} |
        Format-Table -AutoSize
}

# --- VOLATILE - SERVICES -------------------------------------------------------
Write-Log "--- Volatile: Services ---"
Save-Output "$OutputPath\volatile\services\running_services.txt" {
    Get-Service | Where-Object Status -eq Running | Select-Object Name, DisplayName, Status | Format-Table -AutoSize
}
Save-Output "$OutputPath\volatile\services\all_services.txt" {
    Get-WmiObject Win32_Service | Select-Object Name, State, StartMode, PathName, StartName | Format-Table -AutoSize
}
Save-Output "$OutputPath\volatile\services\drivers.txt" {
    Get-WmiObject Win32_SystemDriver | Select-Object Name, State, PathName | Format-Table -AutoSize
}

# --- NON-VOLATILE - EVENT LOGS ------------------------------------------------
Write-Log "--- Non-Volatile: Event Logs ---"
$EventLogs = @(
    "Security", "System", "Application",
    "Microsoft-Windows-PowerShell/Operational",
    "Microsoft-Windows-Sysmon/Operational",
    "Microsoft-Windows-TaskScheduler/Operational",
    "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational",
    "Microsoft-Windows-WMI-Activity/Operational"
)
foreach ($log in $EventLogs) {
    $safeName = $log -replace "[/\\]", "_"
    $dest = "$OutputPath\nonvolatile\eventlogs\$safeName.evtx"
    try {
        wevtutil epl $log $dest
        Write-Log "Exported event log: $log"
    } catch {
        Write-Log "Could not export: $log - $_" "WARN"
    }
}

# --- NON-VOLATILE - REGISTRY HIVES -------------------------------------------
Write-Log "--- Non-Volatile: Registry Hives ---"
$Hives = @{
    "SYSTEM"   = "HKLM\SYSTEM"
    "SOFTWARE" = "HKLM\SOFTWARE"
    "SAM"      = "HKLM\SAM"
    "SECURITY" = "HKLM\SECURITY"
    "NTUSER"   = "HKCU"
}
foreach ($name in $Hives.Keys) {
    $dest = "$OutputPath\nonvolatile\registry\$name.hiv"
    reg export $Hives[$name] "$dest.reg" /y 2>$null
    try {
        reg save $Hives[$name] $dest /y 2>$null
        Write-Log "Saved hive: $name"
    } catch {
        Write-Log "Could not save hive: $name" "WARN"
    }
}

# --- NON-VOLATILE - PERSISTENCE -----------------------------------------------
Write-Log "--- Non-Volatile: Persistence ---"
Save-Output "$OutputPath\nonvolatile\persistence\run_keys.txt" {
    "=== HKLM Run ==="
    Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" 2>$null
    "=== HKLM RunOnce ==="
    Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" 2>$null
    "=== HKCU Run ==="
    Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" 2>$null
    "=== HKCU RunOnce ==="
    Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" 2>$null
}
Save-Output "$OutputPath\nonvolatile\persistence\startup_folders.txt" {
    Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -Force
    Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" -Force
}
Save-Output "$OutputPath\nonvolatile\persistence\wmi_subscriptions.txt" {
    Get-WMIObject -Namespace root\subscription -Class __EventFilter
    Get-WMIObject -Namespace root\subscription -Class __EventConsumer
    Get-WMIObject -Namespace root\subscription -Class __FilterToConsumerBinding
}

# --- NON-VOLATILE - SCHEDULED TASKS ------------------------------------------
Write-Log "--- Non-Volatile: Scheduled Tasks ---"
Save-Output "$OutputPath\nonvolatile\scheduled_tasks\all_tasks.txt" {
    Get-ScheduledTask | Select-Object TaskName, TaskPath, State,
        @{N="Actions";E={($_.Actions | ForEach-Object {$_.Execute + " " + $_.Arguments}) -join "; "}},
        @{N="Triggers";E={($_.Triggers | ForEach-Object {$_.CimClass.CimClassName}) -join "; "}} |
        Format-Table -AutoSize
}
schtasks /query /fo LIST /v | Out-File "$OutputPath\nonvolatile\scheduled_tasks\schtasks_verbose.txt" -Encoding UTF8

# Copy raw task XML files
$TaskPath = "$env:SystemRoot\System32\Tasks"
if (Test-Path $TaskPath) {
    Copy-Item -Path $TaskPath -Destination "$OutputPath\nonvolatile\scheduled_tasks\xml_tasks" -Recurse -Force
    Write-Log "Copied scheduled task XML files"
}

# --- NON-VOLATILE - PREFETCH --------------------------------------------------
Write-Log "--- Non-Volatile: Prefetch ---"
$PrefetchSrc = "$env:SystemRoot\Prefetch"
if (Test-Path $PrefetchSrc) {
    Copy-Item -Path "$PrefetchSrc\*.pf" -Destination "$OutputPath\nonvolatile\prefetch\" -Force
    Write-Log "Copied $($(Get-ChildItem $PrefetchSrc -Filter *.pf).Count) prefetch files"
} else {
    Write-Log "Prefetch directory not found (may be disabled)" "WARN"
}

# --- NON-VOLATILE - RECENTLY ACCESSED FILES ----------------------------------
Write-Log "--- Non-Volatile: Recent Files ---"
Save-Output "$OutputPath\nonvolatile\recent_files\recent_docs.txt" {
    Get-ChildItem "$env:APPDATA\Microsoft\Windows\Recent" -Force | Select-Object Name, LastWriteTime | Sort-Object LastWriteTime -Descending
}
Save-Output "$OutputPath\nonvolatile\recent_files\recently_modified_system32.txt" {
    Get-ChildItem "$env:SystemRoot\System32" -Recurse -Force |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } |
        Select-Object FullName, LastWriteTime | Sort-Object LastWriteTime -Descending
}

# --- INSTALLED SOFTWARE -------------------------------------------------------
Write-Log "--- Installed Software ---"
Save-Output "$OutputPath\installed_software.txt" {
    Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Sort-Object InstallDate -Descending | Format-Table -AutoSize
}

# --- HASH SUMMARY -------------------------------------------------------------
Write-Log "--- Hashing Collected Files ---"
$HashManifest = "$OutputPath\hashes\manifest.csv"
"FilePath,SHA256,SizeMB,CollectedAt" | Out-File $HashManifest -Encoding UTF8
Get-ChildItem -Path $OutputPath -Recurse -File |
    Where-Object { $_.FullName -notlike "*\hashes\*" } |
    ForEach-Object {
        $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        $size = [math]::Round($_.Length / 1MB, 3)
        "$($_.FullName),$hash,$size,$(Get-Date -Format 'o')" | Add-Content $HashManifest
    }
Write-Log "Hash manifest written: $HashManifest"

# --- SUMMARY ------------------------------------------------------------------
$EndTime   = Get-Date
$Duration  = $EndTime - $StartTime
$FileCount = (Get-ChildItem -Path $OutputPath -Recurse -File).Count
$SizeMB    = [math]::Round((Get-ChildItem -Path $OutputPath -Recurse | Measure-Object Length -Sum).Sum / 1MB, 1)

Write-Log "=== COLLECTION COMPLETE ==="
Write-Log "Host         : $Hostname"
Write-Log "Duration     : $($Duration.ToString('hh\:mm\:ss'))"
Write-Log "Files saved  : $FileCount"
Write-Log "Total size   : $SizeMB MB"
Write-Log "Output path  : $OutputPath"
Write-Log "NEXT STEP    : Acquire memory dump with winpmem, then disk image with FTK Imager"

'@
Write-Script (Join-Path $Root '01_Triage\windows\collect_artifacts.ps1') $caScript 'collect_artifacts.ps1'

# -- Windows: isolate_host.ps1 --
$ihScript = @'
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    IR Jumpkit - Windows Host Isolation Script
.DESCRIPTION
    Isolates a Windows host from the network while preserving USB/local access.
    Blocks all inbound/outbound traffic except from a specified IR analyst IP.
    Run ONLY after memory capture is complete.
.USAGE
    .\isolate_host.ps1 -AnalystIP "10.0.0.50"
    .\isolate_host.ps1 -AnalystIP "10.0.0.50" -Undo   # Restore original rules
.NOTES
    CAUTION: This will drop all active network connections except your analyst IP.
    Ensure you have physical or out-of-band access before running.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$AnalystIP,
    [switch]$Undo
)

$BackupPath = "$PSScriptRoot\firewall_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').wfw"

if ($Undo) {
    Write-Host "[*] Restoring firewall rules from backup..." -ForegroundColor Yellow
    $backups = Get-ChildItem "$PSScriptRoot\firewall_backup_*.wfw" | Sort-Object LastWriteTime -Descending
    if ($backups) {
        netsh advfirewall import $backups[0].FullName
        Write-Host "[+] Firewall rules restored from: $($backups[0].Name)" -ForegroundColor Green
    } else {
        Write-Host "[-] No backup file found. Manually reset with: netsh advfirewall reset" -ForegroundColor Red
    }
    exit
}

Write-Host "`n[!] IR JUMPKIT - HOST ISOLATION" -ForegroundColor Red
Write-Host "    Host      : $env:COMPUTERNAME" -ForegroundColor White
Write-Host "    Analyst IP: $AnalystIP" -ForegroundColor White
Write-Host "    Backup    : $BackupPath" -ForegroundColor White
Write-Host ""
$confirm = Read-Host "Type 'ISOLATE' to proceed"
if ($confirm -ne "ISOLATE") { Write-Host "Aborted." ; exit }

# 1. Backup current rules
Write-Host "[*] Backing up current firewall rules..." -ForegroundColor Cyan
netsh advfirewall export $BackupPath
Write-Host "[+] Backup saved: $BackupPath" -ForegroundColor Green

# 2. Set all profiles to block by default
Write-Host "[*] Setting all profiles to block inbound and outbound by default..." -ForegroundColor Cyan
netsh advfirewall set allprofiles firewallpolicy blockinbound,blockoutbound

# 3. Allow analyst IP bidirectionally
Write-Host "[*] Allowing analyst IP: $AnalystIP ..." -ForegroundColor Cyan
netsh advfirewall firewall add rule name="IR_ANALYST_IN"  dir=in  action=allow remoteip=$AnalystIP
netsh advfirewall firewall add rule name="IR_ANALYST_OUT" dir=out action=allow remoteip=$AnalystIP

# 4. Allow loopback (required for many local services)
netsh advfirewall firewall add rule name="IR_LOOPBACK_IN"  dir=in  action=allow remoteip=127.0.0.1
netsh advfirewall firewall add rule name="IR_LOOPBACK_OUT" dir=out action=allow remoteip=127.0.0.1

# 5. Allow DNS to localhost only (in case local DNS resolver is needed)
netsh advfirewall firewall add rule name="IR_DNS_LOCAL" dir=out action=allow protocol=UDP remoteport=53 remoteip=127.0.0.1

Write-Host ""
Write-Host "[+] HOST ISOLATED SUCCESSFULLY" -ForegroundColor Green
Write-Host "    All traffic blocked except from analyst: $AnalystIP" -ForegroundColor Green
Write-Host "    To restore: .\isolate_host.ps1 -AnalystIP $AnalystIP -Undo" -ForegroundColor Yellow
Write-Host "    Or manually: netsh advfirewall import '$BackupPath'" -ForegroundColor Yellow

# Log the action
$logLine = "$(Get-Date -Format 'o') | ISOLATED | Host=$env:COMPUTERNAME | AnalystIP=$AnalystIP | Backup=$BackupPath"
Add-Content -Path "$PSScriptRoot\isolation.log" -Value $logLine

'@
Write-Script (Join-Path $Root '01_Triage\windows\isolate_host.ps1') $ihScript 'isolate_host.ps1'

# -- Windows: hash_files.ps1 --
$hfScript = @'
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    IR Jumpkit - Hash Files for Chain of Custody
.DESCRIPTION
    Hashes a file or all files in a directory (recursively) using SHA-256 and MD5.
    Outputs a CSV manifest suitable for chain of custody documentation.
.USAGE
    .\hash_files.ps1 -Target "D:\07_Evidence\2024-01-01_Incident"
    .\hash_files.ps1 -Target "C:\suspicious_binary.exe"
    .\hash_files.ps1 -Target "D:\07_Evidence" -Algorithm SHA256   (default)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Target,
    [ValidateSet("SHA256","SHA512","MD5","SHA1")]
    [string]$Algorithm = "SHA256",
    [string]$OutputCSV = ""
)

if (-not (Test-Path $Target)) {
    Write-Host "[-] Target not found: $Target" -ForegroundColor Red
    exit 1
}

$timestamp   = Get-Date -Format "yyyy-MM-dd_HHmmss"
$Hostname    = $env:COMPUTERNAME
if ($OutputCSV -eq "") {
    $OutputCSV = "$PSScriptRoot\hashes_${timestamp}.csv"
}

# Collect files
if ((Get-Item $Target).PSIsContainer) {
    $Files = Get-ChildItem -Path $Target -Recurse -File
} else {
    $Files = Get-Item $Target
}

Write-Host "[*] Hashing $($Files.Count) file(s) with $Algorithm ..." -ForegroundColor Cyan

# Write CSV header
"FilePath,FileName,SizeBytes,$Algorithm,MD5,CollectedAt,Hostname" | Out-File $OutputCSV -Encoding UTF8

$i = 0
foreach ($f in $Files) {
    $i++
    Write-Progress -Activity "Hashing files" -Status "$i / $($Files.Count)" -PercentComplete (($i / $Files.Count) * 100)
    try {
        $primary = (Get-FileHash $f.FullName -Algorithm $Algorithm).Hash
        $md5     = (Get-FileHash $f.FullName -Algorithm MD5).Hash
        "$($f.FullName),$($f.Name),$($f.Length),$primary,$md5,$(Get-Date -Format 'o'),$Hostname" |
            Add-Content $OutputCSV -Encoding UTF8
    } catch {
        "$($f.FullName),$($f.Name),$($f.Length),ERROR,ERROR,$(Get-Date -Format 'o'),$Hostname" |
            Add-Content $OutputCSV -Encoding UTF8
    }
}

Write-Progress -Completed -Activity "Done"
Write-Host "[+] Hashing complete." -ForegroundColor Green
Write-Host "    Files hashed : $($Files.Count)"
Write-Host "    Manifest     : $OutputCSV"

# Also print to screen for quick verification
Write-Host "`n--- Hash Manifest Preview ---" -ForegroundColor Cyan
Import-Csv $OutputCSV | Format-Table FileName, $Algorithm, SizeBytes -AutoSize

'@
Write-Script (Join-Path $Root '01_Triage\windows\hash_files.ps1') $hfScript 'hash_files.ps1'

# -- Linux: collect_artifacts.sh --
$lca = @'
#!/usr/bin/env bash
# =============================================================================
# IR Jumpkit - Linux Triage Artifact Collector
# =============================================================================
# USAGE : sudo bash collect_artifacts.sh [output_dir]
# OUTPUT: Timestamped folder on USB (or current dir if not specified)
# NOTE  : Run from the USB. Do not write output to the suspect's disk.
# =============================================================================

set -euo pipefail

# --- Setup --------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
HOSTNAME_VAL="$(hostname)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/../../07_Evidence/${TIMESTAMP}_linux_triage}"

if [[ $EUID -ne 0 ]]; then
    echo "[-] This script must be run as root. Use: sudo bash $0"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"/{volatile/{processes,network,users,memory},nonvolatile/{logs,cron,persistence,filesystem},hashes}

LOG="$OUTPUT_DIR/collection.log"

log() {
    local level="${2:-INFO}"
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$level] $1" | tee -a "$LOG"
}

save() {
    # save <output_file> <command...>
    local outfile="$1"; shift
    if "$@" > "$outfile" 2>>"$LOG"; then
        log "Saved: $outfile"
    else
        log "PARTIAL/FAILED: $outfile" "WARN"
    fi
}

log "=== IR Jumpkit Linux Triage === Host: $HOSTNAME_VAL ==="
log "Output directory: $OUTPUT_DIR"
log "Start time: $(date -u '+%Y-%m-%dT%H:%M:%SZ') UTC"

# --- SYSTEM INFORMATION ------------------------------------------------------
log "--- System Information ---"
{
    echo "=== hostname ===";          hostname -f
    echo "=== uname ===";             uname -a
    echo "=== uptime ===";            uptime
    echo "=== os-release ===";        cat /etc/os-release 2>/dev/null || true
    echo "=== system time ===";       date
    echo "=== utc time ===";          date -u
    echo "=== timezone ===";          timedatectl 2>/dev/null || cat /etc/timezone 2>/dev/null || true
    echo "=== ntp status ===";        timedatectl show 2>/dev/null | grep NTP || true
    echo "=== hardware ===";          dmidecode -t system 2>/dev/null || true
    echo "=== cpu ===";               lscpu 2>/dev/null || cat /proc/cpuinfo
    echo "=== memory ===";            free -h
    echo "=== disk ===";              df -h
    echo "=== block devices ===";     lsblk -a
    echo "=== mount points ===";      mount | column -t
} > "$OUTPUT_DIR/system_info.txt"
log "System info collected"

# --- VOLATILE - PROCESSES ----------------------------------------------------
log "--- Volatile: Processes ---"
save "$OUTPUT_DIR/volatile/processes/ps_aux.txt"         ps aux
save "$OUTPUT_DIR/volatile/processes/ps_tree.txt"        ps auxf
save "$OUTPUT_DIR/volatile/processes/process_fds.txt"    bash -c 'ls -la /proc/*/fd 2>/dev/null | head -500'
save "$OUTPUT_DIR/volatile/processes/lsof_all.txt"       lsof -n 2>/dev/null || true
save "$OUTPUT_DIR/volatile/processes/cmdlines.txt"       bash -c 'for p in /proc/[0-9]*/cmdline; do pid="${p%/cmdline}"; pid="${pid#/proc/}"; printf "PID %s: " "$pid"; tr "\0" " " < "$p" 2>/dev/null; echo; done'
save "$OUTPUT_DIR/volatile/processes/maps_suspicious.txt" bash -c 'for p in /proc/[0-9]*/maps; do pid="${p%/maps}"; pid="${pid#/proc/}"; if grep -q "(deleted)\|memfd" "$p" 2>/dev/null; then echo "=== PID $pid ==="; cat "$p"; fi; done'
save "$OUTPUT_DIR/volatile/processes/deleted_exes.txt"   bash -c 'ls -la /proc/*/exe 2>/dev/null | grep "(deleted)" || true'

# --- VOLATILE - NETWORK ------------------------------------------------------
log "--- Volatile: Network ---"
save "$OUTPUT_DIR/volatile/network/ss_all.txt"           ss -tulpan
save "$OUTPUT_DIR/volatile/network/netstat_all.txt"      bash -c 'netstat -tulpan 2>/dev/null || ss -tulpan'
save "$OUTPUT_DIR/volatile/network/netstat_established.txt" bash -c 'ss -tnp state established 2>/dev/null || netstat -tnp 2>/dev/null || true'
save "$OUTPUT_DIR/volatile/network/arp_table.txt"        arp -n
save "$OUTPUT_DIR/volatile/network/routing_table.txt"    route -n
save "$OUTPUT_DIR/volatile/network/ip_addr.txt"          ip addr show
save "$OUTPUT_DIR/volatile/network/ip_route.txt"         ip route show table all
save "$OUTPUT_DIR/volatile/network/resolv_conf.txt"      cat /etc/resolv.conf
save "$OUTPUT_DIR/volatile/network/hosts_file.txt"       cat /etc/hosts
save "$OUTPUT_DIR/volatile/network/iptables.txt"         bash -c 'iptables -L -n -v 2>/dev/null; ip6tables -L -n -v 2>/dev/null; true'
save "$OUTPUT_DIR/volatile/network/nft_rules.txt"        bash -c 'nft list ruleset 2>/dev/null || true'
save "$OUTPUT_DIR/volatile/network/interfaces.txt"       ip link show

# --- VOLATILE - USERS & SESSIONS ---------------------------------------------
log "--- Volatile: Users & Sessions ---"
save "$OUTPUT_DIR/volatile/users/who.txt"                who -a
save "$OUTPUT_DIR/volatile/users/w.txt"                  w
save "$OUTPUT_DIR/volatile/users/last.txt"               last -F -n 100
save "$OUTPUT_DIR/volatile/users/lastb.txt"              bash -c 'lastb -F -n 100 2>/dev/null || true'
save "$OUTPUT_DIR/volatile/users/passwd.txt"             cat /etc/passwd
save "$OUTPUT_DIR/volatile/users/shadow_exists.txt"      bash -c 'ls -la /etc/shadow 2>/dev/null || echo "No shadow file found"'
save "$OUTPUT_DIR/volatile/users/groups.txt"             cat /etc/group
save "$OUTPUT_DIR/volatile/users/sudoers.txt"            bash -c 'cat /etc/sudoers 2>/dev/null; ls /etc/sudoers.d/ 2>/dev/null || true'
save "$OUTPUT_DIR/volatile/users/ssh_authorized_keys.txt" bash -c 'for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do [ -f "$f" ] && echo "=== $f ===" && cat "$f"; done 2>/dev/null || true'
save "$OUTPUT_DIR/volatile/users/bash_history_root.txt"  bash -c 'cat /root/.bash_history 2>/dev/null || true'
save "$OUTPUT_DIR/volatile/users/bash_history_users.txt" bash -c 'for f in /home/*/.bash_history; do [ -f "$f" ] && echo "=== $f ===" && cat "$f"; done 2>/dev/null || true'

# --- VOLATILE - MEMORY INDICATORS --------------------------------------------
log "--- Volatile: Memory Indicators ---"
save "$OUTPUT_DIR/volatile/memory/meminfo.txt"           cat /proc/meminfo
save "$OUTPUT_DIR/volatile/memory/shmem.txt"             bash -c 'ls -la /proc/*/maps 2>/dev/null | grep shm | head -100 || true'
save "$OUTPUT_DIR/volatile/memory/anonymous_maps.txt"    bash -c 'for p in /proc/[0-9]*/maps; do pid="${p%/maps}"; pid="${pid#/proc/}"; name=$(cat "${p%maps}comm" 2>/dev/null); if grep -q "^[0-9].*rwxp" "$p" 2>/dev/null; then echo "=== PID $pid ($name) has RWX anonymous mapping ==="; grep "^[0-9].*rwxp" "$p"; fi; done 2>/dev/null || true'

# --- NON-VOLATILE - LOGS -----------------------------------------------------
log "--- Non-Volatile: System Logs ---"
LOG_PATHS=(
    /var/log/auth.log
    /var/log/secure
    /var/log/syslog
    /var/log/messages
    /var/log/kern.log
    /var/log/dmesg
    /var/log/faillog
    /var/log/wtmp
    /var/log/btmp
    /var/log/lastlog
    /var/log/audit/audit.log
)
for lp in "${LOG_PATHS[@]}"; do
    [ -f "$lp" ] || continue
    fname="${lp//\//_}"
    cp "$lp" "$OUTPUT_DIR/nonvolatile/logs/${fname#_}" 2>/dev/null || true
    log "Copied: $lp"
done

# Collect journalctl if systemd
if command -v journalctl &>/dev/null; then
    journalctl --no-pager -n 5000 > "$OUTPUT_DIR/nonvolatile/logs/journalctl_recent.txt" 2>/dev/null || true
    journalctl --no-pager -p err > "$OUTPUT_DIR/nonvolatile/logs/journalctl_errors.txt" 2>/dev/null || true
    log "Collected journalctl logs"
fi

# --- NON-VOLATILE - PERSISTENCE ----------------------------------------------
log "--- Non-Volatile: Persistence ---"
save "$OUTPUT_DIR/nonvolatile/persistence/crontab_root.txt"    bash -c 'crontab -l 2>/dev/null || echo "No root crontab"'
save "$OUTPUT_DIR/nonvolatile/persistence/crontab_users.txt"   bash -c 'for u in $(cut -f1 -d: /etc/passwd); do crontab -u "$u" -l 2>/dev/null && echo "--- user: $u ---" || true; done'
save "$OUTPUT_DIR/nonvolatile/persistence/cron_dirs.txt"       bash -c 'ls -la /etc/cron* /var/spool/cron* 2>/dev/null || true'

# Copy cron files
for d in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly /var/spool/cron; do
    [ -d "$d" ] && cp -r "$d" "$OUTPUT_DIR/nonvolatile/cron/" 2>/dev/null || true
done

save "$OUTPUT_DIR/nonvolatile/persistence/systemd_units.txt"   bash -c 'systemctl list-units --all --no-pager 2>/dev/null || true'
save "$OUTPUT_DIR/nonvolatile/persistence/systemd_enabled.txt" bash -c 'systemctl list-unit-files --state=enabled --no-pager 2>/dev/null || true'
save "$OUTPUT_DIR/nonvolatile/persistence/rc_local.txt"        bash -c 'cat /etc/rc.local 2>/dev/null || true'
save "$OUTPUT_DIR/nonvolatile/persistence/init_d.txt"          bash -c 'ls -la /etc/init.d/ 2>/dev/null || true'
save "$OUTPUT_DIR/nonvolatile/persistence/ld_preload.txt"      bash -c 'echo "$LD_PRELOAD"; cat /etc/ld.so.preload 2>/dev/null || echo "No ld.so.preload"'
save "$OUTPUT_DIR/nonvolatile/persistence/bashrc_profiles.txt" bash -c 'for f in /etc/profile /etc/bash.bashrc /root/.bashrc /root/.profile; do echo "=== $f ==="; cat "$f" 2>/dev/null || true; done'
save "$OUTPUT_DIR/nonvolatile/persistence/ssh_config.txt"      bash -c 'cat /etc/ssh/sshd_config 2>/dev/null || true'
save "$OUTPUT_DIR/nonvolatile/persistence/pam_modules.txt"     bash -c 'ls -la /etc/pam.d/ 2>/dev/null; cat /etc/pam.conf 2>/dev/null || true'

# --- NON-VOLATILE - FILESYSTEM ANOMALIES -------------------------------------
log "--- Non-Volatile: Filesystem Anomalies ---"
save "$OUTPUT_DIR/nonvolatile/filesystem/suid_sgid_files.txt"  bash -c 'find / -perm /6000 -type f -ls 2>/dev/null | grep -v "Permission denied" || true'
save "$OUTPUT_DIR/nonvolatile/filesystem/world_writable.txt"   bash -c 'find /tmp /var/tmp /dev/shm -type f -ls 2>/dev/null | head -200 || true'
save "$OUTPUT_DIR/nonvolatile/filesystem/tmp_contents.txt"     bash -c 'ls -laRt /tmp /var/tmp /dev/shm 2>/dev/null || true'
save "$OUTPUT_DIR/nonvolatile/filesystem/recently_modified.txt" bash -c 'find / -mtime -3 -type f -not -path "/proc/*" -not -path "/sys/*" -not -path "/run/*" -ls 2>/dev/null | grep -v "Permission denied" | head -500 || true'
save "$OUTPUT_DIR/nonvolatile/filesystem/hidden_files_root.txt" bash -c 'find /root /home /tmp /var/tmp -name ".*" -ls 2>/dev/null || true'
save "$OUTPUT_DIR/nonvolatile/filesystem/installed_packages.txt" bash -c 'dpkg -l 2>/dev/null || rpm -qa 2>/dev/null || true'
save "$OUTPUT_DIR/nonvolatile/filesystem/kernel_modules.txt"   lsmod

# --- HASH MANIFEST -----------------------------------------------------------
log "--- Hashing Collected Files ---"
HASH_MANIFEST="$OUTPUT_DIR/hashes/manifest.sha256"
find "$OUTPUT_DIR" -type f -not -path "*/hashes/*" -print0 | \
    xargs -0 sha256sum 2>/dev/null > "$HASH_MANIFEST" || true
log "Hash manifest: $HASH_MANIFEST"

# --- SUMMARY -----------------------------------------------------------------
FILE_COUNT=$(find "$OUTPUT_DIR" -type f | wc -l)
SIZE=$(du -sh "$OUTPUT_DIR" | cut -f1)

log "=== COLLECTION COMPLETE ==="
log "Host         : $HOSTNAME_VAL"
log "Files saved  : $FILE_COUNT"
log "Total size   : $SIZE"
log "Output path  : $OUTPUT_DIR"
log "NEXT STEP    : Acquire memory dump with avml/LiME, then disk image with dcfldd"

echo ""
echo "==================================="
echo " Collection complete: $OUTPUT_DIR"
echo " Files: $FILE_COUNT | Size: $SIZE"
echo "==================================="

'@
Write-ShellScript (Join-Path $Root '01_Triage\linux\collect_artifacts.sh') $lca 'collect_artifacts.sh'

# -- Linux: isolate_host.sh --
$lih = @'
#!/usr/bin/env bash
# =============================================================================
# IR Jumpkit - Linux Host Isolation Script
# =============================================================================
# USAGE : sudo bash isolate_host.sh <analyst_ip> [--undo]
# EXAMPLE: sudo bash isolate_host.sh 10.0.0.50
#          sudo bash isolate_host.sh 10.0.0.50 --undo
# =============================================================================
# CAUTION: Run ONLY after memory acquisition is complete.
#          Ensure you have physical or out-of-band access before isolating.
# =============================================================================

set -euo pipefail

ANALYST_IP="${1:-}"
UNDO="${2:-}"
BACKUP_FILE="/tmp/iptables_backup_$(date +%Y%m%d_%H%M%S).rules"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPT_DIR/isolation.log"

if [[ $EUID -ne 0 ]]; then
    echo "[-] Must run as root: sudo bash $0 <analyst_ip>"
    exit 1
fi

if [[ -z "$ANALYST_IP" ]]; then
    echo "Usage: $0 <analyst_ip> [--undo]"
    echo "  Example: $0 10.0.0.50"
    exit 1
fi

# --- UNDO / RESTORE ----------------------------------------------------------
if [[ "$UNDO" == "--undo" ]]; then
    echo "[*] Restoring iptables rules..."
    LATEST=$(ls -t /tmp/iptables_backup_*.rules 2>/dev/null | head -1 || true)
    if [[ -n "$LATEST" ]]; then
        iptables-restore < "$LATEST"
        ip6tables -F; ip6tables -X; ip6tables -P INPUT ACCEPT; ip6tables -P OUTPUT ACCEPT; ip6tables -P FORWARD ACCEPT
        echo "[+] Rules restored from: $LATEST"
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') | RESTORED | from=$LATEST" >> "$LOG"
    else
        echo "[-] No backup found. Flushing all rules (open policy)."
        iptables -F; iptables -X
        iptables -P INPUT ACCEPT; iptables -P OUTPUT ACCEPT; iptables -P FORWARD ACCEPT
        ip6tables -F; ip6tables -X
        ip6tables -P INPUT ACCEPT; ip6tables -P OUTPUT ACCEPT; ip6tables -P FORWARD ACCEPT
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') | FLUSHED | no backup found" >> "$LOG"
    fi
    exit 0
fi

# --- CONFIRM -----------------------------------------------------------------
echo ""
echo "+==========================================+"
echo "|   IR JUMPKIT - LINUX HOST ISOLATION      |"
echo "+==========================================+"
echo "|  Host       : $(hostname)"
echo "|  Analyst IP : $ANALYST_IP"
echo "|  Backup     : $BACKUP_FILE"
echo "+==========================================+"
echo ""
read -r -p "Type 'ISOLATE' to proceed: " confirm
if [[ "$confirm" != "ISOLATE" ]]; then
    echo "Aborted."
    exit 0
fi

# --- BACKUP CURRENT RULES ----------------------------------------------------
echo "[*] Backing up current iptables rules to $BACKUP_FILE ..."
iptables-save > "$BACKUP_FILE"
echo "[+] Backup saved."

# --- APPLY ISOLATION RULES ---------------------------------------------------
echo "[*] Flushing existing rules..."
iptables -F
iptables -X
iptables -Z

echo "[*] Setting default DROP policies..."
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

echo "[*] Allowing loopback..."
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

echo "[*] Allowing established/related connections..."
iptables -A INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

echo "[*] Allowing analyst IP ($ANALYST_IP) bidirectionally..."
iptables -A INPUT  -s "$ANALYST_IP" -j ACCEPT
iptables -A OUTPUT -d "$ANALYST_IP" -j ACCEPT

# Optional: allow DNS to local resolver only
LOCAL_DNS="127.0.0.53"
iptables -A OUTPUT -d "$LOCAL_DNS" -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -d "$LOCAL_DNS" -p tcp --dport 53 -j ACCEPT

# Block everything else (explicit reject with logging)
iptables -A INPUT  -j LOG --log-prefix "IR_BLOCKED_IN: " --log-level 4
iptables -A OUTPUT -j LOG --log-prefix "IR_BLOCKED_OUT: " --log-level 4

# Also isolate IPv6
ip6tables -F; ip6tables -X
ip6tables -P INPUT DROP; ip6tables -P OUTPUT DROP; ip6tables -P FORWARD DROP
ip6tables -A INPUT -i lo -j ACCEPT; ip6tables -A OUTPUT -o lo -j ACCEPT

echo ""
echo "[+] HOST ISOLATED SUCCESSFULLY"
echo "    All traffic dropped except analyst: $ANALYST_IP"
echo "    To restore: sudo bash $0 $ANALYST_IP --undo"

echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') | ISOLATED | host=$(hostname) | analyst=$ANALYST_IP | backup=$BACKUP_FILE" >> "$LOG"

'@
Write-ShellScript (Join-Path $Root '01_Triage\linux\isolate_host.sh') $lih 'isolate_host.sh'

# -- Linux: hash_files.sh --
$lhf = @'
#!/usr/bin/env bash
# =============================================================================
# IR Jumpkit - Hash Files for Chain of Custody (Linux)
# =============================================================================
# USAGE : bash hash_files.sh <target_file_or_dir> [output.csv]
# =============================================================================

TARGET="${1:-}"
OUTPUT_CSV="${2:-hashes_$(date +%Y%m%d_%H%M%S).csv}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <file_or_directory> [output.csv]"
    exit 1
fi

if [[ ! -e "$TARGET" ]]; then
    echo "[-] Target not found: $TARGET"
    exit 1
fi

echo "FilePath,FileName,SizeBytes,SHA256,MD5,CollectedAt,Hostname" > "$OUTPUT_CSV"

hash_file() {
    local f="$1"
    local size; size=$(stat -c%s "$f" 2>/dev/null || echo 0)
    local sha256; sha256=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1 || echo "ERROR")
    local md5; md5=$(md5sum "$f" 2>/dev/null | cut -d' ' -f1 || echo "ERROR")
    local ts; ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local fname; fname=$(basename "$f")
    echo "\"$f\",\"$fname\",$size,$sha256,$md5,$ts,$(hostname)"
}

if [[ -d "$TARGET" ]]; then
    COUNT=0
    while IFS= read -r -d '' file; do
        hash_file "$file" >> "$OUTPUT_CSV"
        COUNT=$((COUNT+1))
        printf "\r[*] Hashed: %d files" "$COUNT"
    done < <(find "$TARGET" -type f -print0)
    echo ""
else
    hash_file "$TARGET" >> "$OUTPUT_CSV"
    COUNT=1
fi

echo "[+] Done. $COUNT file(s) hashed."
echo "[+] Manifest: $OUTPUT_CSV"
echo ""
echo "--- Preview ---"
column -t -s ',' "$OUTPUT_CSV" | head -20

'@
Write-ShellScript (Join-Path $Root '01_Triage\linux\hash_files.sh') $lhf 'hash_files.sh'


# Write README for scripts
@"
# IR Jumpkit -- Triage Scripts

## Windows (01_Triage\windows\) -- run as Administrator from USB

| Script                  | Purpose                                        | Run time   |
|-------------------------|------------------------------------------------|------------|
| triage_collect.ps1      | Fast volatile triage (RUN FIRST on live host)  | ~90 sec    |
| collect_artifacts.ps1   | Full non-volatile artefact collection          | ~5-10 min  |
| isolate_host.ps1        | Firewall isolation (run AFTER memory capture)  | Instant    |
| hash_files.ps1          | Hash files/dirs for chain of custody           | Varies     |

## Linux (01_Triage\linux\) -- run as root

| Script                  | Purpose                                        |
|-------------------------|------------------------------------------------|
| collect_artifacts.sh    | Full Linux triage collection                   |
| isolate_host.sh         | iptables isolation                             |
| hash_files.sh           | Hash files for chain of custody                |

## Usage examples

  # Windows -- quick triage
  powershell -ExecutionPolicy Bypass -File .\triage_collect.ps1

  # Windows -- full collection
  powershell -ExecutionPolicy Bypass -File .\collect_artifacts.ps1 -OutputPath E:\07_Evidence\2024-01-01

  # Windows -- isolate (AFTER memory dump)
  powershell -ExecutionPolicy Bypass -File .\isolate_host.ps1 -AnalystIP 10.0.0.50

  # Linux -- triage
  sudo bash collect_artifacts.sh /mnt/usb/07_Evidence/hostname_triage

  # Linux -- isolate
  sudo bash isolate_host.sh 10.0.0.50
"@ | Out-File (Join-Path $Root "01_Triage\SCRIPTS_README.md") -Encoding ASCII

# ============================================================
#  STEP 5  REFERENCE DOCUMENTS
# ============================================================
Write-Step "STEP 5 -- Writing Reference Documents"

# Imaging tools note (tools we cannot auto-download due to licensing/installer-only distribution)
@"
# Disk Imaging Tools -- NOT included in this kit
# ================================================
# These tools cannot be automatically downloaded and bundled due to licensing
# restrictions, installer-only distribution, or platform requirements.
# Download them manually and add to this folder before deploying the USB.

## Windows

### FTK Imager (Exterro) -- RECOMMENDED
  - Free to use, industry standard for forensic disk imaging
  - Download from: https://www.exterro.com/ftk-product-family/ftk-imager
  - Usage:
      FTK Imager GUI -> File -> Create Disk Image -> Physical Drive
      Or CLI: ftkimager.exe \\.\PhysicalDrive0 E:\07_Evidence\disk.E01 --e01 --compress 6

### dcfldd (Windows port)
  - Forensic dd with on-the-fly hashing; available as a Windows binary
  - Search: dcfldd windows binary (SourceForge / unofficial ports)
  - Usage:
      dcfldd if=\\.\PhysicalDrive0 of=E:\07_Evidence\disk.dd hash=sha256 hashlog=disk.sha256

## Linux

### dcfldd
  sudo apt install dcfldd   # Debian/Ubuntu
  sudo yum install dcfldd   # RHEL/CentOS

  sudo dcfldd if=/dev/sda of=/mnt/usb/disk.dd hash=sha256 hashlog=/mnt/usb/disk.sha256

### dd (built-in)
  sudo dd if=/dev/sda of=/mnt/usb/disk.dd bs=4M status=progress conv=noerror,sync
  sha256sum /mnt/usb/disk.dd | tee /mnt/usb/disk.sha256

### ddrescue (best for failing drives)
  sudo apt install gddrescue
  sudo ddrescue -d -r3 /dev/sda /mnt/usb/disk.dd /mnt/usb/disk.log

### Guymager (GUI -- available in Kali/SIFT)
  sudo guymager   # GUI imager with E01/AFF support

## macOS

### FTK Imager for macOS
  Download from Exterro (same link as above -- select macOS build)

### Target Disk Mode (Apple Silicon / Intel)
  Hold T on boot -> connect via Thunderbolt -> image with FTK Imager on analyst Mac

### MacQuisition (commercial, Apple Silicon memory + disk)
  Commercial tool from BlackBag Technologies / OpenText

"@ | Out-File (Join-Path $Root "02_Forensics\imaging\IMAGING_TOOLS.md") -Encoding ASCII
Add-Result "Reference" "Imaging Tools Note" "OK" "Manual download instructions written" (Join-Path $Root "02_Forensics\imaging\IMAGING_TOOLS.md")

# Quick-Start README
@"
# IR Jumpkit -- Quick Start

## Order of Operations (LIVE HOST)

| Step | Action                              | Windows                                     | Linux                             | macOS                          |
|------|-------------------------------------|---------------------------------------------|-----------------------------------|--------------------------------|
| 1    | CAPTURE MEMORY FIRST                | 02_Forensics\memory\winpmem.exe mem.raw     | sudo ./avml /mnt/usb/mem.lime     | sudo ./osxpmem mem.aff4        |
| 2    | Run quick triage                    | 01_Triage\windows\triage_collect.ps1        | 01_Triage\linux\collect_artifacts.sh  | lsof -n > lsof.txt; ps aux > ps.txt |
| 3    | Capture live traffic                | 03_Network\Wireshark\tshark.exe -i 1 -w c.pcap | sudo tcpdump -i any -w /mnt/usb/cap.pcap | sudo tcpdump -i en0 -w /Volumes/usb/cap.pcap |
| 4    | Isolate the host                    | 01_Triage\windows\isolate_host.ps1 -AnalystIP X.X.X.X | sudo bash isolate_host.sh X.X.X.X | sudo pfctl -e -f /etc/pf.conf (manual) |
| 5    | Full artefact collection            | 01_Triage\windows\collect_artifacts.ps1     | (already done in step 2)         | log collect --output ./logs    |
| 6    | Disk image                          | 02_Forensics\imaging\IMAGING_TOOLS.md       | sudo dcfldd if=/dev/sda of=/mnt/usb/disk.dd | Use Target Disk Mode + FTK Imager |
| 7    | Hash all evidence                   | 01_Triage\windows\hash_files.ps1            | 01_Triage\linux\hash_files.sh    | shasum -a 256 *                |

## Memory Acquisition -- Platform Notes

### Windows
  winpmem.exe D:\07_Evidence\HOSTNAME_mem.raw
  certutil -hashfile D:\07_Evidence\HOSTNAME_mem.raw SHA256

### Linux
  sudo ./avml /mnt/usb/mem.lime              # Best option -- static binary, no compile
  sha256sum /mnt/usb/mem.lime | tee /mnt/usb/mem.lime.sha256

### macOS (Intel)
  sudo ./osxpmem mem.aff4                    # Requires SIP disabled or kext approval
  # Modern Apple Silicon: use MacQuisition (commercial) or collect unified logs instead:
  log collect --output /Volumes/USB/unified_logs.logarchive

## Key Contacts
  Incident Coordinator : _______________
  Legal / Counsel      : _______________
  CISO                 : _______________
  Law Enforcement      : _______________

## Tools by Category

| Category            | Tool                  | Location                              |
|---------------------|-----------------------|---------------------------------------|
| Memory (Windows)    | winpmem               | 02_Forensics\memory\winpmem.exe       |
| Memory (Linux)      | avml                  | 02_Forensics\memory\avml              |
| Memory (Linux KM)   | LiME                  | 02_Forensics\memory\LiME\             |
| Artefacts (Windows) | EZ Tools              | 02_Forensics\artefacts\EZTools\       |
| Live Collection     | Velociraptor          | 02_Forensics\artefacts\Velociraptor\  |
| Process Monitor     | ProcMon               | 04_Malware\ProcMon\                   |
| Persistence Scan    | Autoruns              | 04_Malware\Autoruns\                  |
| YARA Scanning       | yara64.exe + rules    | 04_Malware\yara\                      |
| IOC Scanner         | Loki                  | 04_Malware\Loki\                      |
| Second-opinion AV   | HitmanPro (Sophos)    | 04_Malware\HitmanPro\                 |
| Rootkit Detection   | RootkitRevealer       | 04_Malware\RootkitRevealer\           |
| Malware Removal     | Malwarebytes          | 04_Malware\Malwarebytes\              |
| Adware / PUP        | AdwCleaner            | 04_Malware\AdwCleaner\                |
| Traffic Capture     | tshark.exe            | 03_Network\Wireshark\tshark.exe       |
| Traffic Capture     | tcpdump (Linux/macOS) | Built into OS                         |
| Log Analysis        | Chainsaw              | 05_Logs\Chainsaw\                     |
| Log Timeline        | Hayabusa              | 05_Logs\Hayabusa\                     |
| Decode/Transform    | CyberChef             | 06_Utils\CyberChef\CyberChef.html     |
| JSON processing     | jq                    | 06_Utils\jq\                          |
| SSH / SCP           | PuTTY / PSCP          | 06_Utils\putty\                       |
| Hashing             | HashMyFiles           | 06_Utils\HashMyFiles\                 |
"@ | Out-File (Join-Path $Root "00_START_HERE\README.md") -Encoding ASCII
Add-Result "Reference" "Quick-Start README" "OK" (Join-Path $Root "00_START_HERE\README.md")

@"
Case Number  : _______________
Incident     : _______________
Analyst      : _______________
Date (UTC)   : $(Get-Date -Format 'yyyy-MM-dd')

EVIDENCE LOG
============
#  | Description          | SHA-256 Hash | Acquired By | Date/Time UTC       | Location
---|----------------------|--------------|-------------|---------------------|----------
1  |                      |              |             |                     |
2  |                      |              |             |                     |
3  |                      |              |             |                     |

TRANSFER LOG
============
Date/Time | From | To | Purpose | Signature
----------|------|----|---------|----------
          |      |    |         |
"@ | Out-File (Join-Path $Root "00_START_HERE\CHAIN_OF_CUSTODY.md") -Encoding ASCII
Add-Result "Reference" "Chain of Custody template" "OK" (Join-Path $Root "00_START_HERE\CHAIN_OF_CUSTODY.md")

# BPF cheatsheet
@"
# BPF / tshark Filter Quick Reference

## tshark -- Capture on the Suspect Host
  tshark.exe -D                                         # list interfaces
  tshark.exe -i 1 -w capture.pcap                       # capture all traffic, interface 1
  tshark.exe -i 1 -w capture.pcap -a duration:300       # stop after 5 minutes
  tshark.exe -i 1 -f "not host 10.0.0.50" -w c.pcap    # exclude analyst IP

## tcpdump -- Linux / macOS (built-in)
  sudo tcpdump -i any -w /mnt/usb/capture.pcap
  sudo tcpdump -i eth0 -f "not host 10.0.0.50" -w c.pcap
  sudo tcpdump -i en0 -w /Volumes/USB/capture.pcap      # macOS Wi-Fi

## Useful BPF filters
  "dst port 4444 or dst port 1337 or dst port 8080"     # common C2 ports
  "port 53"                                              # DNS only
  "port 443 and not net 10.0.0.0/8"                     # external HTTPS

## tshark -- Post-capture analysis (on analyst machine)
  tshark -r c.pcap -T fields -e ip.dst -e dns.qry.name | sort | uniq -c | sort -rn
  tshark -r c.pcap -Y "http.request" -T fields -e http.host -e http.request.uri
  # All unique external IPs:
  tshark -r c.pcap -T fields -e ip.dst | grep -Ev "^(10\.|192\.168\.|172\.1[6-9]\.|127\.)" | sort | uniq -c | sort -rn
"@ | Out-File (Join-Path $Root "03_Network\pcap_filters\bpf_cheatsheet.md") -Encoding ASCII
Add-Result "Reference" "BPF Cheatsheet" "OK" (Join-Path $Root "03_Network\pcap_filters\bpf_cheatsheet.md")

# IOC template
@"
IndicatorType,Value,Confidence,FirstSeen,Source,Notes
ip,,,,,
domain,,,,,
hash-sha256,,,,,
hash-md5,,,,,
filename,,,,,
registry-key,,,,,
url,,,,,
"@ | Out-File (Join-Path $Root "09_Reference\IOC_template.csv") -Encoding ASCII
Add-Result "Reference" "IOC Template CSV" "OK" (Join-Path $Root "09_Reference\IOC_template.csv")

# ============================================================
#  STEP 6  BUILD REPORT
# ============================================================
Write-Step "STEP 6 -- Generating Build Report"

$BuildEnd   = Get-Date
$Duration   = $BuildEnd - $BuildStart
$cntOK      = ($Script:Results | Where-Object Status -eq "OK").Count
$cntWarn    = ($Script:Results | Where-Object Status -eq "WARN").Count
$cntFail    = ($Script:Results | Where-Object Status -eq "FAIL").Count
$cntSkip    = ($Script:Results | Where-Object Status -eq "SKIP").Count
$cntCompile = ($Script:Results | Where-Object Status -eq "COMPILE").Count

# -- Plain text report --------------------------------------------------------
$txtOut = Join-Path $Root "00_START_HERE\BUILD_REPORT.txt"
$sb     = [System.Text.StringBuilder]::new()

$null = $sb.AppendLine("IR JUMPKIT BUILD REPORT")
$null = $sb.AppendLine("=" * 60)
$null = $sb.AppendLine("Builder       : v$BuilderVersion")
$null = $sb.AppendLine("Built by      : $env:USERNAME on $env:COMPUTERNAME")
$null = $sb.AppendLine("Started       : $($BuildStart.ToString('yyyy-MM-dd HH:mm:ss'))")
$null = $sb.AppendLine("Finished      : $($BuildEnd.ToString('yyyy-MM-dd HH:mm:ss'))")
$null = $sb.AppendLine("Duration      : $($Duration.ToString('hh\:mm\:ss'))")
$null = $sb.AppendLine("Target        : $Root")
$null = $sb.AppendLine("")
$null = $sb.AppendLine("SUMMARY")
$null = $sb.AppendLine("-" * 40)
$null = $sb.AppendLine("  OK          : $cntOK")
$null = $sb.AppendLine("  Warnings    : $cntWarn")
$null = $sb.AppendLine("  Failed      : $cntFail")
$null = $sb.AppendLine("  Skipped     : $cntSkip")
$null = $sb.AppendLine("  Need compile: $cntCompile (compile LiME on target Linux)")
$null = $sb.AppendLine("  Total steps : $($Script:Results.Count)")
$null = $sb.AppendLine("")

$Script:Results | Group-Object Category | ForEach-Object {
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("[$($_.Name.ToUpper())]")
    $null = $sb.AppendLine("-" * 60)
    $_.Group | ForEach-Object {
        $icon = switch ($_.Status) {"OK"{"[OK]"} "WARN"{"[!!]"} "FAIL"{"[XX]"} "SKIP"{"[--]"} "COMPILE"{"[cc]"} default{"[..]"}}
        $null = $sb.AppendLine(("  {0,-9} {1}  {2}" -f $_.Status, $icon, $_.Name))
        if ($_.Detail)  { $null = $sb.AppendLine("             $($_.Detail)") }
        if ($_.Path)    { $null = $sb.AppendLine("             Path: $($_.Path)") }
        if ($_.Hash)    { $null = $sb.AppendLine("             SHA256: $($_.Hash)") }
        if ($_.Version) { $null = $sb.AppendLine("             Version: $($_.Version)") }
    }
}

if ($Script:Warnings.Count -gt 0) {
    $null = $sb.AppendLine("")
    $null = $sb.AppendLine("[WARNINGS]")
    $null = $sb.AppendLine("-" * 60)
    $Script:Warnings | ForEach-Object { $null = $sb.AppendLine("  [!!] $_") }
}

$null = $sb.AppendLine("")
$null = $sb.AppendLine("[DIRECTORY TREE]")
$null = $sb.AppendLine("-" * 60)
Get-ChildItem $Root -Recurse | ForEach-Object {
    $depth  = ($_.FullName -replace [regex]::Escape($Root), "").TrimStart('\').Split('\').Count - 1
    $indent = "  " * $depth
    $null   = $sb.AppendLine("$indent$($_.Name)")
}

[IO.File]::WriteAllText($txtOut, $sb.ToString(), [Text.Encoding]::ASCII)
Add-Result "Report" "Text Report" "OK" $txtOut

# -- HTML report --------------------------------------------------------------
$htmlOut  = Join-Path $Root "00_START_HERE\BUILD_REPORT.html"
$rowsHtml = ""
foreach ($r in $Script:Results) {
    $bg  = switch ($r.Status) {"OK"{"#f0fff0"} "WARN"{"#fffbe6"} "FAIL"{"#fff0f0"} "SKIP"{"#f5f5f5"} "COMPILE"{"#f5eeff"} default{"#fff"}}
    $fg  = switch ($r.Status) {"OK"{"#1a7a1a"} "WARN"{"#8a6200"} "FAIL"{"#8a1a1a"} "SKIP"{"#555"} "COMPILE"{"#6a2a8a"} default{"#333"}}
    $ico = switch ($r.Status) {"OK"{"[OK]"} "WARN"{"[!!]"} "FAIL"{"[XX]"} "SKIP"{"[--]"} "COMPILE"{"[cc]"} default{"[..]"}}
    $rowsHtml += "<tr style='background:$bg'><td style='color:$fg;font-weight:600'>$ico $($r.Status)</td><td>$($r.Category)</td><td><strong>$($r.Name)</strong></td><td style='font-size:12px;color:#555'>$($r.Detail)</td><td style='font-size:11px;font-family:monospace;color:#888'>$($r.Version)</td><td style='font-size:10px;font-family:monospace;color:#aaa;word-break:break-all'>$($r.Hash)</td><td>$($r.Time)</td></tr>`n"
}

$failBox = if ($cntFail -gt 0) { "<div style='background:#fff0f0;border:1px solid #f08080;border-radius:8px;padding:12px 16px;margin-bottom:16px;font-size:13px'><strong>[!!] $cntFail tool(s) failed.</strong> Re-run with <code>-Force</code> for specific tools.</div>" } else { "" }
$warnItems = ($Script:Warnings | ForEach-Object { "<li>$_</li>" }) -join ""
$warnBox  = if ($Script:Warnings.Count -gt 0) { "<div style='background:#fffbe6;border:1px solid #f0c040;border-radius:8px;padding:12px 16px;margin-bottom:16px;font-size:13px'><strong>Warnings:</strong><ul style='margin:6px 0 0;padding-left:20px'>$warnItems</ul></div>" } else { "" }

$html = @"
<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><title>IR Jumpkit Build Report</title>
<style>
body{font-family:-apple-system,Segoe UI,sans-serif;background:#f8f8f8;margin:0;padding:24px;color:#222}
h1{color:#c0392b;margin:0 0 4px;font-size:26px}
h2{color:#333;font-size:16px;margin:24px 0 8px;border-bottom:1px solid #ddd;padding-bottom:6px}
.meta{font-size:13px;color:#666;margin-bottom:24px}
.summary{display:flex;gap:16px;margin-bottom:24px;flex-wrap:wrap}
.stat{padding:12px 20px;border-radius:8px;text-align:center;min-width:80px}
.stat .n{font-size:28px;font-weight:700}.stat .l{font-size:12px;font-weight:500;margin-top:2px}
.ok{background:#f0fff0;color:#1a7a1a}.warn{background:#fffbe6;color:#8a6200}
.fail{background:#fff0f0;color:#8a1a1a}.skip{background:#f5f5f5;color:#555}.comp{background:#f5eeff;color:#6a2a8a}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 4px rgba(0,0,0,.08);font-size:13px}
th{background:#2c2c2c;color:#fff;padding:10px 12px;text-align:left;font-size:12px;font-weight:500}
td{padding:8px 12px;border-bottom:1px solid #f0f0f0;vertical-align:top}
tr:hover td{filter:brightness(0.97)}
</style></head><body>
<h1>IR Jumpkit -- Build Report</h1>
<div class='meta'>Built by <strong>$env:USERNAME</strong> on <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; $($BuildStart.ToString('yyyy-MM-dd HH:mm:ss')) &nbsp;|&nbsp; Duration: $($Duration.ToString('hh\:mm\:ss')) &nbsp;|&nbsp; Target: <code>$Root</code> &nbsp;|&nbsp; Builder v$BuilderVersion</div>
<div class='summary'>
  <div class='stat ok'><div class='n'>$cntOK</div><div class='l'>OK</div></div>
  <div class='stat warn'><div class='n'>$cntWarn</div><div class='l'>WARN</div></div>
  <div class='stat fail'><div class='n'>$cntFail</div><div class='l'>FAIL</div></div>
  <div class='stat skip'><div class='n'>$cntSkip</div><div class='l'>SKIPPED</div></div>
  <div class='stat comp'><div class='n'>$cntCompile</div><div class='l'>COMPILE</div></div>
</div>
$failBox$warnBox
<h2>All Results</h2>
<table><thead><tr><th>Status</th><th>Category</th><th>Name</th><th>Detail</th><th>Version</th><th>SHA-256</th><th>Time</th></tr></thead>
<tbody>$rowsHtml</tbody></table>
<p style='font-size:11px;color:#aaa;margin-top:24px'>Generated by IR Jumpkit Builder v$BuilderVersion</p>
</body></html>
"@

[IO.File]::WriteAllText($htmlOut, $html, [Text.Encoding]::ASCII)
Add-Result "Report" "HTML Report" "OK" $htmlOut

# Cleanup temp
Remove-Item $TempDir -Recurse -Force -EA SilentlyContinue

# ============================================================
#  FINAL CONSOLE SUMMARY
# ============================================================
Write-Host ""
Write-Host "  +================================================================+" -ForegroundColor Cyan
Write-Host "  |                    BUILD COMPLETE                              |" -ForegroundColor Cyan
Write-Host "  +================================================================+" -ForegroundColor DarkCyan
Write-Host "  |  Target     : $Root" -ForegroundColor White
Write-Host "  |  Duration   : $($Duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host ("  |  OK         : {0}" -f $cntOK) -ForegroundColor Green
Write-Host ("  |  Warnings   : {0}" -f $cntWarn) -ForegroundColor Yellow
Write-Host ("  |  Failed     : {0}" -f $cntFail) -ForegroundColor $(if ($cntFail -gt 0) {"Red"} else {"White"})
Write-Host ("  |  Skipped    : {0}" -f $cntSkip) -ForegroundColor Gray
Write-Host ("  |  Compile    : {0} (LiME -- compile on target Linux)" -f $cntCompile) -ForegroundColor Magenta
Write-Host "  +================================================================+" -ForegroundColor DarkCyan
Write-Host "  |  Text report : $txtOut"    -ForegroundColor White
Write-Host "  |  HTML report : $htmlOut"   -ForegroundColor White
Write-Host "  +================================================================+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Open BUILD_REPORT.html in a browser for the full interactive report." -ForegroundColor Cyan
if ($cntFail -gt 0) {
    Write-Host "  Re-run failed tools with: .\Build-IRJumpkit.ps1 -TargetPath '$TargetPath' -Force" -ForegroundColor Yellow
}
Write-Host ""
