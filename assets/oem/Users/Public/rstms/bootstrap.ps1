
param (
    [string]$Command = "help"
)

$scriptName ="$([System.IO.Path]::GetFileName($MyInvocation.MyCommand.Path))"
$logFile = "c:\users\public\rstms\bootstrap.log"
cd "c:\users\public\rstms"

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
    Run-Command msiexec "/package c:\users\public\rstms\reliance-anydesk-client.msi /passive /norestart /l* c:\users\public\rstms\anydesk-install.log"
    Write-Log "anydesk client installed"

    Write-Log "installing winhance"
    Run-Command c:\users\public\rstms\Winhance.Installer.exe "/NOICONS /ALLUSERS /SILENT"
    Write-Log "winhance installed"

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
