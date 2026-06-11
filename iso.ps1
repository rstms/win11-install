param (
    [switch]$Mount,
    [switch]$Dismount,
    [switch]$Show,
    [switch]$Drive,
    [string]$IsoImage
)
    
try {
    
    if ( $IsoImage -eq '' ) {
        $IsoImage = Get-ChildItem -Path . -Filter *.iso | Select-Object -First 1
    }
    if ( $IsoImage -ne '' ) {
        $IsoImage = (Resolve-Path -Path $IsoImage)
    }
    
    if ($Mount -or $Dismount) {
	Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.OperationalStatus -eq 'OK' } | ForEach-Object {
	    $DriveLetter = $_.DriveLetter
	    $DevicePath = $_.Path.TrimEnd('\')
	    $ImagePath = (Get-DiskImage -DevicePath $DevicePath).ImagePath
	    if ($ImagePath -eq $IsoImage) {
		if ($Mount) {
		    # already mounted
		    $Mount = $false
		}
		if ($Dismount) {
		    $result = Dismount-DiskImage -DevicePath $DevicePath
		} 
	    }
        }
        if ($Mount) {
	   $result = Mount-DiskImage -ImagePath $IsoImage
        }
    }
    
    if ($Show -or $Drive) {
	Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.OperationalStatus -eq 'OK' } | ForEach-Object {
	    $DriveLetter = $_.DriveLetter
	    $DevicePath = $_.Path.TrimEnd('\')
	    $ImagePath = (Get-DiskImage -DevicePath $DevicePath).ImagePath
	    if ($Show) {
		Write-Host $_.DriveLetter $ImagePath
	   } else {
		Write-Host $_.DriveLetter
	   }
	}
    }
} 
catch {
    Write-Output $_ -ErrorAction stop
}
