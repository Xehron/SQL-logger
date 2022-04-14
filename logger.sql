CREATE PROC dbo.logger
    @procedure_path NVARCHAR(100)
,   @procedure_parameters NVARCHAR(100)
,   @pass_log_id INT = 1

/*
=============================================================================
DESCRIPTION:
    A procedure that generates and inserts logs into target table.

PARAMETERS:
    @procedure_path: a string with path to stored procedure that will be executed.
        Example: @procedure_path = testing.dbo.load_data
    @procedure_parameters: a string with all parameters that procedure declared in @procedure_path needs.
        Example: @procedure_parameters = '@metric_name='asd',@value=100'
    @pass_log_id: Possible states 1 and 0. If 1 procedure will pass log_id that was generated during
        execution of this procedure so that the procedure declared in @procedure_path can receive it and further process it.

ADDITIONAL INFO:
    A procedure declared in @procedure_path can return a single column of data that will be retrieved by this
        procedure and it will store it in proc_params column. If there are multiple rows they will be aggregated to a single row.
    Procedure updates any logs where 'running' status remains too long and sets appropriate error message.
 =============================================================================
*/
AS
BEGIN TRY
    DECLARE @log_id NVARCHAR(50);
    DECLARE @procedure_call NVARCHAR(200);
    DECLARE @catch_output_tbl TABLE(returned_string NVARCHAR(MAX));
    DECLARE @catch_output_str NVARCHAR(MAX);

    -- Changing status to 'failed' to any entry that has 'running status for a long time
        -- (Not all errors are caught by TRY/CATCH or user canceled execution).
    UPDATE testing.dbo.proc_logs
        SET status = 'failed'
        ,   error_message = 'Had running status for too long. Status automatically changed to failed.'
    WHERE status = 'running'
      AND DATEDIFF(hour, created_at, GETDATE()) >= 24;

    -- Creating initial log.
    INSERT INTO testing.dbo.proc_logs(created_at, finished_at, proc_name, status, session_username, error_message, proc_params, proc_outputs)
    SELECT  GETDATE(), NULL, @procedure_path, 'running', session_user, ERROR_MESSAGE(), @procedure_parameters, NULL
    ;
    SET @log_id = SCOPE_IDENTITY();

    -- Preparing dynamic SQL string.
    IF @pass_log_id = 1
        SET @procedure_call = CONCAT_WS(' ', @procedure_path, @procedure_parameters, ',@log_id =' + @log_id);
    ELSE
        SET @procedure_call = CONCAT_WS(' ', @procedure_path, @procedure_parameters)

    -- Executing dynamic SQL and storing potential value returned from stored procedure.
    INSERT INTO @catch_output_tbl
    EXEC(@procedure_call);
    SET @catch_output_str = (SELECT STRING_AGG(returned_string, ', ') FROM @catch_output_tbl)

    -- Updating initial log
    UPDATE testing.dbo.proc_logs
        SET status = 'complete'
        ,   finished_at = GETDATE()
        ,   proc_outputs = @catch_output_str
    WHERE log_id = @log_id
    ;

END TRY
BEGIN CATCH
    -- Creating or updating initial log in case of an error.
    MERGE INTO testing.dbo.proc_logs AS TGT
    USING (
        SELECT
            @log_id AS log_id
        ,   'failed' AS status
        ,   ERROR_MESSAGE() AS error_message
        ,   GETDATE() AS created_at
        ,   GETDATE() AS finished_at
        ,   @procedure_path AS proc_name
        ,   session_user AS session_username
        ,   @procedure_parameters AS proc_params
        ,   @catch_output_str AS proc_outputs
        ) AS SRC
        ON SRC.log_id = TGT.log_id
    WHEN NOT MATCHED BY TARGET
        THEN INSERT(created_at, finished_at, proc_name, status, session_username, error_message, proc_params, proc_outputs)
             VALUES(created_at, finished_at, proc_name, status, session_username, error_message, proc_params, proc_outputs)
    WHEN MATCHED
        THEN UPDATE
            SET TGT.status = SRC.status
            ,   TGT.finished_at = SRC.finished_at
            ,   TGT.error_message = SRC.error_message
    ;
END CATCH
;

