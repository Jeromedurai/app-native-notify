using System.Collections.Generic;
using System.Data;

namespace AppNativeNotification.DataAccess;

/// <summary>Admin-authored campaign content stored on a schedule (all optional).</summary>
public sealed class ScheduleContent
{
    public string? Subject { get; set; }
    public string? Headline { get; set; }
    public string? Message { get; set; }
    public string? CtaText { get; set; }
    public string? CtaUrl { get; set; }
}

/// <summary>
/// A schedule's full enqueue configuration, read in one query (schedule row joined to its
/// template). AudienceSp comes from SA_EMAILTEMPLATE; the rest from SA_EMAILSCHEDULE.
/// </summary>
public sealed class ScheduleConfig
{
    public string? AudienceSp { get; set; }                              // SA_EMAILTEMPLATE.AUDIENCESP
    public long? TenantId { get; set; }
    public HashSet<long> ExcludedUserIds { get; set; } = new();
    public string? CouponCode { get; set; }
    public ScheduleContent Content { get; set; } = new();
    public List<string> Channels { get; set; } = new() { "Email" };      // default Email when unset
}

/// <summary>
/// Data access interface for notification service
/// </summary>
public interface INotificationDataAccess
{
    Task<bool> CheckConnectionHealthAsync();
    DataTable GetEmailSchedule();
    DataTable GetEmailScheduleForTimeScheduler();
    DataTable GetEmailsWaitingToBeSent(byte status = 0);
    DataTable GetEmailTemplates();
    int UpdateEmailStatus(long id, byte status, string? correlationId = null, string? errorMsg = null);
    int? GetTemplateIdFromScheduleId(int scheduleId);
    void UpdateServiceStatus(string serviceName, byte status, string? errorMessage = null);

    // Audience generation (scheduled sends) — read the schedule's full config (joined to its
    // template's audience SP) in one query, run the SP, and enqueue one queue row per recipient.
    ScheduleConfig? GetScheduleConfig(int scheduleId);   // null when scheduleId not found
    DataTable RunAudienceSp(string spName, long? tenantId, long templateId);
    long EnqueueEmail(long templateId, string emailSpJson, string? correlationId, long? tenantId, string channel);
    bool EmailExistsForCorrelation(string correlationId);
}
