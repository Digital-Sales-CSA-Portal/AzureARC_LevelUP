$Env:ArcBoxDir = "C:\ArcBox"
$Env:ArcBoxLogsDir = "$Env:ArcBoxDir\Logs"
$Env:ArcBoxVMDir = "$Env:ArcBoxDir\Virtual Machines"
$agentScript = "$Env:ArcBoxDir\agentScript"

Start-Transcript -Path $Env:ArcBoxLogsDir\ArcServersLogonScript.log

# Required for CLI commands
az login --service-principal --username $env:spnClientID --password $env:spnClientSecret --tenant $env:spnTenantId

# Register Azure providers
az provider register --namespace Microsoft.HybridCompute --wait
az provider register --namespace Microsoft.GuestConfiguration --wait
az provider register --namespace Microsoft.AzureArcData --wait

# Install and configure DHCP service (used by Hyper-V nested VMs)
Write-Output "Configure DHCP service"
$dnsClient = Get-DnsClient | Where-Object {$_.InterfaceAlias -eq "Ethernet" }
Add-DhcpServerv4Scope -Name "ArcBox" -StartRange 10.10.1.100 -EndRange 10.10.1.200 -SubnetMask 255.0.0.0 -State Active
Add-DhcpServerv4ExclusionRange -ScopeID 10.10.1.0 -StartRange 10.10.1.101 -EndRange 10.10.1.120
Set-DhcpServerv4OptionValue -DnsDomain $dnsClient.ConnectionSpecificSuffix -DnsServer 168.63.129.16
Set-DhcpServerv4OptionValue -OptionID 3 -Value 10.10.1.1 -ScopeID 10.10.1.0
Set-DhcpServerv4Scope -ScopeId 10.10.1.0 -LeaseDuration 1.00:00:00
Set-DhcpServerv4OptionValue -ComputerName localhost -ScopeId 10.10.10.0 -DnsServer 8.8.8.8
Restart-Service dhcpserver

# Create the NAT network
Write-Output "Create internal NAT"
$natName = "InternalNat"
New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix 10.10.0.0/16

# Create an internal switch with NAT
Write-Output "Create internal switch"
$switchName = 'InternalNATSwitch'
New-VMSwitch -Name $switchName -SwitchType Internal
$adapter = Get-NetAdapter | Where-Object { $_.Name -like "*"+$switchName+"*" }

# Create an internal network (gateway first)
Write-Output "Create gateway"
New-NetIPAddress -IPAddress 10.10.1.1 -PrefixLength 24 -InterfaceIndex $adapter.ifIndex

# Enable Enhanced Session Mode on Host
Write-Output "Enable Enhanced Session Mode"
Set-VMHost -EnableEnhancedSessionMode $true

$sourceFolder = 'https://jumpstart.blob.core.windows.net/v2images'
$sas = "?sp=rl&st=2022-01-27T01:47:01Z&se=2025-01-27T09:47:01Z&spr=https&sv=2020-08-04&sr=c&sig=NB8g7f4JT3IM%2FL6bUfjFdmnGIqcc8WU015socFtkLYc%3D"
$Env:AZCOPY_BUFFER_GB=4

$fileList = (
    'ArcBox-Ubuntu-01.vhdx',
    'ArcBox-Ubuntu-02.vhdx',
    'ArcBox-Win2K19.vhdx',
    'ArcBox-Win2K22.vhdx'
)



azcopy cp $sourceFolder/*$sas $Env:ArcBoxVMDir --include-path ($fileList -Join ';') --check-length=false --log-level=ERROR

# Create the nested VMs
Write-Output "Create Hyper-V VMs"
New-VM -Name ArcBox-Win2K19 -MemoryStartupBytes 12GB -BootDevice VHD -VHDPath "$Env:ArcBoxVMDir\ArcBox-Win2K19.vhdx" -Path $Env:ArcBoxVMDir -Generation 2 -Switch $switchName
Set-VMProcessor -VMName ArcBox-Win2K19 -Count 2

New-VM -Name ArcBox-Win2K22 -MemoryStartupBytes 12GB -BootDevice VHD -VHDPath "$Env:ArcBoxVMDir\ArcBox-Win2K22.vhdx" -Path $Env:ArcBoxVMDir -Generation 2 -Switch $switchName
Set-VMProcessor -VMName ArcBox-Win2K22 -Count 2

# New-VM -Name ArcBox-SQL -MemoryStartupBytes 12GB -BootDevice VHD -VHDPath "$Env:ArcBoxVMDir\ArcBox-SQL.vhdx" -Path $Env:ArcBoxVMDir -Generation 2 -Switch $switchName
# Set-VMProcessor -VMName ArcBox-SQL -Count 2

New-VM -Name ArcBox-Ubuntu-01 -MemoryStartupBytes 4GB -BootDevice VHD -VHDPath "$Env:ArcBoxVMDir\ArcBox-Ubuntu-01.vhdx" -Path $Env:ArcBoxVMDir -Generation 2 -Switch $switchName
Set-VMFirmware -VMName ArcBox-Ubuntu-01 -EnableSecureBoot On -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'
Set-VMProcessor -VMName ArcBox-Ubuntu-01 -Count 1

New-VM -Name ArcBox-Ubuntu-02 -MemoryStartupBytes 4GB -BootDevice VHD -VHDPath "$Env:ArcBoxVMDir\ArcBox-Ubuntu-02.vhdx" -Path $Env:ArcBoxVMDir -Generation 2 -Switch $switchName
Set-VMFirmware -VMName ArcBox-Ubuntu-02 -EnableSecureBoot On -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'
Set-VMProcessor -VMName ArcBox-Ubuntu-02 -Count 1

# We always want the VMs to start with the host and shut down cleanly with the host
Write-Output "Set VM auto start/stop"
Set-VM -Name ArcBox-Win2K19 -AutomaticStartAction Start -AutomaticStopAction ShutDown
Set-VM -Name ArcBox-Win2K22 -AutomaticStartAction Start -AutomaticStopAction ShutDown
# Set-VM -Name ArcBox-SQL -AutomaticStartAction Start -AutomaticStopAction ShutDown
Set-VM -Name ArcBox-Ubuntu-01 -AutomaticStartAction Start -AutomaticStopAction ShutDown
Set-VM -Name ArcBox-Ubuntu-02 -AutomaticStartAction Start -AutomaticStopAction ShutDown

Write-Output "Enabling Guest Integration Service"
Get-VM | Get-VMIntegrationService | Where-Object {-not($_.Enabled)} | Enable-VMIntegrationService -Verbose

# Start all the VMs
Write-Output "Start VMs"
Start-VM -Name ArcBox-Win2K19
Start-VM -Name ArcBox-Win2K22
# Start-VM -Name ArcBox-SQL
Start-VM -Name ArcBox-Ubuntu-01
Start-VM -Name ArcBox-Ubuntu-02

# Expand Windows partition sizes
Start-Sleep -Seconds 20
$username = "Administrator"
$password = "ArcDemo123!!"
$secstr = New-Object -TypeName System.Security.SecureString
$password.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $secstr
Invoke-Command -VMName ArcBox-Win2K19 -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $cred
Invoke-Command -VMName ArcBox-Win2K22 -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $cred
# Invoke-Command -VMName ArcBox-SQL -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $cred

Start-Sleep -Seconds 5

# Configure the ArcBox Hyper-V host to allow the nested VMs onboard as Azure Arc-enabled servers
Write-Output "Configure the ArcBox VM to allow the nested VMs onboard as Azure Arc-enabled servers"
Set-Service WindowsAzureGuestAgent -StartupType Disabled -Verbose
Stop-Service WindowsAzureGuestAgent -Force -Verbose
New-NetFirewallRule -Name BlockAzureIMDS -DisplayName "Block access to Azure IMDS" -Enabled True -Profile Any -Direction Outbound -Action Block -RemoteAddress 169.254.169.254

# Hard-coded username and password for the nested VMs
$nestedWindowsUsername = "Administrator"
$nestedWindowsPassword = "ArcDemo123!!"
$nestedLinuxUsername = "arcdemo"
$nestedLinuxPassword = "ArcDemo123!!"

# Getting the Ubuntu-01 nested VM IP address
Get-VM -Name ArcBox-Ubuntu-01 | Select-Object -ExpandProperty NetworkAdapters | Select-Object IPAddresses | Format-List | Out-File "$agentScript\Ubuntu01-IP.txt"
$Ubuntu01IP = "$agentScript\Ubuntu01-IP.txt"
(Get-Content $Ubuntu01IP | Select-Object -Skip 2) | Set-Content $Ubuntu01IP
$string = Get-Content "$Ubuntu01IP"
$string.split(',')[0] | Set-Content $Ubuntu01IP
$string = Get-Content "$Ubuntu01IP"
$string.split('{')[-1] | Set-Content $Ubuntu01IP
$Ubuntu01IP = Get-Content "$Ubuntu01IP"

# Getting the Ubuntu-02 nested VM IP address
Get-VM -Name ArcBox-Ubuntu-02 | Select-Object -ExpandProperty NetworkAdapters | Select-Object IPAddresses | Format-List | Out-File "$agentScript\Ubuntu02-IP.txt"
$Ubuntu02IP = "$agentScript\Ubuntu02-IP.txt"
(Get-Content $Ubuntu02IP | Select-Object -Skip 2) | Set-Content $Ubuntu02IP
$string = Get-Content "$Ubuntu02IP"
$string.split(',')[0] | Set-Content $Ubuntu02IP
$string = Get-Content "$Ubuntu02IP"
$string.split('{')[-1] | Set-Content $Ubuntu02IP
$Ubuntu02IP = Get-Content "$Ubuntu02IP"

# Copying the Azure Arc Connected Agent to nested VMs
Write-Output "Copying the Azure Arc onboarding script to the nested VMs"
(Get-Content -path "$agentScript\installArcAgent.ps1" -Raw) -replace '\$spnClientId',"'$env:spnClientId'" -replace '\$spnClientSecret',"'$env:spnClientSecret'" -replace '\$resourceGroup',"'$env:resourceGroup'" -replace '\$spnTenantId',"'$env:spnTenantId'" -replace '\$azureLocation',"'$env:azureLocation'" -replace '\$subscriptionId',"'$env:subscriptionId'" | Set-Content -Path "$agentScript\installArcAgentModified.ps1"
(Get-Content -path "$agentScript\installArcAgentUbuntu.sh" -Raw) -replace '\$spnClientId',"'$env:spnClientId'" -replace '\$spnClientSecret',"'$env:spnClientSecret'" -replace '\$resourceGroup',"'$env:resourceGroup'" -replace '\$spnTenantId',"'$env:spnTenantId'" -replace '\$azureLocation',"'$env:azureLocation'" -replace '\$subscriptionId',"'$env:subscriptionId'" | Set-Content -Path "$agentScript\installArcAgentModifiedUbuntu.sh"
(Get-Content -path "$agentScript\installArcAgentCentOS.sh" -Raw) -replace '\$spnClientId',"'$env:spnClientId'" -replace '\$spnClientSecret',"'$env:spnClientSecret'" -replace '\$resourceGroup',"'$env:resourceGroup'" -replace '\$spnTenantId',"'$env:spnTenantId'" -replace '\$azureLocation',"'$env:azureLocation'" -replace '\$subscriptionId',"'$env:subscriptionId'" | Set-Content -Path "$agentScript\installArcAgentModifiedCentOS.sh"

Copy-VMFile ArcBox-Win2K19 -SourcePath "$agentScript\installArcAgentModified.ps1" -DestinationPath C:\ArcBox\installArcAgent.ps1 -CreateFullPath -FileSource Host

Write-Output y | pscp -P 22 -pw $nestedLinuxPassword "$agentScript\installArcAgentModifiedUbuntu.sh" $nestedLinuxUsername@"$Ubuntu01IP":/home/"$nestedLinuxUsername"
Write-Output y | pscp -P 22 -pw $nestedLinuxPassword "$agentScript\installArcAgentModifiedCentOS.sh" $nestedLinuxUsername@"$Ubuntu02IP":/home/"$nestedLinuxUsername"

# Onboarding the nested VMs as Azure Arc-enabled servers
# $secstr = New-Object -TypeName System.Security.SecureString
# $nestedWindowsPassword.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
# $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $nestedWindowsUsername, $secstr

# Write-Output "Onboarding the nested Windows Server 2019 VM as Azure Arc-enabled server"
# Invoke-Command -VMName ArcBox-Win2K19 -ScriptBlock { powershell -File C:\ArcBox\installArcAgent.ps1 } -Credential $cred

# Converting Linux credentials to secure string  
$secpasswd = ConvertTo-SecureString $nestedLinuxPassword -AsPlainText -Force
$Credentials = New-Object System.Management.Automation.PSCredential($nestedLinuxUsername, $secpasswd)

# Write-Output "Onboarding the nested Ubuntu-02 VM as an Azure Arc-enabled server"
# $SessionID = New-SSHSession -ComputerName $Ubuntu02IP -Credential $Credentials -Force -WarningAction SilentlyContinue # Connect Over SSH
# $Command = "sudo sh /home/$nestedLinuxUsername/installArcAgentModifiedCentOS.sh"
# Invoke-SSHCommand -Index $sessionid.sessionid -Command $Command -TimeOut 500 -WarningAction SilentlyContinue | Out-Null

Write-Output "Disabling IMDS on the nested Ubuntu VM"
$SessionID = New-SSHSession -ComputerName $Ubuntu01IP -Credential $Credentials -Force -WarningAction SilentlyContinue # Connect Over SSH
$Command = "sudo sh /home/$nestedLinuxUsername/installArcAgentModifiedUbuntu.sh"
Invoke-SSHCommand -Index $sessionid.sessionid -Command $Command -Timeout 120 -WarningAction SilentlyContinue | Out-Null

# Creating Hyper-V Manager desktop shortcut
Copy-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Administrative Tools\Hyper-V Manager.lnk" -Destination "C:\Users\All Users\Desktop" -Force

# Changing to Jumpstart ArcBox wallpaper
$imgPath="$Env:ArcBoxDir\wallpaper.png"
$code = @' 
using System.Runtime.InteropServices; 
namespace Win32{ 
    
     public class Wallpaper{ 
        [DllImport("user32.dll", CharSet=CharSet.Auto)] 
         static extern int SystemParametersInfo (int uAction , int uParam , string lpvParam , int fuWinIni) ; 
         
         public static void SetWallpaper(string thePath){ 
            SystemParametersInfo(20,0,thePath,3); 
         }
    }
 } 
'@

add-type $code 
[Win32.Wallpaper]::SetWallpaper($imgPath)

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "ArcServersLogonScript" -Confirm:$false

# Executing the deployment logs bundle PowerShell script in a new window
Invoke-Expression 'cmd /c start Powershell -Command { 
    $RandomString = -join ((48..57) + (97..122) | Get-Random -Count 6 | % {[char]$_})
    Write-Host "Sleeping for 5 seconds before creating deployment logs bundle..."
    Start-Sleep -Seconds 5
    Write-Host "`n"
    Write-Host "Creating deployment logs bundle"
    7z a $Env:ArcBoxLogsDir\LogsBundle-"$RandomString".zip $Env:ArcBoxLogsDir\*.log
}'
