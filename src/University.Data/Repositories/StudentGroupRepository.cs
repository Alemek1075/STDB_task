using Npgsql;
using University.Data.Entities;
using University.Data.Infrastructure;

namespace University.Data.Repositories;

internal sealed class StudentGroupRepository(IUnitOfWorkContext context) : RepositoryBase(context), IStudentGroupRepository
{
    private const string Columns =
        "id, code, specialty_id, specialty, degree_level, enrollment_year, curator_id, curator_name, active_students, updated_at, updated_by";

    public async Task<IReadOnlyList<StudentGroup>> GetAllAsync(CancellationToken ct = default) =>
        await QueryAsync($"SELECT {Columns} FROM v_active_groups ORDER BY code", Map, ct);

    public async Task<StudentGroup?> GetByIdAsync(int id, CancellationToken ct = default) =>
        await QuerySingleAsync($"SELECT {Columns} FROM v_active_groups WHERE id = @id", Map, ct, P("id", id));

    public async Task<StudentGroup?> GetByCodeAsync(string code, CancellationToken ct = default) =>
        await QuerySingleAsync($"SELECT {Columns} FROM v_active_groups WHERE code = @code", Map, ct, P("code", code));

    public async Task<IReadOnlyList<CourseOffering>> GetOfferingsAsync(int groupId, bool currentTermOnly = true, CancellationToken ct = default) =>
        await QueryAsync(
            "SELECT id, course_code, course_name, ects_credits, term_id, term, is_current, group_id, group_code, lecturer_id, lecturer_name " +
            "FROM v_course_offerings WHERE group_id = @group AND (is_current OR NOT @current) ORDER BY term_id, course_code",
            r => new CourseOffering(r.Get<int>("id"), r.Get<string>("course_code"), r.Get<string>("course_name"),
                r.Get<decimal>("ects_credits"), r.Get<int>("term_id"), r.Get<string>("term"), r.Get<bool>("is_current"),
                r.Get<int>("group_id"), r.Get<string>("group_code"), r.Get<int>("lecturer_id"), r.Get<string>("lecturer_name")),
            ct, P("group", groupId), P("current", currentTermOnly));

    public void Add(StudentGroup g) =>
        Enqueue($"create group {g.Code}", async ct =>
            g.Id = await ScalarAsync<int>("CALL sp_group_create(@specialty, @code, @year::smallint, @curator::int, NULL)", ct,
                P("specialty", g.SpecialtyId), P("code", g.Code), P("year", g.EnrollmentYear), P("curator", g.CuratorId)));

    public void Update(StudentGroup g) =>
        Enqueue($"update group #{g.Id}", ct =>
            ExecuteAsync("CALL sp_group_update(@id, @code, @curator::int)", ct,
                P("id", g.Id), P("code", g.Code), P("curator", g.CuratorId)));

    public void Remove(StudentGroup g) =>
        Enqueue($"soft-delete group #{g.Id}", ct => ExecuteAsync("CALL sp_group_soft_delete(@id)", ct, P("id", g.Id)));

    private static StudentGroup Map(NpgsqlDataReader r) => new()
    {
        Id = r.Get<int>("id"),
        Code = r.Get<string>("code"),
        SpecialtyId = r.Get<int>("specialty_id"),
        Specialty = r.Get<string?>("specialty"),
        DegreeLevel = r.Get<string?>("degree_level"),
        EnrollmentYear = r.Get<short>("enrollment_year"),
        CuratorId = r.Get<int?>("curator_id"),
        CuratorName = r.Get<string?>("curator_name"),
        ActiveStudents = r.Get<long>("active_students"),
        UpdatedAt = r.Get<DateTime>("updated_at"),
        UpdatedBy = r.Get<string?>("updated_by"),
    };
}
