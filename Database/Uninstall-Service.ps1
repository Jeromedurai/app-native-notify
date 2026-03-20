# =============================================
# Uninstall App Native Notification Service
# Run as Administrator
# =============================================

param(
    [string]$ServiceName = "AppNativeNotificationService"
)

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    exit 1
}

# Check if service exists
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if (-not $service) {
    Write-Host "Service '$ServiceName' not found. Nothing to uninstall." -ForegroundColor Yellow
    exit 0
}

Write-Host "Uninstalling $ServiceName..." -ForegroundColor Green

# Stop service if running
if ($service.Status -eq 'Running') {
    Write-Host "Stopping service..." -ForegroundColor Cyan
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 2
    Write-Host "Service stopped" -ForegroundColor Green
}

# Delete service
Write-Host "Removing service..." -ForegroundColor Cyan
sc.exe delete $ServiceName

Start-Sleep -Seconds 2

# Verify removal
$checkService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $checkService) {
    Write-Host "Service uninstalled successfully!" -ForegroundColor Green
} else {
    Write-Host "Warning: Service may still exist. Please reboot and try again." -ForegroundColor Yellow
}
