using University.Data.Entities;

namespace University.Data.Repositories;

// Reads hit the database immediately (views / table functions).
// Writes (Add / Update / Remove / ...) are queued and executed by IUnitOfWork.SaveChangesAsync
// in one transaction through stored procedures.

public interface IStudentRepository
{
    Task<Student?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<IReadOnlyList<Student>> GetByGroupAsync(int groupId, CancellationToken ct = default);
    Task<IReadOnlyList<Student>> SearchAsync(string namePart, CancellationToken ct = default);
    Task<IReadOnlyList<DeletedStudent>> GetDeletedAsync(CancellationToken ct = default);
    Task<IReadOnlyList<TranscriptLine>> GetTranscriptAsync(int studentId, CancellationToken ct = default);
    Task<decimal?> GetGpaAsync(int studentId, CancellationToken ct = default);

    void Add(Student student);
    void Update(Student student);
    void Remove(Student student);                 // soft delete
    void Restore(int studentId);
    void Transfer(Student student, int newGroupId);
}

public interface IStudentGroupRepository
{
    Task<IReadOnlyList<StudentGroup>> GetAllAsync(CancellationToken ct = default);
    Task<StudentGroup?> GetByIdAsync(int id, CancellationToken ct = default);
    Task<StudentGroup?> GetByCodeAsync(string code, CancellationToken ct = default);
    Task<IReadOnlyList<CourseOffering>> GetOfferingsAsync(int groupId, bool currentTermOnly = true, CancellationToken ct = default);

    void Add(StudentGroup group);
    void Update(StudentGroup group);
    void Remove(StudentGroup group);              // soft delete, refused while the group has students
}

public interface IEnrollmentRepository
{
    Task<IReadOnlyList<Enrollment>> GetByStudentAsync(int studentId, bool currentTermOnly = false, CancellationToken ct = default);
    Task<IReadOnlyList<Enrollment>> GetByOfferingAsync(int offeringId, CancellationToken ct = default);

    void Add(Enrollment enrollment);
    void Withdraw(Enrollment enrollment);
    void FinalizeOffering(int offeringId);
}

public interface IGradeRepository
{
    Task<IReadOnlyList<Grade>> GetByStudentAsync(int studentId, CancellationToken ct = default);
    Task<IReadOnlyList<Grade>> GetByOfferingAsync(int offeringId, CancellationToken ct = default);
    Task<IReadOnlyList<Assessment>> GetAssessmentsAsync(int offeringId, CancellationToken ct = default);

    void Set(Grade grade);                        // insert or correct
    void Remove(Grade grade);
}

public interface IAuditRepository
{
    Task<IReadOnlyList<AuditEntry>> GetHistoryAsync(string table, long recordId, CancellationToken ct = default);
    Task<IReadOnlyList<AppUser>> GetUsersAsync(CancellationToken ct = default);
}
