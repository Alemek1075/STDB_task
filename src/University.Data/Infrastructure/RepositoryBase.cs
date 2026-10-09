using Npgsql;

namespace University.Data.Infrastructure;

/// <summary>
/// Shared plumbing for repositories. By convention the SQL passed here only touches
/// views (v_*), functions (fn_*) and procedures (CALL sp_*), never tables.
/// </summary>
internal abstract class RepositoryBase
{
    protected IUnitOfWorkContext Context { get; }

    protected RepositoryBase(IUnitOfWorkContext context) => Context = context;

    protected async Task<List<T>> QueryAsync<T>(string sql, Func<NpgsqlDataReader, T> map,
        CancellationToken ct, params NpgsqlParameter[] parameters)
    {
        await using var cmd = CreateCommand(sql, parameters);
        try
        {
            await using var reader = await cmd.ExecuteReaderAsync(ct);
            var result = new List<T>();
            while (await reader.ReadAsync(ct))
                result.Add(map(reader));
            return result;
        }
        catch (PostgresException ex)
        {
            throw DataAccessException.From(ex, sql);
        }
    }

    protected async Task<T?> QuerySingleAsync<T>(string sql, Func<NpgsqlDataReader, T> map,
        CancellationToken ct, params NpgsqlParameter[] parameters) where T : class =>
        (await QueryAsync(sql, map, ct, parameters)).FirstOrDefault();

    protected async Task<T> ScalarAsync<T>(string sql, CancellationToken ct, params NpgsqlParameter[] parameters)
    {
        await using var cmd = CreateCommand(sql, parameters);
        try
        {
            var value = await cmd.ExecuteScalarAsync(ct);
            return value is null or DBNull ? default! : (T)Convert.ChangeType(value, Nullable.GetUnderlyingType(typeof(T)) ?? typeof(T));
        }
        catch (PostgresException ex)
        {
            throw DataAccessException.From(ex, sql);
        }
    }

    protected async Task ExecuteAsync(string sql, CancellationToken ct, params NpgsqlParameter[] parameters)
    {
        await using var cmd = CreateCommand(sql, parameters);
        try
        {
            await cmd.ExecuteNonQueryAsync(ct);
        }
        catch (PostgresException ex)
        {
            throw DataAccessException.From(ex, sql);
        }
    }

    /// <summary>Defers a write until SaveChangesAsync.</summary>
    protected void Enqueue(string description, Func<CancellationToken, Task> operation) =>
        Context.Register(description, operation);

    protected static NpgsqlParameter P(string name, object? value) => new(name, value ?? DBNull.Value);

    private NpgsqlCommand CreateCommand(string sql, NpgsqlParameter[] parameters)
    {
        var cmd = new NpgsqlCommand(sql, Context.Connection, Context.Transaction);
        cmd.Parameters.AddRange(parameters);
        return cmd;
    }
}
