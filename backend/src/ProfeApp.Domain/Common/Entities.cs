namespace ProfeApp.Domain.Common;

/// <summary>Toda entidad persistida tiene Id Guid y marcas de auditoría.</summary>
public abstract class BaseEntity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTimeOffset CreatedAt { get; set; }
    public Guid? CreatedBy { get; set; }
    public DateTimeOffset? UpdatedAt { get; set; }
    public Guid? UpdatedBy { get; set; }
}

/// <summary>Marca las entidades sujetas al filtro global de tenant.</summary>
public interface IMustHaveTenant
{
    Guid TenantId { get; set; }
}

public abstract class TenantEntity : BaseEntity, IMustHaveTenant
{
    public Guid TenantId { get; set; }
}

/// <summary>Soft delete opcional: solo donde el histórico importa.</summary>
public interface ISoftDelete
{
    DateTimeOffset? DeletedAt { get; set; }
}

public sealed class DomainException(string message) : Exception(message);
