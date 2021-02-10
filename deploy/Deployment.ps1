#configurations - FILL OUT WITH DESIRED VALUES
$dir = "C:\GitHub\SynapseServerlessImporter\deploy"     #Working directory of where your Deployment.ps1 file is located
$resourceGroupName = "ssi-rg-test2"                     #Name of Azure resource group to deploy the lab resrouces to, will create if it does not exist
$location = "East US 2"                                 #Geo location of resource group, resources will use this as well
$resourceNamePrefix = "ssi"                             #prefix to append on to unique names such as Synapse Workspace and Storage account
$subscriptionName = "MS Internal Sandbox"               #Name of subscription to use for deployment (in case you want to deploy not to your default subscription)
$serverlessDatabaseName = "synapseServerless"           #Name of Synapse Servless Pool

#Sign-in
#Connect-AzAccount

#set subscription context
$sub = Get-AzSubscription -SubscriptionName $subscriptionName | Select-AzSubscription

#verify RG does not exist
$RGnotExist = 0
Get-AzResourceGroup -Name $resourceGroupName -ev RGnotExist -ea 0
if ($RGnotExist){
    #Create Resource Group
    New-AzResourceGroup -Name $resourceGroupName -Location $location
}
else {
    Write-Output "Exiting: RG $resourceGroupName already exists"
    return
}

#get credentials for SQL Server
$cred = Get-Credential -Message "Please set the sql admin user and password for the Synapse Workspace"
$username = $cred.UserName
$passwd= $cred.getNetworkCredential().Password

#set working directory
Set-Location $dir

#set access policy for Azure Key Vault for user
$userObjectID = (Get-AzADUser -UserPrincipalName (Get-AzContext).Account).Id
$akvPol = '[ { "objectId": "#USERID#", "tenantId": "#TENANTID#", "permissions": { "keys": [ "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore" ], "secrets": [ "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore" ], "certificates": [ "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore", "ManageContacts", "ManageIssuers", "GetIssuers", "ListIssuers", "SetIssuers", "DeleteIssuers" ] }, "applicationId": "" } ]'
$akvPol.Replace("#USERID#",$userObjectID)
$akvPol.Replace("#TENANTID#",$sub.TentantID)

#Deploy Workspace + Storage
$ARMoutput = New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile Deploy.json -resourcesBasePrefix $resourceNamePrefix -sqlUsername $username -sqlPassword $cred.Password -akvAccessPolicies $akvPol
Write-Output "Storage and Synapse accounts created"

#Get Synapse Workspace managed identity
$synapseMI = (Get-AzSynapseWorkspace -ResourceGroupName $resourceGroupName).Identity
#add access policy for Synapse to AKV
Set-AzKeyVaultAccessPolicy -VaultName $($ARMoutput.Outputs.keyVaultName.Value) -ObjectId $synapseMI -PermissionsToSecrets ["Get"]

#upload files to container
#$ctx = New-AzStorageContext -StorageAccountName $ARMoutput.Outputs.storageName -UseConnectedAccount
Set-AzCurrentStorageAccount -ResourceGroupName $resourceGroupName -Name $ARMoutput.Outputs.storageName.Value
New-AzDataLakeGen2Item -FileSystem "synapseadls" -Path "config" -Directory -Permission rwxrwxrwx
New-AzDataLakeGen2Item  -FileSystem "synapseadls" -Path "config/Control-RefinedDefinition.csv" -Source "$dir\storageArtifacts\Control-RefinedDefinition.csv" -Force
New-AzDataLakeGen2Item  -FileSystem "synapseadls" -Path "config/Import-HTTP.csv" -Source "$dir\storageArtifacts\Import-HTTP.csv" -Force

#run SQL script to create ServerlessDB
$ConnectionStringMaster = "Server=$($ARMoutput.Outputs.synapseName.Value)-ondemand.sql.azuresynapse.net;Database=master;User ID=$username;Password=$passwd"
# connect to database
$dbConn = New-Object System.Data.SqlClient.SqlConnection
$dbConn.ConnectionString = $ConnectionStringMaster
$dbConn.Open()
# construct command
$dbCmd = New-Object System.Data.SqlClient.SqlCommand
$dbCmd.Connection = $dbConn
$dbCmd.CommandText = "CREATE DATABASE $serverlessDatabaseName"
# fetch all results
$dataset = New-Object System.Data.DataSet
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$adapter.SelectCommand = $dbCmd
$adapter.Fill($dataset)
$dbConn.Close()

#run SQL script to create SPs on ServerlessDB
$ConnectionStringServerless = "Server=$($ARMoutput.Outputs.synapseName.Value)-ondemand.sql.azuresynapse.net;Database=$serverlessDatabaseName;User ID=$username;Password=$passwd"

$SSmaster = ConvertTo-SecureString -String $ConnectionStringMaster -AsPlainText -Force
$SSserverless = ConvertTo-SecureString -String $ConnectionStringServerless -AsPlainText -Force

#add key vault secret for Serverless DB
Set-AzKeyVaultSecret -VaultName $($ARMoutput.Outputs.keyVaultName.Value) -Name "SSI-ServerlessDB" -SecretValue $SSserverless
