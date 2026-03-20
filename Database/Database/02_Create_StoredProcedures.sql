-- =============================================
-- App Native Notification Service - Stored Procedures
-- Simple and Clean Implementation
-- =============================================

USE [XTRACHEF_DB]
GO

-- =============================================
-- SP: MTS_GetEmailSchedule
-- Get immediate email schedules (SENDBY = 1)
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_GetEmailSchedule]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_GetEmailSchedule]
GO

CREATE PROCEDURE [dbo].[MTS_GetEmailSchedule]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        SCHEDULEID,
        TEMPLATEID,
        SCHEDULEDESCRIPTION,
        SENDBY,
        DAY,
        [TIME]
    FROM MTS_EMAILSCHEDULE WITH (NOLOCK)
    WHERE SENDBY = 1; -- Immediate only
END
GO

-- =============================================
-- SP: MTS_GetEmailScheduleForTimeScheduler
-- Get time-based schedules (Daily, Weekly, Monthly)
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_GetEmailScheduleForTimeScheduler]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_GetEmailScheduleForTimeScheduler]
GO

CREATE PROCEDURE [dbo].[MTS_GetEmailScheduleForTimeScheduler]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        SCHEDULEID,
        TEMPLATEID,
        SCHEDULEDESCRIPTION,
        SENDBY,
        DAY,
        [TIME]
    FROM MTS_EMAILSCHEDULE WITH (NOLOCK)
    WHERE SENDBY IN (2, 3, 4); -- Daily, Weekly, Monthly
END
GO

-- =============================================
-- SP: MTS_GetEmailsWaitingToBeSend
-- Get emails by status
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_GetEmailsWaitingToBeSend]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_GetEmailsWaitingToBeSend]
GO

CREATE PROCEDURE [dbo].[MTS_GetEmailsWaitingToBeSend]
    @STATUS TINYINT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 100
        ID,
        TEMPLATEID,
        EMAILSP,
        REQUESTTIME,
        STATUS,
        RETRY_COUNT,
        ERROR_MSG,
        CORRELATION_ID
    FROM MTS_EMAILMASTER WITH (NOLOCK)
    WHERE STATUS = @STATUS
    ORDER BY REQUESTTIME ASC;
END
GO

-- =============================================
-- SP: MTS_GetEmailTemplate
-- Get all active templates
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_GetEmailTemplate]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_GetEmailTemplate]
GO

CREATE PROCEDURE [dbo].[MTS_GetEmailTemplate]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        TEMPLATEID,
        TEMPLATENAME,
        DESCRIPTION,
        ACTIVE
    FROM MTS_EMAILTEMPLATE WITH (NOLOCK)
    WHERE ACTIVE = 1;
END
GO

-- =============================================
-- SP: MTS_UpdateEmailStatus
-- Update email status with retry logic
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_UpdateEmailStatus]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_UpdateEmailStatus]
GO

CREATE PROCEDURE [dbo].[MTS_UpdateEmailStatus]
    @Id BIGINT,
    @STATUS TINYINT,
    @CORRELATION_ID VARCHAR(100) = NULL,
    @ERROR_MSG VARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RETRY_COUNT INT = 0;
    DECLARE @MAX_RETRIES INT = 3;
    DECLARE @NEW_STATUS TINYINT = @STATUS;

    -- Get current retry count
    SELECT @RETRY_COUNT = RETRY_COUNT
    FROM MTS_EMAILMASTER WITH (NOLOCK)
    WHERE ID = @Id;

    -- Handle failure with retry logic
    IF @STATUS = 2 -- Failed
    BEGIN
        IF @RETRY_COUNT < @MAX_RETRIES
        BEGIN
            SET @NEW_STATUS = 3; -- Retry
            SET @RETRY_COUNT = @RETRY_COUNT + 1;
        END
        ELSE
        BEGIN
            SET @NEW_STATUS = 2; -- Final failure
        END
    END

    -- Update record
    UPDATE MTS_EMAILMASTER
    SET
        STATUS = @NEW_STATUS,
        RETRY_COUNT = @RETRY_COUNT,
        ERROR_MSG = @ERROR_MSG,
        CORRELATION_ID = ISNULL(@CORRELATION_ID, CORRELATION_ID)
    WHERE ID = @Id;

    -- Return new status
    SELECT @NEW_STATUS AS RESULT_STATUS;
END
GO

-- =============================================
-- SP: MTS_GETTEMPLATEIDFROMSCHEDULEID
-- Get template ID from schedule ID
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_GETTEMPLATEIDFROMSCHEDULEID]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_GETTEMPLATEIDFROMSCHEDULEID]
GO

CREATE PROCEDURE [dbo].[MTS_GETTEMPLATEIDFROMSCHEDULEID]
    @Scheduleid INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TEMPLATEID
    FROM MTS_EMAILSCHEDULE WITH (NOLOCK)
    WHERE SCHEDULEID = @Scheduleid;
END
GO

-- =============================================
-- SP: MTS_EMAILMASTERENTRY
-- Insert new email into queue
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_EMAILMASTERENTRY]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_EMAILMASTERENTRY]
GO

CREATE PROCEDURE [dbo].[MTS_EMAILMASTERENTRY]
    @TEMPLATEID BIGINT,
    @EMAILSP VARCHAR(500),
    @CORRELATION_ID VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO MTS_EMAILMASTER
        (TEMPLATEID, EMAILSP, REQUESTTIME, STATUS, RETRY_COUNT, CORRELATION_ID)
    VALUES
        (@TEMPLATEID, @EMAILSP, GETDATE(), 0, 0, @CORRELATION_ID);

    SELECT SCOPE_IDENTITY() AS NEW_ID;
END
GO

-- =============================================
-- SP: MTS_GETSERVICECONFIG
-- Get all service configurations
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_GETSERVICECONFIG]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_GETSERVICECONFIG]
GO

CREATE PROCEDURE [dbo].[MTS_GETSERVICECONFIG]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        SERVICEID,
        SERVICENAME,
        SERVICEDISPLAYNAME,
        SERVICEDESCRIPTION,
        SERVICEINVOKETYPE,
        TIME,
        STATUS,
        LAST_RUN,
        LAST_ERROR
    FROM MTS_SERVICECONFIG WITH (NOLOCK);
END
GO

-- =============================================
-- SP: MTS_GETSERVICECONFIGFORSERVICE
-- Get specific service configuration
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_GETSERVICECONFIGFORSERVICE]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_GETSERVICECONFIGFORSERVICE]
GO

CREATE PROCEDURE [dbo].[MTS_GETSERVICECONFIGFORSERVICE]
    @Servicename VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        SERVICEID,
        SERVICENAME,
        SERVICEDISPLAYNAME,
        SERVICEDESCRIPTION,
        SERVICEINVOKETYPE,
        TIME,
        STATUS,
        LAST_RUN,
        LAST_ERROR
    FROM MTS_SERVICECONFIG WITH (NOLOCK)
    WHERE SERVICENAME = @Servicename;
END
GO

-- =============================================
-- SP: MTS_UPDATESERVICESTATUS
-- Update service status
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_UPDATESERVICESTATUS]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_UPDATESERVICESTATUS]
GO

CREATE PROCEDURE [dbo].[MTS_UPDATESERVICESTATUS]
    @Servicename VARCHAR(100),
    @Status TINYINT,
    @ErrorMessage VARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE MTS_SERVICECONFIG
    SET
        STATUS = @Status,
        LAST_RUN = GETDATE(),
        LAST_ERROR = @ErrorMessage
    WHERE SERVICENAME = @Servicename;
END
GO

-- =============================================
-- SP: MTS_UpdateServiceConfig
-- Update service configuration
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_UpdateServiceConfig]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_UpdateServiceConfig]
GO

CREATE PROCEDURE [dbo].[MTS_UpdateServiceConfig]
    @Servicename VARCHAR(100),
    @Servicedisplayname VARCHAR(100),
    @Servicedescription VARCHAR(255),
    @Serviceinvoketype TINYINT,
    @Time VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE MTS_SERVICECONFIG
    SET
        SERVICEDISPLAYNAME = @Servicedisplayname,
        SERVICEDESCRIPTION = @Servicedescription,
        SERVICEINVOKETYPE = @Serviceinvoketype,
        TIME = @Time
    WHERE SERVICENAME = @Servicename;
END
GO

-- =============================================
-- SP: MTS_GetSTMPDetails (Placeholder - Not used in API model)
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_GetSTMPDetails]') AND type in (N'P'))
    DROP PROCEDURE [dbo].[MTS_GetSTMPDetails]
GO

CREATE PROCEDURE [dbo].[MTS_GetSTMPDetails]
AS
BEGIN
    SET NOCOUNT ON;
    -- This SP is not needed since we're using API endpoint
    -- Keeping for compatibility
    SELECT 1 AS [PLACEHOLDER];
END
GO

PRINT 'Stored Procedures created successfully!'
GO
