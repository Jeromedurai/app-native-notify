-- =============================================
-- App Native Notification Service - Database Tables
-- Simple and Clean Implementation
-- =============================================

USE [XTRACHEF_DB]
GO

-- Table: MTS_EMAILMASTER (Email Queue)
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_EMAILMASTER]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[MTS_EMAILMASTER](
        [ID] [bigint] IDENTITY(1,1) NOT NULL,
        [TEMPLATEID] [bigint] NOT NULL,
        [EMAILSP] [varchar](500) NOT NULL, -- Format: "SP_NAME|Param1,Param2" or "Email~Name~Data"
        [REQUESTTIME] [datetime] NOT NULL DEFAULT GETDATE(),
        [STATUS] [tinyint] NOT NULL DEFAULT 0, -- 0=Pending, 1=Success, 2=Failed, 3=Retry
        [RETRY_COUNT] [int] NOT NULL DEFAULT 0,
        [ERROR_MSG] [varchar](500) NULL,
        [CORRELATION_ID] [varchar](100) NULL,
        CONSTRAINT [PK_MTS_EMAILMASTER] PRIMARY KEY CLUSTERED ([ID] ASC)
    ) ON [PRIMARY]

    CREATE NONCLUSTERED INDEX [IX_MTS_EMAILMASTER_STATUS] ON [dbo].[MTS_EMAILMASTER]([STATUS]) INCLUDE ([TEMPLATEID])
END
GO

-- Table: MTS_EMAILSCHEDULE (Schedule Configuration)
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_EMAILSCHEDULE]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[MTS_EMAILSCHEDULE](
        [SCHEDULEID] [bigint] IDENTITY(1,1) NOT NULL,
        [TEMPLATEID] [bigint] NOT NULL,
        [SCHEDULEDESCRIPTION] [varchar](100) NOT NULL,
        [SENDBY] [tinyint] NOT NULL, -- 0=NotScheduled, 1=Immediate, 2=Daily, 3=Weekly, 4=Monthly
        [DAY] [varchar](50) NULL, -- Weekly: "1,3,5" (Mon,Wed,Fri), Monthly: "1,15" (1st,15th)
        [TIME] [time](7) NULL, -- Time to send
        CONSTRAINT [PK_MTS_EMAILSCHEDULE] PRIMARY KEY CLUSTERED ([SCHEDULEID] ASC)
    ) ON [PRIMARY]
END
GO

-- Table: MTS_EMAILTEMPLATE (Template Info)
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_EMAILTEMPLATE]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[MTS_EMAILTEMPLATE](
        [TEMPLATEID] [bigint] IDENTITY(1,1) NOT NULL,
        [TEMPLATENAME] [varchar](100) NOT NULL,
        [DESCRIPTION] [varchar](255) NULL,
        [ACTIVE] [bit] NOT NULL DEFAULT 1,
        CONSTRAINT [PK_MTS_EMAILTEMPLATE] PRIMARY KEY CLUSTERED ([TEMPLATEID] ASC)
    ) ON [PRIMARY]
END
GO

-- Table: MTS_SERVICECONFIG (Service Configuration)
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[MTS_SERVICECONFIG]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[MTS_SERVICECONFIG](
        [SERVICEID] [bigint] IDENTITY(1,1) NOT NULL,
        [SERVICENAME] [varchar](100) NOT NULL,
        [SERVICEDISPLAYNAME] [varchar](100) NOT NULL,
        [SERVICEDESCRIPTION] [varchar](255) NULL,
        [SERVICEINVOKETYPE] [tinyint] NOT NULL DEFAULT 0, -- 0=Polling
        [TIME] [varchar](10) NULL, -- Polling interval in minutes
        [STATUS] [tinyint] NOT NULL DEFAULT 0, -- 0=Stopped, 1=Running
        [LAST_RUN] [datetime] NULL,
        [LAST_ERROR] [varchar](500) NULL,
        CONSTRAINT [PK_MTS_SERVICECONFIG] PRIMARY KEY CLUSTERED ([SERVICEID] ASC),
        CONSTRAINT [UQ_MTS_SERVICECONFIG_NAME] UNIQUE NONCLUSTERED ([SERVICENAME])
    ) ON [PRIMARY]
END
GO

-- Insert Sample Templates
IF NOT EXISTS (SELECT 1 FROM MTS_EMAILTEMPLATE WHERE TEMPLATEID = 1)
BEGIN
    SET IDENTITY_INSERT [dbo].[MTS_EMAILTEMPLATE] ON

    INSERT INTO [dbo].[MTS_EMAILTEMPLATE] ([TEMPLATEID], [TEMPLATENAME], [DESCRIPTION], [ACTIVE])
    VALUES
        (1, 'Order Notification', 'Order placed notification', 1),
        (2, 'Offer Notification', 'Promotional offer notification', 1),
        (3, 'Reset Password', 'Password reset link', 1),
        (4, 'Login', 'Login notification', 1),
        (5, 'Change Password', 'Password changed confirmation', 1),
        (6, 'Sale Notification', 'Sale notification', 1),
        (7, 'Lower Price Notification', 'Price drop alert', 1),
        (9, 'User Password Reset', 'User password reset', 1)

    SET IDENTITY_INSERT [dbo].[MTS_EMAILTEMPLATE] OFF
END
GO

-- Insert Sample Schedule
IF NOT EXISTS (SELECT 1 FROM MTS_EMAILSCHEDULE WHERE SCHEDULEID = 1)
BEGIN
    SET IDENTITY_INSERT [dbo].[MTS_EMAILSCHEDULE] ON

    INSERT INTO [dbo].[MTS_EMAILSCHEDULE] ([SCHEDULEID], [TEMPLATEID], [SCHEDULEDESCRIPTION], [SENDBY], [DAY], [TIME])
    VALUES
        (1, 1, 'Order Notification', 0, NULL, NULL),
        (2, 2, 'Offer Notification', 1, NULL, NULL),
        (3, 3, 'Reset Password', 1, NULL, NULL),
        (4, 4, 'Login', 0, NULL, NULL),
        (5, 5, 'Change Password', 1, NULL, NULL),
        (6, 6, 'Sale Notification', 0, NULL, NULL),
        (7, 7, 'Lower Price Notification', 0, NULL, NULL),
        (9, 9, 'User Password Reset', 1, NULL, NULL)

    SET IDENTITY_INSERT [dbo].[MTS_EMAILSCHEDULE] OFF
END
GO

-- Insert Service Config
IF NOT EXISTS (SELECT 1 FROM MTS_SERVICECONFIG WHERE SERVICENAME = 'AppNativeNotificationService')
BEGIN
    INSERT INTO [dbo].[MTS_SERVICECONFIG]
        ([SERVICENAME], [SERVICEDISPLAYNAME], [SERVICEDESCRIPTION], [SERVICEINVOKETYPE], [TIME], [STATUS])
    VALUES
        ('AppNativeNotificationService', 'App Native Notification Service', 'Simple email notification service', 0, '1', 0)
END
GO

PRINT 'Database tables created successfully!'
GO
