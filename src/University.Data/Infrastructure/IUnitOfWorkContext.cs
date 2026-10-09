using Npgsql;

namespace University.Data.Infrastructure;

/// <summary>What a repository needs from its unit of work.</summary>
internal interface IUnitOfWorkContext
{
    NpgsqlConnection Connection { get; }

    /// <summary>Open transaction while <c>SaveChangesAsync</c> runs; null for plain reads.</summary>
    NpgsqlTransaction? Transaction { get; }

    /// <summary>Queue a write. It runs later, inside the single transaction of <c>SaveChangesAsync</c>.</summary>
    void Register(string description, Func<CancellationToken, Task> operation);
}
