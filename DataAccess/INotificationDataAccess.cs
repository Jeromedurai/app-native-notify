using System.Data;

namespace AppNativeNotification.DataAccess;

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
}
