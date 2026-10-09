using University.Data.Entities;
using University.Data.Infrastructure;

namespace University.Data.Repositories;

internal sealed class AuditRepository(IUnitOfWorkContext context) : RepositoryBase(context), IAuditRepository
{
    public async Task<IReadOnlyList<AuditEntry>> GetHistoryAsync(string table, long recordId, CancellationToken ct = default) =>
        await QueryAsync(
            "SELECT changed_at, changed_by, table_name, record_id, operation, changes::text AS changes " +
            "FROM v_audit_trail WHERE table_name = @table AND record_id = @id ORDER BY id",
            r => new AuditEntry(r.Get<DateTime>("changed_at"), r.Get<string>("changed_by"), r.Get<string>("table_name"),
                r.Get<long>("record_id"), r.Get<string>("operation"), r.Get<string?>("changes")),
            ct, P("table", table), P("id", recordId));

    public async Task<IReadOnlyList<AppUser>> GetUsersAsync(CancellationToken ct = default) =>
        await QueryAsync("SELECT id, username, role, person_name FROM v_app_users ORDER BY id",
            r => new AppUser(r.Get<int>("id"), r.Get<string>("username"), r.Get<string>("role"), r.Get<string?>("person_name")), ct);
}
