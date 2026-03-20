# =============================================
# Install App Native Notification Service
# Run as Administrator
# =============================================

param(
    [string]$ServiceName = "AppNativeNotificationService",
    [string]$DisplayName = "App Native Notification Service",
    [string]$Description = "Email notification service for XtraChef",
    [string]$BinPath = ""
)

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Determine binary path
if ([string]::IsNullOrEmpty($BinPath)) {
    $BinPath = Join-Path $PSScriptRoot "src\AppNativeNotification\bin\Release\net8.0\AppNativeNotification.exe"
}

# Check if binary exists
if (-not (Test-Path $BinPath)) {
    Write-Host "ERROR: Binary not found at: $BinPath" -ForegroundColor Red
    Write-Host "Please build the project first with: dotnet build -c Release" -ForegroundColor Yellow
    exit 1
}

Write-Host "Installing $DisplayName..." -ForegroundColor Green
Write-Host "Binary Path: $BinPath" -ForegroundColor Cyan

# Check if service already exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($existingService) {
    Write-Host "Service already exists. Stopping and removing..." -ForegroundColor Yellow

    # Stop service if running
    if ($existingService.Status -eq 'Running') {
        Stop-Service -Name $ServiceName -Force
        Write-Host "Service stopped" -ForegroundColor Green
    }

    # Delete service
    sc.exe delete $ServiceName
    Start-Sleep -Seconds 2
    Write-Host "Existing service removed" -ForegroundColor Green
}

# Create new service
Write-Host "Creating service..." -ForegroundColor Cyan
sc.exe create $ServiceName binPath= "`"$BinPath`"" DisplayName= "$DisplayName" start= auto

# Set description
sc.exe description $ServiceName "$Description"

# Configure recovery options (restart on failure)
sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000

Write-Host ""
Write-Host "Service installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Service Name: $ServiceName" -ForegroundColor Cyan
Write-Host "Display Name: $DisplayName" -ForegroundColor Cyan
Write-Host "Binary Path: $BinPath" -ForegroundColor Cyan
Write-Host ""

# Ask to start service
$startService = Read-Host "Do you want to start the service now? (Y/N)"
if ($startService -eq 'Y' -or $startService -eq 'y') {
    Write-Host "Starting service..." -ForegroundColor Cyan
    Start-Service -Name $ServiceName

    Start-Sleep -Seconds 2
    $service = Get-Service -Name $ServiceName

    if ($service.Status -eq 'Running') {
        Write-Host "Service started successfully!" -ForegroundColor Green
    } else {
        Write-Host "Warning: Service did not start. Status: $($service.Status)" -ForegroundColor Yellow
        Write-Host "Check Windows Event Viewer for errors" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Management Commands:" -ForegroundColor Yellow
Write-Host "  Start:   Start-Service $ServiceName" -ForegroundColor White
Write-Host "  Stop:    Stop-Service $ServiceName" -ForegroundColor White
Write-Host "  Status:  Get-Service $ServiceName" -ForegroundColor White
Write-Host "  Remove:  sc.exe delete $ServiceName" -ForegroundColor White
Write-Host ""
