-- =============================================
-- Test Data Script
-- Add sample emails to test the service
-- =============================================

USE [XTRACHEF_DB]
GO

-- Test 1: Insert Immediate Email (SENDBY=1)
PRINT 'Inserting test immediate email...'
EXEC MTS_EMAILMASTERENTRY
    @TEMPLATEID = 2,
    @EMAILSP = 'test@example.com~Test User~This is a test offer notification',
    @CORRELATION_ID = 'TEST-IMMEDIATE-001'
GO

-- Test 2: Insert Password Reset Email (SENDBY=1)
PRINT 'Inserting test password reset email...'
EXEC MTS_EMAILMASTERENTRY
    @TEMPLATEID = 3,
    @EMAILSP = 'user@example.com~John Doe~https://reset-link.com/token123',
    @CORRELATION_ID = 'TEST-RESET-001'
GO

-- Test 3: Insert Order Notification (SENDBY=0 - Not Scheduled)
PRINT 'Inserting test order notification...'
EXEC MTS_EMAILMASTERENTRY
    @TEMPLATEID = 1,
    @EMAILSP = 'customer@example.com~Jane Smith~Order #12345 has been placed',
    @CORRELATION_ID = 'TEST-ORDER-001'
GO

-- View pending emails
PRINT 'Pending emails in queue:'
SELECT
    ID,
    TEMPLATEID,
    EMAILSP,
    REQUESTTIME,
    STATUS,
    RETRY_COUNT,
    CORRELATION_ID
FROM MTS_EMAILMASTER
WHERE STATUS = 0
ORDER BY REQUESTTIME DESC
GO

-- View schedules
PRINT 'Email schedules:'
SELECT
    s.SCHEDULEID,
    s.TEMPLATEID,
    t.TEMPLATENAME,
    s.SCHEDULEDESCRIPTION,
    s.SENDBY,
    CASE s.SENDBY
        WHEN 0 THEN 'Not Scheduled'
        WHEN 1 THEN 'Immediate'
        WHEN 2 THEN 'Daily'
        WHEN 3 THEN 'Weekly'
        WHEN 4 THEN 'Monthly'
    END AS SENDBY_DESC,
    s.DAY,
    s.[TIME]
FROM MTS_EMAILSCHEDULE s
INNER JOIN MTS_EMAILTEMPLATE t ON s.TEMPLATEID = t.TEMPLATEID
ORDER BY s.SCHEDULEID
GO

-- View service status
PRINT 'Service configuration:'
SELECT
    SERVICENAME,
    SERVICEDISPLAYNAME,
    STATUS,
    LAST_RUN,
    LAST_ERROR
FROM MTS_SERVICECONFIG
WHERE SERVICENAME = 'AppNativeNotificationService'
GO

PRINT 'Test data created successfully!'
PRINT 'Run the service with: AppNativeNotification.exe --runonce'
GO
