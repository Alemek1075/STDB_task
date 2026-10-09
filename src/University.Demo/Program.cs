using System.Text;
using University.Data;
using University.Data.Entities;
using University.Data.Infrastructure;
using static University.Demo.ConsoleUi;

// Demo of Repository + Unit of Work over stored procedures and views.
//   dotnet run --project src/University.Demo            run all steps
//   dotnet run --project src/University.Demo -- --pause stop after each step
// Connection: env UNIVERSITY_DB, default Host=localhost;Port=5433;Database=university;Username=postgres

Console.OutputEncoding = Encoding.UTF8;
PauseBetweenSteps = args.Contains("--pause");

await using var factory = new UnitOfWorkFactory(Environment.GetEnvironmentVariable("UNIVERSITY_DB"));
var run = DateTime.Now.ToString("HHmmss");   // keeps record book numbers / codes unique between runs

// ─────────────────────────────────────────────────────────────────────────────
Step("Accounts and groups (reads go through views v_app_users, v_active_groups)");

Dictionary<string, int> users;
await using (var uow = await factory.CreateAsync(actingUserId: 1))
{
    var all = await uow.Audit.GetUsersAsync();
    users = all.ToDictionary(u => u.Username, u => u.Id);
    Table(all, ("id", u => u.Id), ("username", u => u.Username), ("role", u => u.Role), ("person", u => u.PersonName));
    Console.WriteLine();
    Table(await uow.Groups.GetAllAsync(),
        ("id", g => g.Id), ("code", g => g.Code), ("specialty", g => g.Specialty), ("level", g => g.DegreeLevel),
        ("curator", g => g.CuratorName), ("students", g => g.ActiveStudents));
}
int deanOffice = users["marchenko"], teacher = users["kravchenko"];

// ─────────────────────────────────────────────────────────────────────────────
Step("One unit of work: new student + enrolment into all current courses of the group");

Student newStudent;
await using (var uow = await factory.CreateAsync(deanOffice))
{
    var group = (await uow.Groups.GetByCodeAsync("КН-м-26"))!;
    var offerings = await uow.Groups.GetOfferingsAsync(group.Id);

    newStudent = new Student
    {
        GroupId = group.Id,
        RecordBookNo = $"2026-D{run}",
        FirstName = "Олег", LastName = "Демо", MiddleName = "Іванович",
        BirthDate = new DateOnly(2004, 5, 17),
        Email = $"oleh.demo.{run}@stud.uni.edu.ua",
        FundingType = "contract",
    };
    uow.Students.Add(newStudent);
    foreach (var o in offerings)
        uow.Enrollments.Add(new Enrollment { Student = newStudent, OfferingId = o.Id });   // id is not known yet

    Pending(uow.PendingChanges);
    Info($"Student id before save: {newStudent.Id}");
    var n = await uow.SaveChangesAsync();
    Ok($"{n} operations committed in one transaction; student id = {newStudent.Id}");

    newStudent = (await uow.Students.GetByIdAsync(newStudent.Id))!;
    Info($"{newStudent}, updated by '{newStudent.UpdatedBy}' at {newStudent.UpdatedAt.ToLocalTime():HH:mm:ss} (set by trigger)");
    Table(await uow.Enrollments.GetByStudentAsync(newStudent.Id),
        ("course", e => e.CourseCode), ("name", e => e.CourseName), ("lecturer", e => e.LecturerName),
        ("status", e => e.Status), ("updated_by", e => e.UpdatedBy));
}

// ─────────────────────────────────────────────────────────────────────────────
Step("Atomicity: second operation violates a rule → the whole unit of work is rolled back");

await using (var uow = await factory.CreateAsync(deanOffice))
{
    var group = (await uow.Groups.GetByCodeAsync("ІПЗ-25"))!;
    var oop = (await uow.Groups.GetOfferingsAsync(group.Id)).First(o => o.CourseCode == "SE201");

    var freshman = new Student
    {
        GroupId = group.Id, RecordBookNo = $"2025-R{run}", FirstName = "Ростислав", LastName = "Відкатний",
        BirthDate = new DateOnly(2007, 1, 9), Email = $"rollback.{run}@stud.uni.edu.ua", FundingType = "budget",
    };
    uow.Students.Add(freshman);
    uow.Enrollments.Add(new Enrollment { Student = freshman, OfferingId = oop.Id });   // OOP requires "Основи програмування"
    Pending(uow.PendingChanges);

    try
    {
        await uow.SaveChangesAsync();
    }
    catch (DataAccessException ex)
    {
        Fail($"[{ex.SqlState}] {ex.Message}");
    }

    var found = await uow.Students.SearchAsync("Відкатний");
    Ok($"Students named 'Відкатний' in the database: {found.Count} (the successful first operation was rolled back too)");
}

// ─────────────────────────────────────────────────────────────────────────────
Step("Teacher puts and then corrects a grade; history shows who changed what");

Grade grade;
await using (var uow = await factory.CreateAsync(teacher))
{
    var offering = (await uow.Groups.GetOfferingsAsync(newStudent.GroupId)).First(o => o.CourseCode == "CS502");
    var module1 = (await uow.Grades.GetAssessmentsAsync(offering.Id)).First();
    Info($"{offering.CourseName}, lecturer {offering.LecturerName}");

    grade = new Grade { AssessmentId = module1.Id, StudentId = newStudent.Id, Points = 21, GradedBy = offering.LecturerId };
    uow.Grades.Set(grade);
    await uow.SaveChangesAsync();
    Ok($"'{module1.Title}' ({module1.MaxPoints} max): {grade.Points} points, grade id {grade.Id}");

    grade.Points = 27;
    uow.Grades.Set(grade);                 // same student + assessment → procedure updates the row
    await uow.SaveChangesAsync();
    Ok($"Corrected to {grade.Points}");

    grade.Points = 35;                     // above the maximum of 30
    uow.Grades.Set(grade);
    try { await uow.SaveChangesAsync(); }
    catch (DataAccessException ex) { Fail($"[{ex.SqlState}] {ex.Message}"); }

    Table(await uow.Grades.GetByStudentAsync(newStudent.Id),
        ("course", g => g.CourseName), ("assessment", g => g.AssessmentTitle), ("points", g => g.Points),
        ("max", g => g.MaxPoints), ("graded_by", g => g.GradedByName), ("updated_by", g => g.UpdatedBy));
    Console.WriteLine();
    Table(await uow.Audit.GetHistoryAsync("grades", grade.Id),
        ("when", a => a.ChangedAt), ("who", a => a.ChangedBy), ("op", a => a.Operation), ("changes", a => a.Changes));
}

// ─────────────────────────────────────────────────────────────────────────────
Step("Transfer to another group (procedure touches students + enrollments)");

await using (var uow = await factory.CreateAsync(deanOffice))
{
    var from = (await uow.Groups.GetByCodeAsync("КН-25-1"))!;
    var to = (await uow.Groups.GetByCodeAsync("КН-25-2"))!;
    Student? student = null;
    foreach (var s in await uow.Students.GetByGroupAsync(from.Id))
        if ((await uow.Enrollments.GetByStudentAsync(s.Id, currentTermOnly: true)).Any(e => e.Status == "enrolled"))
        {
            student = s;
            break;
        }

    if (student is null)
    {
        Info($"No student of {from.Code} with current enrolments (already transferred by an earlier run).");
    }
    else
    {
        Info($"{student} → {to.Code}");
        uow.Students.Transfer(student, to.Id);
        await uow.SaveChangesAsync();
        Table(await uow.Enrollments.GetByStudentAsync(student.Id, currentTermOnly: true),
            ("course", e => e.CourseCode), ("group", e => e.GroupCode), ("status", e => e.Status), ("updated_by", e => e.UpdatedBy));
    }
}

// ─────────────────────────────────────────────────────────────────────────────
Step("Soft delete and restore");

await using (var uow = await factory.CreateAsync(deanOffice))
{
    uow.Students.Remove(newStudent);
    await uow.SaveChangesAsync();
    Ok($"Removed. GetByIdAsync → {(await uow.Students.GetByIdAsync(newStudent.Id))?.ToString() ?? "null"} (view hides deleted rows)");
    Table((await uow.Students.GetDeletedAsync()).Take(3),
        ("id", d => d.Id), ("name", d => d.FullName), ("group", d => d.GroupCode), ("deleted_at", d => d.DeletedAt), ("deleted_by", d => d.DeletedBy));

    uow.Students.Restore(newStudent.Id);
    await uow.SaveChangesAsync();
    Ok($"Restored. GetByIdAsync → {await uow.Students.GetByIdAsync(newStudent.Id)}");

    Table(await uow.Audit.GetHistoryAsync("students", newStudent.Id),
        ("when", a => a.ChangedAt), ("who", a => a.ChangedBy), ("op", a => a.Operation), ("changes", a => a.Changes));
}

// ─────────────────────────────────────────────────────────────────────────────
Step("New group and its first student in one unit of work; group delete rules");

await using (var uow = await factory.CreateAsync(deanOffice))
{
    var ipz = (await uow.Groups.GetByCodeAsync("ІПЗ-25"))!;
    var group = new StudentGroup { Code = $"ІПЗ-26-{run[^4..]}", SpecialtyId = ipz.SpecialtyId, EnrollmentYear = 2026, CuratorId = 3 };
    var student = new Student
    {
        Group = group,                                   // group id is assigned during the same save
        RecordBookNo = $"2026-G{run}", FirstName = "Ганна", LastName = "Першокурсниця",
        BirthDate = new DateOnly(2009, 3, 3), Email = $"hanna.{run}@stud.uni.edu.ua", FundingType = "budget",
    };
    uow.Groups.Add(group);
    uow.Students.Add(student);
    Pending(uow.PendingChanges);
    await uow.SaveChangesAsync();
    Ok($"Group {group} with student {student.Id}");

    uow.Groups.Remove(group);
    try { await uow.SaveChangesAsync(); }
    catch (DataAccessException ex) { Fail($"[{ex.SqlState}] {ex.Message}"); }

    uow.Students.Remove(student);
    uow.Groups.Remove(group);
    Pending(uow.PendingChanges);
    await uow.SaveChangesAsync();
    Ok($"Student and group soft-deleted together; GetByCodeAsync → {(await uow.Groups.GetByCodeAsync(group.Code))?.ToString() ?? "null"}");
}

// ─────────────────────────────────────────────────────────────────────────────
Step("Transcript and GPA (view v_student_transcript, function fn_student_gpa)");

await using (var uow = await factory.CreateAsync(deanOffice))
{
    var student = (await uow.Students.GetByGroupAsync((await uow.Groups.GetByCodeAsync("ІПЗ-25"))!.Id))[0];
    Info($"{student}, GPA = {await uow.Students.GetGpaAsync(student.Id)}");
    Table(await uow.Students.GetTranscriptAsync(student.Id),
        ("year", t => t.AcademicYear), ("sem", t => t.Semester), ("course", t => t.CourseName), ("ECTS", t => t.EctsCredits),
        ("points", t => t.FinalPoints), ("grade", t => t.EctsGrade), ("national", t => t.NationalGrade));
}

Console.WriteLine();
Ok("Demo finished.");
