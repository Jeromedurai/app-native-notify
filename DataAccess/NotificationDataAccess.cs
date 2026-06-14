using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Polly;
using Polly.Retry;

namespace AppNativeNotification.DataAccess;

/// <summary>
/// Data access for the notification worker.
///
/// Architecture:
///   SA_EMAILSCHEDULE / SA_EMAILTEMPLATE  — admin-configured via settings UI (read-only here)
///   SA_EMAILMASTER                       — email queue; app code enqueues rows, worker dequeues
///   SA_SERVICECONFIG                     — worker heartbeat (LAST_RUN updated each cycle)
///
/// Flow:
///   1. Admin creates template + schedule in SA_* tables via the settings page.
///   2. App code calls MTS_EMAILMASTERENTRY to enqueue an email with EMAILSP payload.
///   3. Worker reads SA_EMAILSCHEDULE to determine WHEN to process each template.
///   4. Worker reads MTS_EMAILMASTER for pending rows matching that template.
///   5. Worker POSTs each row to the API /notification/send endpoint for rendering + SMTP.
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
                    _logger.LogWarning("DB retry {Attempt}/3 after {Delay}ms: {Error}",
                        args.AttemptNumber + 1, args.RetryDelay.TotalMilliseconds,
                        args.Outcome.Exception?.Message);
                    return default;
                }
            })
            .Build();
    }

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

    // -------------------------------------------------------------------------
    // Schedules — read from SA_EMAILSCHEDULE (admin-managed, ACTIVE=1 only)
    // SENDBY: 0=NotScheduled, 1=Immediate, 2=Daily, 3=Weekly, 4=Monthly
    // -------------------------------------------------------------------------

    public DataTable GetEmailSchedule()
    {
        // Immediate schedules only (SENDBY=1)
        return _retryPipeline.Execute(() => ExecuteQuery(
            "SELECT SCHEDULEID, TEMPLATEID, SCHEDULEDESCRIPTION, SENDBY, DAY, TIME " +
            "FROM SA_EMAILSCHEDULE WITH (NOLOCK) WHERE SENDBY = 1 AND ACTIVE = 1"));
    }

    public DataTable GetEmailScheduleForTimeScheduler()
    {
        // Timed schedules: Daily=2, Weekly=3, Monthly=4
        return _retryPipeline.Execute(() => ExecuteQuery(
            "SELECT SCHEDULEID, TEMPLATEID, SCHEDULEDESCRIPTION, SENDBY, DAY, TIME " +
            "FROM SA_EMAILSCHEDULE WITH (NOLOCK) WHERE SENDBY IN (2,3,4) AND ACTIVE = 1"));
    }

    public int? GetTemplateIdFromScheduleId(int scheduleId)
    {
        return _retryPipeline.Execute<int?>(() =>
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand(
                "SELECT TEMPLATEID FROM SA_EMAILSCHEDULE WITH (NOLOCK) WHERE SCHEDULEID = @id", conn);
            cmd.Parameters.AddWithValue("@id", scheduleId);
            conn.Open();
            var result = cmd.ExecuteScalar();
            return result != null && result != DBNull.Value ? Convert.ToInt32(result) : null;
        });
    }

    // -------------------------------------------------------------------------
    // Templates — read from SA_EMAILTEMPLATE (admin-managed, ACTIVE=1 only)
    // -------------------------------------------------------------------------

    public DataTable GetEmailTemplates()
    {
        return _retryPipeline.Execute(() => ExecuteQuery(
            "SELECT TEMPLATEID, TEMPLATENAME, DESCRIPTION, AUDIENCESP, CATEGORY, ACTIVE " +
            "FROM SA_EMAILTEMPLATE WITH (NOLOCK) WHERE ACTIVE = 1"));
    }

    // -------------------------------------------------------------------------
    // Audience generation — scheduled sends fan out one queue row per recipient
    // -------------------------------------------------------------------------

    /// <summary>
    /// Reads a schedule's full enqueue config in a single round-trip: the schedule row joined to
    /// its template (for AUDIENCESP). Returns null when the scheduleId does not exist.
    /// </summary>
    public ScheduleConfig? GetScheduleConfig(int scheduleId)
    {
        return _retryPipeline.Execute<ScheduleConfig?>(() =>
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand(
                "SELECT t.AUDIENCESP, s.TENANTID, s.EXCLUDEDUSERIDS, s.COUPONCODE, " +
                "       s.SUBJECT, s.HEADLINE, s.MESSAGE, s.CTATEXT, s.CTAURL, s.CHANNELS " +
                "FROM SA_EMAILSCHEDULE s WITH (NOLOCK) " +
                "LEFT JOIN SA_EMAILTEMPLATE t WITH (NOLOCK) ON t.TEMPLATEID = s.TEMPLATEID " +
                "WHERE s.SCHEDULEID = @id", conn);
            cmd.Parameters.AddWithValue("@id", scheduleId);
            conn.Open();
            using var reader = cmd.ExecuteReader();
            if (!reader.Read()) return null;

            string? S(int i) => reader.IsDBNull(i) ? null : reader.GetString(i);

            var cfg = new ScheduleConfig
            {
                AudienceSp = S(0),
                TenantId   = reader.IsDBNull(1) ? null : reader.GetInt64(1),
                CouponCode = S(3),
                Content = new ScheduleContent
                {
                    Subject  = S(4),
                    Headline = S(5),
                    Message  = S(6),
                    CtaText  = S(7),
                    CtaUrl   = S(8),
                }
            };

            // ExcludedUserIds: CSV of UserIds → HashSet<long>
            foreach (var part in (S(2) ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries))
            {
                if (long.TryParse(part.Trim(), out var uid)) cfg.ExcludedUserIds.Add(uid);
            }

            // Channels: CSV → trimmed list; default to Email when not configured.
            var channels = (S(9) ?? "")
                .Split(',', StringSplitOptions.RemoveEmptyEntries)
                .Select(c => c.Trim())
                .Where(c => c.Length > 0)
                .ToList();
            if (channels.Count > 0) cfg.Channels = channels;

            return cfg;
        });
    }

    public DataTable RunAudienceSp(string spName, long? tenantId, long templateId)
    {
        return _retryPipeline.Execute(() =>
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand(spName, conn)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 60
            };
            cmd.Parameters.AddWithValue("@TenantId", (object?)tenantId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TemplateId", templateId);
            using var adapter = new SqlDataAdapter(cmd);
            var dt = new DataTable();
            adapter.Fill(dt);
            return dt;
        });
    }

    public long EnqueueEmail(long templateId, string emailSpJson, string? correlationId, long? tenantId, string channel)
    {
        return _retryPipeline.Execute(() =>
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("SA_EmailMasterEntry", conn)
            {
                CommandType = CommandType.StoredProcedure
            };
            cmd.Parameters.AddWithValue("@TEMPLATEID", templateId);
            cmd.Parameters.AddWithValue("@EMAILSP", emailSpJson);
            cmd.Parameters.AddWithValue("@CORRELATION_ID", (object?)correlationId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@TENANTID", (object?)tenantId ?? DBNull.Value);
            cmd.Parameters.AddWithValue("@CHANNEL", string.IsNullOrWhiteSpace(channel) ? "Email" : channel);
            conn.Open();
            var result = cmd.ExecuteScalar();
            return result != null && result != DBNull.Value ? Convert.ToInt64(result) : 0L;
        });
    }

    public bool EmailExistsForCorrelation(string correlationId)
    {
        return _retryPipeline.Execute(() =>
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand(
                "SELECT TOP 1 1 FROM SA_EMAILMASTER WITH (NOLOCK) WHERE CORRELATION_ID = @cid", conn);
            cmd.Parameters.AddWithValue("@cid", correlationId);
            conn.Open();
            var result = cmd.ExecuteScalar();
            return result != null && result != DBNull.Value;
        });
    }

    // -------------------------------------------------------------------------
    // Email queue — MTS_EMAILMASTER
    // Enqueued by app code via MTS_EMAILMASTERENTRY SP.
    // STATUS: 0=Pending, 1=Success, 2=Failed, 3=Retry
    // -------------------------------------------------------------------------

    public DataTable GetEmailsWaitingToBeSent(byte status = 0)
    {
        return _retryPipeline.Execute(() => ExecuteQuery(
            "SELECT TOP 100 ID, TENANTID, CHANNEL, TEMPLATEID, EMAILSP, REQUESTTIME, STATUS, " +
            "RETRY_COUNT, ERROR_MSG, CORRELATION_ID " +
            "FROM SA_EMAILMASTER WITH (NOLOCK) WHERE STATUS = @s ORDER BY REQUESTTIME ASC",
            new SqlParameter("@s", status)));
    }

    public int UpdateEmailStatus(long id, byte status, string? correlationId = null, string? errorMsg = null)
    {
        return _retryPipeline.Execute(() =>
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand("SA_UpdateEmailStatus", conn)
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

    // -------------------------------------------------------------------------
    // Service heartbeat — SA_SERVICECONFIG (LAST_RUN only, simple upsert)
    // -------------------------------------------------------------------------

    public void UpdateServiceStatus(string serviceName, byte status, string? errorMessage = null)
    {
        _retryPipeline.Execute(() =>
        {
            using var conn = new SqlConnection(_connectionString);
            using var cmd = new SqlCommand(
                "IF EXISTS (SELECT 1 FROM SA_SERVICECONFIG WHERE SERVICENAME = @name) " +
                "    UPDATE SA_SERVICECONFIG SET LAST_RUN = GETDATE() WHERE SERVICENAME = @name " +
                "ELSE " +
                "    INSERT INTO SA_SERVICECONFIG (SERVICENAME, LAST_RUN) VALUES (@name, GETDATE())",
                conn);
            cmd.Parameters.AddWithValue("@name", serviceName);
            conn.Open();
            cmd.ExecuteNonQuery();
        });
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private DataTable ExecuteQuery(string sql, params SqlParameter[] parameters)
    {
        using var conn = new SqlConnection(_connectionString);
        using var cmd = new SqlCommand(sql, conn) { CommandTimeout = 30 };
        if (parameters.Length > 0) cmd.Parameters.AddRange(parameters);
        using var adapter = new SqlDataAdapter(cmd);
        var dt = new DataTable();
        adapter.Fill(dt);
        return dt;
    }

    private static bool IsTransientError(SqlException ex)
    {
        int[] transientCodes = { -2, -1, 2, 53, 64, 233, 10053, 10054, 10060, 10061,
                                  40197, 40501, 40613, 49918, 49919, 49920 };
        return transientCodes.Contains(ex.Number);
    }
}
