#!/bin/sh

# Block Azure IMDS
systemctl unmask --now firewalld
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --direct --add-rule ipv4 filter OUTPUT 0 -d 169.254.169.254  -j REJECT
firewall-cmd --permanent --zone=public --set-target=ACCEPT
firewall-cmd --reload

# Download the installation package
wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh # 2>/dev/null

# Install the hybrid agent
bash ~/install_linux_azcmagent.sh # 2>/dev/null

# Run connect command
azcmagent connect --service-principal-id $spnClientId --service-principal-secret $spnClientSecret --resource-group $resourceGroup --tenant-id $spnTenantId --location $Azurelocation --subscription-id $subscriptionId --resource-name "ArcBox-CentOS" --cloud "AzureCloud" --tags "Project=jumpstart_arcbox" --correlation-id "d009f5dd-dba8-4ac7-bac9-b54ef3a6671a"