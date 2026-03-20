using AppNativeNotification;
using AppNativeNotification.DataAccess;
using AppNativeNotification.Services;
using AppNativeNotification.Utilities;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = Host.CreateApplicationBuilder(args);

// Get service configuration
var serviceName = builder.Configuration["ServiceSettings:ServiceName"] ?? "AppNativeNotificationService";
var apiBaseUrl = builder.Configuration["ServiceSettings:ApiBaseUrl"] ?? throw new InvalidOperationException("ServiceSettings:ApiBaseUrl is required");
var apiEndpoint = builder.Configuration["ServiceSettings:ApiEndpoint"] ?? "/api/notification/send";
var httpTimeout = builder.Configuration.GetValue("ServiceSettings:HttpTimeoutSeconds", 30);

// Configure Windows Service
builder.Services.AddWindowsService(options =>
{
    options.ServiceName = serviceName;
});

// Get database connection string and decrypt password
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection")
    ?? throw new InvalidOperationException("ConnectionStrings:DefaultConnection is required");
// connectionString = SetConnectionString(connectionString);

// Register data access
builder.Services.AddSingleton<INotificationDataAccess>(sp =>
{
    var logger = sp.GetRequiredService<ILogger<NotificationDataAccess>>();
    return new NotificationDataAccess(connectionString, logger);
});

// Configure HTTP client for API calls
builder.Services.AddHttpClient("NotificationApi", client =>
{
    client.Timeout = TimeSpan.FromSeconds(httpTimeout);
})
.ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
{
    ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
});

// Register notification processor
builder.Services.AddSingleton<NotificationProcessor>(sp =>
{
    var httpFactory = sp.GetRequiredService<IHttpClientFactory>();
    var httpClient = httpFactory.CreateClient("NotificationApi");
    var logger = sp.GetRequiredService<ILogger<NotificationProcessor>>();
    var dataAccess = sp.GetRequiredService<INotificationDataAccess>();

    return new NotificationProcessor(dataAccess, httpClient, logger, apiBaseUrl, apiEndpoint, serviceName);
});

// Register background worker
builder.Services.AddHostedService<Worker>();

var host = builder.Build();

// Support command line arguments
if (args.Contains("--runonce", StringComparer.OrdinalIgnoreCase))
{
    // Run once mode - execute single cycle and exit
    Console.WriteLine($"Running {serviceName} once...");

    using var scope = host.Services.CreateScope();
    var processor = scope.ServiceProvider.GetRequiredService<NotificationProcessor>();
    var result = await processor.RunOnceAsync();

    Console.WriteLine($"Run completed. Status: {(result ? "Success" : "Failed")}");
    return result ? 0 : 1;
}

// Normal mode - run as Windows Service
await host.RunAsync();
return 0;

static string SetConnectionString(string connectionString)
{
    var builder = new SqlConnectionStringBuilder(connectionString);
    builder.Password = Encryption.EnDecrypt(builder.Password, true);
    return builder.ToString();
}
