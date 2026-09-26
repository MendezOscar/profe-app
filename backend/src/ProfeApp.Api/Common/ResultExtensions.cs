using Microsoft.AspNetCore.Mvc;
using ProfeApp.Application.Common;

namespace ProfeApp.Api.Common;

public static class ResultExtensions
{
    public static IResult ToHttp<T>(this Result<T> result, Func<T, IResult>? onSuccess = null) =>
        result.IsSuccess
            ? onSuccess?.Invoke(result.Value) ?? Results.Ok(result.Value)
            : Problem(result.Error!);

    public static IResult ToHttp(this Result result) =>
        result.IsSuccess ? Results.NoContent() : Problem(result.Error!);

    public static IResult ToCreated<T>(this Result<T> result, Func<T, string> location) =>
        result.IsSuccess ? Results.Created(location(result.Value), result.Value) : Problem(result.Error!);

    private static IResult Problem(Error error)
    {
        var status = error.Kind switch
        {
            ErrorKind.Validation => StatusCodes.Status400BadRequest,
            ErrorKind.NotFound => StatusCodes.Status404NotFound,
            ErrorKind.Conflict => StatusCodes.Status409Conflict,
            ErrorKind.Forbidden => StatusCodes.Status403Forbidden,
            _ => StatusCodes.Status500InternalServerError
        };

        return Results.Problem(new ProblemDetails
        {
            Status = status,
            Title = error.Code,
            Detail = error.Message,
            Extensions = { ["code"] = error.Code }
        });
    }
}
