-- =============================================
-- Admin Dashboard Queries
-- Copy these for your UI/reporting
-- =============================================

USE [XTRACHEF_DB]
GO

-- =============================================
-- 1. OVERVIEW DASHBOARD
-- =============================================

-- Real-time Statistics
SELECT
    'Last 1 Hour' AS PERIOD,
    COUNT(*) AS TOTAL,
    SUM(CASE WHEN STATUS = 0 THEN 1 ELSE 0 END) AS PENDING,
    SUM(CASE WHEN STATUS = 1 THEN 1 ELSE 0 END) AS SUCCESS,
    SUM(CASE WHEN STATUS = 2 THEN 1 ELSE 0 END) AS FAILED,
    SUM(CASE WHEN STATUS = 3 THEN 1 ELSE 0 END) AS RETRY
FROM MTS_EMAILMASTER
WHERE REQUESTTIME >= DATEADD(HOUR, -1, GETDATE())

UNION ALL

SELECT
    'Last 24 Hours',
    COUNT(*),
    SUM(CASE WHEN STATUS = 0 THEN 1 ELSE 0 END),
    SUM(CASE WHEN STATUS = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN STATUS = 2 THEN 1 ELSE 0 END),
    SUM(CASE WHEN STATUS = 3 THEN 1 ELSE 0 END)
FROM MTS_EMAILMASTER
WHERE REQUESTTIME >= DATEADD(HOUR, -24, GETDATE())

UNION ALL

SELECT
    'Last 7 Days',
    COUNT(*),
    SUM(CASE WHEN STATUS = 0 THEN 1 ELSE 0 END),
    SUM(CASE WHEN STATUS = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN STATUS = 2 THEN 1 ELSE 0 END),
    SUM(CASE WHEN STATUS = 3 THEN 1 ELSE 0 END)
FROM MTS_EMAILMASTER
WHERE REQUESTTIME >= DATEADD(DAY, -7, GETDATE())
GO

-- =============================================
-- 2. SERVICE STATUS
-- =============================================

SELECT
    SERVICENAME,
    CASE STATUS
        WHEN 0 THEN '🔴 Stopped'
        WHEN 1 THEN '🟢 Running'
        ELSE '⚪ Unknown'
    END AS STATUS,
    LAST_RUN,
    DATEDIFF(MINUTE, LAST_RUN, GETDATE()) AS MINUTES_AGO,
    CASE
        WHEN LAST_RUN IS NULL THEN '❌ Never Run'
        WHEN DATEDIFF(MINUTE, LAST_RUN, GETDATE()) > 10 THEN '⚠️ Stale'
        WHEN DATEDIFF(MINUTE, LAST_RUN, GETDATE()) > 5 THEN '⚡ Warning'
        ELSE '✅ Healthy'
    END AS HEALTH,
    LAST_ERROR
FROM MTS_SERVICECONFIG
WHERE SERVICENAME = 'AppNativeNotificationService'
GO

-- =============================================
-- 3. EMAIL QUEUE BY TEMPLATE
-- =============================================

SELECT
    t.TEMPLATEID,
    t.TEMPLATENAME,
    s.SCHEDULEDESCRIPTION,
    CASE s.SENDBY
        WHEN 0 THEN 'Not Scheduled'
        WHEN 1 THEN '⚡ Immediate'
        WHEN 2 THEN '📅 Daily at ' + CAST(s.TIME AS VARCHAR)
        WHEN 3 THEN '📆 Weekly on ' + s.DAY
        WHEN 4 THEN '📌 Monthly on ' + s.DAY
    END AS SCHEDULE,
    COUNT(em.ID) AS PENDING_COUNT,
    MIN(em.REQUESTTIME) AS OLDEST,
    MAX(em.REQUESTTIME) AS NEWEST
FROM MTS_EMAILTEMPLATE t
LEFT JOIN MTS_EMAILSCHEDULE s ON t.TEMPLATEID = s.TEMPLATEID
LEFT JOIN MTS_EMAILMASTER em ON t.TEMPLATEID = em.TEMPLATEID AND em.STATUS = 0
WHERE t.ACTIVE = 1
GROUP BY t.TEMPLATEID, t.TEMPLATENAME, s.SCHEDULEDESCRIPTION, s.SENDBY, s.TIME, s.DAY
ORDER BY PENDING_COUNT DESC
GO

-- =============================================
-- 4. RECENT ACTIVITY (Last 50)
-- =============================================

SELECT TOP 50
    em.ID,
    t.TEMPLATENAME,
    LEFT(em.EMAILSP, 50) + '...' AS EMAIL_DATA,
    CASE em.STATUS
        WHEN 0 THEN '⏳ Pending'
        WHEN 1 THEN '✅ Success'
        WHEN 2 THEN '❌ Failed'
        WHEN 3 THEN '🔄 Retry'
    END AS STATUS,
    em.RETRY_COUNT,
    em.REQUESTTIME,
    DATEDIFF(MINUTE, em.REQUESTTIME, GETDATE()) AS AGE_MINUTES,
    em.ERROR_MSG,
    em.CORRELATION_ID
FROM MTS_EMAILMASTER em
JOIN MTS_EMAILTEMPLATE t ON em.TEMPLATEID = t.TEMPLATEID
ORDER BY em.REQUESTTIME DESC
GO

-- =============================================
-- 5. FAILED EMAILS (Need Attention)
-- =============================================

SELECT
    em.ID,
    t.TEMPLATENAME,
    em.EMAILSP,
    em.REQUESTTIME,
    DATEDIFF(HOUR, em.REQUESTTIME, GETDATE()) AS HOURS_AGO,
    em.RETRY_COUNT,
    em.ERROR_MSG,
    em.CORRELATION_ID
FROM MTS_EMAILMASTER em
JOIN MTS_EMAILTEMPLATE t ON em.TEMPLATEID = t.TEMPLATEID
WHERE em.STATUS = 2 -- Failed
    AND em.REQUESTTIME >= DATEADD(DAY, -7, GETDATE())
ORDER BY em.REQUESTTIME DESC
GO

-- =============================================
-- 6. HOURLY PERFORMANCE (Last 24 Hours)
-- =============================================

SELECT
    DATEPART(HOUR, REQUESTTIME) AS HOUR,
    COUNT(*) AS TOTAL,
    SUM(CASE WHEN STATUS = 1 THEN 1 ELSE 0 END) AS SUCCESS,
    SUM(CASE WHEN STATUS = 2 THEN 1 ELSE 0 END) AS FAILED,
    CAST(SUM(CASE WHEN STATUS = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS SUCCESS_RATE
FROM MTS_EMAILMASTER
WHERE REQUESTTIME >= DATEADD(HOUR, -24, GETDATE())
GROUP BY DATEPART(HOUR, REQUESTTIME)
ORDER BY HOUR DESC
GO

-- =============================================
-- 7. TEMPLATE SUCCESS RATES
-- =============================================

SELECT
    t.TEMPLATENAME,
    COUNT(em.ID) AS TOTAL_SENT,
    SUM(CASE WHEN em.STATUS = 1 THEN 1 ELSE 0 END) AS SUCCESS,
    SUM(CASE WHEN em.STATUS = 2 THEN 1 ELSE 0 END) AS FAILED,
    CAST(SUM(CASE WHEN em.STATUS = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(em.ID) AS DECIMAL(5,2)) AS SUCCESS_RATE,
    AVG(em.RETRY_COUNT) AS AVG_RETRIES
FROM MTS_EMAILTEMPLATE t
JOIN MTS_EMAILMASTER em ON t.TEMPLATEID = em.TEMPLATEID
WHERE em.REQUESTTIME >= DATEADD(DAY, -7, GETDATE())
    AND em.STATUS IN (1, 2) -- Completed only
GROUP BY t.TEMPLATENAME
ORDER BY SUCCESS_RATE ASC
GO

-- =============================================
-- 8. STUCK EMAILS (Pending > 1 Hour)
-- =============================================

SELECT
    em.ID,
    t.TEMPLATENAME,
    em.EMAILSP,
    em.REQUESTTIME,
    DATEDIFF(MINUTE, em.REQUESTTIME, GETDATE()) AS MINUTES_PENDING,
    em.RETRY_COUNT,
    em.CORRELATION_ID
FROM MTS_EMAILMASTER em
JOIN MTS_EMAILTEMPLATE t ON em.TEMPLATEID = t.TEMPLATEID
WHERE em.STATUS = 0 -- Pending
    AND DATEDIFF(HOUR, em.REQUESTTIME, GETDATE()) >= 1
ORDER BY em.REQUESTTIME
GO

-- =============================================
-- 9. SCHEDULE CONFIGURATION
-- =============================================

SELECT
    s.SCHEDULEID,
    t.TEMPLATENAME,
    s.SCHEDULEDESCRIPTION,
    CASE s.SENDBY
        WHEN 0 THEN 'Not Scheduled'
        WHEN 1 THEN 'Immediate'
        WHEN 2 THEN 'Daily'
        WHEN 3 THEN 'Weekly'
        WHEN 4 THEN 'Monthly'
    END AS TYPE,
    s.DAY AS [Days/Dates],
    CONVERT(VARCHAR(5), s.TIME, 108) AS [Time],
    t.ACTIVE AS [Template Active]
FROM MTS_EMAILSCHEDULE s
JOIN MTS_EMAILTEMPLATE t ON s.TEMPLATEID = t.TEMPLATEID
ORDER BY s.SCHEDULEID
GO

PRINT 'Dashboard queries ready! Copy-paste these for your admin UI.'
GO
