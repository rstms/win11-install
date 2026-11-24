
param (
    [string]$Command = "help"
)

$scriptName ="$([System.IO.Path]::GetFileName($MyInvocation.MyCommand.Path))"
$cfgDir = "c:\users\public\rstms"
$logFile = "${cfgDir}\bootstrap.log"


function Write-Log {
    param (
	[Parameter(Mandatory=$true)][string]$message
    )
    $message | Write-Host
    echo "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") ${scriptName} ${message}" | Add-Content -Path $logFile
}

function Log-Error {
    param (
	[string]$Message
    )
    Write-Log "Error: $Message"
    Write-Error $Message
}

function Run-Command {
    param (
	[Parameter(Mandatory=$true)][string]$FilePath,
	[Parameter(Mandatory=$true)][string]$ArgumentList,
	[int]$SuccessExitCode=0,
	[string]$Directory
    )

    Write-Host "${FilePath} ${ArgumentList}"

    if ($Directory) {
	Set-Location $Directory
    }
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -NoNewWindow -Wait -PassThru
    $proc.WaitForExit()
    $exit_code = $proc.ExitCode
    if ($exit_code -eq $null) {
	Log-Error "NULL ExitCode"
    }
    if ($exit_code -gt $SuccessExitCode) {
	Log-Error "${FilePath} failed with exit code ${exit_code}"
    }
    return $proc.Stdout
}

function Admin-First-Login {

    Write-Log "installing anydesk client"
    Write-Progress -Activity "Administrator First Login" -Status "Installing Anydesk Client..."
    Run-Command msiexec "/package ${cfgDir}\reliance-anydesk-client.msi /passive /norestart /l* ${cfgDir}\anydesk-install.log"
    Write-Log "anydesk client installed"

    Write-Log "installing winhance"
    Write-Progress -Activity "Administrator First Login" -Status "Installing Winhance..."
    Run-Command ${cfgDir}\Winhance.Installer.exe "/NOICONS /ALLUSERS /SILENT"
    Write-Log "winhance installed"

    Write-Log "executing winhance install"
    Write-Progress -Activity "Administrator First Login" -Status "Executing winhance install..."
    Run-Command PowerShell ${cfgDir}\apply-winhance-config.ps1 install
    Write-Log "winhance install complete"

    Write-Log "executing winhance uninstall"
    Write-Progress -Activity "Administrator First Login" -Status "Executing winhance uninstall..."
    Run-Command PowerShell ${cfgDir}\apply-winhance-config.ps1 remove
    Write-Log "winhance uninstall complete"

    Write-Log "installing vmware workstation"
    Write-Progress -Activity "Administrator First Login" -Status "Installing VMware Workstation..."
    $vmwareInstaller = Get-ChildItem -Path "${cfgDir}\vmware-workstation-*.exe" -File | Select-Object -First 1
    Run-Command $vmwareInstaller "/passive /norestart /l ${cfgDir}\vmware-install.log /v `"/qn EULAS_AGREED=1 AUTOSOFTWAREUPDATE=1 DATACOLLECTION=0`""
    Write-Log "vmware workstation installed"

    Write-Progress -Activity "Administrator First Login" -Status "Restarting..."
    Write-Log "restarting in 5 seconds..."
    shutdown /r /f /t 005
}

function User-First-Login {
    Write-Log "user first login commands"
}

function Before-Account-Creation {
	Write-Log "before account creation commands"
}

function Modify-Default-User {
    Write-Log "modify default user commands"
}

try {

    Write-Log "executing ${Command}"	
    cd $cfgDir

    switch ($Command) {
	"admin-first-login" {
	    Admin-First-Login
	}
	"user-first-login" {
	    User-First-Login
	}
	"before-account-creation" {
	    Before-Account-Creation
	}
	"modify-default-user" {
	    Modify-Default-User
	}
	"help" {
	    Write-Host "Commands: admin-first-login user-first-login before-account-creation modify-default-user help"
	}
	default {
	    Log-Error "unexpected command: ${Command}"
	}
    }
} finally {
    Write-Log "exiting ${Command}"
}
