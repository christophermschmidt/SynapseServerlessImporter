# Summary
This repo is a collection of a Synapse workspace plus a storage account. It can be used as an accelerator or as a demo to show the value of using Synapse Serverless external tables and how they can be dynamically created on top of any file within storage. Right now, the solution demonstrates loading files from an http source, and then dynamically creating the external table within a Serverless SQL Pool for querying or initial transformations downstream. In the future we are considering adding sample scripts that demonstrate a similar approach for:

    - flat files from an on-prem data source
    - sql server from an on-prem data source

# Deployment
The simplest way to deploy this is to simply use the "Deploy to Azure" button below. No kidding! Just plug in some parameters, and the solution does the rest. It includes a sample list of 50 files from the now famous taxi cab dataset that the NYC Taxi and Limousine Commission makes available here: https://www1.nyc.gov/site/tlc/about/tlc-trip-record-data.page


[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fchristophermschmidt%2FSynapseServerlessImporter%2Fdeploy%2Fdeploy%2FDeploy.json)
