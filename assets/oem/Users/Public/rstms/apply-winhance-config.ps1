
# apply winhance config

param (
    [string]$Command = "help"
)

$ErrorActionPreference = "Stop"

$scriptName ="$([System.IO.Path]::GetFileName($MyInvocation.MyCommand.Path))"
$cfgDir = "c:\users\public\rstms"
$logFile = "${cfgDir}\winhance.log"

$autobot = "${cfgDir}\autobot.exe"
$winscrape = "${cfgDir}\winscrape.exe"
$configAppliedTimeout = 300
$global:stdout = ""

function Write-Log {
    param (
	[string]$message
    )
    if (-not ($message -eq "")) {
	$message | Write-Host
    }
    echo "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") ${scriptName} ${message}" | Add-Content -Path $logFile
}

function Log-Error {
    param (
	[string]$Message
    )
    Write-Log "Error: $Message"
    Write-Error $Message
}

function Run-Program {
    param (
	[string]$Executable,
	[string]$Arguments,
	[bool]$FailOK=$false,
	[bool]$Quiet=$false
    )
    
    if (-not $Quiet) {
	Write-Log "executing: ${Executable} ${Arguments}"
    }
    $tempFile = [System.IO.Path]::GetTempFileName()
    $proc = Start-Process -FilePath $Executable -ArgumentList $Arguments -PassThru -NoNewWindow -RedirectStandardOutput $tempFile
    $handle = $proc.Handle
    $proc.WaitForExit()
    #Write-Log "exitCode=$($proc.ExitCode)"
    if ($proc.ExitCode -eq $null) {
	Log-Error "NULL ExitCode"
    }
    $global:stdout = Get-Content -Path $tempFile | ForEach-Object {
	[System.Text.Encoding]::ASCII.GetString([System.Text.Encoding]::ASCII.GetBytes($_))
    }
    Remove-Item -Path $tempFile -Force
    if ( -not $Quiet ) {
	foreach ($line in $global:stdout) {
	    Write-Log "$line"
	}
    }
    if ("$($proc.Stderr)" -ne "") {
	Write-Error "$($proc.Stderr)"
    }
    if ($proc.ExitCode -eq 0 ) {
	return $true
    }
    if ($FailOk -and ($proc.ExitCode -eq 1)) {
	return $false
    }
    Log-Error "${Executable} failed with exit code $($proc.ExitCode)"
}

function Auto-Bot {
    param (
	[string]$Arguments,
	[switch]$FailOK,
	[switch]$Quiet
    )
    return Run-Program $autobot -Arguments $Arguments -Quiet $Quiet -FailOk $FailOk
}

function Find-Installed-Binary {
    param (
	[Parameter(Mandatory=$true)][string]$dirName,
	[Parameter(Mandatory=$true)][string]$exeName
    )
    $paths = @(
        "${env:ProgramFiles}\$dirName\$exeName",
        "${env:ProgramFiles(X86)}\$dirName\$exeName",
        "${env:LOCALAPPDATA}\$dirName\$exeName"
    )
    foreach ($path in $paths) {
        if (Test-Path -Path $path) {
            return $path
        }
    }
    Write-Error "Not found: $exeName"
}

function Start-Winhance {

    Write-Log "starting winhance..."
    $winhanceProc = Start-Process -FilePath $winhance -PassThru

    Write-Log "winhance started as pid $winhanceProc.Id"

    Auto-Bot "window wait present Winhance"

    Wait-Winhance-Idle
    Handle-Popups
}

function Wait-Winhance-Idle {
    Auto-Bot "window wait idle Winhance -v --timeout 300 --interval-ms 1000 --threshold-percent 0.2 --duration-ms 5000"
}

function Stop-Winhance {
    if (Auto-Bot "window present Winhance" -FailOk) {

	Handle-Open-Configuration

	Write-Log "Closing Winhance..."
	Auto-Bot "scan -w title=Winhance --close"

	Handle-Popups

	Auto-Bot "window wait absent Winhance"
    } else {
	Write-Log "Winhance is not running"
    }
}

function Handle-Popups {
    $count = 0
    $maxCount = 5
    while ( $count < $maxCount ) {
	$handled = $false
	if (Handle-Open-Configuration) { 
	    $handled = $true
	}
	if (Handle-Contributors-Popup) {
	    $handled = $true
	}
	if (Handle-System-Protection-Popup) {
	    $handled = $true
	}
	if (Handle-Support-Popup) {
	    $handled = $true
	}
	if ($handled) {
	    $count = 0
	} else {
	    $count = $count + 1
	    Sleep 1
	}
    }
}

function Handle-Contributors-Popup {
    if ( Auto-Bot "window elements Winhance -e type=WindowControl -e text=Popup" -FailOk) {
	Write-Log "detected contributors popup"
	if ( Auto-Bot "window elements Winhance -e type=TextControl -e depth=6 -e text=`"/Winhance is free .* and always will be/`"" -FailOk) {
	    Auto-Bot "scan -w title=Winhance -e depth=6 -e type=CheckBoxControl -e text=`"/Don.t show this again/`" --set-on"
	    Write-Log "Clicking Contributors exit window"
	    Auto-Bot "element click Winhance -e depth=5 -e type=ButtonControl -e text=Exit" 
	    return $true
	}
    }
    return $false
}


function Handle-System-Protection-Popup {
    if ( Auto-Bot "window elements Winhance -e type=WindowControl -e text=`"System Protection`"" -FailOk) {
	if ( Auto-Bot "window elements Winhance -e type=TextControl -e depth=6 -e text=`"/Welcome to Winhance. Before making any changes.*/`"" -FailOk) {
	    Write-Log "Clicking Create Restore Point"
	    Auto-Bot "element click Winhance -e depth=5 -e type=ButtonControl -e text=`"Create Restore Point`""
	    return $true
	}
    }
    return $false
}

function Handle-Support-Popup {
    if (Auto-Bot "window elements Winhance -e type=WindowControl -e text=`"Support Winhance`"" -FailOk) {
	Auto-Bot "scan -w title=Winhance -e depth=6 -e type=CheckBoxControl -e text=`"/Don.t show this again/`" --set-on"
	Write-Log "Clicking Support Popup"
	Auto-Bot "element click Winhance -e depth=5 -e type=ButtonControl -e text=No"
	return $true
    }
    return $false
}

function Handle-Open-Configuration { 
    if (Auto-Bot "window elements Winhance -e depth=2 -e type=WindowControl -e text=`"Open Configuration`"" -FailOk) {
	Write-Log "Open Configuration Window detected"
	Auto-Bot "element click Winhance -e depth=3 -e type=ButtonControl -e text=Cancel"
	return $true
    }
    return $false
}

function Import-File {
    param (
	[string]$File,
	[string]$Action
    )
    $confirmLabel="undefined"

    switch ($Action) {
	"Install" {
	    $confirmLabel = "Installation"
	}
	"Uninstall" { 
	    $confirmLabel = "Removal"
	}
	default: {
	    Write-Error "Unexpected action: $Action"
	}
    }

    Stop-Winhance 
    Start-Winhance

    Write-Log "Awaiting settings button presence..."
    Auto-Bot "element wait present Winhance -e depth=5 -e type=ButtonControl -e text=Settings"

    Write-Log "Clicking Settings..."
    Auto-Bot "element click Winhance -e depth=5 -e type=ButtonControl -e text=Settings"

    Write-Log "Clicking Import..."
    Auto-Bot "element click Winhance -e depth=7 -e type=ButtonControl -e text=Import"

    Write-Log "Verifying 'Import Config' dialog..."
    Auto-Bot "window elements Winhance -e type=WindowControl -e text=`"Import Config`""

    Write-Log "Clicking 'Import my own config...'"
    Auto-Bot "element click Winhance -e type=ButtonControl -e depth=7 -e text=`"/^Import my own config.*/`""

    Write-Log "Setting import options..."
    Auto-Bot "scan -w title=Winhance -e depth=7 -e type=CheckBoxControl -e text=`"Skip review and apply immediately`" --set-on"
    Auto-Bot "element click Winhance -e depth=7 -e type=RadioButtonControl -e text=`"Windows Apps:: ${Action}`""
    Auto-Bot "element click Winhance -e depth=7 -e type=RadioButtonControl -e text=`"External Apps:: ${Action}`""
    Auto-Bot "scan -w title=Winhance -e depth=7 -e type=CheckBoxControl -e text=`"Apply default wallpaper for theme`" --set-on"
    Auto-Bot "scan -w title=Winhance -e depth=7 -e type=CheckBoxControl -e text=`"Clean Taskbar`" --set-on"
    Auto-Bot "scan -w title=Winhance -e depth=7 -e type=CheckBoxControl -e text=`"Clean Start Menu`" --set-on"
    Auto-Bot "element click Winhance -e depth=5 -e type=ButtonControl -e text=`"Continue`""

    Auto-Bot "window wait present Winhance -e depth=2 -e type=WindowControl -e text=`"Open Configuration`""
    Auto-Bot "element wait present Winhance -e depth=5 -e type=EditControl -e text=`"File name:`""

    Auto-Bot "scan -w title=Winhance -e depth=5 -e type=EditControl -e text=`"File name:`" --set --value `"${File}`""

    Auto-Bot "element click Winhance -e depth=3 -e type=SplitButtonControl -e text=Open"

    if ( $Action -eq "Install" ) {
	Wait-Configuration-Applied
    }

    Wait-Confirm-Action $confirmLabel

    if ( $action -eq "Uninstall" ) {
	Wait-Configuration-Applied
    }

    Wait-Configuration-Complete
}

function Wait-Configuration-Applied {
	Auto-Bot "element wait present Winhance -e depth=4 -e type=WindowControl -e text=`"Configuration Applied`" --timeout `"${configAppliedTimeout}`""

	Auto-Bot "element click Winhance -e depth=5 -e type=ButtonControl -e text=OK"
}

function Wait-Confirm-Action {
    param (
	[string]$label
    )
    Auto-Bot "element wait present Winhance -e type=WindowControl -e text=`"Confirm ${label}`""
    Auto-Bot "window elements Winhance -e depth=7 -e type=ListItemControl -f fields=text"
    Auto-Bot "element click Winhance -e depth=5 -e type=ButtonControl -e text=Continue"
}

function Wait-Configuration-Complete {
    $result = Auto-Bot "window elements Winhance -e class=InputSiteWindowClass -f fields=id -f header=0" -Quiet
    $wid = $stdout
    #Write-Log "winbotId=${wid}"
    $complete = $false
    $lastLine = ""
    $lastProgress = ""
    $emptyCount = 0
    $emptyLimit = 10
    while (-not $complete) {
	# Auto-Bot "window elements Winhance -e parent=${wid} -e type=TextControl -f fields=text -e text=`"/[a-zA-Z0-9]/`""
	$count = 0
	$result = Auto-Bot "window elements Winhance -e depth=4 -e type=TextControl -f fields=text -e text=`"/[a-zA-Z0-9]/`" -f header=0" -Quiet -FailOk
	#Write-Log "---BEGIN---"
	foreach ($line in $stdout) {
	    switch($line) {
		{ $_ -eq 'Winhance' } { break }
		{ $_ -eq 'by Memory' } { break }
		{ $_ -eq 'Manage Windows Apps and Install Software' } { break }
		{ $_ -eq 'Software & Apps' } { break }
		{ $_ -eq 'Winhance Mode' } { break }
		{ $_ -eq 'Winhance Settings' } { break }
		{ $_ -eq 'Configure Winhance Application Preferences' } { break }
		{ $_ -match '^Next:.*' } { break }
		{ $_ -eq '' } { break }
		default {
		    $emptyCount = 0
		    $count = $count + 1 
		    if ( $line -match '^[0-9]+ / [0-9]+' ) {
			$progress = $line
			if ( $progress -ne $lastProgress) {
			    $lastProgress = $progress
			}
		    } else {
			if ( $line -ne $lastLine ) {
			    Write-Log "${progress} ${line}"
			    $lastLine = $line
			    Handle-Powershell-Windows
			}
		    }
		}
	    }
	}
	#Write-Log "---END---"
	if ($count -eq 0 ) {
	    $emptyCount = $emptyCount + 1
	}
	if ($emptyCount -gt $emptyLimit ) {
	    $complete = $true
	}
	sleep 1
    }
    Handle-Powershell-Windows
}

function Handle-PowerShell-Windows {
    $ret = Auto-Bot "window list -w title=`"/.*Administrator.*Windows PowerShell.*/`" -f fields=id -f header=0" -Quiet -FailOk
    foreach ($id in $stdout) {
	Close-Completed-PowerShell $id
    }
}

function Close-Completed-PowerShell {
    param (
	[string]$id
    )
    Auto-Bot "scan -w id=${id} -e type=ButtonControl -e text=Restore --click --no-focus" -FailOk
    Auto-Bot "scan -w id=${id} -e type=ButtonControl -e text=Maximize --click --no-focus"
    Auto-Bot "scan -w id=${id} -e type=PaneControl -e text=`"/.*Window.*/`" --set-focus"
    Run-Program -Executable $winscrape "text root" -Quiet $true
    $psout = $stdout
    if ( $psout -match '.*Press Enter to continue...:' ) {
	Write-Log "---BEGIN POWERSHELL OUTPUT---"
	foreach ($line in $psout ) {
	    Write-Log "${line}"
	}
	Write-Log "---END POWERSHELL OUTPUT---"
	#Auto-Bot "scan -w id=${id} -e type=CustomControl --set-focus"
	Auto-Bot "element send `"<enter>`" -w id=${id} -e type=CustomControl --no-activate"
    } else {
	Auto-Bot "scan -w id=${id} -e type=ButtonControl -e text=Restore --click --no-focus"
    }
}

try {
    Write-Log "executing ${Command}"	
    cd $cfgDir
    $winhance = Find-Installed-Binary Winhance Winhance.exe

    switch ($Command) {
	"close" {
	    Handle-Powershell-Windows
	}
	"wait" {
            Wait-Configuration-Complete
	}
	"install" {
            Import-File "${cfgDir}\install.winhance" -Action "Install"
	}
	"remove" {
            Import-File "${cfgDir}\remove.winhance" -Action "Uninstall"
	}
	"help" {
	    Write-Log "Commands: remove install help"
	}
	default {
	    Log-Error "unexpected command: ${Command}"
	}
    }
} finally {
    Write-Log "exiting ${Command}"
}
