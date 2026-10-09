using Npgsql;

namespace University.Data.Infrastructure;

/// <summary>
/// A database rule was violated (trigger, constraint, procedure check).
/// Carries the PostgreSQL SQLSTATE so callers can react to specific cases.
/// </summary>
public sealed class DataAccessException : Exception
{
    public string SqlState { get; }
    public string? Operation { get; }

    public DataAccessException(string message, string sqlState, string? operation, Exception inner)
        : base(message, inner)
    {
        SqlState = sqlState;
        Operation = operation;
    }

    internal static DataAccessException From(PostgresException ex, string? operation) =>
        new(ex.MessageText, ex.SqlState, operation, ex);
}
