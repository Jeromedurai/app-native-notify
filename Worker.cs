using AppNativeNotification.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace AppNativeNotification;

/// <summary>
/// Background worker service that runs continuously
/// </summary>
public class Worker : BackgroundService
{
    private readonly NotificationProcessor _processor;
    private readonly ILogger<Worker> _logger;
    private readonly double _pollingIntervalMinutes;

    public Worker(
        NotificationProcessor processor,
        ILogger<Worker> logger,
        IConfiguration configuration)
    {
        _processor = processor;
        _logger = logger;
        _pollingIntervalMinutes = configuration.GetValue<double>("ServiceSettings:PollingIntervalMinutes", 1.0);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("App Native Notification Service started. Polling every {Minutes} minute(s)", _pollingIntervalMinutes);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await _processor.RunOnceAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("Service stopping requested");
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Notification processing failed");
            }

            // Wait for next poll interval
            await Task.Delay(TimeSpan.FromMinutes(_pollingIntervalMinutes), stoppingToken);
        }

        _logger.LogInformation("App Native Notification Service stopped");
    }
}
