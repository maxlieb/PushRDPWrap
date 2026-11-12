#Requires -Version 5.1

# 1. Self-elevation logic
if (-Not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')) {
    Write-Host 'Script requires Administrator privileges. Re-launching...' -ForegroundColor Green
    Start-Sleep -Milliseconds 2000
    Start-Process PowerShell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $PSCommandPath) -Verb RunAs
    Exit
}

$OSArchitecture = (Get-CimInstance -ClassName Win32_OperatingSystem).OSArchitecture
$termsrvDllFile = "$env:SystemRoot\System32\termsrv.dll"
$termsrvDllCopy = "$env:SystemRoot\System32\termsrv.dll.copy"
$termsrvPatched = "$env:SystemRoot\System32\termsrv.dll.patched"

$patterns = @{
    Pattern = [regex]'39 81 3C 06 00 00 0F (?:[0-9A-F]{2} ){4}00'
    Win24H2 = [regex]'8B 81 38 06 00 00 39 81 3C 06 00 00 75'
    # Windows 11 25H2/26H2 (build >= 26200). Source: fabianosrc/TermsrvPatcher.
    Win26H2 = [regex]'44 8B 87 3C 06 00 00 44 8B 8F 38 06 00 00 45 3B C1 75 14'
}

# --- Helper Functions ---

function Get-OSInfo {
    $OSInfo = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [PSCustomObject]@{
        CurrentBuild = $OSInfo.CurrentBuild
        BuildRevision = $OSInfo.UBR
        FullOSBuild = "$($OSInfo.CurrentBuild).$($OSInfo.UBR)"
        DisplayVersion = $OSInfo.DisplayVersion
        InstallationType = $OSInfo.InstallationType
    }
}

function Get-OSVersion {
    [version]$OSVersion = [System.Environment]::OSVersion.Version
    $installationType = (Get-OSInfo).InstallationType
    if ($OSVersion.Major -eq 6 -and $OSVersion.Minor -eq 1) { return 'Windows 7' }
    elseif ($OSVersion.Major -eq 10 -and $OSVersion.Build -lt 22000 -and $installationType -eq 'Client') { return 'Windows 10' }
    elseif ($OSVersion.Major -eq 10 -and $OSVersion.Build -gt 22000) { return 'Windows 11' }
    elseif ($OSVersion.Major -eq 10 -and $OSVersion.Build -lt 22000 -and $installationType -eq 'Server') { return 'Windows Server 2016' }
    elseif ($OSVersion.Major -eq 10 -and $OSVersion.Build -eq 20348) { return 'Windows Server 2022' }
    elseif ($OSVersion.Major -eq 10 -and $OSVersion.Build -ge 26100 -and $installationType -eq 'Server') { return 'Windows Server 2025' }
    else { return 'Unsupported OS' }
}

function Stop-LockingProcesses {
    Write-Host "Searching for processes locking termsrv.dll..." -ForegroundColor Cyan
    # Check for any process that has the DLL loaded
    $LockingProcs = Get-Process | Where-Object { 
        try { $_.Modules.ModuleName -contains "termsrv.dll" } catch { $false }
    }
    
    if ($LockingProcs) {
        foreach ($Proc in $LockingProcs) {
            try {
                Write-Host "Force killing $($Proc.ProcessName) (PID: $($Proc.Id))..." -ForegroundColor Yellow
                Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
            } catch {
                Write-Warning "Could not kill $($Proc.ProcessName). This is normal for core system processes."
            }
        }
    }
}

function Stop-TermService {
    $Services = @('UmRdpService', 'TermService')
    foreach ($Service in $Services) {
        if ((Get-Service $Service -ErrorAction SilentlyContinue).Status -eq 'Running') {
            Write-Host "Stopping $Service..." -ForegroundColor Cyan
            Stop-Service -Name $Service -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 2
}

function Update-Dll {
    # Returns $true if the DLL is patched (just now, or already was), $false otherwise.
    # Service start / ACL restore are handled once by the caller so try-each can
    # attempt several patterns against the same in-memory bytes without churn.
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [regex]$InputPattern,
        [Parameter(Mandatory)] [string]$Replacement,
        [Parameter(Mandatory)] [string]$TermsrvDllAsText,
        [Parameter(Mandatory)] [string]$TermsrvDllAsFile,
        [Parameter(Mandatory)] [string]$TermsrvDllAsPatch
    )

    $alreadyPatched = $TermsrvDllAsText -match $Replacement
    if ($alreadyPatched) {
        Write-Host "The file already contains these patched bytes. Skipping." -ForegroundColor Green
        return $true
    }

    if ($TermsrvDllAsText -notmatch $InputPattern) {
        Write-Host "Pattern not found for this candidate." -ForegroundColor Yellow
        return $false
    }

    Write-Host "Pattern matched! Applying patch..." -ForegroundColor Green
    $dllAsTextReplaced = $TermsrvDllAsText -replace $InputPattern, $Replacement
    [byte[]]$dllAsBytesReplaced = -split $dllAsTextReplaced -replace '^', '0x'
    [System.IO.File]::WriteAllBytes($TermsrvDllAsPatch, $dllAsBytesReplaced)

    # KILL AND MOVE STRATEGY
    Stop-LockingProcesses

    $BackupPath = "$TermsrvDllAsFile.$(Get-Date -Format 'yyyyMMddHHmmss').bak"
    try {
        # Move the locked file (Windows allows moving/renaming locked files more easily than overwriting)
        Move-Item -Path $TermsrvDllAsFile -Destination $BackupPath -Force -ErrorAction Stop
        Copy-Item -Path $TermsrvDllAsPatch -Destination $TermsrvDllAsFile -Force -ErrorAction Stop
        Write-Host "DLL successfully swapped. Backup: $BackupPath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to swap DLL: $($_.Exception.Message)"
        return $false
    }

    return $true
}

function Invoke-PatchCandidates {
    # Try each (pattern, replacement) in order until one is applied or already present.
    param (
        [Parameter(Mandatory)] [array]$Candidates,
        [Parameter(Mandatory)] [hashtable]$CommonParams
    )
    foreach ($c in $Candidates) {
        if (Update-Dll @CommonParams -InputPattern $c.Pattern -Replacement $c.Replacement) {
            return $true
        }
    }
    Write-Host "None of the known patterns matched this build." -ForegroundColor Yellow
    return $false
}

# --- Main Execution ---

Stop-TermService

# Take ownership and permissions
$termsrvDllAcl = Get-Acl -Path $termsrvDllFile
takeown.exe /F $termsrvDllFile
$currentUserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
icacls.exe $termsrvDllFile /grant "$($currentUserName):F"

# Read bytes
$dllAsByte = [System.IO.File]::ReadAllBytes($termsrvDllFile)
$dllAsText = ($dllAsByte | ForEach-Object { $_.ToString('X2') }) -join ' '

$commonParams = @{
    TermsrvDllAsText  = $dllAsText
    TermsrvDllAsFile  = $termsrvDllFile
    TermsrvDllAsPatch = $termsrvPatched
}

# Replacement bytes that go with each pattern.
$replOld    = 'B8 00 01 00 00 89 81 38 06 00 00 90'
$replWin24H2 = 'B8 00 01 00 00 89 81 38 06 00 00 90 EB'
$replWin26H2 = '41 B9 00 01 00 00 90 44 89 8F 38 06 00 00 90 90 90 EB 14'

# Newest-first candidate list for modern Windows 11 / Server 2025+.
# Covers 26H2 and 25H2 (Win26H2), 24H2 (Win24H2), and 22H2/23H2 (old Pattern)
# by trying each until one matches -- no reliance on exact DisplayVersion strings.
$modernCandidates = @(
    @{ Pattern = $patterns.Win26H2; Replacement = $replWin26H2 }
    @{ Pattern = $patterns.Win24H2; Replacement = $replWin24H2 }
    @{ Pattern = $patterns.Pattern;  Replacement = $replOld }
)

$osv = Get-OSVersion
$osInfo = Get-OSInfo
Write-Host "Detected OS: $osv (Build $($osInfo.FullOSBuild), $($osInfo.DisplayVersion))" -ForegroundColor Cyan

switch ($osv) {
    'Windows 10'          { Update-Dll @commonParams -InputPattern $patterns.Pattern -Replacement $replOld | Out-Null }
    'Windows 11'          { Invoke-PatchCandidates -Candidates $modernCandidates -CommonParams $commonParams | Out-Null }
    'Windows Server 2016' { Update-Dll @commonParams -InputPattern $patterns.Pattern -Replacement $replOld | Out-Null }
    'Windows Server 2022' { Update-Dll @commonParams -InputPattern $patterns.Pattern -Replacement $replOld | Out-Null }
    'Windows Server 2025' { Invoke-PatchCandidates -Candidates $modernCandidates -CommonParams $commonParams | Out-Null }
    Default               { Write-Warning "OS Version not recognized for auto-patching." }
}

# Restore the original ACL once, regardless of which candidate applied.
Set-Acl -Path $termsrvDllFile -AclObject $termsrvDllAcl

Write-Host "`nPatching sequence finished. Restarting Services..." -ForegroundColor Cyan
Start-Service UmRdpService -ErrorAction SilentlyContinue
Start-Service TermService -ErrorAction SilentlyContinue

Write-Host "Done! If you see any errors above, try running this script immediately after a reboot." -ForegroundColor Green
