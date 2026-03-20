# Quick Start Guide - App Native Notification Service

## 5-Minute Setup

### Step 1: Database Setup (2 minutes)

```sql
-- Run these scripts in SQL Server Management Studio
USE XTRACHEF_DB

-- 1. Create tables
-- Run: Database\01_Create_Tables.sql

-- 2. Create stored procedures
-- Run: Database\02_Create_StoredProcedures.sql

-- 3. Add test data (optional)
-- Run: Database\03_Test_Data.sql
```

### Step 2: Configure Service (1 minute)

Edit `src/AppNativeNotification/appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=YOUR_SERVER;Database=XTRACHEF_DB;User Id=sa;Password=YOUR_PASSWORD;TrustServerCertificate=true;"
  },
  "ServiceSettings": {
    "ApiBaseUrl": "https://your-api.com",
    "ApiEndpoint": "/api/notification/send",
    "PollingIntervalMinutes": 1
  }
}
```

### Step 3: Build (1 minute)

```bash
cd src/AppNativeNotification
dotnet build -c Release
```

### Step 4: Test Run (1 minute)

```bash
# Test run once
cd src/AppNativeNotification/bin/Release/net8.0
.\AppNativeNotification.exe --runonce
```

You should see:
```
Running AppNativeNotificationService once...
Starting notification run cycle
...
Run completed. Status: Success
```

### Step 5: Install as Windows Service (Optional)

Run PowerShell as Administrator:

```powershell
cd app-native-notification
.\Install-Service.ps1
```

## Verify Installation

### Check Database

```sql
-- View pending emails
SELECT * FROM MTS_EMAILMASTER WHERE STATUS = 0

-- View service status
SELECT * FROM MTS_SERVICECONFIG WHERE SERVICENAME = 'AppNativeNotificationService'
```

### Check Windows Service

```powershell
Get-Service AppNativeNotificationService
```

## Common Tasks

### Add Email to Queue

```sql
EXEC MTS_EMAILMASTERENTRY
    @TEMPLATEID = 2,
    @EMAILSP = 'user@example.com~John Doe~Welcome!',
    @CORRELATION_ID = NEWID()
```

### Check Email Status

```sql
SELECT TOP 10
    ID,
    TEMPLATEID,
    EMAILSP,
    STATUS, -- 0=Pending, 1=Success, 2=Failed, 3=Retry
    RETRY_COUNT,
    ERROR_MSG,
    REQUESTTIME
FROM MTS_EMAILMASTER
ORDER BY REQUESTTIME DESC
```

### Update Schedule

```sql
-- Make template immediate
UPDATE MTS_EMAILSCHEDULE SET SENDBY = 1 WHERE TEMPLATEID = 2

-- Daily at 9 AM
UPDATE MTS_EMAILSCHEDULE SET SENDBY = 2, TIME = '09:00' WHERE TEMPLATEID = 3

-- Weekly (Mon/Wed/Fri at 2 PM)
UPDATE MTS_EMAILSCHEDULE SET SENDBY = 3, DAY = '1,3,5', TIME = '14:00' WHERE TEMPLATEID = 4

-- Monthly (1st and 15th at 10 AM)
UPDATE MTS_EMAILSCHEDULE SET SENDBY = 4, DAY = '1,15', TIME = '10:00' WHERE TEMPLATEID = 5
```

## Troubleshooting

### Service Won't Start

1. Check Event Viewer: `Windows Logs > Application`
2. Verify SQL connection string
3. Test database connectivity

### Emails Not Sending

1. Check API endpoint is accessible
2. Review error messages:
   ```sql
   SELECT * FROM MTS_EMAILMASTER WHERE STATUS = 2 AND ERROR_MSG IS NOT NULL
   ```
3. Test API manually with Postman

### Manual Service Control

```powershell
# Start
Start-Service AppNativeNotificationService

# Stop
Stop-Service AppNativeNotificationService

# Restart
Restart-Service AppNativeNotificationService

# Check status
Get-Service AppNativeNotificationService | Select-Object Status, DisplayName
```

## Next Steps

1. Configure your API endpoint to handle POST requests
2. Set up logging (Windows Event Log)
3. Configure email templates in your database
4. Set up monitoring and alerts

## Need Help?

Check the full [README.md](README.md) for detailed documentation.
