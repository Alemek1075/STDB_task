using Npgsql;
using University.Data.Infrastructure;
using University.Data.Repositories;

namespace University.Data;

public interface IUnitOfWork : IAsyncDisposable
{
    IStudentRepository Students { get; }
    IStudentGroupRepository Groups { get; }
    IEnrollmentRepository Enrollments { get; }
    IGradeRepository Grades { get; }
    IAuditRepository Audit { get; }

    /// <summary>Descriptions of the writes queued since the last save.</summary>
    IReadOnlyList<string> PendingChanges { get; }

    /// <summary>
    /// Runs every queued write in one transaction on behalf of the acting user.
    /// All or nothing: on the first error the transaction is rolled back and the queue is cleared.
    /// </summary>
    Task<int> SaveChangesAsync(CancellationToken ct = default);

    /// <summary>Drops queued writes without touching the database.</summary>
    void DiscardChanges();
}

/// <summary>
/// Unit of Work over one PostgreSQL connection.
/// Repositories share the connection; reads run immediately, writes are queued and
/// flushed by <see cref="SaveChangesAsync"/>. The acting user is passed to the database
/// via <c>set_config('app.user_id', ..., true)</c>, which the audit triggers read.
/// </summary>
public sealed class UnitOfWork : IUnitOfWork, IUnitOfWorkContext
{
    private readonly NpgsqlConnection _connection;
    private readonly int _userId;
    private readonly List<(string Description, Func<CancellationToken, Task> Run)> _pending = [];

    private StudentRepository? _students;
    private StudentGroupRepository? _groups;
    private EnrollmentRepository? _enrollments;
    private GradeRepository? _grades;
    private AuditRepository? _audit;

    internal UnitOfWork(NpgsqlConnection connection, int userId)
    {
        _connection = connection;
        _userId = userId;
    }

    public IStudentRepository Students => _students ??= new StudentRepository(this);
    public IStudentGroupRepository Groups => _groups ??= new StudentGroupRepository(this);
    public IEnrollmentRepository Enrollments => _enrollments ??= new EnrollmentRepository(this);
    public IGradeRepository Grades => _grades ??= new GradeRepository(this);
    public IAuditRepository Audit => _audit ??= new AuditRepository(this);

    public IReadOnlyList<string> PendingChanges => _pending.Select(p => p.Description).ToList();

    NpgsqlConnection IUnitOfWorkContext.Connection => _connection;
    public NpgsqlTransaction? Transaction { get; private set; }

    void IUnitOfWorkContext.Register(string description, Func<CancellationToken, Task> operation) =>
        _pending.Add((description, operation));

    public async Task<int> SaveChangesAsync(CancellationToken ct = default)
    {
        if (_pending.Count == 0)
            return 0;

        var operations = _pending.ToList();
        _pending.Clear();

        Transaction = await _connection.BeginTransactionAsync(ct);
        string? current = null;
        try
        {
            await using (var cmd = new NpgsqlCommand("SELECT set_config('app.user_id', @id, true)", _connection, Transaction))
            {
                cmd.Parameters.AddWithValue("id", _userId.ToString());
                await cmd.ExecuteNonQueryAsync(ct);
            }

            foreach (var (description, run) in operations)
            {
                current = description;
                await run(ct);
            }

            await Transaction.CommitAsync(ct);
            return operations.Count;
        }
        catch (Exception ex)
        {
            await Transaction.RollbackAsync(CancellationToken.None);
            if (ex is DataAccessException dae)
                throw new DataAccessException($"{current}: {dae.Message}", dae.SqlState, current, dae);
            throw;
        }
        finally
        {
            await Transaction.DisposeAsync();
            Transaction = null;
        }
    }

    public void DiscardChanges() => _pending.Clear();

    public async ValueTask DisposeAsync()
    {
        _pending.Clear();
        await _connection.DisposeAsync();
    }
}

/// <summary>Creates units of work; one per business operation / request.</summary>
public sealed class UnitOfWorkFactory : IAsyncDisposable
{
    public const string DefaultConnectionString = "Host=localhost;Port=5433;Database=university;Username=postgres";

    private readonly NpgsqlDataSource _dataSource;

    public UnitOfWorkFactory(string? connectionString = null) =>
        _dataSource = NpgsqlDataSource.Create(connectionString ?? DefaultConnectionString);

    /// <param name="actingUserId">app_users.id recorded in created_by / updated_by / audit_log.</param>
    public async Task<IUnitOfWork> CreateAsync(int actingUserId, CancellationToken ct = default)
    {
        var connection = await _dataSource.OpenConnectionAsync(ct);
        return new UnitOfWork(connection, actingUserId);
    }

    public ValueTask DisposeAsync() => _dataSource.DisposeAsync();
}
