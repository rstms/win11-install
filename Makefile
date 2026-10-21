# win11 custom setup USB makefile

psh = dotenv powershell.exe -ExecutionPolicy RemoteSigned '.\build-usb-installer.ps1'

winiso := $(shell find assets -type f -name *.iso | head -1)
oem_dir = assets/oem/Users/Public/rstms
hostname := $(shell awk <.env -F= '/^HOST=/{print $$2}')

oem_filenames = \
  Winhance.Installer.exe \
  bootstrap.cmd \
  customize.winhance \
  reliance-anydesk-client.msi \
  update-anydesk.lnk \
  update-anydesk.ps1

oem_files = $(foreach f,$(oem_filenames),$(oem_dir)/$(f))
secrets_files = $(wildcard secrets/$(hostname)/*)

default:
	@echo
	@echo Targets:
	@echo
	@echo format - select target USB and format
	@echo sync - sync target USB filesystems with source ISO
	@echo update - customize target USB with autounattend.xml and OEM directory
	@echo
	@echo iso=$(winiso)
	@echo hostname=$(hostname)

lsusb:
	@$(psh) lsusb

generate:
	$(psh) generate

build: format update

rebuild:
	$(psh) build

.usb_formatted: .iso_mounted
	$(psh) format
	@touch $@

reformat: 
	$(psh) format
	@touch .usb_formatted

format: .usb_formatted

sync: .usb_formatted
	$(psh) sync -no_oem -no_xml

update: .usb_formatted assets/template.xml $(oem_files)
	$(psh) update

dist/win11-install-$(hostname).iso: assets/template.xml $(oem_files)
	$(psh) write-iso

iso: dist/win11-install-$(hostname).iso

.iso_mounted: $(winiso)
	$(psh) mount-iso
	@touch $@

mount: .iso_mounted

umount:
	$(psh) dismount-iso -quiet || true
	rm -f .iso_mounted

show:
	@$(psh) show-iso

$(winiso):
	mkdir -p $(dir $(winiso))
	scp rigel:iso/$(notdir $(winiso)) .
	$(ps) -c 'Unblock-File -LiteralPath ".\$@"'
	$(ps) -c 'Get-FileHash -LiteralPath ".\$@"'

$(oem_dir)/reliance-anydesk-client.msi:
	mkdir -p $(oem_dir)
	scp beaker:$$(ssh beaker ls -t Downloads/anydesk*.msi | head -1) $@

$(oem_dir)/Winhance.Installer.exe:
	mkdir -p $(oem_dir)
	curl -L https://github.com/memstechtips/Winhance/releases/latest/download/Winhance.Installer.exe -o $@

$(oem_dir)/bootstrap.cmd:
	mkdir -p $(oem_dir)
	echo >'$@' 'cd C:\users\public\rstms'
	echo >>'$@' 'msiexec /package c:\users\public\rstms\reliance-anydesk-client.msi /passive'
	echo >>'$@' 'c:\users\public\rstms\Winhance.Installer.exe /NOICONS /ALLUSERS /SILENT'
	#echo >>'$@' 'winget install --silent Microsoft.Sysinternals.PsTools'
	echo >>'$@' 'shutdown /r /f /t 000'

template-keys:
	@sed -n <assets/template.xml 's/^.*\(__[^_].*[^_]__\).*$$/\1/p'

clean: umount
	rm -f .iso_mounted .usb_formatted assets/oem/bootstrap.cmd assets/autounattend.xml

sterile: clean
	rm -f $(winiso) assets/oem/reliance-anydesk-client.msi assets/oem/Winhance.Installer.exe  
	rm -rf assets/staging assets/wim dist

