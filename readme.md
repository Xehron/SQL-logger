# SQL Logger

#### A wrapper procedure that executes any provided procedure and generates logs into log table.

## Target table schema

```sql
CREATE TABLE dbo.logs(
    log_id INT IDENTITY(1,1)
,   created_at DATETIME2
,   finished_at DATETIME2
,   proc_name NVARCHAR(100)
,   status NVARCHAR(50)
,   session_username NVARCHAR(50)
,   proc_params NVARCHAR(MAX)
,   proc_outputs NVARCHAR(MAX)
,   error_message NVARCHAR(4000)
,   error_proc NVARCHAR(128)
,   error_line INT
,   error_severity INT
,   error_state INT
)
```

## Editing target table in procedure

Target table of this stored procedure needs to be edited before use so that it references your table. 
Currently it uses logger.dbo.logs as target table.


## Example

```sql
-- inner procedure that will be wrapped by dbo.logger procedure. 
CREATE PROC dbo.load_data
    @metric_name NVARCHAR(100)
,   @value INT
,   @log_id INT
,   @json_log NVARCHAR(MAX) OUTPUT
AS
BEGIN
    DECLARE @finished_at DATETIME2;
    SET @json_log = '{}';
    
    INSERT INTO dbo.data_table(log_id, created_at, metric_name, value)
    SELECT @log_id, GETDATE(), @metric_name, @value;

    SET @finished_at = GETDATE()
    SET @json_log = JSON_MODIFY(@json_log, '$.finished_at', CONVERT(CHAR(19), @finished_at, 20))
    SET @json_log = JSON_MODIFY(@json_log, '$.additional_data', JSON_QUERY('{"data": ["value1", "value2"]}'))
END;

-- target table of dbo.load_data procedure
CREATE TABLE dbo.data_table(
    log_id INT
,   created_at DATETIME2
,   metric_name NVARCHAR(100)
,   value INT
);

-- executing dbo.load_data procedure by dbo.logger. 
    -- By setting @pass_log_id = 1 we let dbo.logger pass @log_id to dbo.load_data
    -- By setting @catch_output we let dbo.logger retrieve @json_log OUTPUT parameter from dbo.load_data
EXEC dbo.logger
    @procedure_path = 'dbo.load_data'
,   @procedure_parameters = '@metric_name=''test'', @value=100'
,   @pass_log_id = 1
,   @catch_output = 1;
```

## Results

```sql
SELECT * FROM logger.dbo.logs;
```

log_id|created_at|finished_at|proc_name|status|session_username|proc_params|proc_outputs|error_message|error_proc|error_line|error_severity|error_state
:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:
1|2022-05-15 18:57:07.7366667|2022-05-15 18:57:07.7400000|dbo.load_data|complete|dbo|@metric_name='test', @value=100|{"final_procedure_output":{"finished_at":"2022-05-15 18:57:07","additional_data":{"data": ["value1", "value2"]}}} 

```sql
SELECT * FROM logger.dbo.data_table;
```

|log_id    |created_at          |metric_name      |value     |
|----------|--------------------|-----------------|----------|
|1         |2022-05-15 18:57:07.7400000 |test             |100       |
