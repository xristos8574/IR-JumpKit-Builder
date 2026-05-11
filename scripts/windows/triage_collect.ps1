#Requires -RunAsAdministrator
<#
.SYNOPSIS
    IR Jumpkit - triage_collect.ps1
    Fast volatile triage: run this FIRST on a live Windows host.

.DESCRIPTION
    Lightweight, fast-running volatile data collector. Completes in ~90-120 seconds.
    Captures data that disappears on reboot:
      - Running processes (tree, cmdlines, hashes, unsigned modules)
      - Network connections mapped to owning processes
      - Active sessions, recent logons/failures
      - Services, drivers
      - Persistence (Run keys, tasks, WMI subscriptions, LSA packages, IFEO)
      - Loaded DLLs per process, unsigned module detection
      - Clipboard, PS history, Defender exclusions, env vars
      - Browser history (Chrome, Edge, Firefox, Brave, Opera, IE) — all user profiles

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
                 "04_services_drivers","05_persistence","06_dlls_modules","07_system","08_browser_history")) {
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

# --- 08  Browser History ------------------------------------------------------
Write-Log "[ 08 ] Browser history"

function Copy-BrowserDb {
    param([string]$SrcFile, [string]$DstDir, [string]$Label)
    if (-not (Test-Path $SrcFile)) { return $false }
    New-Item -ItemType Directory -Force -Path $DstDir | Out-Null
    $srcDir  = Split-Path $SrcFile -Parent
    $srcName = Split-Path $SrcFile -Leaf
    $dstFile = Join-Path $DstDir $srcName
    & robocopy $srcDir $DstDir $srcName /B /R:1 /W:0 /NP /NJH /NJS 2>$null | Out-Null
    if (-not (Test-Path $dstFile)) {
        Write-Log "    SKIP $Label : file locked or unreadable" "WARN"
        return $false
    }
    # SQLite stores strings as UTF-8 internally — readable via binary scan
    $raw  = [System.IO.File]::ReadAllText($dstFile, [System.Text.Encoding]::GetEncoding('iso-8859-1'))
    $urls = [regex]::Matches($raw, 'https?://[^\x00-\x1F\x7F\s"<>]{8,}') |
            ForEach-Object { $_.Value } | Sort-Object -Unique
    $quickTxt = Join-Path $DstDir "${Label}_urls_quick.txt"
    "# Quick URL scan from $Label (open raw SQLite with DB Browser for full history)" | Out-File $quickTxt -Encoding UTF8
    $urls | Add-Content $quickTxt
    Write-Log "    OK   $Label — $($urls.Count) unique URLs" "OK"
    return $true
}

$UserProfiles = Get-ChildItem "C:\Users" -Directory |
    Where-Object { $_.Name -notmatch "^(Public|Default|Default User|All Users)$" }

foreach ($prof in $UserProfiles) {
    $uname   = $prof.Name
    $local   = "$($prof.FullName)\AppData\Local"
    $roaming = "$($prof.FullName)\AppData\Roaming"
    $bhUser  = "$OutputPath\08_browser_history\$uname"
    $found   = 0

    Write-Log "  Profile: $uname"

    # Chrome
    Get-ChildItem "$local\Google\Chrome\User Data" -Directory 2>$null |
        Where-Object { $_.Name -match "^(Default|Profile)" } | ForEach-Object {
            if (Copy-BrowserDb "$($_.FullName)\History" "$bhUser\chrome\$($_.Name)" "chrome") { $found++ }
        }
    # Edge (Chromium)
    Get-ChildItem "$local\Microsoft\Edge\User Data" -Directory 2>$null |
        Where-Object { $_.Name -match "^(Default|Profile)" } | ForEach-Object {
            if (Copy-BrowserDb "$($_.FullName)\History" "$bhUser\edge\$($_.Name)" "edge") { $found++ }
        }
    # Brave
    Get-ChildItem "$local\BraveSoftware\Brave-Browser\User Data" -Directory 2>$null |
        Where-Object { $_.Name -match "^(Default|Profile)" } | ForEach-Object {
            if (Copy-BrowserDb "$($_.FullName)\History" "$bhUser\brave\$($_.Name)" "brave") { $found++ }
        }
    # Opera GX / Opera Stable
    if (Copy-BrowserDb "$roaming\Opera Software\Opera GX Stable\History" "$bhUser\opera_gx" "opera_gx") { $found++ }
    if (Copy-BrowserDb "$roaming\Opera Software\Opera Stable\History"    "$bhUser\opera"    "opera")    { $found++ }
    # Firefox
    Get-ChildItem "$roaming\Mozilla\Firefox\Profiles" -Directory 2>$null |
        Where-Object { $_.Name -match "\.default" } | ForEach-Object {
            if (Copy-BrowserDb "$($_.FullName)\places.sqlite" "$bhUser\firefox\$($_.Name)" "firefox") { $found++ }
        }

    # IE / Edge Legacy TypedURLs — resolve SID via ProfileList then read HKU hive
    $sidKey = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" 2>$null |
              Where-Object { (Get-ItemProperty $_.PSPath -EA SilentlyContinue).ProfileImagePath -eq $prof.FullName }
    if ($sidKey) {
        $sid    = $sidKey.PSChildName
        $ieKey  = "Registry::HKEY_USERS\$sid\Software\Microsoft\Internet Explorer\TypedURLs"
        $ieVals = Get-ItemProperty $ieKey 2>$null
        if ($ieVals) {
            New-Item -ItemType Directory -Force -Path $bhUser | Out-Null
            $ieOut = "$bhUser\ie_typed_urls.txt"
            "IE / Edge Legacy TypedURLs for $uname" | Out-File $ieOut -Encoding UTF8
            $ieVals.PSObject.Properties | Where-Object { $_.Name -match "^url" } |
                ForEach-Object { "$($_.Name): $($_.Value)" } | Add-Content $ieOut
            Write-Log "    OK   IE TypedURLs for $uname" "OK"
            $found++
        }
    }

    if ($found -eq 0) { Write-Log "  No browser history found for $uname" "WARN" }
}

# --- Hash manifest ------------------------------------------------------------
if (-not $SkipHash) {
    Write-Log "[ 09 ] Hashing output files"
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
