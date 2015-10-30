Import-Module ServerManager
$CustPrefix = Read-Host "Please Enter the customer prefix for the machine hostnames, e.g. FT for Flint, PS for plimsoll etc"
$SQLName = $CustPrefix + "-SQL-1"
$WSName = $CustPrefix + "-WS-1"
$TheHost = Hostname
$WorkgroupName = Read-Host “Please enter the workgroup you would like this computer to be added to (Type FLINT for default)” 
#$NewName = Read-Host ‘The current hostname is ‘ $TheHost ‘ Please Enter the new Hostname’
$NewName = $CustPrefix + "-VHST-1"

#Set Computer Name
Rename-Computer -ComputerName $TheHost -NewName $NewName

#Add to Workgroup
Add-Computer -WorkgroupName $workgroupName -Force

#Enable remote desktop
set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server'-name "fDenyTSConnections" -Value 0
set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -name "UserAuthentication" -Value 1   

#Set Custom RDP port
Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\Terminal*Server\WinStations\RDP-TCP\ -Name PortNumber -Value 62323

#change CDROM drive to :z
(gwmi Win32_cdromdrive).drive | %{$a = mountvol $_ /l;mountvol $_ /d;$a = $a.Trim();mountvol z: $a}

#Initialize Disks
Get-Disk | Where partitionstyle -eq 'raw' | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -Confirm:$false

#Create loc_admin user and add as administrator
$HostName = hostname
$computername =$HostName   # place computername here for remote access
$username = 'loc_admin'
$password = 'K1ng0fB33r$'
$desc = 'local admin account'

$computer = [ADSI]"WinNT://$computername,computer"
$user = $computer.Create("user", $username)
$user.SetPassword($password)
$user.Setinfo()
$user.description = $desc
$user.setinfo()
$user.UserFlags = 65536
$user.SetInfo()
$group = [ADSI]("WinNT://$computername/administrators,group")
$group.add("WinNT://$username,user")

#Create scripts folder
mkdir C:\Scripts

#Disable IE Enhanced security
function Disable-IEESC
{
$AdminKey = “HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}”
$UserKey = “HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}”
Set-ItemProperty -Path $AdminKey -Name “IsInstalled” -Value 0
Set-ItemProperty -Path $UserKey -Name “IsInstalled” -Value 0
Stop-Process -Name Explorer
Write-Host “IE Enhanced Security Configuration (ESC) has been disabled.” -ForegroundColor Green
}
Disable-IEESC


#install choclatey
iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))


#Open Common Firewall Ports
New-NetFirewallRule -DisplayName “SNMP” -Direction Inbound –Protocol UDP –LocalPort 161 -Action allow
New-NetFirewallRule -DisplayName “Custom RDP” -Direction Inbound –Protocol TCP –LocalPort 62323 -Action allow
New-NetFirewallRule -DisplayName “FTP” -Direction Inbound –Protocol TCP –LocalPort 21 -Action allow
New-NetFirewallRule -DisplayName “FTP PSV” -Direction Inbound –Protocol TCP –LocalPort 7600-7700 -Action allow
New-NetFirewallRule -DisplayName “Ping” -Direction Inbound –Protocol icmpv4 -Action allow -enabled True
New-NetFirewallRule -DisplayName “WinRM” -Direction Inbound –Protocol TCP –LocalPort 5985 -Action allow
netsh advfirewall firewall set rule group="windows management instrumentation (wmi)" new enable=yes

#Set up remote powershell
Enable-PSRemoting -Force
winrm s winrm/config/client '@{TrustedHosts="PC-CSTM-1"}'
winrm s winrm/config/client '@{TrustedHosts="2012-MON-2"}'

#Install Common Windows Features
Import-Module ServerManager
Install-WindowsFeature -Name SNMP-Service -IncludeAllSubFeature
Install-WindowsFeature -Name RSAT-SNMP
Install-WindowsFeature -Name AS-NET-Framework 
Install-WindowsFeature -Name Web-Asp-Net


#Pause to make sure  disks are online
Write-Host "Hyper-V installation will now commence.  Please check all your disks are configured and online.  Press any key to continue ..." -ForegroundColor Green
pause

#
#
##
###HYPER V CONFIGURATION
Install-WindowsFeature Hyper-V -IncludeManagementTools

#Pin Hyper-V manager to taskbar
$sa = new-object -c shell.application
$pn = $sa.namespace('C:\Windows\System32').parsename('virtmgmt.msc')
$pn.invokeverb('taskbarpin')

Import-Module Hyper-V
#Create External switch and internal LAN switch for VMs
$Ethernet = Get-NetAdapter -Name Ethernet
New-VMSwitch -Name ExternalSwitch -NetAdapterName $Ethernet.Name -AllowManagementOS $true -Notes 'External Facing Switch'
New-VMSwitch -Name InternalLAN -SwitchType Private -Notes 'LAN for VMs'

#Create scripts & VHDs folders
mkdir E:\VHDs, c:\ISOs, D:\VHDs

$CustPrefix = Read-Host "Please Enter the customer prefix for the machine hostnames, e.g. FT for Flint, PS for plimsoll etc"

#Create SQL VM
$SQLName = $CustPrefix + "-SQL-1"
$SQLC = "D:\VHDs\" +  $SQLName + "\" + $SQLName + "-C.vhdx"
$SQLD = "D:\VHDs\" +  $SQLName + "\" + $SQLName + "-D-Data.vhdx"
$SQLE = "D:\VHDs\" +  $SQLName + "\" + $SQLName + "-E-Logs.vhdx"
$SQLMAC = Read-Host "Please Enter the Static MAC Address for the SQL Server"

New-VHD -Path $SQLC -Dynamic -SizeBytes 120000000000
New-VHD -Path $SQLD -Dynamic -SizeBytes 200000000000
New-VHD -Path $SQLE -Dynamic -SizeBytes 200000000000
New-VM –Name $SQLName –MemoryStartupBytes 1GB –VHDPath $SQLC
Connect-VMNetworkAdapter –VMName $SQLName –Switchname "ExternalSwitch"
ADD-VMNetworkAdapter –VMName $SQLName –Switchname "InternalLAN"
SET-VMProcessor –VMName $SQLName –Count 2
Set-VMMemory -VMName $SQLName -DynamicMemoryEnabled $True
ADD-VMHardDiskDrive -VMName $SQLName -Path $SQLD
ADD-VMHardDiskDrive -VMName $SQLName -Path $SQLE
Get-VMNetworkAdapter -VMName $SQLName | Where-Object {$_.SwitchName -like "ExternalSwitch"} | Set-VMNetworkAdapter -StaticMacAddress $SQLMAC

#Create Web Server VM
$WSName = $CustPrefix + "-WS-1"
$WSC = "D:\VHDs\" +  $WSName + "\" + $WSName + "-C.vhdx"
$WSD = "D:\VHDs\" +  $WSName + "\" + $WSName + "-D-Data.vhdx"
$WSMAC = Read-Host "Please Enter the Static MAC Address for the webserver"

New-VHD -Path $WSC -Dynamic -SizeBytes 120000000000
New-VHD -Path $WSD -Dynamic -SizeBytes 200000000000
New-VM –Name $WSName –MemoryStartupBytes 1GB –VHDPath $WSC
Connect-VMNetworkAdapter –VMName $WSName -Name "External" –Switchname "ExternalSwitch" -StaticMacAddress "020000192ec7"
ADD-VMNetworkAdapter –VMName $WSName –Switchname "InternalLAN"
SET-VMProcessor –VMName $WSName –Count 2
Set-VMMemory -VMName $WSName -DynamicMemoryEnabled $True
ADD-VMHardDiskDrive -VMName $WSName -Path $WSD
Get-VMNetworkAdapter -VMName $WSName | Where-Object {$_.SwitchName -like "ExternalSwitch"} | Set-VMNetworkAdapter -StaticMacAddress $WSMAC

#Install Common Applications
choco install GoogleChrome -y
choco install filezilla -y
choco install notepadplusplus -y
choco install spacesniffer -y
choco install filezilla.server -y

#Create and disable a Reboot Scheduled Task
$action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\shutdown.exe' -Argument '/r'
$trigger =  New-ScheduledTaskTrigger -Once -At 10pm
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "Reboot" -Description "Reboot scheduled task" -User $username -Password $password
Disable-ScheduledTask -TaskName "Reboot"

#Create Scheduled Task to turn on the firewall daily
"Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True" > C:\Scripts\Firewall_On.ps1

$action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument 'C:\Scripts\Firewall_On.ps1'
$trigger =  New-ScheduledTaskTrigger -Daily -At 10pm
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "FirewallOnTest" -Description "Turn On Firewall" -User $username -Password $password

#Disable Server Manager on login
Disable-ScheduledTask -TaskPath ‘\Microsoft\Windows\Server Manager\’ -TaskName ‘ServerManager’

Set-NetFirewallProfile -Name "Public" -Enabled True

#Reboot
shutdown /r /t 05
echo "Rebooting...."
