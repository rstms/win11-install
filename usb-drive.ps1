try {
    Get-Volume | Where-Object { 
	($_.DriveType -eq "Removable") -and ($_.OperationalStatus -eq "OK") -and ($_.FileSystemLabel -eq "WIN11SETUP") -and ($_.FileSystem -eq "FAT32")
    } | ForEach-Object {
	Write-Output $_.DriveLetter
	exit 0
    }
} catch {
    Write-Output $_ -ErrorAction stop
}
exit 1
