$computerName = if($args.Count -eq 1){$args[0]} else {read-host "Enter remote computer name"}
$rdpwrapURL = "https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip"
$autoupdateURL = "https://github.com/asmtron/rdpwrap/raw/master/autoupdate.zip"

Function Execute-Command ($commandPath, $commandArguments, $credential=$null,[switch]$Elevate)
{
	$pinfo = New-Object System.Diagnostics.ProcessStartInfo
	$pinfo.FileName = $commandPath
	$pinfo.RedirectStandardError = $true
	$pinfo.RedirectStandardOutput = $true
	$pinfo.UseShellExecute = $false
	$pinfo.Arguments = $commandArguments
	if($Elevate){$pinfo.Verb = "runas"}
	if($credential)
	{
		$pinfo.Domain = $credential.GetNetworkCredential().Domain
		$pinfo.UserName = $credential.GetNetworkCredential().Username
		$pinfo.Password = $credential.Password
	}
	$p = New-Object System.Diagnostics.Process
	$p.StartInfo = $pinfo
	$p.Start() | Out-Null
	$p.WaitForExit()
	[pscustomobject]@{        
		stdout = $p.StandardOutput.ReadToEnd()
		stderr = $p.StandardError.ReadToEnd()
		ExitCode = $p.ExitCode
	}
}

# Ping it before we go further...
if(!(test-connection -Quiet -Count 1 -ComputerName $computerName))
{
    Write-Host "Computer not reachable."
    break
}
# Connect to the remote computer
$session = New-PSSession -ComputerName $computerName -EnableNetworkAccess -ea SilentlyContinue
if ($session -eq $null) {
    # PSRemoting is not enabled, try to enable it
    Enable-PSRemoting -Force -ErrorAction SilentlyContinue
    $session = New-PSSession -ComputerName $computerName -ea SilentlyContinue
    if ($session -eq $null) {
        Write-Host "Failed to connect to the remote computer, PSRemoting could not be enabled"
        break
    }
}
if($session)
{
    write-host "Connection to $computerName successfull"
}

write-host "Pre creating folders"
# Create dirs on local and remote pc
Invoke-Command -Session $session -ScriptBlock {

    if(!(test-path "${env:SystemDrive}\temp\RDPWrap"))
    {
        start-process cmd -verb RunAs -args "/c mkdir ""${env:SystemDrive}\temp\RDPWrap"""
    }
    if(!(test-path "${env:SystemDrive}\temp\RDPWrap\INIs"))
    {
        start-process cmd -verb RunAs -args "/c mkdir ""${env:SystemDrive}\temp\RDPWrap\INIs"""
    }
    if(!(test-path "${env:ProgramFiles}\RDP Wrapper"))
    {
        start-process cmd -verb RunAs -args "/c mkdir ""${env:ProgramFiles}\RDP Wrapper"""
    }
}
New-Item -ItemType Directory -Force -Path "${env:SystemDrive}\temp\RDPWrap" | Out-Null
New-Item -ItemType Directory -Force -Path "${env:SystemDrive}\temp\RDPWrap\INIs" | Out-Null

Write-Host "Downloading RDPWrap"
# Download latest files from github loaclly (Because unfortunatly it might be blocked remotely)
Invoke-WebRequest -Uri $rdpwrapURL -OutFile "${env:SystemDrive}\temp\RDPWrap\RDPWrap-v1.6.2.zip"
Invoke-WebRequest -Uri $autoupdateURL -OutFile "${env:SystemDrive}\temp\RDPWrap\autoupdate.zip"

# Extract autoupdate archive, read the batch file, get the URLs in it and clean up
Expand-Archive "${env:SystemDrive}\temp\RDPWrap\autoupdate.zip" -DestinationPath "${env:SystemDrive}\temp\RDPWrap" -Force
#Start-Process cmd -Verb RunAs -args "/c rmdir /S /Q ""${env:SystemDrive}\temp\RDPWrap\helper"""
Start-Process cmd -args "/c rmdir /S /Q ""${env:SystemDrive}\temp\RDPWrap\helper"""
$AutoUpdateText = Get-Content "${env:SystemDrive}\temp\RDPWrap\autoupdate.bat"
Remove-Item "${env:SystemDrive}\temp\RDPWrap\autoupdate.bat"
$autoupdateURLs = $AutoUpdateText | ? {$_ -like "*https://*" -and !($_.ToString().StartsWith("::"))} | % {$_.Split("=")[1].replace("""","")}

# Pre-Download rdpwrap.ini files from github
for ($i = 0; $i -lt $autoupdateURLs.count; $i++)
{ 
    New-Item -ItemType Directory -Force -Path "${env:SystemDrive}\temp\RDPWrap\INIs\$i" | Out-Null
    Invoke-WebRequest -Uri $autoupdateURLs[$i] -OutFile "${env:SystemDrive}\temp\RDPWrap\INIs\$i\rdpwrap.ini"  
}

Write-Host "Transferring files to remote computer"
# Move downloaded files to remote pc
$RemoteSystemDrive = Get-CimInstance -Class Win32_OperatingSystem -ComputerName $computerName -Property SystemDrive | Select-Object -ExpandProperty SystemDrive

Copy-Item -Path "${env:SystemDrive}\temp\RDPWrap" -Destination "\\$computerName\$($RemoteSystemDrive.replace(":","$"))\temp" -Recurse -Force
#Start-Process cmd -Verb RunAs -args "/c rmdir /S /Q ""${env:SystemDrive}\temp\RDPWrap"""
Start-Process cmd -args "/c rmdir /S /Q ""${env:SystemDrive}\temp\RDPWrap"""

Write-host "Extracting files and placing in program files"
# Extract archivers and move to Program Files dir
Invoke-Command -Session $session -ScriptBlock {
    Expand-Archive "${env:SystemDrive}\temp\RDPWrap\RDPWrap-v1.6.2.zip" -DestinationPath "${env:SystemDrive}\temp\RDPWrap" -Force
    Expand-Archive "${env:SystemDrive}\temp\RDPWrap\autoupdate.zip" -DestinationPath "${env:SystemDrive}\temp\RDPWrap" -Force
    Remove-Item "${env:SystemDrive}\temp\RDPWrap\RDPWrap-v1.6.2.zip" -Force
    Remove-Item "${env:SystemDrive}\temp\RDPWrap\autoupdate.zip" -Force

    Start-Process cmd -Verb RunAs -args "/c xcopy ""${env:SystemDrive}\temp\RDPWrap"" ""${env:ProgramFiles}\RDP Wrapper\"" /s /e /y"
    Start-Sleep -Seconds 5
    Start-Process cmd -Verb RunAs -args "/c rmdir /S /Q ""${env:SystemDrive}\temp\RDPWrap"""
}

write-host "Patching RDP"
# Start rdp patching
Invoke-Command -ComputerName $computerName -ScriptBlock {
    $null = New-Item -Path function: -Name $args[0] -Value $args[1]
    #Start-Process cmd -Verb runas "/c ""${env:ProgramFiles}\RDP Wrapper\autoupdate.bat"" -log && exit" -wait
    #$LogCont = Get-Content -Path "${env:ProgramFiles}\RDP Wrapper\autoupdate.log"
    #if(@($LogCont | ?{$_ -like "*Please check you internet*"}).Count -gt 0)
    #{
    #    Write-Host "Cannot download from github remotely, will try do use locally pre-downloaded .ini files"
        $Ver= (Get-Item "${env:SystemRoot}\System32\termsrv.dll").VersionInfo.fileversionRaw.tostring()
        write-host "termsrv.dll Version is $Ver"
        $INIsCount = @(Get-ChildItem "${env:ProgramFiles}\RDP Wrapper\INIs").Count
        $found = $false
        for ($i = 0; $i -lt $INIsCount -and $found -eq $false; $i++)
        { 
            $inipath = "${env:ProgramFiles}\RDP Wrapper\INIs\$i\rdpwrap.ini"
            Write-Host "Testing .ini #$i"
            if((test-path $inipath) -and @(Get-Content $inipath | ?{$_ -like "*$Ver*"}).Count -gt 0)
            {
                $found = $true
                #Write-Host "Found matching rdpwrap.ini, reinstalling..."
                Write-Host "Found matching rdpwrap.ini, patching..."
                
                #Write-Host "Uninstalling"
                #$Result = Execute-Command -commandPath cmd -commandArguments "/c ""${env:ProgramFiles}\RDP Wrapper\RDPWInst.exe"" -u" -Elevate
                #if($Result.stdout){ $Result.stdout } else { $Result.stderr }

                Write-Host "Placing correct .ini file"
                Start-Process cmd -Verb RunAs -args "/c copy ""$inipath"" ""${env:ProgramFiles}\RDP Wrapper\"""

                Write-Host "Installing"
                $Result = Execute-Command -commandPath cmd -commandArguments "/c ""${env:ProgramFiles}\RDP Wrapper\RDPWInst.exe"" -i" -Elevate
                if($Result.stdout){ $Result.stdout } else { $Result.stderr } 
                
                Write-Host "If the above text says ""This version of Terminal Services is not supported"" ignore it, we found a supported .ini and it should work." -ForegroundColor Green              
            }
        }
    #}
    #else
    #{
    #    $LogCont
    #}
} -ArgumentList ${function:Execute-Command}.Ast.Name,${function:Execute-Command}

# Wait for user input
Write-Host "RDP patching attempt done, press ENTER to unpatch and clean up... (or exit script to keep patched)"
read-host 

write-host "Unpatching and cleaning up"
# Uninstalling and removing traces
Invoke-Command -Session $session -ScriptBlock {
    $null = New-Item -Path function: -Name $args[0] -Value $args[1]
    $Result = Execute-Command -commandPath cmd -commandArguments "/c ""${env:ProgramFiles}\RDP Wrapper\RDPWInst.exe"" -u" -Elevate
    if($Result.stdout){ $Result.stdout } else { $Result.stderr }     
    $Result = Execute-Command -commandPath cmd -commandArguments "/c rmdir /S /Q ""${env:ProgramFiles}\RDP Wrapper""" -Elevate
    if($Result.stdout){ $Result.stdout } else { $Result.stderr }
} -ArgumentList ${function:Execute-Command}.Ast.Name,${function:Execute-Command}

# Disconnect from the remote computer
Remove-PSSession $session