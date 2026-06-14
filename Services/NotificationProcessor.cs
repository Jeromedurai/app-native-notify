using System.Data;
using System.Net.Http.Json;
using System.Text.Json;
using AppNativeNotification.DataAccess;
using AppNativeNotification.Models;
using Microsoft.Extensions.Logging;

namespace AppNativeNotification.Services;

/// <summary>
/// Core notification processing logic
/// Handles immediate, daily, weekly, and monthly email schedules
/// </summary>
public class NotificationProcessor
{
    // Schedule Types
    private const byte SendByImmediate = 1;
    private const byte SendByDaily = 2;
    private const byte SendByWeekly = 3;
    private const byte SendByMonthly = 4;

    // Status Codes
    private const byte StatusPending = 0;
    private const byte StatusSuccess = 1;
    private const byte StatusFailure = 2;
    private const byte StatusRetry = 3;

    private readonly INotificationDataAccess _data;
    private readonly HttpClient _httpClient;
    private readonly ILogger<NotificationProcessor> _logger;
    private readonly string _apiEndpoint;
    private readonly string _whatsAppEndpoint;
    private readonly string _serviceName;

    private Dictionary<long, TimeSpan> _alarmList = new();
    private DataTable? _schedule;
    private DataTable? _timeScheduler;
    private DataTable? _templates;

    public NotificationProcessor(
        INotificationDataAccess data,
        HttpClient httpClient,
        ILogger<NotificationProcessor> logger,
        string apiBaseUrl,
        string apiEndpoint,
        string whatsAppEndpoint,
        string workerKey,
        string serviceName)
    {
        _data = data;
        _httpClient = httpClient;
        _logger = logger;
        _serviceName = serviceName;
        _httpClient.BaseAddress = new Uri(apiBaseUrl.TrimEnd('/'));
        _apiEndpoint = apiEndpoint.TrimStart('/');
        _whatsAppEndpoint = (whatsAppEndpoint ?? "/api/1.0/email/notification/whatsapp").TrimStart('/');

        // Shared-secret header the API validates on the dispatch endpoints.
        if (!string.IsNullOrWhiteSpace(workerKey))
        {
            _httpClient.DefaultRequestHeaders.Remove("X-Worker-Key");
            _httpClient.DefaultRequestHeaders.Add("X-Worker-Key", workerKey);
        }
    }

    /// <summary>
    /// Execute one cycle of notification processing
    /// </summary>
    public async Task<bool> RunOnceAsync(CancellationToken cancellationToken = default)
    { 
        try
        {
            _logger.LogInformation("Starting notification run cycle");

            // Update service status to Running
            _data.UpdateServiceStatus(_serviceName, 1);

            // Load schedules
            LoadSchedules();

            // Process retry emails first
            await ProcessRetryEmailsAsync(cancellationToken);

            // Check if midnight refresh is needed
            CheckMidnightRefresh();

            // Process scheduled emails (Daily, Weekly, Monthly)
            await ProcessScheduledEmailsAsync(cancellationToken);

            // Process immediate emails
            await ProcessImmediateEmailsAsync(cancellationToken);

            _logger.LogInformation("Notification run cycle completed successfully");
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Notification run cycle failed");
            _data.UpdateServiceStatus(_serviceName, 1, ex.Message);
            return false;
        }
    }

    /// <summary>
    /// Load all schedules from database
    /// </summary>
    private void LoadSchedules()
    {
        _schedule = _data.GetEmailSchedule();
        _timeScheduler = _data.GetEmailScheduleForTimeScheduler();
         _templates = _data.GetEmailTemplates();
        _logger.LogDebug("Schedules loaded: Immediate={ImmediateCount}, Timed={TimedCount}",
            _schedule?.Rows.Count ?? 0, _timeScheduler?.Rows.Count ?? 0);
    }

    /// <summary>
    /// Build alarm list based on current date and schedule configuration
    /// </summary>
    private void LoadAlarmList()
    {
        _alarmList = new Dictionary<long, TimeSpan>();
        if (_timeScheduler == null) return;

        var now = DateTime.Now;

        foreach (DataRow dr in _timeScheduler.Rows)
        {
            var sendBy = GetByte(dr, "SENDBY");
            var scheduleId = GetLong(dr, "SCHEDULEID");

            // Daily: Add all daily schedules
            if (sendBy == SendByDaily)
            {
                _alarmList[scheduleId] = GetTimeSpan(dr, "TIME");
                continue;
            }

            // Weekly: Check if today is in the schedule
            if (sendBy == SendByWeekly)
            {
                var days = (dr["DAY"]?.ToString() ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries);
                if (days.Contains(((int)now.DayOfWeek).ToString()))
                {
                    _alarmList[scheduleId] = GetTimeSpan(dr, "TIME");
                }
                continue;
            }

            // Monthly: Check if today is in the schedule or end of month
            if (sendBy == SendByMonthly)
            {
                var dayOfMonth = now.Day.ToString();
                var days = (dr["DAY"]?.ToString() ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries);
                var isEndOfMonth = now.Day == DateTime.DaysInMonth(now.Year, now.Month);

                // Add if today matches or if it's end of month and scheduled day > current day
                if (days.Contains(dayOfMonth) ||
                    (isEndOfMonth && days.Length > 0 && int.TryParse(days[0], out var d) && d > now.Day))
                {
                    _alarmList[scheduleId] = GetTimeSpan(dr, "TIME");
                }
            }
        }

        _logger.LogDebug("Alarm list built with {Count} schedules for today", _alarmList.Count);
    }

    /// <summary>
    /// Check if midnight refresh is needed
    /// </summary>
    private void CheckMidnightRefresh()
    {
        if (DateTime.Now.ToString("HH:mm") == "00:00")
        {
            LoadSchedules();
            LoadAlarmList();
            _logger.LogInformation("Schedule alarm list refreshed at midnight");
        }
        else if (_alarmList.Count == 0)
        {
            LoadAlarmList();
        }
    }

    /// <summary>
    /// Process emails marked for retry
    /// </summary>
    private async Task ProcessRetryEmailsAsync(CancellationToken ct)
    {
        var dt = _data.GetEmailsWaitingToBeSent(StatusRetry);
        _logger.LogDebug("Processing {Count} retry emails", dt.Rows.Count);
        await ProcessEmailTableAsync(dt, ct);
    }

    /// <summary>
    /// Process scheduled emails (Daily, Weekly, Monthly)
    /// </summary>
    private async Task ProcessScheduledEmailsAsync(CancellationToken ct)
    {
        LoadAlarmList();
        var toRemove = new List<long>();

        foreach (var kv in _alarmList)
        {
            // Check if current time has passed the scheduled time
            if (DateTime.Now.TimeOfDay >= kv.Value)
            {
                _logger.LogInformation("Triggering scheduled email for ScheduleId={ScheduleId}", kv.Key);

                var templateId = _data.GetTemplateIdFromScheduleId((int)kv.Key);
                if (templateId.HasValue)
                {
                    // Generate the audience for this scheduled template (one queue row
                    // per recipient) BEFORE draining, so the same cycle sends them.
                    EnqueueAudienceForTemplate(templateId.Value, (int)kv.Key);

                    await ProcessEmailsByTemplateAsync(templateId.Value, ct);
                }

                toRemove.Add(kv.Key);
            }
        }

        // Remove processed schedules from alarm list
        foreach (var k in toRemove)
        {
            _alarmList.Remove(k);
        }
    }

    /// <summary>
    /// Generate the recipient audience for a scheduled template and enqueue one
    /// SA_EMAILMASTER row per recipient. No-op when the template has no audience SP
    /// (transactional templates send via the API directly, not the worker).
    /// </summary>
    private void EnqueueAudienceForTemplate(int templateId, int scheduleId)
    {
        // Single round-trip: schedule row joined to its template (audience SP + campaign config).
        var cfg = _data.GetScheduleConfig(scheduleId);
        if (cfg == null) return;

        var audienceSp = cfg.AudienceSp?.Trim();
        if (string.IsNullOrWhiteSpace(audienceSp)) return;

        var tenantId = cfg.TenantId;
        var excluded = cfg.ExcludedUserIds;
        var couponCode = cfg.CouponCode;
        var content = cfg.Content; // admin-authored Subject/Headline/Message/CTA
        var channels = cfg.Channels; // e.g. ["Email"] or ["Email","WhatsApp"]

        DataTable recipients;
        try
        {
            recipients = _data.RunAudienceSp(audienceSp, tenantId, templateId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Audience SP '{Sp}' failed for TemplateId={TemplateId}", audienceSp, templateId);
            return;
        }

        var today = DateTime.Now.ToString("yyyyMMdd");
        int enqueued = 0;
        int skippedExcluded = 0;

        foreach (DataRow r in recipients.Rows)
        {
            // All result-set columns become the EMAILSP payload (envelope + merge fields)
            var payload = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            foreach (DataColumn col in recipients.Columns)
            {
                var val = r[col];
                payload[col.ColumnName] = val == DBNull.Value ? null : val;
            }

            var to = FirstNonEmpty(payload, "to", "email");
            if (string.IsNullOrWhiteSpace(to))
            {
                _logger.LogWarning("Audience row for TemplateId={TemplateId} has no email; skipped", templateId);
                continue;
            }
            payload["to"] = to;

            var recipientId = FirstNonEmpty(payload, "recipientid", "userid", "id") ?? to;

            // Per-schedule exclusion list: skip customers the admin opted out of this campaign
            if (long.TryParse(recipientId, out var uid) && excluded.Contains(uid))
            {
                skippedExcluded++;
                continue;
            }

            // Campaign coupon: apply the schedule's code unless the audience SP
            // already supplied a per-recipient one (unique codes win).
            if (!string.IsNullOrWhiteSpace(couponCode) &&
                string.IsNullOrWhiteSpace(FirstNonEmpty(payload, "couponcode")))
            {
                payload["CouponCode"] = couponCode;
            }

            // Admin-authored campaign content (Subject/Headline/Message/CTA): inject
            // each only when the audience SP didn't already supply it (SP value wins).
            void Apply(string key, string? value)
            {
                if (!string.IsNullOrWhiteSpace(value) && string.IsNullOrWhiteSpace(FirstNonEmpty(payload, key)))
                    payload[key] = value!;
            }
            Apply("Subject",  content.Subject);
            Apply("Headline", content.Headline);
            Apply("Message",  content.Message);
            Apply("CtaText",  content.CtaText);
            Apply("CtaUrl",   content.CtaUrl);

            // Recipient's own tenant (from the audience SP) wins; fall back to the schedule's tenant.
            long? rowTenant = tenantId;
            if (long.TryParse(FirstNonEmpty(payload, "tenantid"), out var t)) rowTenant = t;

            var hasPhone = !string.IsNullOrWhiteSpace(FirstNonEmpty(payload, "phone", "mobile"));
            var json = JsonSerializer.Serialize(payload);

            // Fan out one queue row per selected channel.
            foreach (var channel in channels)
            {
                // Skip WhatsApp for recipients with no phone number.
                if (channel.Equals("WhatsApp", StringComparison.OrdinalIgnoreCase) && !hasPhone) continue;

                // Fire-once dedup: template + day + recipient + channel
                var correlationId = $"{templateId}-{today}-{recipientId}-{channel}";
                if (_data.EmailExistsForCorrelation(correlationId)) continue;

                _data.EnqueueEmail(templateId, json, correlationId, rowTenant, channel);
                enqueued++;
            }
        }

        if (enqueued > 0 || skippedExcluded > 0)
        {
            _logger.LogInformation(
                "Audience SP '{Sp}' enqueued {Count} email(s) for TemplateId={TemplateId} ({Excluded} excluded)",
                audienceSp, enqueued, templateId, skippedExcluded);
        }
    }

    /// <summary>
    /// Process immediate emails
    /// </summary>
    private async Task ProcessImmediateEmailsAsync(CancellationToken ct)
    {
        if (_schedule == null) return;

        foreach (DataRow dr in _schedule.Rows)
        {
            if (GetByte(dr, "SENDBY") != SendByImmediate) continue;

            var templateId = GetInt(dr, "TEMPLATEID");
            var scheduleId = GetInt(dr, "SCHEDULEID");

            // Generate the audience for this immediate template (one queue row per
            // recipient) BEFORE draining, so the same cycle sends them. Without this
            // the immediate path only drained pre-existing rows and never enqueued any.
            EnqueueAudienceForTemplate(templateId, scheduleId);

            await ProcessEmailsByTemplateAsync(templateId, ct);
        }
    }

    /// <summary>
    /// Process emails by template ID
    /// </summary>
    private async Task ProcessEmailsByTemplateAsync(int templateId, CancellationToken ct)
    {
        var dt = _data.GetEmailsWaitingToBeSent(StatusPending);
        var rows = dt.AsEnumerable().Where(r => GetInt(r, "TEMPLATEID") == templateId).ToArray();

        _logger.LogDebug("Processing {Count} emails for TemplateId={TemplateId}", rows.Length, templateId);

        foreach (DataRow row in rows)
        {
            await SendOneAsync(row, ct);
        }
    }

    /// <summary>
    /// Process email data table
    /// </summary>
    private async Task ProcessEmailTableAsync(DataTable dt, CancellationToken ct)
    {
        foreach (DataRow row in dt.Rows)
        {
            await SendOneAsync(row, ct);
        }
    }

    /// <summary>
    /// Send one email via API
    /// </summary>
    private async Task SendOneAsync(DataRow row, CancellationToken ct)
    {
        long id = GetLong(row, "ID");
        int templateId = GetInt(row, "TEMPLATEID");
        string emailSp = row["EMAILSP"]?.ToString() ?? "";
        int retryCount = GetInt(row, "RETRY_COUNT");
        string? correlationId = row["CORRELATION_ID"]?.ToString();
        // API requires TenantId > 0; coerce NULL/0 to the default tenant. Global
        // templates still resolve for any tenant, tenant overrides resolve correctly.
        long tenantId = GetTenantOrDefault(row, "TENANTID");
        // CHANNEL routes the row to the email or WhatsApp dispatch endpoint.
        string channel = row.Table.Columns.Contains("CHANNEL") ? (row["CHANNEL"]?.ToString() ?? "Email") : "Email";
        bool isWhatsApp = channel.Equals("WhatsApp", StringComparison.OrdinalIgnoreCase);
        string endpoint = isWhatsApp ? _whatsAppEndpoint : _apiEndpoint;

        var request = new EmailSendRequest
        {
            Id = id,
            TenantId = tenantId,
            TemplateId = templateId,
            EmailSP = emailSp,
            CorrelationId = correlationId,
            RetryCount = retryCount
        };

        try
        {
            _logger.LogDebug("Sending {Channel} Id={Id}, TemplateId={TemplateId}", channel, id, templateId);

            var response = await _httpClient.PostAsJsonAsync(endpoint, request, ct);

            if (response.IsSuccessStatusCode)
            {
                _data.UpdateEmailStatus(id, StatusSuccess, correlationId);
                _logger.LogInformation("Email {Id} sent successfully", id);
            }
            else
            {
                var err = await response.Content.ReadAsStringAsync(ct);
                SetStatusWithRetry(id, StatusFailure, err);
                _logger.LogWarning("Email {Id} failed: {Error}", id, err);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Email {Id} send failed", id);
            SetStatusWithRetry(id, StatusFailure, ex.Message);
        }
    }

    /// <summary>
    /// Set status with retry logic
    /// </summary>
    private void SetStatusWithRetry(long id, byte status, string? errorMsg)
    {
        errorMsg = errorMsg?.Length > 500 ? errorMsg.Substring(0, 500) : errorMsg;
        var result = _data.UpdateEmailStatus(id, status, null, errorMsg);

        if (result == StatusRetry)
        {
            _logger.LogInformation("Email {Id} marked for retry", id);
        }
    }

    // Helper methods
    private static string? FirstNonEmpty(IDictionary<string, object?> d, params string[] keys)
    {
        foreach (var k in keys)
        {
            if (d.TryGetValue(k, out var v) && v != null)
            {
                var s = v.ToString();
                if (!string.IsNullOrWhiteSpace(s)) return s;
            }
        }
        return null;
    }

    private const long DefaultTenantId = 1;
    private static long GetTenantOrDefault(DataRow r, string col, long def = DefaultTenantId)
    {
        var v = r[col];
        if (v == null || v == DBNull.Value) return def;
        var t = Convert.ToInt64(v);
        return t > 0 ? t : def;
    }

    private static long GetLong(DataRow r, string col) => Convert.ToInt64(r[col] ?? 0);
    private static int GetInt(DataRow r, string col) => Convert.ToInt32(r[col] ?? 0);
    private static byte GetByte(DataRow r, string col) => Convert.ToByte(r[col] ?? 0);
    private static TimeSpan GetTimeSpan(DataRow r, string col)
    {
        var v = r[col];
        if (v == null || v == DBNull.Value) return TimeSpan.Zero;
        if (v is TimeSpan ts) return ts;
        if (v is DateTime dt) return dt.TimeOfDay;
        var s = v.ToString()?.Trim();
        if (string.IsNullOrEmpty(s)) return TimeSpan.Zero;
        if (TimeSpan.TryParse(s, out var parsed)) return parsed;
        return TimeSpan.Zero;
    }
}
