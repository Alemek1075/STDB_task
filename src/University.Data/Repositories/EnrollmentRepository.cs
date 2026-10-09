using Npgsql;
using University.Data.Entities;
using University.Data.Infrastructure;

namespace University.Data.Repositories;

internal sealed class EnrollmentRepository(IUnitOfWorkContext context) : RepositoryBase(context), IEnrollmentRepository
{
    private const string Columns =
        "id, student_id, student_name, offering_id, course_code, course_name, term_id, term, group_code, lecturer_name, " +
        "status, current_points, final_points, ects_grade, updated_by";

    public async Task<IReadOnlyList<Enrollment>> GetByStudentAsync(int studentId, bool currentTermOnly = false, CancellationToken ct = default) =>
        await QueryAsync(
            $"SELECT {Columns} FROM v_enrollment_details " +
            "WHERE student_id = @id AND (NOT @current OR term_id = fn_current_term_id()) ORDER BY term_id, group_code, course_code",
            Map, ct, P("id", studentId), P("current", currentTermOnly));

    public async Task<IReadOnlyList<Enrollment>> GetByOfferingAsync(int offeringId, CancellationToken ct = default) =>
        await QueryAsync($"SELECT {Columns} FROM v_enrollment_details WHERE offering_id = @id ORDER BY student_name",
            Map, ct, P("id", offeringId));

    public void Add(Enrollment e) =>
        Enqueue($"enrol student into offering #{e.OfferingId}", async ct =>
            e.Id = await ScalarAsync<int>("CALL sp_enrollment_create(@student, @offering, NULL)", ct,
                P("student", e.StudentId), P("offering", e.OfferingId)));

    public void Withdraw(Enrollment e) =>
        Enqueue($"withdraw enrollment #{e.Id}", ct => ExecuteAsync("CALL sp_enrollment_withdraw(@id)", ct, P("id", e.Id)));

    public void FinalizeOffering(int offeringId) =>
        Enqueue($"finalize offering #{offeringId}", ct =>
            ExecuteAsync("CALL sp_finalize_offering(@id, NULL, NULL)", ct, P("id", offeringId)));

    private static Enrollment Map(NpgsqlDataReader r) => new()
    {
        Id = r.Get<int>("id"),
        StudentId = r.Get<int>("student_id"),
        StudentName = r.Get<string>("student_name"),
        OfferingId = r.Get<int>("offering_id"),
        CourseCode = r.Get<string>("course_code"),
        CourseName = r.Get<string>("course_name"),
        TermId = r.Get<int>("term_id"),
        Term = r.Get<string>("term"),
        GroupCode = r.Get<string>("group_code"),
        LecturerName = r.Get<string>("lecturer_name"),
        Status = r.Get<string>("status"),
        CurrentPoints = r.Get<decimal>("current_points"),
        FinalPoints = r.Get<decimal?>("final_points"),
        EctsGrade = r.Get<string?>("ects_grade"),
        UpdatedBy = r.Get<string?>("updated_by"),
    };
}
