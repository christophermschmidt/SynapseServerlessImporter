-- create master key that will protect the credentials, if you haven't already done so
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys)
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '#MASTERKEY#'

IF NOT EXISTS(SELECT 1 FROM sys.credentials WHERE [name] = 'sqlondemand')
-- create credentials for containers in our demo storage account
CREATE DATABASE SCOPED CREDENTIAL [sqlondemand]
WITH IDENTITY='Managed Identity'  --alternatively you can use the Storage Account Key (SAS) instead.

--if you don't already have any external data sources defined, create them! For this scenario, there are 2. The first external data source points to the raw storage container, and the 2nd assumes that data is to be moved to a refined container in either the same or different storage account. I split this out to look/feel more "real-world"
IF EXISTS (SELECT 1 FROM sys.external_data_sources WHERE [name] = 'ADLSStorage') 
DROP EXTERNAL DATA SOURCE [ADLSStorage]

CREATE EXTERNAL DATA SOURCE [ADLSStorage] 
WITH 
	(
		LOCATION = N'https:/#STORAGENAME#.dfs.core.windows.net/',
		CREDENTIAL = [sqlondemand]) --the credential you created earlier

--create the external file formats we need
IF EXISTS (SELECT 1 FROM sys.external_file_formats WHERE [name] = 'csv_file_format')
DROP EXTERNAL FILE FORMAT [csv_file_format]


--the first external file format it for CSV files that match our NYC import pattern
CREATE EXTERNAL FILE FORMAT [csv_file_format] 
WITH (
	FORMAT_TYPE = DELIMITEDTEXT,
	FORMAT_OPTIONS (FIELD_TERMINATOR = N',', 
	STRING_DELIMITER = N'"', 
	USE_TYPE_DEFAULT = False)
	)

--the second file format is the underlying storage mechanism for our sink tables. We'll be using Parquet here.
IF EXISTS (SELECT 1 FROM sys.external_file_formats WHERE [name] = 'ParquetFF')
DROP EXTERNAL FILE FORMAT [ParquetFF]


CREATE EXTERNAL FILE FORMAT [ParquetFF] 
WITH (
	FORMAT_TYPE = PARQUET, 
	DATA_COMPRESSION = N'org.apache.hadoop.io.compress.SnappyCodec');