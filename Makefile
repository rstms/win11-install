# win11 custom setup USB makefile

winiso = Win11_25H2_English_x64_v2.iso

oem_dir = oem/$$1/Users/Public/rstms
ps = powershell.exe -ExecutionPolicy RemoteSigned 
psrun = $(ps) '.\$(1)' $(2)

installers = \
	$(oem_dir)/reliance-anydesk-client.msi \
	$(oem_dir)/Winhance.Installer.exe \
	$(oem_dir)/bootstrap.cmd \
	$(oem_dir)/customize.winhance

default:
	@echo
	@echo Targets:
	@echo
	@echo format - write bootable USB installer image
	@echo update - rewrite USB $OEM$ directory and autounattend.xml
	@echo


oem: $(installers)

$(oem_dir):
	mkdir -p '$(oem_dir)'

autounattend.xml: template.xml
	./generate-xml <$< >$@

build: format image update

format:	.iso_mounted
	./format-usb

image: .iso_mounted 
	./image-usb

update: autounattend.xml oem
	./update-usb

.iso_mounted: $(winiso)
	$(call psrun,iso.ps1,-Mount -Drive) >$@

mount: .iso_mounted

umount:
	$(call psrun,iso-drive.ps1,) && $(call psrun,iso.ps1,-Dismount) || true
	rm -f .iso_mounted

show:
	$(call psrun,iso.ps1,-Show)

$(winiso):
	scp rigel:iso/$(winiso) .
	$(ps) -c 'Unblock-File -LiteralPath ".\$@"'
	$(ps) -c 'Get-FileHash -LiteralPath ".\$@"'

$(oem_dir)/reliance-anydesk-client.msi: $(oem_dir)
	scp rigel:reliance-anydesk-client.msi '$@'

$(oem_dir)/Winhance.Installer.exe: $(oem_dir)
	curl -L https://github.com/memstechtips/Winhance/releases/latest/download/Winhance.Installer.exe -o '$@'

$(oem_dir)/bootstrap.cmd: $(oem_dir)
	echo >'$@' 'cd C:\users\public\rstms'
	echo >>'$@' 'msiexec /package c:\users\public\rstms\reliance-anydesk-client.msi /passive'
	echo >>'$@' 'c:\users\public\rstms\Winhance.Installer.exe /NOICONS /ALLUSERS /SILENT'
	echo >>'$@' 'winget install Microsoft.Sysinternals.PsTools'
	echo >>'$@' 'psshutdown -nobanner -t 3 -r'

$(oem_dir)/customize.winhance: $(oem_dir)
	cp $(notdir $@) '$@'

clean: umount
	rm -f autounattend.xml .iso_mounted

sterile: clean
	rm -f $(winiso)
	rm -rf oem 
