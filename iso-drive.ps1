
$ErrorActionPreference = "Stop"
try {
    Get-Volume | Where-Object { 
	($_.DriveType -eq "CD-ROM") -and ($_.OperationalStatus -eq "OK") -and ($_.FileSystem -eq "UDF")
    } | ForEach-Object {
	Write-Output $_.DriveLetter
	exit 0
    }
} catch {
    exit 1
}
exit 1
