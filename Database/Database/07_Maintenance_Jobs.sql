-- =============================================
-- Maintenance & Cleanup Jobs
-- Schedule these to run periodically
-- =============================================

USE [XTRACHEF_DB]
GO

-- =============================================
-- Job 1: Archive Old Emails (Run Daily)
-- =============================================

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_ArchiveOldEmails]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_ArchiveOldEmails]
GO

CREATE PROCEDURE [dbo].[MTS_ArchiveOldEmails]
    @DaysToKeep INT = 30,
    @DryRun BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CutoffDate DATETIME = DATEADD(DAY, -@DaysToKeep, GETDATE());
    DECLARE @RecordsToDelete INT;

    -- Count records to be deleted
    SELECT @RecordsToDelete = COUNT(*)
    FROM MTS_EMAILMASTER
    WHERE REQUESTTIME < @CutoffDate
        AND STATUS IN (1, 2); -- Only success or failed

    IF @DryRun = 1
    BEGIN
        PRINT 'DRY RUN MODE - No records will be deleted'
        PRINT 'Records that would be deleted: ' + CAST(@RecordsToDelete AS VARCHAR)
        PRINT 'Cutoff date: ' + CAST(@CutoffDate AS VARCHAR)

        -- Show sample
        SELECT TOP 10
            ID,
            TEMPLATEID,
            STATUS,
            REQUESTTIME,
            DATEDIFF(DAY, REQUESTTIME, GETDATE()) AS DAYS_OLD
        FROM MTS_EMAILMASTER
        WHERE REQUESTTIME < @CutoffDate
            AND STATUS IN (1, 2)
        ORDER BY REQUESTTIME
    END
    ELSE
    BEGIN
        -- Delete old records
        DELETE FROM MTS_EMAILMASTER
        WHERE REQUESTTIME < @CutoffDate
            AND STATUS IN (1, 2);

        PRINT 'Deleted ' + CAST(@@ROWCOUNT AS VARCHAR) + ' old email records'
    END
END
GO

-- =============================================
-- Job 2: Reset Stuck Emails (Run Hourly)
-- =============================================

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_ResetStuckEmails]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_ResetStuckEmails]
GO

CREATE PROCEDURE [dbo].[MTS_ResetStuckEmails]
    @HoursThreshold INT = 2
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StuckCount INT;
    DECLARE @CutoffTime DATETIME = DATEADD(HOUR, -@HoursThreshold, GETDATE());

    -- Find stuck emails (pending for too long)
    SELECT @StuckCount = COUNT(*)
    FROM MTS_EMAILMASTER
    WHERE STATUS = 0 -- Pending
        AND REQUESTTIME < @CutoffTime;

    IF @StuckCount > 0
    BEGIN
        -- Mark as failed so they don't block forever
        UPDATE MTS_EMAILMASTER
        SET
            STATUS = 2, -- Failed
            ERROR_MSG = 'Email stuck in pending for over ' + CAST(@HoursThreshold AS VARCHAR) + ' hours. Auto-marked as failed.'
        WHERE STATUS = 0
            AND REQUESTTIME < @CutoffTime;

        PRINT 'Reset ' + CAST(@@ROWCOUNT AS VARCHAR) + ' stuck emails'
    END
    ELSE
    BEGIN
        PRINT 'No stuck emails found'
    END
END
GO

-- =============================================
-- Job 3: Update Statistics (Run Weekly)
-- =============================================

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_UpdateEmailStatistics]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_UpdateEmailStatistics]
GO

CREATE PROCEDURE [dbo].[MTS_UpdateEmailStatistics]
AS
BEGIN
    SET NOCOUNT ON;

    -- Update statistics on main table
    UPDATE STATISTICS MTS_EMAILMASTER WITH FULLSCAN;
    PRINT 'Updated statistics for MTS_EMAILMASTER'

    UPDATE STATISTICS MTS_EMAILSCHEDULE WITH FULLSCAN;
    PRINT 'Updated statistics for MTS_EMAILSCHEDULE'

    UPDATE STATISTICS MTS_EMAILTEMPLATE WITH FULLSCAN;
    PRINT 'Updated statistics for MTS_EMAILTEMPLATE'

    UPDATE STATISTICS MTS_SERVICECONFIG WITH FULLSCAN;
    PRINT 'Updated statistics for MTS_SERVICECONFIG'

    -- Rebuild indexes if fragmented
    DECLARE @TableName VARCHAR(100) = 'MTS_EMAILMASTER';
    DECLARE @IndexName VARCHAR(100);
    DECLARE @Fragmentation FLOAT;

    DECLARE index_cursor CURSOR FOR
    SELECT
        i.name,
        ps.avg_fragmentation_in_percent
    FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('MTS_EMAILMASTER'), NULL, NULL, 'LIMITED') ps
    JOIN sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
    WHERE ps.avg_fragmentation_in_percent > 30
        AND i.name IS NOT NULL;

    OPEN index_cursor;
    FETCH NEXT FROM index_cursor INTO @IndexName, @Fragmentation;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT 'Rebuilding index ' + @IndexName + ' (Fragmentation: ' + CAST(@Fragmentation AS VARCHAR) + '%)'
        EXEC('ALTER INDEX [' + @IndexName + '] ON [MTS_EMAILMASTER] REBUILD')
        FETCH NEXT FROM index_cursor INTO @IndexName, @Fragmentation;
    END

    CLOSE index_cursor;
    DEALLOCATE index_cursor;

    PRINT 'Statistics update complete'
END
GO

-- =============================================
-- Job 4: Generate Daily Report
-- =============================================

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_GenerateDailyReport]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_GenerateDailyReport]
GO

CREATE PROCEDURE [dbo].[MTS_GenerateDailyReport]
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '========================================='
    PRINT 'DAILY EMAIL NOTIFICATION REPORT'
    PRINT 'Date: ' + CAST(GETDATE() AS VARCHAR)
    PRINT '========================================='
    PRINT ''

    -- Summary
    PRINT '--- SUMMARY (Last 24 Hours) ---'
    SELECT
        COUNT(*) AS TOTAL_EMAILS,
        SUM(CASE WHEN STATUS = 1 THEN 1 ELSE 0 END) AS SUCCESS,
        SUM(CASE WHEN STATUS = 2 THEN 1 ELSE 0 END) AS FAILED,
        SUM(CASE WHEN STATUS = 0 THEN 1 ELSE 0 END) AS PENDING,
        SUM(CASE WHEN STATUS = 3 THEN 1 ELSE 0 END) AS RETRY,
        CAST(SUM(CASE WHEN STATUS = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS SUCCESS_RATE
    FROM MTS_EMAILMASTER
    WHERE REQUESTTIME >= DATEADD(HOUR, -24, GETDATE())

    PRINT ''
    PRINT '--- BY TEMPLATE ---'
    SELECT
        t.TEMPLATENAME,
        COUNT(*) AS TOTAL,
        SUM(CASE WHEN em.STATUS = 1 THEN 1 ELSE 0 END) AS SUCCESS,
        SUM(CASE WHEN em.STATUS = 2 THEN 1 ELSE 0 END) AS FAILED
    FROM MTS_EMAILMASTER em
    JOIN MTS_EMAILTEMPLATE t ON em.TEMPLATEID = t.TEMPLATEID
    WHERE em.REQUESTTIME >= DATEADD(HOUR, -24, GETDATE())
    GROUP BY t.TEMPLATENAME
    ORDER BY TOTAL DESC

    PRINT ''
    PRINT '--- SERVICE HEALTH ---'
    SELECT
        SERVICENAME,
        STATUS,
        LAST_RUN,
        DATEDIFF(MINUTE, LAST_RUN, GETDATE()) AS MINUTES_SINCE_LAST_RUN,
        LAST_ERROR
    FROM MTS_SERVICECONFIG
    WHERE SERVICENAME = 'AppNativeNotificationService'

    PRINT ''
    PRINT '--- ERRORS (If Any) ---'
    SELECT TOP 10
        ID,
        TEMPLATEID,
        REQUESTTIME,
        ERROR_MSG
    FROM MTS_EMAILMASTER
    WHERE STATUS = 2
        AND REQUESTTIME >= DATEADD(HOUR, -24, GETDATE())
    ORDER BY REQUESTTIME DESC

    PRINT ''
    PRINT '========================================='
    PRINT 'END OF REPORT'
    PRINT '========================================='
END
GO

-- =============================================
-- SQL Agent Job Creation Scripts
-- =============================================

PRINT ''
PRINT '========================================='
PRINT 'CREATE SQL AGENT JOBS'
PRINT '========================================='
PRINT ''
PRINT '-- Job 1: Daily Archive (Run at 2 AM)'
PRINT 'EXEC MTS_ArchiveOldEmails @DaysToKeep = 30, @DryRun = 0'
PRINT ''
PRINT '-- Job 2: Hourly Stuck Email Reset'
PRINT 'EXEC MTS_ResetStuckEmails @HoursThreshold = 2'
PRINT ''
PRINT '-- Job 3: Weekly Statistics Update (Run Sunday 3 AM)'
PRINT 'EXEC MTS_UpdateEmailStatistics'
PRINT ''
PRINT '-- Job 4: Daily Report (Run at 8 AM)'
PRINT 'EXEC MTS_GenerateDailyReport'
PRINT ''

PRINT 'Maintenance procedures created successfully!'
GO
