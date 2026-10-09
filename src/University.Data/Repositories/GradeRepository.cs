using Npgsql;
using University.Data.Entities;
using University.Data.Infrastructure;

namespace University.Data.Repositories;

internal sealed class GradeRepository(IUnitOfWorkContext context) : RepositoryBase(context), IGradeRepository
{
    private const string Columns =
        "id, assessment_id, assessment_title, max_points, offering_id, course_name, student_id, student_name, " +
        "points, graded_by, graded_by_name, graded_at, updated_at, updated_by";

    public async Task<IReadOnlyList<Grade>> GetByStudentAsync(int studentId, CancellationToken ct = default) =>
        await QueryAsync($"SELECT {Columns} FROM v_grade_details WHERE student_id = @id ORDER BY offering_id, assessment_id",
            Map, ct, P("id", studentId));

    public async Task<IReadOnlyList<Grade>> GetByOfferingAsync(int offeringId, CancellationToken ct = default) =>
        await QueryAsync($"SELECT {Columns} FROM v_grade_details WHERE offering_id = @id ORDER BY student_name, assessment_id",
            Map, ct, P("id", offeringId));

    public async Task<IReadOnlyList<Assessment>> GetAssessmentsAsync(int offeringId, CancellationToken ct = default) =>
        await QueryAsync(
            "SELECT id, offering_id, title, assessment_type, max_points, due_date FROM v_offering_assessments " +
            "WHERE offering_id = @id ORDER BY due_date, id",
            r => new Assessment(r.Get<int>("id"), r.Get<int>("offering_id"), r.Get<string>("title"),
                r.Get<string>("assessment_type"), r.Get<decimal>("max_points"), r.Get<DateOnly?>("due_date")),
            ct, P("id", offeringId));

    public void Set(Grade g) =>
        Enqueue($"set {g.Points} points for assessment #{g.AssessmentId}", async ct =>
            g.Id = await ScalarAsync<int>("CALL sp_grade_set(@assessment, @student, @points, @by, NULL)", ct,
                P("assessment", g.AssessmentId), P("student", g.StudentId), P("points", g.Points), P("by", g.GradedBy)));

    public void Remove(Grade g) =>
        Enqueue($"delete grade #{g.Id}", ct => ExecuteAsync("CALL sp_grade_delete(@id)", ct, P("id", g.Id)));

    private static Grade Map(NpgsqlDataReader r) => new()
    {
        Id = r.Get<int>("id"),
        AssessmentId = r.Get<int>("assessment_id"),
        AssessmentTitle = r.Get<string>("assessment_title"),
        MaxPoints = r.Get<decimal>("max_points"),
        OfferingId = r.Get<int>("offering_id"),
        CourseName = r.Get<string>("course_name"),
        StudentId = r.Get<int>("student_id"),
        StudentName = r.Get<string>("student_name"),
        Points = r.Get<decimal>("points"),
        GradedBy = r.Get<int>("graded_by"),
        GradedByName = r.Get<string>("graded_by_name"),
        GradedAt = r.Get<DateTime>("graded_at"),
        UpdatedAt = r.Get<DateTime>("updated_at"),
        UpdatedBy = r.Get<string?>("updated_by"),
    };
}
