@echo off
setlocal EnableExtensions
title Antigravity and Git Visibility Manager
color 0B

rem ======================================================================
rem  YOUR INSTALL FOLDERS  (if a folder is wrong, auto-detect takes over)
rem ======================================================================
set "ANTI_GIT=C:\Program Files\Git"
set "ANTI_AG=C:\Users\WALTON\AppData\Local\Programs\Antigravity IDE"
rem ======================================================================

set "ANTI_SELF=%~f0"
set "ELEV=0"
if /i "%~1"=="elevated" (
    set "ELEV=1"
    shift
)
set "ANTI_CLI=%~1"

fltmc >nul 2>&1
if errorlevel 1 (set "ISADMIN=0") else (set "ISADMIN=1")
if "%ISADMIN%"=="0" if "%ELEV%"=="0" goto ELEVATE

:START
rem Command line use:  anti-hide.bat hide | show | diagnose
if not "%ANTI_CLI%"=="" (
    call :RUNPS "%ANTI_CLI%"
    if "%ELEV%"=="1" pause
    exit /b
)

:MENU
cls
echo ==========================================
echo    ANTIGRAVITY + GIT VISIBILITY MANAGER
echo ==========================================
if "%ISADMIN%"=="1" (echo  Administrator : yes) else (echo  Administrator : NO - some entries may fail)
echo.
echo  [1] SHOW both  - Start Menu + right-click menu + Open with
echo  [2] HIDE both  - Start Menu + right-click menu + Open with
echo  [3] Diagnose / status
echo  [4] Restart Explorer (refresh Start Menu and icons)
echo  [0] Exit
echo.
set "OPT="
set /p "OPT=Select option: "

if "%OPT%"=="1" goto DO_SHOW
if "%OPT%"=="2" goto DO_HIDE
if "%OPT%"=="3" goto DO_DIAG
if "%OPT%"=="4" goto DO_EXPLORER
if "%OPT%"=="0" exit /b
goto MENU

:DO_SHOW
call :RUNPS show
goto BACK

:DO_HIDE
call :RUNPS hide
goto BACK

:DO_DIAG
call :RUNPS diagnose
goto BACK

:DO_EXPLORER
choice /c YN /m "Explorer will close and reopen (open folder windows will close). Continue"
if errorlevel 2 goto MENU
call :RUNPS restart-explorer
goto BACK

:BACK
echo.
pause
goto MENU

:ELEVATE
echo Requesting administrator rights (needed for the Git right-click entries)...
powershell.exe -NoLogo -NoProfile -Command "$q=[char]34; $a='/c '+$q+$q+$env:ANTI_SELF+$q+' elevated '+$env:ANTI_CLI+$q; Start-Process -FilePath 'cmd.exe' -ArgumentList $a -Verb RunAs"
if errorlevel 1 (
    echo.
    echo Administrator rights were refused. Continuing without them - some entries may fail.
    echo.
    pause
    set "ELEV=1"
    goto START
)
exit /b

:RUNPS
set "ANTI_ACTION=%~1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:ANTI_SELF); $m='##PS'+'BEGIN##'; $c=$t.Substring($t.IndexOf($m)+$m.Length); & ([scriptblock]::Create($c)) $env:ANTI_ACTION"
exit /b

rem ---- everything below this line is PowerShell and is never run by cmd ----
##PSBEGIN##
param(
    [Parameter(Position = 0)]
    [string]$Action = 'diagnose'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Action)) { $Action = 'diagnose' }
$Action = $Action.Trim().ToLower()

# Folders given by the .bat (auto-detect is used when they do not exist)
$ManualGitRoot         = $env:ANTI_GIT
$ManualAntigravityRoot = $env:ANTI_AG

$StateDir  = Join-Path $env:LOCALAPPDATA 'AntiHide'
$BackupDir = Join-Path $StateDir 'shortcuts'
$Manifest  = Join-Path $StateDir 'state.json'
$StartMenus = @(
    (Join-Path $env:APPDATA     'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
)
$NamePattern = '(?i)antigravity|git_shell|git_gui|git-bash|git-gui|git bash|git gui'
$ClassesBases = @('Registry::HKEY_CURRENT_USER\Software\Classes', 'Registry::HKEY_LOCAL_MACHINE\Software\Classes')

# ------------------------------------------------------------------ helpers
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FixedRoots {
    @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.Name })
}

function Get-GitRoot {
    if ($ManualGitRoot -and (Test-Path -LiteralPath $ManualGitRoot)) { return $ManualGitRoot.TrimEnd('\') }

    foreach ($k in 'HKLM:\SOFTWARE\GitForWindows', 'HKCU:\SOFTWARE\GitForWindows') {
        try {
            $p = (Get-ItemProperty -LiteralPath $k -ErrorAction Stop).InstallPath
            if ($p -and (Test-Path -LiteralPath $p)) { return $p.TrimEnd('\') }
        } catch {}
    }

    $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $root = Split-Path (Split-Path $cmd.Source -Parent) -Parent
        if (Test-Path -LiteralPath (Join-Path $root 'git-bash.exe')) { return $root }
    }

    foreach ($drv in Get-FixedRoots) {
        foreach ($rel in 'Program Files\Git', 'Program Files (x86)\Git', 'Git') {
            $c = Join-Path $drv $rel
            if (Test-Path -LiteralPath (Join-Path $c 'git-bash.exe')) { return $c }
        }
    }
    return $null
}

function Get-AntigravityRoot {
    if ($ManualAntigravityRoot -and (Test-Path -LiteralPath $ManualAntigravityRoot)) { return $ManualAntigravityRoot.TrimEnd('\') }

    $keys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($k in $keys) {
        $hit = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -match '(?i)antigravity' } |
               Select-Object -First 1
        if ($hit) {
            $loc = $hit.InstallLocation
            if (-not $loc -and $hit.DisplayIcon) {
                $icon = ($hit.DisplayIcon -replace ',\s*-?\d+$', '') -replace '"', ''
                $loc = Split-Path $icon -Parent
            }
            if ($loc -and (Test-Path -LiteralPath $loc)) { return $loc.TrimEnd('\') }
        }
    }

    $bases = @((Join-Path $env:LOCALAPPDATA 'Programs'))
    foreach ($drv in Get-FixedRoots) {
        $bases += $drv
        foreach ($rel in 'Program Files', 'Program Files (x86)', 'Programs') { $bases += (Join-Path $drv $rel) }
    }
    foreach ($b in $bases) {
        if (-not (Test-Path -LiteralPath $b)) { continue }
        $d = Get-ChildItem -LiteralPath $b -Directory -Filter 'Antigravity*' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($d) { return $d.FullName }
    }
    return $null
}

$GitRoot = Get-GitRoot
$AgRoot  = Get-AntigravityRoot
$Roots   = @(@($GitRoot, $AgRoot) | Where-Object { $_ })

function Test-Match([string]$Text) {
    if ($Text -match $NamePattern) { return $true }
    foreach ($r in $Roots) {
        $prefix = $r.TrimEnd('\') + '\'
        if ($Text.IndexOf($prefix, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

# ------------------------------------------------------------------ Start Menu shortcuts
function Get-LnkTarget([string]$Path) {
    try { return (New-Object -ComObject WScript.Shell).CreateShortcut($Path).TargetPath } catch { return '' }
}

function Find-Shortcuts([string[]]$Targets, [string]$NameRx) {
    $found = @()
    foreach ($menu in $StartMenus) {
        if (-not (Test-Path -LiteralPath $menu)) { continue }
        $files = Get-ChildItem -LiteralPath $menu -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $t = Get-LnkTarget $f.FullName
            $hit = $false
            foreach ($r in $Targets) {
                if (-not $r) { continue }
                $prefix = $r.TrimEnd('\') + '\'
                if ($t -and $t.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $hit = $true }
            }
            if (-not $hit -and $NameRx -and ($f.BaseName -match $NameRx)) { $hit = $true }
            if ($hit) { $found += $f }
        }
    }
    return $found
}

function New-Lnk([string]$Path, [string]$Target, [string]$WorkDir) {
    New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
    $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($Path)
    $sc.TargetPath = $Target
    $sc.WorkingDirectory = $WorkDir
    $sc.IconLocation = "$Target,0"
    $sc.Save()
}

function Get-AgExe {
    if (-not $AgRoot) { return $null }
    $x = Get-ChildItem -LiteralPath $AgRoot -Filter '*.exe' -File -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -match '(?i)^antigravity' -and $_.Name -notmatch '(?i)unins' } | Select-Object -First 1
    if (-not $x) {
        $x = Get-ChildItem -LiteralPath $AgRoot -Filter '*.exe' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match '(?i)^antigravity' -and $_.Name -notmatch '(?i)unins' } | Select-Object -First 1
    }
    return $x
}

function Ensure-Shortcuts {
    $menu = $StartMenus[0]
    if ($AgRoot -and (@(Find-Shortcuts @($AgRoot) '(?i)antigravity').Count -eq 0)) {
        $exe = Get-AgExe
        if ($exe) {
            New-Lnk (Join-Path $menu 'Antigravity IDE.lnk') $exe.FullName $exe.DirectoryName
            Write-Host 'Created Start Menu shortcut: Antigravity IDE' -ForegroundColor Green
        } else {
            Write-Host 'Antigravity executable not found - shortcut not created.' -ForegroundColor Yellow
        }
    }
    if ($GitRoot -and (@(Find-Shortcuts @($GitRoot) '').Count -eq 0)) {
        $items = @(@('Git Bash', 'git-bash.exe'), @('Git GUI', 'cmd\git-gui.exe'), @('Git CMD', 'git-cmd.exe'))
        foreach ($it in $items) {
            $exe = Join-Path $GitRoot $it[1]
            if (Test-Path -LiteralPath $exe) {
                New-Lnk (Join-Path $menu ('Git\' + $it[0] + '.lnk')) $exe $GitRoot
                Write-Host ('Created Start Menu shortcut: ' + $it[0]) -ForegroundColor Green
            }
        }
    }
}

# ------------------------------------------------------------------ right-click entries / Open with
function Find-ContextKeys {
    $subs = '*\shell', 'AllFilesystemObjects\shell', 'Directory\shell', 'Directory\Background\shell',
            'Drive\shell', 'Folder\shell', 'DesktopBackground\shell', 'LibraryFolder\Background\shell'
    foreach ($b in $ClassesBases) {
        foreach ($s in $subs) {
            $root = "$b\$s"
            if (-not (Test-Path -LiteralPath $root)) { continue }
            foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                $text = $key.PSChildName + ' ' + [string]$key.GetValue('') + ' ' +
                        [string]$key.GetValue('MUIVerb') + ' ' + [string]$key.GetValue('Icon')
                $sk = $key.OpenSubKey('command')
                if ($sk) { $text += ' ' + [string]$sk.GetValue(''); $sk.Close() }
                if (Test-Match $text) { $key }
            }
        }
    }
}

function Find-AppKeys {
    foreach ($b in $ClassesBases) {
        $root = "$b\Applications"
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $text = $key.PSChildName
            $sk = $key.OpenSubKey('shell\open\command')
            if ($sk) { $text += ' ' + [string]$sk.GetValue(''); $sk.Close() }
            if (Test-Match $text) { $key }
        }
    }
}

function Add-Flag($Key, [string]$Name) {
    if ($Key.GetValueNames() -contains $Name) { return 'already' }
    New-ItemProperty -LiteralPath $Key.PSPath -Name $Name -Value '' -PropertyType String | Out-Null
    return 'added'
}

function Get-Visible {
    [pscustomobject]@{
        Links    = @(Find-Shortcuts $Roots '(?i)antigravity')
        Verbs    = @(Find-ContextKeys | Where-Object { $_.GetValueNames() -notcontains 'LegacyDisable' })
        OpenWith = @(Find-AppKeys     | Where-Object { $_.GetValueNames() -notcontains 'NoOpenWith' })
    }
}

# ------------------------------------------------------------------ saved state
function Load-State {
    $out = @()
    if (Test-Path -LiteralPath $Manifest) {
        try {
            $raw = Get-Content -LiteralPath $Manifest -Raw
            if ($raw -and $raw.Trim()) {
                $parsed = $raw | ConvertFrom-Json
                foreach ($p in $parsed) { $out += $p }
            }
        } catch {}
    }
    return $out
}

function Save-State($items) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    ConvertTo-Json -InputObject @($items) -Depth 4 | Set-Content -LiteralPath $Manifest -Encoding UTF8
}

function Show-Verify([bool]$ExpectHidden) {
    $v = Get-Visible
    Write-Host ''
    if ($ExpectHidden) {
        $left = $v.Links.Count + $v.Verbs.Count + $v.OpenWith.Count
        if ($left -eq 0) {
            Write-Host 'VERIFIED: nothing from Antigravity or Git is visible in Start Menu, right-click menu or Open with.' -ForegroundColor Green
        } else {
            Write-Host "STILL VISIBLE ($left item(s)) - run as administrator or check the warnings above:" -ForegroundColor Yellow
            $v.Links    | ForEach-Object { Write-Host ('  shortcut : ' + $_.FullName) }
            $v.Verbs    | ForEach-Object { Write-Host ('  right-click : ' + $_.Name) }
            $v.OpenWith | ForEach-Object { Write-Host ('  open with : ' + $_.Name) }
        }
        Write-Host 'Right-click menus update instantly. If the Start Menu still shows an app, use option 4 (Restart Explorer).' -ForegroundColor Cyan
    } else {
        Write-Host ('Visible now: ' + $v.Links.Count + ' shortcut(s), ' + $v.Verbs.Count + ' right-click entr(ies), ' + $v.OpenWith.Count + ' Open-with entr(ies).') -ForegroundColor Cyan
    }
}

# ------------------------------------------------------------------ actions
function Invoke-Diagnose {
    Write-Host ''
    Write-Host ("User: $env:USERNAME    Administrator: " + (Test-Admin)) -ForegroundColor Cyan

    Write-Host "`nGIT" -ForegroundColor Cyan
    if ($GitRoot) { Write-Host "  Folder     : $GitRoot" -ForegroundColor Green }
    else { Write-Host '  NOT FOUND' -ForegroundColor Red }

    Write-Host "`nANTIGRAVITY" -ForegroundColor Cyan
    if ($AgRoot) {
        Write-Host "  Folder     : $AgRoot" -ForegroundColor Green
        $exe = Get-AgExe
        if ($exe) { Write-Host "  Executable : $($exe.FullName)" -ForegroundColor Green }
    } else { Write-Host '  NOT FOUND' -ForegroundColor Red }

    Write-Host "`nSTART MENU SHORTCUTS (visible)" -ForegroundColor Cyan
    $links = @(Find-Shortcuts $Roots '(?i)antigravity')
    if ($links.Count -eq 0) { Write-Host '  (none)' }
    $links | ForEach-Object { Write-Host ('  ' + $_.FullName) }

    Write-Host "`nRIGHT-CLICK ENTRIES (Git Bash Here, Open with Antigravity, ...)" -ForegroundColor Cyan
    $keys = @(Find-ContextKeys)
    if ($keys.Count -eq 0) { Write-Host '  (none found)' }
    foreach ($k in $keys) {
        if ($k.GetValueNames() -contains 'LegacyDisable') { Write-Host ('  [HIDDEN]  ' + $k.Name) -ForegroundColor DarkGray }
        else { Write-Host ('  [VISIBLE] ' + $k.Name) -ForegroundColor Yellow }
    }

    Write-Host "`nOPEN WITH LIST" -ForegroundColor Cyan
    $apps = @(Find-AppKeys)
    if ($apps.Count -eq 0) { Write-Host '  (none found)' }
    foreach ($k in $apps) {
        if ($k.GetValueNames() -contains 'NoOpenWith') { Write-Host ('  [HIDDEN]  ' + $k.Name) -ForegroundColor DarkGray }
        else { Write-Host ('  [VISIBLE] ' + $k.Name) -ForegroundColor Yellow }
    }

    try {
        $pk = @(Get-AppxPackage -Name '*antigravity*' -ErrorAction Stop)
        if ($pk.Count -gt 0) {
            Write-Host "`nNOTE: a packaged (Windows 11 modern menu) Antigravity entry exists: $($pk[0].Name)" -ForegroundColor Yellow
            Write-Host '      Those cannot be hidden by registry flags. Tell me and I will add a fix.' -ForegroundColor Yellow
        }
    } catch {}

    $state = @(Load-State)
    Write-Host ("`nItems currently hidden by this tool: " + $state.Count) -ForegroundColor Cyan
}

function Invoke-Hide {
    if (-not (Test-Admin)) {
        Write-Host 'Not running as administrator: all-users shortcuts and Git right-click entries may fail.' -ForegroundColor Yellow
    }
    if ($Roots.Count -eq 0) {
        Write-Host 'Neither Git nor Antigravity was found. Run option 3 (Diagnose).' -ForegroundColor Red
        return
    }

    $state = @(Load-State)
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

    Write-Host "`n[1/3] Start Menu shortcuts" -ForegroundColor Cyan
    $links = @(Find-Shortcuts $Roots '(?i)antigravity')
    if ($links.Count -eq 0) { Write-Host '  Nothing visible to hide.' }
    foreach ($f in $links) {
        try {
            $dest = Join-Path $BackupDir ([guid]::NewGuid().ToString('N') + '_' + $f.Name)
            Move-Item -LiteralPath $f.FullName -Destination $dest -Force
            $state += [pscustomobject]@{ Type = 'lnk'; Original = $f.FullName; Backup = $dest }
            Write-Host "  Hid shortcut: $($f.FullName)" -ForegroundColor Green
        } catch {
            Write-Host "  Could not move $($f.FullName): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host "`n[2/3] Right-click menu entries (files, folders, background, drives)" -ForegroundColor Cyan
    $keys = @(Find-ContextKeys)
    if ($keys.Count -eq 0) { Write-Host '  No matching entries found.' }
    foreach ($key in $keys) {
        try {
            if ((Add-Flag $key 'LegacyDisable') -eq 'added') {
                $state += [pscustomobject]@{ Type = 'regval'; Key = $key.PSPath; Name = 'LegacyDisable' }
                Write-Host "  Hid: $($key.Name)" -ForegroundColor Green
            } else { Write-Host "  Already hidden: $($key.Name)" }
        } catch {
            Write-Host "  Could not hide $($key.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host "`n[3/3] Open with list" -ForegroundColor Cyan
    $apps = @(Find-AppKeys)
    if ($apps.Count -eq 0) { Write-Host '  No matching entries found.' }
    foreach ($key in $apps) {
        try {
            if ((Add-Flag $key 'NoOpenWith') -eq 'added') {
                $state += [pscustomobject]@{ Type = 'regval'; Key = $key.PSPath; Name = 'NoOpenWith' }
                Write-Host "  Hid: $($key.Name)" -ForegroundColor Green
            } else { Write-Host "  Already hidden: $($key.Name)" }
        } catch {
            Write-Host "  Could not hide $($key.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Save-State $state
    Show-Verify $true
}

function Invoke-Show {
    $state = @(Load-State)
    $remaining = @()

    Write-Host "`n[1/3] Restoring what Hide changed" -ForegroundColor Cyan
    if ($state.Count -eq 0) { Write-Host '  No saved items (will still sweep below).' }
    foreach ($i in $state) {
        try {
            if ($i.Type -eq 'lnk') {
                if (Test-Path -LiteralPath $i.Backup) {
                    New-Item -ItemType Directory -Path (Split-Path $i.Original -Parent) -Force | Out-Null
                    Move-Item -LiteralPath $i.Backup -Destination $i.Original -Force
                    Write-Host "  Restored shortcut: $($i.Original)" -ForegroundColor Green
                } else {
                    Write-Host "  Backup missing, skipped: $($i.Backup)" -ForegroundColor Yellow
                }
            }
            elseif ($i.Type -eq 'regval' -or $i.Type -eq 'reg') {
                $name = 'LegacyDisable'
                if ($i.Name) { $name = [string]$i.Name }
                if (Test-Path -LiteralPath $i.Key) {
                    $k = Get-Item -LiteralPath $i.Key
                    if ($k.GetValueNames() -contains $name) {
                        Remove-ItemProperty -LiteralPath $i.Key -Name $name
                        Write-Host "  Restored: $($k.Name)" -ForegroundColor Green
                    }
                }
            }
        } catch {
            Write-Host "  Could not restore: $($_.Exception.Message)" -ForegroundColor Yellow
            $remaining += $i
        }
    }

    Write-Host "`n[2/3] Sweeping any leftover hidden entries" -ForegroundColor Cyan
    foreach ($key in @(Find-ContextKeys)) {
        if ($key.GetValueNames() -contains 'LegacyDisable') {
            try { Remove-ItemProperty -LiteralPath $key.PSPath -Name 'LegacyDisable'; Write-Host "  Restored: $($key.Name)" -ForegroundColor Green }
            catch { Write-Host "  Could not restore $($key.Name): $($_.Exception.Message)" -ForegroundColor Yellow }
        }
    }
    foreach ($key in @(Find-AppKeys)) {
        if ($key.GetValueNames() -contains 'NoOpenWith') {
            try { Remove-ItemProperty -LiteralPath $key.PSPath -Name 'NoOpenWith'; Write-Host "  Restored: $($key.Name)" -ForegroundColor Green }
            catch { Write-Host "  Could not restore $($key.Name): $($_.Exception.Message)" -ForegroundColor Yellow }
        }
    }

    if ($remaining.Count -gt 0) { Save-State $remaining }
    elseif (Test-Path -LiteralPath $Manifest) { Remove-Item -LiteralPath $Manifest -Force }

    Write-Host "`n[3/3] Start Menu shortcuts" -ForegroundColor Cyan
    Ensure-Shortcuts

    Show-Verify $false
    Write-Host 'If the Start Menu does not update right away, use option 4 (Restart Explorer).' -ForegroundColor Cyan
}

function Invoke-RestartExplorer {
    Write-Host 'Restarting Explorer...' -ForegroundColor Cyan
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    for ($n = 0; $n -lt 10; $n++) {
        Start-Sleep -Milliseconds 500
        if (Get-Process -Name explorer -ErrorAction SilentlyContinue) { break }
    }
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Write-Host 'Done.' -ForegroundColor Green
}

switch ($Action) {
    'diagnose'         { Invoke-Diagnose }
    'hide'             { Invoke-Hide }
    'show'             { Invoke-Show }
    'restart-explorer' { Invoke-RestartExplorer }
    default            { Write-Host "Unknown action: $Action  (use hide, show, diagnose)" -ForegroundColor Red }
}