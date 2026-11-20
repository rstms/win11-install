$logfile="c:\users\public\rstms\bootstrap.log"
$script="$([System.IO.Path]::GetFileName($MyInvocation.MyCommand.Path))"
echo "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $script begin" | Add-Content -Path $logfile

echo "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") $script end" | Add-Content -Path $logfile
