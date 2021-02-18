CREATE   PROCEDURE [dbo].[uspExternalTblCreate]
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
	SET @fullSourceFilePath = 'raw/'+@sourceDataFolder +'/'+ @sourceDataFile
	SET @fulllocation = 'refined/'+@sourceDataFolder + '/'+ @sinkTableName + '.parquet'

	--create the parameterized sql statement
	SET @sql = '
		IF EXISTS(SELECT 1 FROM sys.external_tables WHERE [name] = '''+ @fullsinkTableName +''')
			DROP EXTERNAL TABLE ' + QUOTENAME(@fullsinkTableName) + '


		CREATE EXTERNAL TABLE ' + QUOTENAME(@fullsinkTableName) + ' WITH 
		(DATA_SOURCE = [ADLSStorage], LOCATION = N''' + @fulllocation + ''',FILE_FORMAT = [ParquetFF])
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