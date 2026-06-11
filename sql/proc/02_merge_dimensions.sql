/* ============================================================================
   02_merge_dimensions.sql
   dm.merge_dimensions — upsert the four data-driven dims from staging.
   Run AFTER stg.load_jira_issue, BEFORE dm.merge_fact_issue.
   MERGE guardrails per forward-verify M2-P2-3: HOLDLOCK on every target,
   key-only ON clauses, matches resolve to index seeks on the UNIQUE keys.
   Walkthrough: TSQL_MODEL.md (repo root).
   ============================================================================ */

CREATE OR ALTER PROCEDURE dm.merge_dimensions
AS
BEGIN
    SET XACT_ABORT, NOCOUNT ON;

    BEGIN TRY
        ------------------------------------------------------------------
        -- Pre-flight: staging must be loaded.
        ------------------------------------------------------------------
        IF NOT EXISTS (SELECT 1 FROM stg.jira_issue)
        BEGIN
            ;THROW 50011, N'dm.merge_dimensions: stg.jira_issue is empty — run stg.load_jira_issue first.', 1;
        END;

        BEGIN TRANSACTION;

        ------------------------------------------------------------------
        -- dim_status: insert new statuses; status_category is mutable in
        -- Jira admin, so update it on drift. IS DISTINCT FROM gives a
        -- NULL-safe change test and a no-op-free UPDATE branch.
        ------------------------------------------------------------------
        MERGE dm.dim_status WITH (HOLDLOCK) AS tgt
        USING (SELECT DISTINCT status_name, status_category
               FROM stg.jira_issue) AS src
           ON tgt.status_name = src.status_name
        WHEN MATCHED AND tgt.status_category IS DISTINCT FROM src.status_category
            THEN UPDATE SET tgt.status_category = src.status_category
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (status_name, status_category)
                 VALUES (src.status_name, src.status_category);

        PRINT CONCAT(N'dim_status: ', @@ROWCOUNT, N' rows affected.');

        ------------------------------------------------------------------
        -- dim_priority / dim_issuetype / dim_component: name-only dims —
        -- insert-only MERGE (nothing to update on match).
        ------------------------------------------------------------------
        MERGE dm.dim_priority WITH (HOLDLOCK) AS tgt
        USING (SELECT DISTINCT priority_name
               FROM stg.jira_issue) AS src
           ON tgt.priority_name = src.priority_name
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (priority_name)
                 VALUES (src.priority_name);

        PRINT CONCAT(N'dim_priority: ', @@ROWCOUNT, N' rows affected.');

        MERGE dm.dim_issuetype WITH (HOLDLOCK) AS tgt
        USING (SELECT DISTINCT issuetype_name
               FROM stg.jira_issue) AS src
           ON tgt.issuetype_name = src.issuetype_name
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (issuetype_name)
                 VALUES (src.issuetype_name);

        PRINT CONCAT(N'dim_issuetype: ', @@ROWCOUNT, N' rows affected.');

        MERGE dm.dim_component WITH (HOLDLOCK) AS tgt
        USING (SELECT DISTINCT component_name
               FROM stg.jira_issue_component) AS src
           ON tgt.component_name = src.component_name
        WHEN NOT MATCHED BY TARGET
            THEN INSERT (component_name)
                 VALUES (src.component_name);

        PRINT CONCAT(N'dim_component: ', @@ROWCOUNT, N' rows affected.');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
