param (
    [string]$ISODrive,
    [string]$USBDrive
)
    
try {

    function HumanSize {
	param (
	    [long]$bytes
	)
	if ($bytes -lt 1KB) { return "${bytes}B" }
	elseif ($bytes -lt 1MB) { return "{0:N1}KB" -f ($bytes / 1KB) }
	elseif ($bytes -lt 1GB) { return "{0:N1}MB" -f ($bytes / 1MB) }
	else { return "{0:N1}GB" -f ($bytes / 1GB) }
    }

    function ProcessRunning {
	param (
	    [long]$pid
	)
	try {
	    Get-Process -Id $pid | ForEach-Object { return $true }
	} catch {
	    return $false
	}
    }

    $sleepInterval = 5
    $wimPath = "${ISODrive}:\sources\install.wim"
    $swmPath = "${USBDrive}:\sources\install*.swm"

    Remove-Item "$swmPath" -Force

    $totalSize = (Get-Item $wimPath).Length
    $total = HumanSize -bytes $totalSize
    $dismArgs = "/Split-Image /ImageFile:$wimPath /SWMFILE:${USBDrive}:\sources\install.swm /FileSize:2048"
    $dismProc = (Start-Process -FilePath 'dism.exe' -ArgumentList "${dismArgs}" -PassThru)
    $progress = 0
    while($progress -lt 100) {
	Start-Sleep -Seconds $sleepInterval
	$currentSize = 0
	$currentFile = ''
	Get-ChildItem "$swmPath" | ForEach-Object {
	    $currentSize += $_.Length
	    $currentFile = $_.Name
	}
	$current = HumanSize -bytes $displayCurrent
	$status = "Writing ${currentFile} (${current} of ${total})" 
	$progress = [math]::Min(100, [math]::Round(($currentSize / $totalSize) * 100))
	if (! ProcessRunning -pid $dismProc.Id) {
	    $progress = 100
	    $status = "complete"
	}
	Write-Progress -Activity "Splitting install.wim..." -Status "$status" -PercentComplete $progress 
    }
} catch {
    Write-Output $_ -ErrorAction stop
}
