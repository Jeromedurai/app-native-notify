using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Polly;
using Polly.Retry;

namespace AppNativeNotification.DataAccess;

/// <summary>
/// Data access implementation for notification service
/// </summary>
public class NotificationDataAccess : INotificationDataAccess
{
    private readonly string _connectionString;
    private readonly ILogger<NotificationDataAccess> _logger;
    private readonly ResiliencePipeline _retryPipeline;

    public NotificationDataAccess(string connectionString, ILogger<NotificationDataAccess> logger)
    {
        _connectionString = connectionString ?? throw new ArgumentNullException(nameof(connectionString));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));

        // Configure retry policy for transient SQL errors
        _retryPipeline = new ResiliencePipelineBuilder()
            .AddRetry(new RetryStrategyOptions
            {
                MaxRetryAttempts = 3,
                Delay = TimeSpan.FromSeconds(2),
                BackoffType = DelayBackoffType.Exponential,
                UseJitter = true,
                ShouldHandle = new PredicateBuilder().Handle<SqlException>(ex => IsTransientError(ex)),
                OnRetry = args =>
                {
                    _logger.LogWarning("Database operation failed (Attempt {Attempt}/{MaxAttempts}). Retrying after {Delay}ms. Error: {Error}",
                        args.AttemptNumber + 1,
                        3,
                        args.RetryDelay.TotalMilliseconds,
                        args.Outcome.Exception?.Message);
                    return default;
                }
            })
            .Build();
    }

    /// <summary>
    /// Determines if a SqlException is a transient error that should be retried
    /// </summary>
    private static bool IsTransientError(SqlException ex)
    {
        // Common transient error codes
        int[] transientErrorNumbers =
        {
            -2,     // Timeout
            -1,     // Connection error
            2,      // Network error
            53,     // Connection initialization error
            64,     // Server error
            233,    // Connection initialization error
            10053,  // Transport-level error
            10054,  // Connection forcibly closed
            10060,  // Network or instance-specific error
            10061,  // Network or instance-specific error
            40197,  // Service error processing request
            40501,  // Service busy
            40613,  // Database unavailable
            49918,  // Cannot process request
            49919,  // Cannot process create or update request
            49920   // Cannot process request
        };

        return transientErrorNumbers.Contains(ex.Number);
    }

    /// <summary>
    /// Check if database connection is healthy
    /// </summary>
    public async Task<bool> CheckConnectionHealthAsync()
    {
        try
        {
            using var conn = new SqlConnection(_connectionString);
            await conn.OpenAsync();
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Database connection health check failed");
            return false;
        }
    }

    public DataTable GetEmailSchedule()
    {
        return _retryPipeline.Execute(() => ExecuteTable("MTS_GetEmailSchedule"));
    }

    public DataTable GetEmailScheduleForTimeScheduler()
    {
        return _retryPipeline.Execute(() => ExecuteTable("MTS_GetEmailScheduleForTimeScheduler"));
    }

    public DataTable GetEmailsWaitingToBeSent(byte status = 0)
    {
        return _retryPipeline.Execute(() => ExecuteTable("MTS_GetEmailsWaitingToBeSend",
            new SqlParameter("@STATUS", status)));
    }

    public DataTable GetEmailTemplates()
    {
        return _retryPipeline.Execute(() => ExecuteTable("MTS_GetEmailTemplate"));
    }

    public int UpdateEmailStatus(long id, byte status, string? correlationId = null, string? errorMsg = null)
    {
        return _retryPipeline.Execute(() =>
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("MTS_UpdateEmailStatus", conn)
            {
                CommandType = CommandType.StoredProcedure
            };

            cmd.Parameters.AddWithValue("@Id", id);
            cmd.Parameters.AddWithValue("@STATUS", status);
            cmd.Parameters.AddWithValue("@CORRELATION_ID", (object?)correlationId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@ERROR_MSG", (object?)errorMsg ?? DBNull.Value);

            conn.Open();
            var result = cmd.ExecuteScalar();
            return result != null && result != DBNull.Value ? Convert.ToInt32(result) : status;
        });
    }

    public int? GetTemplateIdFromScheduleId(int scheduleId)
    {
        return _retryPipeline.Execute<int?>(() =>
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("MTS_GETTEMPLATEIDFROMSCHEDULEID", conn)
            {
                CommandType = CommandType.StoredProcedure
            };

            cmd.Parameters.AddWithValue("@Scheduleid", scheduleId);

            conn.Open();
            var result = cmd.ExecuteScalar();
            return result != null && result != DBNull.Value ? Convert.ToInt32(result) : null;
        });
    }

    public void UpdateServiceStatus(string serviceName, byte status, string? errorMessage = null)
    {
        _retryPipeline.Execute(() =>
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("MTS_UPDATESERVICESTATUS", conn)
            {
                CommandType = CommandType.StoredProcedure
            };

            cmd.Parameters.AddWithValue("@Servicename", serviceName);
            cmd.Parameters.AddWithValue("@Status", status);
            // cmd.Parameters.AddWithValue("@ErrorMessage", (object?)errorMessage ?? DBNull.Value);

            conn.Open();
            cmd.ExecuteNonQuery();
        });
    }

    private DataTable ExecuteTable(string procedureName, params SqlParameter[] parameters)
    {
        using var conn = new SqlConnection(_connectionString);
        using var cmd = new SqlCommand(procedureName, conn)
        {
            CommandType = CommandType.StoredProcedure,
            CommandTimeout = 30 // 30 second timeout
        };

        if (parameters.Length > 0)
            cmd.Parameters.AddRange(parameters);

        using var adapter = new SqlDataAdapter(cmd);
        var dt = new DataTable();
        adapter.Fill(dt);
        return dt;
    }
}
