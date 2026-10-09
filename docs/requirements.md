# Requirements

The model is built top-down from the subject area: first the requirements below, then the entities that
cover them. Each requirement lists the tables it maps to.

## Users and roles

| Role | Who | Typical actions |
|------|-----|-----------------|
| `admin` | IT staff | Reference data, users, restoring deleted records |
| `dean_office` | Dean's office methodists | Students, groups, transfers, terms, schedule, payments |
| `teacher` | Lecturers | Assessments, grades, attendance for their own offerings |
| `student` | Students | Read-only: own grades, transcript, schedule |

Stored in `app_users`. An account is linked to an employee or a student (never both).

## Functional requirements

| ID | Requirement | Entities |
|----|-------------|----------|
| FR-01 | Keep the university structure: faculties, departments, their deans and heads | faculties, departments, employees |
| FR-02 | Keep staff records with position, department and salary | employees, positions |
| FR-03 | Keep specialties by degree level (bachelor, master, PhD) | specialties, degree_levels |
| FR-04 | Manage academic groups with a curator; enrol students into groups and transfer between groups | student_groups, students |
| FR-05 | Track student status: active, academic leave, expelled, graduated | students |
| FR-06 | Keep the curriculum: courses with ECTS credits, hours and prerequisites | courses, course_prerequisites |
| FR-07 | Plan which course is taught to which group in which term and by whom | academic_terms, course_offerings |
| FR-08 | Register students for offerings; do not allow it if prerequisites are not passed | enrollments, course_prerequisites |
| FR-09 | Define control points (modules, labs, exam) with max points; the sum of max points of an offering must not exceed 100 | assessments |
| FR-10 | Put grades; points cannot exceed the assessment's maximum; record who graded | grades |
| FR-11 | Compute the final result of a course (100-point scale + ECTS letter A–F) and the student's GPA | enrollments, grades |
| FR-12 | Keep a weekly timetable without room conflicts (same room, day, pair and week parity) | schedule_slots, classrooms, buildings |
| FR-13 | Mark attendance and compute attendance rate | attendance |
| FR-14 | Record tuition payments of contract students and show debts | tuition_payments |
| FR-15 | Reports: group performance, teacher workload, faculty statistics, transcript | views over the above |

## Non-functional requirements

### NFR-01 Soft delete

People and structural units are never physically removed, because grades, payments and history refer to them
and the university is legally required to keep these records.

Soft-deletable tables: `faculties`, `departments`, `employees`, `student_groups`, `students`, `courses`.

- Columns `deleted_at timestamptz NULL` and `deleted_by int -> app_users`. `NULL` means the row is active.
- A plain `DELETE` on these tables is intercepted by a trigger and turned into setting `deleted_at`,
  so even a careless query cannot destroy data.
- Application code reads through views that hide deleted rows (`v_active_*`).
- A deleted row can be restored by a procedure (admin only).
- Unique constraints (e-mail, record book number) apply to active rows only (partial unique indexes),
  so a new student can reuse the e-mail of a deleted one.

### NFR-02 Last change: when and who

Tables with `created_at`, `created_by`, `updated_at`, `updated_by`:
`faculties`, `departments`, `employees`, `student_groups`, `students`, `courses`,
`course_offerings`, `enrollments`, `assessments`, `grades`, `tuition_payments`.

- The values are set by a `BEFORE INSERT OR UPDATE` trigger, not by the client, so they cannot be forged.
- The current user is taken from the transaction-level setting `app.user_id`. The application's
  Unit of Work runs `SELECT set_config('app.user_id', '<id>', true)` at the start of each transaction.

### NFR-03 Change history

Every insert/update/delete/soft delete on `students`, `employees`, `enrollments` and `grades` is written to
`audit_log` with the old and new row as `jsonb`, the user and the time. This answers "who changed this grade
from 60 to 90 and when".

### NFR-04 Integrity

- All relations are foreign keys; enumerations are `CHECK` constraints.
- Business rules that span several rows (FR-08, FR-09, FR-10, FR-12) are enforced by triggers in the database,
  so they hold no matter which client writes the data.

### NFR-05 Data access from code

The application does not write SQL against tables. Reads go through views and table functions, writes through
stored procedures. Several related changes are committed together through the Unit of Work.

### NFR-06 Performance

Indexes on foreign keys and on the most frequent filters (active students of a group, grades of a student,
full-text search of courses, audit log by time).
