
function Is-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Is-Admin)) {
    Start-Process powershell -ArgumentList "Start-Process PowerShell -Verb RunAs -ArgumentList '$PSCommandPath'" -Verb RunAs
    exit
}


function Uninstaller() {
    param (
	[string]$name,
	[string]$cmd
    )
    $cmd, $args = $cmd -split ' ', 2
    if ($cmd -like "msiexec*") {
	$args = "${args} /passive"
    }
    Write-Host "uninstalling '$name' with '$cmd' args='$args'"
    Start-Process -FilePath "$cmd" -ArgumentList "$args" -Wait
}

Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
    Where-Object { $_.DisplayName -like "*anydesk*" } |
    Foreach-Object { Uninstaller -name $_.DisplayName -cmd $_.UninstallString }

Get-ItemProperty "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
    Where-Object { $_.DisplayName -like "*anydesk*" } |
    Foreach-Object { Uninstaller -name $_.DisplayName -cmd $_.UninstallString }


$msi = Get-ChildItem -Path "C:\Users\Public\rstms" -Recurse -Filter "anydesk*.msi" |
    Sort-Object LastWriteTime -Descending  |
    Select-Object -first 1

$installer = ($msi.VersionInfo.FileName)

$args = "/package $installer /passive"

Write-Host "Installing '$args'..."
Start-Process -FilePath "msiexec.exe" -ArgumentList "$args" -Wait

