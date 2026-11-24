
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

function Install-VMWare-Workstation {
    $installeExe = Get-Children -Path "c:\users\public\rstms\vmware-workstation-full-*.exe" -File | Select-Object -First 1
    Write-Log "installExe=$installExe"
    Run-Command $installExe /x
    $installDir = Get-Children -Path [System.IO.Path]::GetTempPath() -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Log "installDir=$installDir"
    dir $installDir
}

Install-VMWare-Workstation
