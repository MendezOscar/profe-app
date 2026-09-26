namespace ProfeApp.Application.Common;

public enum ErrorKind { Validation, NotFound, Conflict, Forbidden, Unexpected }

public sealed record Error(ErrorKind Kind, string Code, string Message)
{
    public static Error Validation(string message, string code = "validation_error") => new(ErrorKind.Validation, code, message);
    public static Error NotFound(string what) => new(ErrorKind.NotFound, "not_found", $"{what} no existe.");
    public static Error Conflict(string message, string code = "conflict") => new(ErrorKind.Conflict, code, message);
    public static Error Forbidden(string message = "No tienes permiso sobre este recurso.") => new(ErrorKind.Forbidden, "forbidden", message);
}

public class Result
{
    protected Result(Error? error) => Error = error;
    public Error? Error { get; }
    public bool IsSuccess => Error is null;
    public static Result Success() => new(null);
    public static Result Fail(Error error) => new(error);
}

public sealed class Result<T> : Result
{
    private Result(T? value, Error? error) : base(error) => _value = value;
    private readonly T? _value;
    public T Value => IsSuccess ? _value! : throw new InvalidOperationException("Result sin valor: " + Error!.Message);
    public static Result<T> Ok(T value) => new(value, null);
    public static new Result<T> Fail(Error error) => new(default, error);
    public static implicit operator Result<T>(T value) => Ok(value);
}
