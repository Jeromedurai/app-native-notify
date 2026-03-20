namespace AppNativeNotification.Models;

/// <summary>
/// Request model for sending email via API
/// </summary>
public class EmailSendRequest
{
    public long Id { get; set; }
    public int TemplateId { get; set; }
    public string EmailSP { get; set; } = string.Empty;
    public string? CorrelationId { get; set; }
    public int RetryCount { get; set; }
}
