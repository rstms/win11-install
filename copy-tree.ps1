param (
    [string]$Source,
    [string]$Destination,
    [string]$Exclude
)

$ErrorActionPreference = "Stop"

$Files = Get-ChildItem -Path $Source -Recurse
$FileCount = $Files.count
$sourcePath = (Resolve-Path -Path $Source).Path

#Remove-Item -Path "$Destination\*" -Recurse -Force

$startTime = (Get-Date)
$percentComplete = 0
$i=0

Foreach ($File in $Files) {
    $i++
    if ("$File" -eq "$Exclude") {
	Write-Host "Skipping excluded file: $File"
    } else {
	if ($File.psiscontainer) {
	    $SourcefileContainer = $File.parent
	} else {
	    $SourcefileContainer = $File.directory
	}
	$RelativePath = $SourcefileContainer.fullname.SubString($sourcePath.length)
	$src = $File.fullname
	if ( $RelativePath.length -gt 0 ) {
	    $dst = $Destination + $RelativePath + '\' + $File.Name
	} else {
	    $dst = $Destination + $File.Name
	}
	if (-not (Test-Path -Path $dst)) {
	    Copy-Item $src $dst
	}

	$percentComplete = [math]::Min(100, [math]::Round(($i / $FileCount) * 100))
	#Write-Host percentComplete=$percentComplete
	if ($percentComplete -gt 0) {
	    $elapsedTime = (Get-Date) - $startTime
	    #Write-Host elapsedTime=$elapsedTime
	    $estimatedTotalTime = ($elapsedTime.TotalSeconds / $percentComplete) * 100
	    #Write-Host estimatedTotalTime=$estimatedTotalTime
	    $estimatedTimeRemaining = $estimatedTotalTime - $elapsedTime.TotalSeconds
	    #Write-Host estimatedTimeRemaining=$estimatedTimeRemaining
	    $secondsRemaining = [math]::Ceiling($estimatedTimeRemaining)
	    #Write-Host secondsRemaining=$secondsRemaining
	    Write-Progress `
		-activity "Copying from $Source to $Destination..." `
		-status "Writing $File ($i of $FileCount)" `
		-percentcomplete (($i/$FileCount)*100) `
		-SecondsRemaining $secondsRemaining
	}
    }
}
