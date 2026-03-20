# App Native Notification Service

A simple Windows Service for sending email notifications via API endpoint. Supports immediate, daily, weekly, and monthly schedules.

## Features

- ✅ **Multiple Schedule Types**
  - Immediate (SENDBY=1)
  - Daily (SENDBY=2)
  - Weekly (SENDBY=3)
  - Monthly (SENDBY=4)

- ✅ **Operational Modes**
  - Run continuously as Windows Service
  - Run once (`--runonce` parameter)
  - Start/Stop via Windows Services

- ✅ **Retry Logic**
  - Automatic retry up to 3 times
  - Exponential backoff
  - Error logging

- ✅ **API Integration**
  - Sends email via ASP.NET Core API endpoint
  - Configurable timeout
  - HTTPS support

## Database Setup

### 1. Run SQL Scripts

Execute these scripts in order:

```sql
-- Create tables
.\Database\01_Create_Tables.sql

-- Create stored procedures
.\Database\02_Create_StoredProcedures.sql
```

### 2. Configure Connection String

Update `appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=YOUR_SERVER;Database=XTRACHEF_DB;User Id=sa;Password=YOUR_PASSWORD;TrustServerCertificate=true;"
  }
}
```

## Configuration

Edit `appsettings.json`:

```json
{
  "ServiceSettings": {
    "ServiceName": "AppNativeNotificationService",
    "ApiBaseUrl": "https://your-api-url.com",
    "ApiEndpoint": "/api/notification/send",
    "PollingIntervalMinutes": 1,
    "HttpTimeoutSeconds": 30
  }
}
```

## Build & Install

### Build

```bash
cd src/AppNativeNotification
dotnet build -c Release
```

### Install as Windows Service

```powershell
# Run as Administrator
sc create AppNativeNotificationService binPath= "C:\Path\To\AppNativeNotification.exe"
sc description AppNativeNotificationService "Email notification service"
sc start AppNativeNotificationService
```

### Using .NET CLI (Recommended)

```powershell
# Install
dotnet publish -c Release -r win-x64 --self-contained
sc create AppNativeNotificationService binPath= "C:\Path\To\publish\AppNativeNotification.exe"

# Start
sc start AppNativeNotificationService

# Stop
sc stop AppNativeNotificationService

# Uninstall
sc delete AppNativeNotificationService
```

## Usage

### Run Once (Manual Test)

```bash
AppNativeNotification.exe --runonce
```

### Insert Email into Queue

```sql
-- Add immediate email
EXEC MTS_EMAILMASTERENTRY
    @TEMPLATEID = 2,
    @EMAILSP = 'user@example.com~John Doe~Welcome Message',
    @CORRELATION_ID = 'test-001'

-- Check status
SELECT * FROM MTS_EMAILMASTER WHERE CORRELATION_ID = 'test-001'
```

## Schedule Configuration

### Immediate Email (SENDBY=1)
Processed on every service cycle (1 minute by default)

```sql
UPDATE MTS_EMAILSCHEDULE SET SENDBY = 1 WHERE TEMPLATEID = 2
```

### Daily Email (SENDBY=2)
Sent every day at specified time

```sql
UPDATE MTS_EMAILSCHEDULE
SET SENDBY = 2, TIME = '09:00'
WHERE TEMPLATEID = 3
```

### Weekly Email (SENDBY=3)
Sent on specific days of week (0=Sunday, 6=Saturday)

```sql
-- Monday, Wednesday, Friday at 2 PM
UPDATE MTS_EMAILSCHEDULE
SET SENDBY = 3, DAY = '1,3,5', TIME = '14:00'
WHERE TEMPLATEID = 4
```

### Monthly Email (SENDBY=4)
Sent on specific days of month

```sql
-- 1st and 15th of each month at 10 AM
UPDATE MTS_EMAILSCHEDULE
SET SENDBY = 4, DAY = '1,15', TIME = '10:00'
WHERE TEMPLATEID = 5
```

## API Endpoint Requirements

Your ASP.NET Core API should accept this request:

### POST /api/notification/send

**Request Body:**
```json
{
  "id": 12345,
  "templateId": 2,
  "emailSP": "user@example.com~John Doe~Message Content",
  "correlationId": "guid-123",
  "retryCount": 0
}
```

**Response:**
- `200 OK` - Email sent successfully
- `400 Bad Request` - Validation error
- `500 Internal Server Error` - Server error

## Status Codes

| Status | Description |
|--------|-------------|
| 0 | Pending - waiting to be sent |
| 1 | Success - sent successfully |
| 2 | Failed - max retries reached |
| 3 | Retry - will retry on next cycle |

## Stored Procedures Used

- `MTS_GetEmailSchedule` - Get immediate emails
- `MTS_GetEmailScheduleForTimeScheduler` - Get timed schedules
- `MTS_GetEmailsWaitingToBeSend` - Get emails by status
- `MTS_GetEmailTemplate` - Get active templates
- `MTS_UpdateEmailStatus` - Update email status with retry logic
- `MTS_GETTEMPLATEIDFROMSCHEDULEID` - Get template from schedule
- `MTS_EMAILMASTERENTRY` - Insert new email
- `MTS_GETSERVICECONFIGFORSERVICE` - Get service config
- `MTS_UPDATESERVICESTATUS` - Update service status

## Troubleshooting

### Service won't start

1. Check connection string in `appsettings.json`
2. Verify SQL Server is accessible
3. Check Windows Event Viewer for errors

### Emails not sending

1. Verify API endpoint is accessible
2. Check `MTS_EMAILMASTER` for error messages
3. Review service logs in Event Viewer
4. Test API endpoint manually

### Check Service Status

```sql
SELECT * FROM MTS_SERVICECONFIG WHERE SERVICENAME = 'AppNativeNotificationService'
```

### View Pending Emails

```sql
SELECT TOP 10 * FROM MTS_EMAILMASTER WHERE STATUS = 0 ORDER BY REQUESTTIME
```

### View Failed Emails

```sql
SELECT TOP 10 * FROM MTS_EMAILMASTER WHERE STATUS = 2 ORDER BY REQUESTTIME DESC
```

## Architecture

```
┌─────────────────────────────────────────┐
│  Windows Service (Worker)               │
│  - Runs every N minutes                 │
│  - Calls NotificationProcessor          │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  NotificationProcessor                  │
│  - LoadSchedules()                      │
│  - ProcessRetryEmails()                 │
│  - ProcessScheduledEmails()             │
│  - ProcessImmediateEmails()             │
└─────────────────────────────────────────┘
                  │
    ┌─────────────┴─────────────┐
    ▼                           ▼
┌──────────────┐        ┌──────────────┐
│  SQL Server  │        │  API         │
│  Database    │        │  Endpoint    │
└──────────────┘        └──────────────┘
```

## License

Internal use only - XtraChef Service Block
