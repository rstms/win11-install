
$logfile="c:\users\public\rstms\bootstrap.log"
$script="$([System.IO.Path]::GetFileName($MyInvocation.MyCommand.Path))"
echo "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $script begin" | Add-Content -Path $logfile

echo "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $script installing anydesk" | Add-Content -Path $logfile
cd C:\users\public\rstms
msiexec /package "c:\users\public\rstms\reliance-anydesk-client.msi" /passive /norestart /l* "c:\users\public\rstms\anydesk-install.log"
echo "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $script anydesk installed" | Add-Content -Path $logfile

echo "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $script installing winhance" | Add-Content -Path $logfile
c:\users\public\rstms\Winhance.Installer.exe /NOICONS /ALLUSERS /SILENT
echo "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $script winhance installed" | Add-Content -Path $logfile

echo "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $script end; rebooting" | Add-Content -Path $logfile
echo "restarting in 5 seconds..."
shutdown /r /f /t 005
