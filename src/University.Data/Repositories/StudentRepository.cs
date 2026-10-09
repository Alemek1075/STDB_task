using Npgsql;
using University.Data.Entities;
using University.Data.Infrastructure;

namespace University.Data.Repositories;

internal sealed class StudentRepository(IUnitOfWorkContext context) : RepositoryBase(context), IStudentRepository
{
    private const string Columns =
        "id, group_id, group_code, record_book_no, first_name, last_name, middle_name, full_name, birth_date, " +
        "email, enrollment_date, funding_type, status, specialty, updated_at, updated_by";

    public async Task<Student?> GetByIdAsync(int id, CancellationToken ct = default) =>
        await QuerySingleAsync($"SELECT {Columns} FROM v_active_students WHERE id = @id", Map, ct, P("id", id));

    public async Task<IReadOnlyList<Student>> GetByGroupAsync(int groupId, CancellationToken ct = default) =>
        await QueryAsync($"SELECT {Columns} FROM fn_group_students(@group)", Map, ct, P("group", groupId));

    public async Task<IReadOnlyList<Student>> SearchAsync(string namePart, CancellationToken ct = default) =>
        await QueryAsync($"SELECT {Columns} FROM v_active_students WHERE full_name ILIKE @q ORDER BY full_name",
            Map, ct, P("q", $"%{namePart}%"));

    public async Task<IReadOnlyList<DeletedStudent>> GetDeletedAsync(CancellationToken ct = default) =>
        await QueryAsync(
            "SELECT id, record_book_no, full_name, group_code, deleted_at, deleted_by FROM v_deleted_students ORDER BY deleted_at DESC",
            r => new DeletedStudent(r.Get<int>("id"), r.Get<string>("record_book_no"), r.Get<string>("full_name"),
                r.Get<string>("group_code"), r.Get<DateTime>("deleted_at"), r.Get<string?>("deleted_by")), ct);

    public async Task<IReadOnlyList<TranscriptLine>> GetTranscriptAsync(int studentId, CancellationToken ct = default) =>
        await QueryAsync(
            "SELECT academic_year, semester, course_code, course_name, ects_credits, status, final_points, ects_grade, national_grade " +
            "FROM v_student_transcript WHERE student_id = @id ORDER BY academic_year, semester, course_code",
            r => new TranscriptLine(r.Get<string>("academic_year"), r.Get<short>("semester"), r.Get<string>("course_code"),
                r.Get<string>("course_name"), r.Get<decimal>("ects_credits"), r.Get<string>("status"),
                r.Get<decimal?>("final_points"), r.Get<string?>("ects_grade"), r.Get<string?>("national_grade")),
            ct, P("id", studentId));

    public Task<decimal?> GetGpaAsync(int studentId, CancellationToken ct = default) =>
        ScalarAsync<decimal?>("SELECT fn_student_gpa(@id)", ct, P("id", studentId));

    public void Add(Student s) =>
        Enqueue($"create student {s.LastName} {s.FirstName}", async ct =>
            s.Id = await ScalarAsync<int>(
                "CALL sp_student_create(@group, @book, @first, @last, @middle::varchar, @birth, @email, @funding, @enrolled::date, NULL)", ct,
                P("group", s.GroupId), P("book", s.RecordBookNo), P("first", s.FirstName), P("last", s.LastName),
                P("middle", s.MiddleName), P("birth", s.BirthDate), P("email", s.Email), P("funding", s.FundingType),
                P("enrolled", s.EnrollmentDate)));

    public void Update(Student s) =>
        Enqueue($"update student #{s.Id}", ct =>
            ExecuteAsync("CALL sp_student_update(@id, @first, @last, @middle::varchar, @birth, @email, @funding, @status)", ct,
                P("id", s.Id), P("first", s.FirstName), P("last", s.LastName), P("middle", s.MiddleName),
                P("birth", s.BirthDate), P("email", s.Email), P("funding", s.FundingType), P("status", s.Status)));

    public void Remove(Student s) =>
        Enqueue($"soft-delete student #{s.Id}", ct => ExecuteAsync("CALL sp_student_soft_delete(@id)", ct, P("id", s.Id)));

    public void Restore(int studentId) =>
        Enqueue($"restore student #{studentId}", ct => ExecuteAsync("CALL sp_student_restore(@id)", ct, P("id", studentId)));

    public void Transfer(Student s, int newGroupId) =>
        Enqueue($"transfer student #{s.Id} to group #{newGroupId}", ct =>
            ExecuteAsync("CALL sp_student_transfer(@id, @group, NULL, NULL)", ct, P("id", s.Id), P("group", newGroupId)));

    private static Student Map(NpgsqlDataReader r) => new()
    {
        Id = r.Get<int>("id"),
        GroupId = r.Get<int>("group_id"),
        GroupCode = r.Get<string>("group_code"),
        RecordBookNo = r.Get<string>("record_book_no"),
        FirstName = r.Get<string>("first_name"),
        LastName = r.Get<string>("last_name"),
        MiddleName = r.Get<string?>("middle_name"),
        FullName = r.Get<string>("full_name"),
        BirthDate = r.Get<DateOnly>("birth_date"),
        Email = r.Get<string>("email"),
        EnrollmentDate = r.Get<DateOnly>("enrollment_date"),
        FundingType = r.Get<string>("funding_type"),
        Status = r.Get<string>("status"),
        Specialty = r.Get<string?>("specialty"),
        UpdatedAt = r.Get<DateTime>("updated_at"),
        UpdatedBy = r.Get<string?>("updated_by"),
    };
}
