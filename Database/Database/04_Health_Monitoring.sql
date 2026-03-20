-- =============================================
-- Health Check & Monitoring Views/Procedures
-- =============================================

USE [XTRACHEF_DB]
GO

-- View: Email Queue Summary
IF EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[dbo].[VW_EMAIL_QUEUE_SUMMARY]'))
    DROP VIEW [dbo].[VW_EMAIL_QUEUE_SUMMARY]
GO

CREATE VIEW [dbo].[VW_EMAIL_QUEUE_SUMMARY]
AS
SELECT
    COUNT(*) AS TOTAL_EMAILS,
    SUM(CASE WHEN STATUS = 0 THEN 1 ELSE 0 END) AS PENDING,
    SUM(CASE WHEN STATUS = 1 THEN 1 ELSE 0 END) AS SUCCESS,
    SUM(CASE WHEN STATUS = 2 THEN 1 ELSE 0 END) AS FAILED,
    SUM(CASE WHEN STATUS = 3 THEN 1 ELSE 0 END) AS RETRY,
    MIN(CASE WHEN STATUS = 0 THEN REQUESTTIME END) AS OLDEST_PENDING,
    MAX(CASE WHEN STATUS = 1 THEN REQUESTTIME END) AS LAST_SUCCESS
FROM MTS_EMAILMASTER
WHERE REQUESTTIME >= DATEADD(HOUR, -24, GETDATE())
GO

-- View: Service Health Check
IF EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[dbo].[VW_SERVICE_HEALTH]'))
    DROP VIEW [dbo].[VW_SERVICE_HEALTH]
GO

CREATE VIEW [dbo].[VW_SERVICE_HEALTH]
AS
SELECT
    SERVICENAME,
    STATUS,
    CASE STATUS WHEN 1 THEN 'Running' ELSE 'Stopped' END AS STATUS_DESC,
    LAST_RUN,
    DATEDIFF(MINUTE, LAST_RUN, GETDATE()) AS MINUTES_SINCE_LAST_RUN,
    CASE
        WHEN LAST_RUN IS NULL THEN 'Never Run'
        WHEN DATEDIFF(MINUTE, LAST_RUN, GETDATE()) > 10 THEN 'Stale - Check Service'
        WHEN DATEDIFF(MINUTE, LAST_RUN, GETDATE()) > 5 THEN 'Warning'
        ELSE 'Healthy'
    END AS HEALTH_STATUS,
    LAST_ERROR
FROM MTS_SERVICECONFIG
WHERE SERVICENAME = 'AppNativeNotificationService'
GO

-- SP: Get Failed Emails Report
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_GetFailedEmailsReport]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_GetFailedEmailsReport]
GO

CREATE PROCEDURE [dbo].[MTS_GetFailedEmailsReport]
    @HoursBack INT = 24
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        em.ID,
        em.TEMPLATEID,
        et.TEMPLATENAME,
        em.EMAILSP,
        em.REQUESTTIME,
        em.RETRY_COUNT,
        em.ERROR_MSG,
        em.CORRELATION_ID
    FROM MTS_EMAILMASTER em
    JOIN MTS_EMAILTEMPLATE et ON em.TEMPLATEID = et.TEMPLATEID
    WHERE em.STATUS = 2 -- Failed
        AND em.REQUESTTIME >= DATEADD(HOUR, -@HoursBack, GETDATE())
    ORDER BY em.REQUESTTIME DESC
END
GO

-- SP: Get Pending Emails Count by Template
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_GetPendingEmailsByTemplate]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_GetPendingEmailsByTemplate]
GO

CREATE PROCEDURE [dbo].[MTS_GetPendingEmailsByTemplate]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        et.TEMPLATEID,
        et.TEMPLATENAME,
        COUNT(*) AS PENDING_COUNT,
        MIN(em.REQUESTTIME) AS OLDEST_PENDING,
        MAX(em.REQUESTTIME) AS NEWEST_PENDING
    FROM MTS_EMAILMASTER em
    JOIN MTS_EMAILTEMPLATE et ON em.TEMPLATEID = et.TEMPLATEID
    WHERE em.STATUS = 0 -- Pending
    GROUP BY et.TEMPLATEID, et.TEMPLATENAME
    ORDER BY PENDING_COUNT DESC
END
GO

-- SP: Clean Old Records
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_CleanOldEmailRecords]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_CleanOldEmailRecords]
GO

CREATE PROCEDURE [dbo].[MTS_CleanOldEmailRecords]
    @DaysToKeep INT = 30,
    @DryRun BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DeleteCount INT;
    DECLARE @CutoffDate DATETIME = DATEADD(DAY, -@DaysToKeep, GETDATE());

    IF @DryRun = 1
    BEGIN
        -- Show what would be deleted
        SELECT
            'Would delete ' + CAST(COUNT(*) AS VARCHAR) + ' records older than ' + CAST(@CutoffDate AS VARCHAR) AS SUMMARY
        FROM MTS_EMAILMASTER
        WHERE REQUESTTIME < @CutoffDate
            AND STATUS IN (1, 2); -- Success or Failed only

        SELECT TOP 100
            ID,
            TEMPLATEID,
            STATUS,
            REQUESTTIME,
            ERROR_MSG
        FROM MTS_EMAILMASTER
        WHERE REQUESTTIME < @CutoffDate
            AND STATUS IN (1, 2)
        ORDER BY REQUESTTIME
    END
    ELSE
    BEGIN
        -- Actually delete
        DELETE FROM MTS_EMAILMASTER
        WHERE REQUESTTIME < @CutoffDate
            AND STATUS IN (1, 2); -- Don't delete pending or retry

        SET @DeleteCount = @@ROWCOUNT;

        SELECT
            @DeleteCount AS RECORDS_DELETED,
            @CutoffDate AS CUTOFF_DATE,
            GETDATE() AS DELETED_AT;
    END
END
GO

-- Quick Health Check Query
PRINT '=== HEALTH CHECK QUERIES ==='
PRINT ''
PRINT '-- Check Queue Summary'
PRINT 'SELECT * FROM VW_EMAIL_QUEUE_SUMMARY'
PRINT ''
PRINT '-- Check Service Health'
PRINT 'SELECT * FROM VW_SERVICE_HEALTH'
PRINT ''
PRINT '-- Get Failed Emails (Last 24 hours)'
PRINT 'EXEC MTS_GetFailedEmailsReport @HoursBack = 24'
PRINT ''
PRINT '-- Get Pending Count by Template'
PRINT 'EXEC MTS_GetPendingEmailsByTemplate'
PRINT ''
PRINT '-- Clean Old Records (Dry Run)'
PRINT 'EXEC MTS_CleanOldEmailRecords @DaysToKeep = 30, @DryRun = 1'
GO

PRINT 'Health monitoring objects created successfully!'
GO
