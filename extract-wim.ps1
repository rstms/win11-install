param (
    [string]$ISODrive,
    [string]$USBDrive
)

$ErrorActionPreference = "Stop"
$sleepInterval = 5
$wimPath = "${ISODrive}:\sources\install.wim"
$swmPath = "${USBDrive}:\sources\install*.swm"
    
function HumanSize {
	param (
	    [long]$bytes
	)
	if ($bytes -lt 1KB) { return "${bytes}B" }
	elseif ($bytes -lt 1MB) { return "{0:N1}KB" -f ($bytes / 1KB) }
	elseif ($bytes -lt 1GB) { return "{0:N1}MB" -f ($bytes / 1MB) }
	else { return "{0:N1}GB" -f ($bytes / 1GB) }
}

function ProcessComplete {
    param (
	[long]$Id
    )
    Get-Process -Id $Id | ForEach-Object { return $false }
    return $true
}

Remove-Item "$swmPath" -Force

$totalSize = (Get-Item $wimPath).Length
$total = HumanSize -bytes $totalSize
$dismArgs = "/Split-Image /ImageFile:$wimPath /SWMFILE:${USBDrive}:\sources\install.swm /FileSize:2048"
$dismProc = (Start-Process -FilePath 'dism.exe' -ArgumentList "${dismArgs}" -PassThru)
$dismPid = $dismProc.Id

$startTime = (Get-Date)

$percentComplete = 0
while($percentComplete -lt 100) {
	Start-Sleep -Seconds $sleepInterval
	$currentSize = 0
	$currentFile = ''
	Get-ChildItem "$swmPath" | ForEach-Object {
	    $currentSize += $_.Length
	    $currentFile = $_.Name
	}
	$current = HumanSize -bytes ${currentSize}
	if ( Get-Process -Id $dismPid -ErrorAction SilentlyContinue ) {
	    $status = "Writing ${currentFile} (${current} of ${total})"
	    $percentComplete = [math]::Min(100, [math]::Round(($currentSize / $totalSize) * 100))
	    $elapsedTime = (Get-Date) - $startTime
	    $estimatedTotalTime = ($elapsedTime.TotalSeconds / $percentComplete) * 100
	    $estimatedTimeRemaining = $estimatedTotalTime - $elapsedTime.TotalSeconds
	    $secondsRemaining = [math]::Ceiling($estimatedTimeRemaining)
	} else {
	    $status = "complete"
	    $percentComplete = 100
	}
	Write-Progress `
	    -Activity "Extracting $wimPath to $swmPath" `
	    -Status $status `
	    -PercentComplete $percentComplete `
	    -SecondsRemaining $secondsRemaining
}
