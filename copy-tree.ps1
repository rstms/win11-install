param (
    [string]$Source,
    [string]$Destination,
    [string]$Exclude
)
    
try {
    $sourcePath = (Resolve-Path -Path $Source).Path

    $Files = Get-ChildItem -Path $Source -Recurse
    $FileCount = $Files.count
    $i=0
    Foreach ($File in $Files) {
	$i++
	if ("$File" -eq "$Exclude") {
	    Write-Host "Skipping excluded file: $File"
	} else {
	    Write-Progress -activity "Copying from $Source to $Destination..." -status "Writing $File ($i of $FileCount)" -percentcomplete (($i/$FileCount)*100)
	    if ($File.psiscontainer) {
		$SourcefileContainer = $File.parent
	    } else {
		$SourcefileContainer = $File.directory
	    }
	    $RelativePath = $SourcefileContainer.fullname.SubString($sourcePath.length)
	    Copy-Item $File.fullname ($Destination + $RelativePath + '\' + $File.Name) 
	}
    }
} catch {
    Write-Output $_ -ErrorAction stop
}
