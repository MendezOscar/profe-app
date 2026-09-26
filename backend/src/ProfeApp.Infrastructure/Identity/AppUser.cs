using Microsoft.AspNetCore.Identity;

namespace ProfeApp.Infrastructure.Identity;

public class AppUser : IdentityUser<Guid>
{
    /// <summary>Null sólo para PlatformAdmin.</summary>
    public Guid? TenantId { get; set; }
    public string FullName { get; set; } = null!;
    public bool IsActive { get; set; } = true;
    public bool MustChangePassword { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? LastLoginAt { get; set; }
}

public class AppRole : IdentityRole<Guid>
{
    public AppRole() { }
    public AppRole(string name) : base(name) => NormalizedName = name.ToUpperInvariant();
}
