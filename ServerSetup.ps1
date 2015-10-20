Import-Module ServerManager
Set-ExecutionPolicy RemoteSigned -force

$TheHost = Hostname
$WorkgroupName = Read-Host “Please enter the workgroup you would like this computer to be added to”
$NewName = Read-Host ‘The current hostname is ‘ $TheHost ‘ Please Enter the new Hostname’


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

#Create developers user and add as administrator
$HostName = hostname
$computername =$HostName   # place computername here for remote access
$username = 'developers'
$password = 'Pixar/Emper0r/Zurg?'
$desc = 'Developer account'

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

#Install Common Windows Features
Import-Module ServerManager
Install-WindowsFeature -Name SNMP-Service -IncludeAllSubFeature
Install-WindowsFeature -Name RSAT-SNMP
Install-WindowsFeature -Name AS-NET-Framework 
Install-WindowsFeature -Name Web-Asp-Net
Install-WindowsFeature -Name Telnet-Client


#Install Common Applications
choco install GoogleChrome -y
choco install filezilla.server -y
choco install filezilla -y
choco install notepadplusplus -y
#choco install duplicati -y
choco install clamwin -y

#Create scripts folder
mkdir C:\Scripts

#Install IIS with Web Deploy
$message  = 'something'
$question = 'Would You like to install IIS?'

$choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
$choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
$choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

$decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
if ($decision -eq 0) {
  Install-WindowsFeature -Name Web-Server -IncludeAllSubFeature -Confirm
  Install-WindowsFeature -Name Web-Mgmt-Tools -IncludeAllSubFeature -Confirm
  Remove-WindowsFeature -Name Web-Ftp-Server
  choco install webdeploy -y
  choco install hmailserver -y

  #Add Firewall Rules
  New-NetFirewallRule -DisplayName “HTTP” -Direction Inbound –Protocol TCP –LocalPort 80 -Action allow
  New-NetFirewallRule -DisplayName “HTTPS” -Direction Inbound –Protocol TCP –LocalPort 443 -Action allow
  New-NetFirewallRule -DisplayName “SMTP” -Direction Inbound –Protocol TCP –LocalPort 25 -Action allow

  mkdir D:\Web\Sites

} 

#EXPERIMENTAL -- Set Duplicati scheduled task
$TheString = '"C:\Program Files\Duplicati\duplicati.commandline" backup --full-if-more-than-n-incrementals=14 --auto-cleanup --no-encryption "D:\Web" "ftp://flintuser:WDkkiEEIXYVdDp0ukyrT@FS-DR-1.flintstudios.net/' + $NewName + '" > C:\Scripts\log.txt && "C:\Program Files\Duplicati\duplicati.commandline"  delete-older-than 14D --force --no-encryption "ftp://flintuser:WDkkiEEIXYVdDp0ukyrT@fs-dr-1.flintstudios.net/' + $NewName + '"'
New-Item C:\Scripts\DuplicatiCmd.bat -ItemType file -Value $TheString
$action = New-ScheduledTaskAction -Execute 'C:\Scripts\DuplicatiCmd.bat' 
$trigger =  New-ScheduledTaskTrigger -Daily -At 11pm
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "Nightly Backups" -Description "Automated Duplicati Backups" -User $username -Password $password

#Create and disable a Reboot Scheduled Task
$action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\shutdown.exe' -Argument '/r'
$trigger =  New-ScheduledTaskTrigger -Once -At 10pm
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "Reboot" -Description "Reboot scheduled task" -User $username -Password $password
Disable-ScheduledTask -TaskName "Reboot"

Set-NetFirewallProfile -Name "Public" -Enabled True

#Reboot
shutdown /r /t 05
echo "Rebooting...."
