#configurations - FILL OUT WITH DESIRED VALUES
$dir = "C:\GitHub\SynapseServerlessImporter\deploy"     #Working directory of where your Deployment.ps1 file is located
$resourceGroupName = "ssi-rg-test2"                     #Name of Azure resource group to deploy the lab resrouces to, will create if it does not exist
$location = "East US 2"                                 #Geo location of resource group, resources will use this as well
$resourceNamePrefix = "ssi"                             #prefix to append on to unique names such as Synapse Workspace and Storage account
$subscriptionName = "Visual Studio Premium with MSDN"               #Name of subscription to use for deployment (in case you want to deploy not to your default subscription)
$serverlessDatabaseName = "synapseServerless"           #Name of Synapse Servless Pool

#Sign-in
#Connect-AzAccount -UseDeviceAuthentication

#set subscription context
$ctx = Get-AzContext

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
$user = Get-AzADUser -Mail $ctx.Account.id
if (-not $user) {  #Try UPN
    $user = Get-AzADUser -UserPrincipalName $ctx.Account.Id
}
if (-not $user) { #User was not found by mail or UPN, try MailNick
    $mail = ($ctx.Account.id -replace "@","_" ) + "#EXT#"
    $user = Get-AzADUser | Where-Object { $_.MailNickName -eq $mail}
}

#Deploy Workspace + Storage
$ARMoutput = New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile Deploy.json -resourcesBasePrefix $resourceNamePrefix -sqlUsername $username -sqlPassword $cred.Password -akvUser $user.Id
Write-Output "Storage and Synapse accounts created"

#Get Synapse Workspace managed identity
$synapseMI = (Get-AzSynapseWorkspace -ResourceGroupName $resourceGroupName).Identity
#add access policy for Synapse to AKV
Set-AzKeyVaultAccessPolicy -VaultName $($ARMoutput.Outputs.keyvaultName.Value) -ObjectId $synapseMI.PrincipalId -PermissionsToSecrets "get"

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

$SSserverless = ConvertTo-SecureString -String $ConnectionStringServerless -AsPlainText -Force

#add key vault secret for Serverless DB
Set-AzKeyVaultSecret -VaultName $($ARMoutput.Outputs.keyvaultName.Value) -Name "SSI-ServerlessDB" -SecretValue $SSserverless

#load Synapse Workspace objects
#replace key vault URL
((Get-Content -path "$dir\workspaceArtifacts\linkedService\LS_AKV.json" -Raw) -replace '#AKVURL#', $($ARMoutput.Outputs.keyvaultName.Value)) | Set-Content -Path "$dir\workspaceArtifacts\linkedService\LS_AKV_Updated.json"
#replace ADLS URL
((Get-Content -path "$dir\workspaceArtifacts\linkedService\LS_Synapse_ADLS.json" -Raw) -replace '#ADLSURL#', $($ARMoutput.Outputs.storageName.Value)) | Set-Content -Path "$dir\workspaceArtifacts\linkedService\LS_Synapse_ADLS_Updated.json"
Set-AzSynapseLinkedService -WorkspaceName $($ARMoutput.Outputs.synapseName.Value) -Name "LS_AKV" -DefinitionFile "$dir\workspaceArtifacts\linkedService\LS_AKV_Updated.json"
Set-AzSynapseLinkedService -WorkspaceName $($ARMoutput.Outputs.synapseName.Value) -Name "LS_Synapse_ADLS" -DefinitionFile "$dir\workspaceArtifacts\linkedService\LS_Synapse_ADLS_Updated.json"
Set-AzSynapseLinkedService -WorkspaceName $($ARMoutput.Outputs.synapseName.Value) -Name "LS_HTTP" -DefinitionFile "$dir\workspaceArtifacts\linkedService\LS_HTTP.json"
Set-AzSynapseLinkedService -WorkspaceName $($ARMoutput.Outputs.synapseName.Value) -Name "LS_AzSQL_ServerlessPool" -DefinitionFile "$dir\workspaceArtifacts\linkedService\LS_AzSQL_ServerlessPool.json"
Set-AzSynapseDataset -WorkspaceName $($ARMoutput.Outputs.synapseName.Value) -Name "DS_HTTP_CSV_Generic" -DefinitionFile "$dir\workspaceArtifacts\dataset\DS_HTTP_CSV_Generic.json"
Set-AzSynapseDataset -WorkspaceName $($ARMoutput.Outputs.synapseName.Value) -Name "DS_ADLS_CSV_Generic" -DefinitionFile "$dir\workspaceArtifacts\dataset\DS_ADLS_CSV_Generic.json"
Set-AzSynapsePipeline -WorkspaceName $($ARMoutput.Outputs.synapseName.Value) -Name "3-SQL Serverless Data Layer" -DefinitionFile "$dir\workspaceArtifacts\pipeline\3-SQL Serverless Data Layer.json"
Set-AzSynapsePipeline -WorkspaceName $($ARMoutput.Outputs.synapseName.Value) -Name "2-HTTP CSV to ADLS CSV" -DefinitionFile "$dir\workspaceArtifacts\pipeline\2-HTTP CSV to ADLS CSV.json"
Set-AzSynapsePipeline -WorkspaceName $($ARMoutput.Outputs.synapseName.Value) -Name "1-Main Orchestrator" -DefinitionFile "$dir\workspaceArtifacts\pipeline\1-Main Orchestrator.json"