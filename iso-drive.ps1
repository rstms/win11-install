try {
    Get-Volume | Where-Object { 
	($_.DriveType -eq "CD-ROM") -and ($_.OperationalStatus -eq "OK") -and ($_.FileSystem -eq "UDF")
    } | ForEach-Object {
	Write-Output $_.DriveLetter
	exit 0
    }
} catch {
    Write-Output $_ -ErrorAction stop
}
exit 1
