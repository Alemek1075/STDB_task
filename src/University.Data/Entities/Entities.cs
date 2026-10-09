namespace University.Data.Entities;

/// <summary>Student (source: v_active_students).</summary>
public sealed class Student
{
    private int _groupId;

    public int Id { get; internal set; }

    /// <summary>Group id; if <see cref="Group"/> is set (a group created in the same unit of work), its id wins.</summary>
    public int GroupId
    {
        get => Group?.Id ?? _groupId;
        set => _groupId = value;
    }

    /// <summary>Reference to a group that may not have an id yet (pending insert).</summary>
    public StudentGroup? Group { get; set; }

    public string GroupCode { get; internal set; } = "";
    public string RecordBookNo { get; set; } = "";
    public string FirstName { get; set; } = "";
    public string LastName { get; set; } = "";
    public string? MiddleName { get; set; }
    public string FullName { get; internal set; } = "";
    public DateOnly BirthDate { get; set; }
    public string Email { get; set; } = "";
    public DateOnly? EnrollmentDate { get; set; }
    public string FundingType { get; set; } = "budget";
    public string Status { get; set; } = "active";
    public string? Specialty { get; internal set; }
    public DateTime UpdatedAt { get; internal set; }
    public string? UpdatedBy { get; internal set; }

    public override string ToString() => $"#{Id} {FullName} ({GroupCode}, {RecordBookNo})";
}

/// <summary>Academic group (source: v_active_groups).</summary>
public sealed class StudentGroup
{
    public int Id { get; internal set; }
    public string Code { get; set; } = "";
    public int SpecialtyId { get; set; }
    public string? Specialty { get; internal set; }
    public string? DegreeLevel { get; internal set; }
    public short EnrollmentYear { get; set; }
    public int? CuratorId { get; set; }
    public string? CuratorName { get; internal set; }
    public long ActiveStudents { get; internal set; }
    public DateTime UpdatedAt { get; internal set; }
    public string? UpdatedBy { get; internal set; }

    public override string ToString() => $"#{Id} {Code}";
}

/// <summary>Student registration for a course offering (source: v_enrollment_details).</summary>
public sealed class Enrollment
{
    private int _studentId;

    public int Id { get; internal set; }

    public int StudentId
    {
        get => Student?.Id ?? _studentId;
        set => _studentId = value;
    }

    /// <summary>Reference to a student that may not have an id yet (pending insert).</summary>
    public Student? Student { get; set; }

    public string StudentName { get; internal set; } = "";
    public int OfferingId { get; set; }
    public string CourseCode { get; internal set; } = "";
    public string CourseName { get; internal set; } = "";
    public int TermId { get; internal set; }
    public string Term { get; internal set; } = "";
    public string GroupCode { get; internal set; } = "";
    public string LecturerName { get; internal set; } = "";
    public string Status { get; internal set; } = "enrolled";
    public decimal CurrentPoints { get; internal set; }
    public decimal? FinalPoints { get; internal set; }
    public string? EctsGrade { get; internal set; }
    public string? UpdatedBy { get; internal set; }
}

/// <summary>Points for one assessment (source: v_grade_details).</summary>
public sealed class Grade
{
    private int _studentId;

    public int Id { get; internal set; }
    public int AssessmentId { get; set; }
    public string AssessmentTitle { get; internal set; } = "";
    public decimal MaxPoints { get; internal set; }
    public int OfferingId { get; internal set; }
    public string CourseName { get; internal set; } = "";

    public int StudentId
    {
        get => Student?.Id ?? _studentId;
        set => _studentId = value;
    }

    public Student? Student { get; set; }
    public string StudentName { get; internal set; } = "";
    public decimal Points { get; set; }
    public int GradedBy { get; set; }
    public string GradedByName { get; internal set; } = "";
    public DateTime GradedAt { get; internal set; }
    public DateTime UpdatedAt { get; internal set; }
    public string? UpdatedBy { get; internal set; }
}

/// <summary>Course taught to a group in a term (source: v_course_offerings).</summary>
public sealed record CourseOffering(
    int Id, string CourseCode, string CourseName, decimal EctsCredits, int TermId, string Term,
    bool IsCurrent, int GroupId, string GroupCode, int LecturerId, string LecturerName);

/// <summary>Control point of an offering (source: v_offering_assessments).</summary>
public sealed record Assessment(int Id, int OfferingId, string Title, string Type, decimal MaxPoints, DateOnly? DueDate);

/// <summary>Line of the academic record (source: v_student_transcript).</summary>
public sealed record TranscriptLine(
    string AcademicYear, short Semester, string CourseCode, string CourseName, decimal EctsCredits,
    string Status, decimal? FinalPoints, string? EctsGrade, string? NationalGrade);

/// <summary>History record (source: v_audit_trail).</summary>
public sealed record AuditEntry(DateTime ChangedAt, string ChangedBy, string Table, long RecordId, string Operation, string? Changes);

/// <summary>Soft-deleted student (source: v_deleted_students).</summary>
public sealed record DeletedStudent(int Id, string RecordBookNo, string FullName, string GroupCode, DateTime DeletedAt, string? DeletedBy);

/// <summary>Application account (source: v_app_users).</summary>
public sealed record AppUser(int Id, string Username, string Role, string? PersonName);
