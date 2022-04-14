# SQL Logger

#### A procedure that generates and inserts logs into target table.


## Target table schema

```sql
CREATE TABLE dbo.proc_logs(
    log_id INT IDENTITY(1,1)
,   created_at DATETIME2
,   finished_at DATETIME2
,   proc_name NVARCHAR(100)
,   status NVARCHAR(50)
,   session_username NVARCHAR(50)
,   error_message NVARCHAR(100)
,   proc_params NVARCHAR(100)
,   proc_outputs NVARCHAR(100)
)
```

## Editing target table in procedure

Target table of this stored procedure needs to be edited before use so that it references your table. 
Currently it uses testing.dbo.proc_logs as target table.

![](../../../Pictures/target_tbl4.png)
![](../../../Pictures/target_tbl1.png)
![](../../../Pictures/target_tbl2.png)
![](../../../Pictures/target_tbl3.png)

## Example

```sql
CREATE TABLE dbo.data_table(
    log_id INT
,   created_at DATETIME2
,   metric_name NVARCHAR(100)
,   value INT
);

CREATE PROC dbo.load_data
    @metric_name NVARCHAR(100)
,   @value INT
,   @log_id INT
AS
BEGIN
    INSERT INTO dbo.data_table(log_id, created_at, metric_name, value)
    SELECT @log_id, GETDATE(), @metric_name, @value;

    SELECT 'Some output' as d;
END;

EXEC dbo.logger
    @procedure_path = 'dbo.load_data'
,   @procedure_parameters = '@metric_name=''test'',@value=100'
,   @pass_log_id = 1;
```

## Results

```sql
SELECT * FROM testing.dbo.proc_logs;
```
![](../../../Pictures/log.png)

```sql
SELECT * FROM testing.dbo.proc_logs;
```
![](../../../Pictures/data_tbl.png)