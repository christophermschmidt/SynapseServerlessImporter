--connect to the proper db
USE test123

-- create master key that will protect the credentials, if you haven't already done so
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys)
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<enter very strong password here>'

IF NOT EXISTS(SELECT 1 FROM sys.credentials WHERE [name] = 'ManagedIdentity')
-- create credentials for containers in our demo storage account
CREATE DATABASE SCOPED CREDENTIAL [sqlondemand]
WITH IDENTITY='Managed Identity'  --alternatively you can use the Storage Account Key (SAS) instead.
GO


--if you don't already have any external data sources defined, create them! For this scenario, there are 2. The first external data source points to the raw storage container, and the 2nd assumes that data is to be moved to a refined container in either the same or different storage account. I split this out to look/feel more "real-world"
IF EXISTS (SELECT 1 FROM sys.external_data_sources WHERE [name] = 'ADLSStorage') 
DROP EXTERNAL DATA SOURCE [ADLSStorage]
GO

CREATE EXTERNAL DATA SOURCE [ADLSStorage] 
WITH 
	(
		LOCATION = N'https://ssi3synapsemkp7j.dfs.core.windows.net/',
		CREDENTIAL = [sqlondemand]) --the credential you created earlier
GO


--create the external file formats we need
IF EXISTS (SELECT 1 FROM sys.external_file_formats WHERE [name] = 'csv_file_format')
DROP EXTERNAL FILE FORMAT [csv_file_format]
GO


--the first external file format it for CSV files that match our NYC import pattern
CREATE EXTERNAL FILE FORMAT [csv_file_format] 
WITH (
	FORMAT_TYPE = DELIMITEDTEXT,
	FORMAT_OPTIONS (FIELD_TERMINATOR = N',', 
	STRING_DELIMITER = N'"', 
	USE_TYPE_DEFAULT = False)
	)
GO

--the second file format is the underlying storage mechanism for our sink tables. We'll be using Parquet here.
IF EXISTS (SELECT 1 FROM sys.external_file_formats WHERE [name] = 'ParquetFF')
DROP EXTERNAL FILE FORMAT [ParquetFF]
GO


CREATE EXTERNAL FILE FORMAT [ParquetFF] 
WITH (
	FORMAT_TYPE = PARQUET, 
	DATA_COMPRESSION = N'org.apache.hadoop.io.compress.SnappyCodec')
GO


--finally, let's create our dynamic stored procedure. The below parameterizes the table name, sink, and source, and writes the raw csv as an optimized parquet file for querying through serverless

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO


--now, creating a regular old external table is boring! whatwe want to do is dynamically generate this based on an input parameter to handle the latest arriving data
CREATE OR ALTER PROCEDURE dbo.uspExternalTblCreate
(
	@sinkTableName NVARCHAR(500) 
	,@sourceDataFile NVARCHAR(500)
	,@sourceDataFolder NVARCHAR(100)
)
AS


/*
Date: 2/1/2021
Author: Chris Schmidt
Desc: This procedure is designed to take a single file at a time with a list of inputs and dynamically create an external table in Synapse Serverless.

Parameters: 

@sinkTableName
DataType: nvarchar(500)
Description: the name of the sink (destination) table that the table will be created as. Will be joined with the NUMERIC only portion of the inputTimeStamp parameter to create the full table name
Example: yellow_vehicles_refined_cetas

@sourceDataFile
DataType: nvarchar(500)
Description: the name of the data file in the source (raw) storage container
Example: 

@sourceDataFolder
DataType: nvarchar(100)
Description: the folder location of the data file to be ingested. Should include the trailing slash: /
Example: 


*/

BEGIN

--if you're data doesn't have headers, be sure to update it in the OPENROWSET function call to change it to false

	--declare some additional parameters to clean up the inputs for the dynamic sql statement
	DECLARE @fullsinkTableName NVARCHAR(525)
	DECLARE @fullSourceFilePath NVARCHAR(600)
	DECLARE @fulllocation NVARCHAR(125)
	DECLARE @cleanedTimeStamp NVARCHAR(25)

	--final sql variable.
	DECLARE @sql NVARCHAR(max)

	--combine the sink table name and the new cleaned time stamp to create the external table in Synapse
	SET @fullsinkTableName = @sinkTableName
	--create the full source file path by combing the source file path, file name pattern, and the RAW input time stamp along with the file extension (hard coded to csv) to create the final file. for example: s3.amazonaws.com/trip+data/yellow_tripdata_2019-01.csv
	SET @fullSourceFilePath = @sourceDataSourceFolder + @sourceDataFile + '.csv'

	--create the parameterized sql statement
	SET @sql = '
		IF EXISTS(SELECT 1 FROM sys.external_tables WHERE [name] = '''+ @fullsinkTableName +''')
			DROP EXTERNAL TABLE ' + QUOTENAME(@fullsinkTableName) + '


		CREATE EXTERNAL TABLE ' + QUOTENAME(@fullsinkTableName) + ' WITH 
		(DATA_SOURCE = ''ADLSStorage'', LOCATION = N''' + @fulllocation + ''',FILE_FORMAT = ''Parquet'')
		AS
		SELECT *
		FROM OPENROWSET(
			BULK ''' + @fullSourceFilePath + '''
			,DATA_SOURCE = ''ADLSStorage''
			,HEADER_ROW = true
			,FORMAT = ''CSV''
			, PARSER_VERSION = ''2.0''
			) as [r]'
	
	--if you want to view the statement, use the print command to view it. Outside of the scope of this tutorial but possible would be to log this to a control table somewhere
	--PRINT @sql

--execute the sql to create your external table!
	EXEC sp_executesql @sql

END;
