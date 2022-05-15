CREATE PROC dbo.logger
    @procedure_path NVARCHAR(100)
,   @procedure_parameters NVARCHAR(500)
,   @pass_log_id BIT = 0
,   @catch_output BIT = 0

/*
=============================================================================
DESCRIPTION:
    A procedure that generates and inserts logs into target table.

PARAMETERS:
    @procedure_path: a string with path to stored procedure that will be executed.
        Example: @procedure_path = testing.dbo.load_data
    @procedure_parameters: a string with all parameters that procedure declared in @procedure_path needs.
        Example: @procedure_parameters = '@metric_name='asd',@value=100'
    @pass_log_id: If 1 procedure will pass log_id that was generated during
        execution of this procedure so that the procedure declared in @procedure_path can receive it and further process it.
        This can be helpful for instance when it's needed to write proc_outputs during the runtime:
            update logger.dbo.logs
                set proc_outputs = json_modify(proc_outputs, '$.runtime_output', json_query('{"something": 500}'))
            where log_id = @log_id
    @catch_output: If 1 then procedure from @procedure_path is required to have @json_log OUTPUT parameter in form of JSON. through which additional logs from inner procedure can be passed. It is required that whole procedure runs without any error to save the output.

ADDITIONAL INFO:
    Procedure updates any logs where 'running' status remains too long and sets appropriate error message.

KNOWN ISSUES:
    If procedure from @procedure_path has TRY CATCH then error and status will not be logged properly. That inner procedure would have to THROW the error from CATCH block.
 =============================================================================
*/
AS
BEGIN TRY
    DECLARE @log_id NVARCHAR(50);
    DECLARE @procedure_call NVARCHAR(200);
    DECLARE @procedure_parameters_combined NVARCHAR(600)
    DECLARE @output_log NVARCHAR(MAX);

    -- Changing status to 'failed' to any entry that has 'running status for a long time
        -- (Not all errors are caught by TRY/CATCH or user canceled execution).
    UPDATE logger.dbo.logs
        SET status = 'failed'
        ,   error_message = 'Had running status for too long. Status automatically changed to failed.'
    WHERE status = 'running'
      AND DATEDIFF(hour, created_at, GETDATE()) >= 24;

    -- Creating initial log.
    INSERT INTO logger.dbo.logs(created_at, finished_at, proc_name, status, session_username, error_message, proc_params, proc_outputs)
    SELECT  GETDATE(), NULL, @procedure_path, 'running', session_user, ERROR_MESSAGE(), @procedure_parameters, '{}';
    -- Storing log id. Inserting row to logs table should be generating new identity value.
    SET @log_id = CAST(SCOPE_IDENTITY() AS VARCHAR(38));

    -- Preparing parameters string for dynamic SQL string.
    SET @procedure_parameters_combined = @procedure_parameters;

    IF @pass_log_id = 1
        SET @procedure_parameters_combined = CONCAT_WS(', ', @procedure_parameters_combined, '@log_id = ' + @log_id);

    IF @catch_output = 1
        SET @procedure_parameters_combined = CONCAT_WS(', ', @procedure_parameters_combined, '@json_log = @catching_output OUTPUT');

    -- Preparing final dynamic SQL string.
    SET @procedure_call = CONCAT_WS(' ', @procedure_path, @procedure_parameters_combined)

    -- Executing dynamic SQL and storing output value returned from stored procedure.
    IF @catch_output = 1
        BEGIN
            EXEC sp_executesql
                @stmt = @procedure_call,
                @params = N'@catching_output NVARCHAR(MAX) OUTPUT',
                @catching_output = @output_log OUTPUT
        END;
    IF @catch_output = 0
        BEGIN
            EXEC(@procedure_call);
        END;

    -- Updating initial log
    UPDATE logger.dbo.logs
        SET status = 'complete'
        ,   finished_at = GETDATE()
        ,   proc_outputs = JSON_MODIFY(proc_outputs, '$.final_procedure_output', JSON_QUERY(COALESCE(@output_log, '{}')))
    WHERE log_id = @log_id;

END TRY
BEGIN CATCH
    -- Creating or updating initial log in case of an error.
    MERGE INTO logger.dbo.logs AS TGT
    USING (
        SELECT
            @log_id AS log_id
        ,   'failed' AS status
        ,   ERROR_MESSAGE() AS error_message
        ,   ERROR_PROCEDURE() AS error_proc
        ,   ERROR_LINE() AS error_line
        ,   ERROR_SEVERITY() AS error_severity
        ,   ERROR_STATE() AS error_state
        ,   GETDATE() AS created_at
        ,   GETDATE() AS finished_at
        ,   @procedure_path AS proc_name
        ,   session_user AS session_username
        ,   @procedure_parameters AS proc_params
        ,   @output_log AS proc_outputs
        ) AS SRC
        ON SRC.log_id = TGT.log_id
    WHEN NOT MATCHED BY TARGET
        THEN INSERT(created_at, finished_at, proc_name, status, session_username, proc_params
                  , proc_outputs
                  , error_message, error_proc, error_line, error_severity, error_state)
             VALUES(SRC.created_at, SRC.finished_at, SRC.proc_name, SRC.status, SRC.session_username, SRC.proc_params
                  , SRC.proc_outputs
                  , SRC.error_message, SRC.error_proc, SRC.error_line, SRC.error_severity, SRC.error_state)
    WHEN MATCHED
        THEN UPDATE
            SET TGT.status = SRC.status
            ,   TGT.finished_at = SRC.finished_at
            ,   TGT.error_message = SRC.error_message
            ,   TGT.error_proc = SRC.error_proc
            ,   TGT.error_line = SRC.error_line
            ,   TGT.error_severity = SRC.error_severity
            ,   TGT.error_state = SRC.error_state
    ;
END CATCH
;