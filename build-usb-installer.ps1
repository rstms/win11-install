
param (
    [string]$Command = "help",
    [string]$TargetDiskName,
    [string]$TargetDiskNumber,
    [string]$IsoImage,
    [string]$xml_template = ".\assets\template.xml",
    [string]$oem_dir = ".\assets\oem",
    [string]$secrets_root = ".\secrets",
    [string]$hostname = ${env:HOST},
    [int]$fat32_size = -1,
    [int]$ntfs_size = -1,
    [switch]$no_oem,
    [switch]$no_xml
)

$ErrorActionPreference = "Stop"

if ($fat32_size -lt 0) {
    $fat32_size = if (${env:FAT32_SIZE}) { [int](${env:FAT32_SIZE}) } else { 1 }
}

if ($ntfs_size -lt 0) {
    $ntfs_size = if (${env:NTFS_SIZE}) { [int](${env:NTFS_SIZE}) } else { 16 }
}

$sgdisk_bin = "assets\bin\sgdisk64.exe"

$global:usb_id_lines = $null

function USB-Device-Decode {
    param (
	[Parameter()][string]$VendorId="XXXX", 
	[Parameter()][string]$ProductId="XXXX",
	[Parameter()][switch]$Vendor,
	[Parameter()][switch]$Product
    )

    $vendor_name="vendor_${VendorId}"
    $product_name="product_${ProductId}"
    $vid_pattern = "^${VendorId}[[:space:]]"
    $in_vid = $false
    if ($global:usb_id_lines -eq $null) {
	$global:usb_id_lines = (Invoke-WebRequest -Uri http://www.linux-usb.org/usb.ids -UseBasicParsing -Verbose:$false).Content -split "`n"
    }
    foreach ($line in $global:usb_id_lines) {
	if ($line -match "^[0-9a-fA-F]{4}\s+") {
	    if ($in_vid) {
		break
	    }
	    if ($line -match "^${VendorId}\s+") {
		$vendor_name = $line -replace "^[0-9a-fA-F]{4}\s+", ""
		$in_vid = $true
	    }
	} elseif ($in_vid -and $line -match "^\s+${ProductId}\s+") {
	    $product_name = $line -replace "^\s+${ProductId}\s+", ""
	    break
	}
    }
    if ($Vendor -and (-not $Product)) {
	return $vendor_name
    }
    if ($Product -and (-not $Vendor)) {
	return $product_name
    }
    return "${vendor_name} ${product_name}"
}


function Confirm-Action {
    param(
	[Parameter(Mandatory=$true)][string]$Prompt,
	[switch]$DefaultNo,
	[switch]$NonFatal
    )
    Write-Host ""
    if ($DefaultNo) {
	$Prompt = "${Prompt} [y/N]"
    } else {
	$Prompt = "${Prompt} [Y/n]"
    }
    $response = Read-Host -Prompt $Prompt 
    if (-not $DefaultNo -and ($response -eq "")) {
	$response = "y"
    } 
    if ( -not (($response -match "^[yY]$") -or ($response -match "^[yY][eE][sS]$"))) {
	if ($NonFatal) {
	    return $false
	}
	Write-Host "Confirmation declined"
	exit 1
    }
    if ($NonFatal) {
	return $true
    }
}

function Get-Target-Disk {
    param (
	[string]$Name,
	[int]$Number
    )
    if (-not $Name) {
	$Name = ${env:TARGET_DISK_NAME}
	#write-host "TARGET_DISK_NAME=${Name}"
    }
    if (-not $Number) {
	$Number = ${env:TARGET_DISK_NUMBER}
	#write-host "TARGET_DISK_NUMBER=${Number}"
    }
    $potential_target_disks = Get-Disk | Where-Object { 
        -not $_.IsSystem `
        -and -not $_.IsBoot `
        -and -not $_.IsReadOnly `
        -and $_.Size -gt 0 `
        -and $_.Size -lt 512GB
    } | Sort-Object Number 
    
    if (-not $potential_target_disks ) {
        Write-Error "No eligible target disk detected (criteria: !system, !boot, !readonly, 0<size<512GB)"
    }

    if ( $Name ) {
	$target_disk = $potential_target_disks | where-object { $_.Model.Trim() -eq $Name }
    } elseif ( $Number ) {
        $target_disk = $potential_target_disks | where-object { $_.Number -eq $Number }
    } else {
	if (($potential_target_disks | Measure-Object).Count -eq 1) {
	    # single potential disk
	    $target_disk = $potential_target_disks 
	    $target_disk | Format-Table | Out-Host
	    Confirm-Action -Prompt "Select target disk #$($target_disk.Number)" 
	} else { 
	    # multiple potential disks
	    $potential_target_disks | Format-Table | Out-Host
	    $response = Read-Host -Prompt "Enter target disk number"
	    Write-Host "response=$response"
	    if ( -not ($response -match "^[0-9]+$" )) {
		Write-Host "No disk selected."
		exit 1
	    }
	    $target_disk = ($potential_target_disks | Where-Object { $_.Number -eq $response })
	}
	Write-Host "Disk $($target_disk.Number) selected."
    }

    if ( -not $target_disk ) {
        Write-Error "Target Disk not found"
    }
    
    if ( $target_disk.IsReadOnly) {
        Write-Error "Target Disk is read-only"
        exit 1
    }
    
    if ( $target_disk.IsSystem ) {
        Write-Error "Target Disk is System disk"
        exit 1
    }
    
    if ( $target_disk.IsBoot ) {
        Write-Error "Target Disk is Boot disk"
        exit 1
    }
    
    if ( $target_disk.Size -gt 256GB ) {
        Write-Error "Target Disk size over 256GB limit"
        exit 1
    }
    return $target_disk
}

function Get-USB-Drive-Letters {
    param (
	[Parameter(Mandatory=$true)][int]$DiskNumber
    )
    $result = @{}
    $partitions = Get-Partition -DiskNumber $DiskNumber

    $expected = 0 

    if ($ntfs_size -gt 0) {
	$expected = $expected + 1
    }
    if ($fat32_size -gt 0) {
	$expected = $expected + 1
    }

    if ( ($partitions | Measure-Object).Count -ne $expected ) {
	$partitions 
	Write-Error "Unexpected partition count"
    }

    $partitions | ForEach-Object { 
	$volume = Get-Volume -Partition $_
	if (($volume.DriveType -eq "Removable") -and ($volume.OperationalStatus -eq "OK") ) {
	    $fs_type = $volume.FileSystemType
	    Write-Host "setting $($volume.FileSystemType) to $($volume.DriveLetter)"
	    $result[$volume.FileSystemType] = $volume.DriveLetter
	} else {
	    $volume 
	    Write-Error "Unexpected volume"
	}
    }
    if ( ($fat32_size -gt 0) -and ( $result.FAT32 -NotMatch '^[D-Z]$')) {
	Write-Error "Missing FAT32 drive letter"
    }
    if ( ($ntfs_size -gt 0) -and ($result.NTFS -NotMatch '^[D-Z]$')) {
	Write-Error "Missing NTFS drive letter"
    }
    return $result
}

function Verified-Directory {
    param (
	[Parameter(Mandatory=$true)][string]$Path,
	[switch]$Create
    )

    if (Test-Path -Path $Path -PathType Container) {
	return (Resolve-Path $Path).Path
    } 

    if (Test-Path -Path $Path -PathType Any) {
	Write-Error "Not a directory: ${Path}"
    }

    if ($Create) {
	$created = New-Item -Path $Path -ItemType Directory -Force
    }

    return (Resolve-Path $Path).Path
}

function Verified-File {
    param (
	[Parameter(Mandatory=$true)][string]$Path
    )
    if (Test-Path -Path $Path -PathType Leaf) {
	return (Resolve-Path $Path).Path
    } elseif (Test-Path -Path $Path -PathType Any) {
	Write-Error "Not a file: ${Path}"
    }
    # generate error
    Get-Item -Path $Path
}

function Humanize {
    param (
	[Parameter(Mandatory=$true)][long]$bytes
    )
    if ($bytes -lt 1KB) { return "${bytes}B" }
    elseif ($bytes -lt 1MB) { return "{0:N1}KB" -f ($bytes / 1KB) }
    elseif ($bytes -lt 1GB) { return "{0:N1}MB" -f ($bytes / 1MB) }
    elseif ($bytes -lt 1TB) { return "{0:N1}GB" -f ($bytes / 1GB) }
    else { return "{0:N1}TB" -f ($bytes / 1TB) }
}

function Partition-Drive-Letter {
    param (
	[Parameter(Mandatory=$true)][string]$letter,
	[Parameter(Mandatory=$true)][string]$label
    )
    if ($letter -match "^[D-Z]$") { 
	Write-Host "${label}_drive_letter=${letter}"
	return $letter
    }
    Write-Error "Unexpected ${label} partition drive letter: ${letter}"
    exit 1
}

function Set-Partition-Name {
    param (
	[Parameter(Mandatory=$true)][int]$DiskNumber,
	[Parameter(Mandatory=$true)][int]$PartitionNumber,
	[Parameter(Mandatory=$true)][string]$Name
    )
    $disk = Get-Disk -Number $DiskNumber
    $partition = Get-Partition -DiskNumber $disk.Number -PartitionNumber $PartitionNumber
    Run-Command $sgdisk_bin "--change-name=$($partition.PartitionNumber):`"${Name}`" $($partition.DiskNumber):" 
}

function Show-Disk-GPT {
    param (
	[Parameter(Mandatory=$true)][int]$DiskNumber
    )
    Run-Command $sgdisk_bin "--print $((Get-Disk -Number $DiskNumber).Number): --verbose"
}

function Format-USB-Disk {
    param (
	[Parameter(Mandatory=$true)][int]$DiskNumber
    )

    $TargetDisk = Get-Disk -Number $DiskNumber
    Confirm-Action -Prompt "Confirm IRRECOVERABLE DESTRUCTION of all data on target disk #$($TargetDisk.Number) '$($TargetDisk.Model.Trim())'"
    Clear-Disk -Number $TargetDisk.Number -RemoveData -RemoveOEM -Confirm:$false
    Set-Disk -Number $TargetDisk.Number -PartitionStyle GPT

    if ($fat32_size -gt 0) {
	$fat32_partition = New-Partition -DiskNumber $TargetDisk.Number -Offset 1MB -Size ($fat32_size * 1GB) -AssignDriveLetter 
	$fat32_drive_letter = Partition-Drive-Letter -letter $fat32_partition.DriveLetter -label "FAT32"
	Set-Partition-Name -DiskNumber $TargetDisk.Number -PartitionNumber $fat32_partition.PartitionNumber -Name WINESP
	$fat32_volume = Format-Volume -DriveLetter $fat32_drive_letter -FileSystem FAT32 -NewFileSystemLabel WINFAT
    }

    if ($ntfs_size -gt 0) {
	$ntfs_partition = New-Partition -DiskNumber $TargetDisk.Number -Size ($ntfs_size * 1GB) -AssignDriveLetter 
	$ntfs_drive_letter = Partition-Drive-Letter -letter $ntfs_partition.DriveLetter -label "NTFS"
	Set-Partition-Name -DiskNumber $TargetDisk.Number -PartitionNumber $ntfs_partition.PartitionNumber -Name WINPAYLOAD
	$ntfs_volume = Format-Volume -DriveLetter $ntfs_drive_letter -FileSystem NTFS -NewFileSystemLabel WINNTFS
    }

    Show-Disk-GPT $TargetDisk.Number
}

function Robo-Copy {
    param (
	[Parameter(Mandatory=$true)][string]$SrcDir,
	[Parameter(Mandatory=$true)][string]$DstDir,
	[string]$Files,
	[string]$Options
    )
    $robo_cmd = "${SrcDir} ${DstDir}"
    if ($Files) {
	$robo_cmd = "${robo_cmd} ${Files}"
    }
    $robo_cmd = "${robo_cmd} /E /PURGE /J /COPYALL /DCOPY:DAT /V /ETA"
    if ($Options) {
	$robo_cmd = "${robo_cmd} ${Options}"
    }
	    
    return Run-Command -FilePath "${env:SYSTEMROOT}\system32\robocopy.exe" -ArgumentList $robo_cmd -SuccessExitCode 3
}

function Run-Command {
    param (
	[Parameter(Mandatory=$true)][string]$FilePath,
	[Parameter(Mandatory=$true)][string]$ArgumentList,
	[int]$SuccessExitCode=0,
	[string]$Directory,
	[switch]$Confirm
    )
    if ($Confirm) {
	Confirm-Action "Execute '${FilePath} ${ArgumentList}'"
    } else {
	Write-Host "${FilePath} ${ArgumentList}"
    }
    if ($Directory) {
	Set-Location $Directory
    }
    $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -NoNewWindow -Wait -PassThru
    $proc.WaitForExit()
    $exit_code = $proc.ExitCode
    if ($exit_code -eq $null) {
	Write-Error "NULL ExitCode"
    }
    if ($exit_code -gt $SuccessExitCode) {
	Write-Error "${FilePath} failed with exit code ${exit_code}"
    }
}

function Update-USB-Files {
    param (
	[Parameter(Mandatory=$true)][int]$DiskNumber
    )

    if (Get-ISO-Volumes -match_image) {
	$mounted = $false
    } else {
	Mount-ISO
	$mounted = $true
    }

    $iso_drive_letter = (Get-ISO-Volumes -match_image -require_one).DriveLetter
    $iso_root = Verified-Directory "${iso_drive_letter}:\"
    $usb_drive_letters = Get-USB-Drive-Letters $DiskNumber

    if ($fat32_size -gt 0) {
	$fat32_root = Verified-Directory "$($usb_drive_letters.FAT32):\"
	$fat32_oem = "${fat32_root}`$OEM`$"	
	if ($ntfs_size -gt 0) {
	    Robo-Copy $iso_root $fat32_root -Options "/XD sources /XD ${fat32_oem}"
	    Robo-Copy (Verified-Directory "${iso_root}sources") (Verified-Directory "${fat32_root}sources" -Create) -Files "boot.wim"
	} else {
	    Robo-Copy $iso_root $fat32_root -Options "/XF install.wim"
	    Extract-WIM -ISODrive $iso_drive_letter -USBDrive $usb_drive_letters.FAT32
	}
	if (-not $no_xml) {
	    Generate-XML-File -OutputPath "${fat32_root}autounattend.xml"
	}
	if ($no_oem) {
	    Remove-Item -Path $fat32_oem -Recurse -Force
	} else {
	    Robo-Copy (Verified-Directory $oem_dir) (Verified-Directory "${fat32_oem}\`$1" -Create)
	}	
    }

    if($ntfs_size -gt 0) {
	$ntfs_root = Verified-Directory "$($usb_drive_letters.NTFS):\"
	$ntfs_oem = "${ntfs_root}`$OEM`$"	
	Robo-Copy $iso_root $ntfs_root "/XD sources /XD ${ntfs_oem}"
	if (-not $no_xml) {
	    Generate-XML-File -OutputPath "${ntfs_root}autounattend.xml"
	}
	if ($no_oem) {
	    Remove-Item -Path $ntfs_oem -Recurse -Force
	} else {
	    Robo-Copy (Verified-Directory $oem_dir) (Verified-Directory "${ntfs_oem}\`$1" -Create)
	}
    }

    if ($mounted) {
	Dismount-ISO
    }
}

function Get-Volume-ISO-File {
    param (
	[Parameter(Mandatory=$true)][string]$vid
    )
    $volume = Get-Volume -UniqueId $vid
    $path = $volume.Path.TrimEnd("\")
    $image = Get-DiskImage -DevicePath $path
    return (Verified-File -Path $image.ImagePath)
}

function Configured-ISO-Image-File {
    if (-not $IsoImage) {
	$IsoImage = (Get-ChildItem -Path ".\assets" -Recurse -Filter *.iso | Select-Object -First 1).FullName
    }
    return (Verified-File -Path $IsoImage)
}
    
function Get-ISO-Volumes {
    param (
	[switch] $match_image,
    	[switch] $require_none,
	[switch] $require_one,
    	[switch] $require_any
    )

    if ($match_image) {
	$match_iso = Configured-ISO-Image-File
    } else {
	$match_iso = $false
    }

    $volumes = (Get-Volume | Where-Object { ($_.DriveType -eq "CD-ROM") -and ($_.OperationalStatus -eq "OK") })
    if ($match_iso) {
	$volumes = ($volumes | Where-Object { (Get-Volume-ISO-File -vid $_.UniqueId) -eq $match_iso})
    }

    $count = ($volumes | Measure-Object).Count

    if ($require_none -and ($count -ne 0)) {
	Write-Error "Unexpected mounted ISO image detected"
    }

    if ($require_one -and ($count -ne 1)) {
	Write-Error "Multiple mounted ISO images detected"
    }

    if ($require_any -and ($count -eq 0)) {
	if ($match_iso) {
	    Write-Error "ISO image ${match_iso} is not mounted" 
	} else {
	    Write-Error "No mounted ISO images detected"
	}
    }
    return $volumes
}


function Mount-ISO {
    if (-not (Get-ISO-Volumes -match_image)) {
	Mount-DiskImage -ImagePath (Configured-ISO-Image-File)
    }
    Get-ISO-Volumes -match_image -require_one
}

function Dismount-ISO {
    Get-ISO-Volumes | ForEach-Object {
	Dismount-DiskImage -ImagePath (Get-Volume-ISO-File $_.UniqueId)
    }
    Get-ISO-Volumes -require_none
}

function Extract-WIM {
    param (
        [Parameter(Mandatory=$true)][string]$ISODrive,
        [Parameter(Mandatory=$true)][string]$USBDrive
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
}

function Get-USB-Devices {
    ForEach ($device in (Get-PnpDevice -Class USB | Where-Object { ($_.Status -eq "OK") })) {
	$device_vid=""
	$device_pid=""
	$vendor="unknown"
	$product="unknown"
	foreach ($field in $device.DeviceID -split '&') {
	    $code = $field -replace '^.*VID_([0-9a-fA-F]{4}).*$', '$1'
	    if ($code -Match "^[0-9a-fA-F]{4}$") {
		$device_vid = $code
	    }
	    $code = $field -replace '^.*PID_([0-9a-fA-F]{4}).*$', '$1'
	    if ($code -Match "^[0-9a-fA-F]{4}$") {
		$device_pid = $code
	    }

	}
	if ($device_vid -ne "") {
	    $vendor = (USB-Device-Decode -VendorId $device_vid -Vendor)
	    if ($device_pid -ne "") {
		$product = (USB-Device-Decode -VendorId $device_vid -ProductId $device_pid -Product)
	    }
	}

	if (
	    ($device_vid -ne "") -and 
	    ($device_pid -ne "") -and
	    ($device.Present) -and 
	    ($device.Status -eq "OK")
	) {
	    [PSCustomObject]@{
		"VID" = $device_vid
		"PID" = $device_pid
		"Name" = "${vendor} ${product}"
		"Type" = $device.FriendlyName
		"DeviceId" = $device.DeviceId
	    }
	}
    }
}

function Generate-XML-File {
    param (
	[string]$OutputPath = ".\autounattend.xml"
    )

    if (-not $hostname) {
	Write-Error "missing hostname (HOST environment var or -hostname command line option)"
    }
    
    $secrets_dir = Verified-Directory "$(Verified-Directory $secrets_root)\${hostname}"
    
    function Encoded {
	param (
	    [string]$Value
	)
	return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Value))
    }

    Class Macro{
	[string]$Name
	[String]$Value
	[string]$Suffix
	[String]$Raw
	[string]$Pattern 

	Macro([string]$Name, [string]$Value, [string]$Suffix) {
	    $this.Name = $Name
	    $this.Value = $Value
	    $this.Pattern = "__${Name}__"
	    if ($Name -eq "PRODUCT_KEY" ) {
		    $this.Pattern = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
	    } elseif ($Name -eq "ADMINISTRATOR_PASSWORD" ) {
		    $this.Raw = $Value
		    $this.Suffix = $Suffix
		    $this.Pattern = Encoded "__${Name}__${Suffix}"
		    $this.Value = Encoded "${Value}${Suffix}"
	    } elseif ($Name -eq "PASSWORD" ) {
		    $this.Raw = $Value
		    $this.Suffix = "Password"
		    $this.Pattern = Encoded "__${Name}__Password"
		    $this.Value = Encoded "${Value}Password"
	    }
	}
    }
		    
    $macros = New-Object System.Collections.Generic.List[Macro]
    Get-ChildItem -Path $secrets_dir -File | Where-Object { $_.Name -like "XML_*" } | ForEach-Object {
	$file = $_
	$macro = ($file.Name -replace "^XML_", "")
	$value = (Get-Content $file.FullName -TotalCount 1).Trim()
	if ($macro -eq "ADMINISTRATOR_PASSWORD") {
	    $macros.Add([Macro]::new($macro, $value, "Password"))
	    $macros.Add([Macro]::new($macro, $value, "AdministratorPassword"))
	} else {
	    $macros.Add([Macro]::new($macro, $value, ""))
	}
    }

    function Expanded {
	param (
	    [Parameter(Mandatory=$true)][string]$Line
	)
	# don't modify the comment line
	if ($Line -match "^\s*<!--.*-->$") {
	    return $Line
	}
	foreach ($macro in $macros) {
	    if ($Line -match $macro.Pattern) {
		$result = $Line -replace $macro.Pattern, $macro.Value
		Write-Host "Expanding $($macro.Name)"
		return $result
	    }
	}
	return $Line
    }

    (Get-Content -Path (Verified-File $xml_template) -Raw) -split "`n" | ForEach-Object { Expanded -Line $_ } | Set-Content -Path $OutputPath -Encoding ASCII
}


switch ($Command) {
    "build" {
	$target_disk = Get-Target-Disk -Name $TargetDiskName -Number $TargetDiskNumber
	Format-USB-Disk -DiskNumber $target_disk.Number
	Update-USB-Files -DiskNumber $target_disk.Number
    }
    "format" {
	$target_disk = Get-Target-Disk -Name $TargetDiskName -Number $TargetDiskNumber
	Format-USB-Disk -DiskNumber $target_disk.Number
    }
    "sync" {
	$target_disk = Get-Target-Disk -Name $TargetDiskName -Number $TargetDiskNumber
	$no_xml = $true
	$no_oem = $true
	Update-USB-Files -DiskNumber $target_disk.Number
    }
    "update" {
	$target_disk = Get-Target-Disk -Name $TargetDiskName -Number $TargetDiskNumber
	Update-USB-Files -DiskNumber $target_disk.Number
    }
    "mount-iso" {
	Mount-ISO 
    }
    "dismount-iso" {
	Dismount-ISO
    }
    "show-iso" {
	Get-ISO-Volumes -match_image
    }
    "is-iso-mounted" {
	if (Get-ISO-Volumes -match_image) { exit 0 } else { exit 1 }
    }
    "iso-drive" {
	(Get-ISO-Volumes -match_image -require_one).DriveLetter
    }
    "lsusb" {
	Get-USB-Devices | Format-Table | Out-Host
    }
    "generate" {
	Generate-XML-File
    }
    "help" {
	Write-Host "Commands: build format sync update mount-iso dismount-iso show-iso is-iso-mounted iso-drive help"
    }
    default {
	Write-Error "unexpected command: ${Command}"
    }
}



