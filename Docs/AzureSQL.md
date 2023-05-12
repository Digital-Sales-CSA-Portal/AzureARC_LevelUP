## Connect your SQL Server to Azure Arc

You can find the offical documentation from Microsoft Learn on Connecing your SQL Server to ARC [Here](https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/connect?view=sql-server-ver16&tabs=windows)

# Generate an onboarding script for SQL Server
1. FromOn your ARCBox Client VM Or Console into ArcBox-SQL, Open up your browser, go to the Azure portal. Go to Azure Arc > SQL Server and select + Add

![Start of SQL Server](/Media/start-creation-of-sql-server-azure-arc-resource.png)

2. Under Connect SQL Server to Azure Arc, select Connect Servers

3. Review the prerequisites and select Next: Server details

4. Specify:

* Subscription
* Resource group
* Region
* Operating system
If necessary, specify the proxy your network uses to connect to the Internet.

To use a specific name for Azure Arc enabled Server instead of default host name, users can add the name for Azure Arc enabled Server in Server Name.

![SQL Server Details](/Media/server-details-sql-server-azure-arc.png)

5. Select the SQL Server edition and license type you are using on this machine. Please note that some Arc-enabled SQL Server features are only available for SQL Servers with Software Assurance (Paid) or with Azure pay-as-you-go. For more information, review Manage SQL Server license type.

6. Specify the SQL Server instance(s) you want to exclude from registering (if you have multiple instances installed on the server). Separate each excluded instance by a space.

![SQL Server Licensing and Exclusions](/Media/server-licensing-sql-server-management-azure-arc.png)

7. Select Next: Tags to optionally add tags to the resource for your SQL Server instance.

8. Select Run script to generate the onboarding script

# Connect SQL Server instances to Azure Arc

1. Download or Copy the Script that was Generated
2. Open PowerShell as Administrator on the ArcBox-SQL Virtual Machine
3. Run the Downloaded script or copy the script into PowerShell


## Validate your Arc-enabled SQL Server resources

Go to Azure Arc > SQL Server and open the newly registered Arc-enabled SQL Server resource to validate.
![Validate SQL](/Media/validate-sql-server-azure-arc.png)