# Entities (data dictionary)

22 entities in 6 subject areas. Full column list with types is in [schema.dbml](schema.dbml),
the picture is in [er-diagram.md](er-diagram.md).

## Organisation

| # | Table | What it stores | Keys and relations |
|---|-------|----------------|--------------------|
| 1 | `faculties` | Faculties of the university | PK `id`; AK `code`, `name`; `dean_id` -> employees (0..1) |
| 2 | `departments` | Departments (кафедри) inside a faculty | PK `id`; AK `code`; -> faculties (N:1); `head_id` -> employees (0..1) |
| 3 | `positions` | Job positions: assistant, docent, professor, methodist... | PK `id`; AK `name` |
| 4 | `employees` | Teaching and administrative staff | PK `id`; AK `email`; -> departments, positions (N:1) |

## Students

| # | Table | What it stores | Keys and relations |
|---|-------|----------------|--------------------|
| 5 | `degree_levels` | Bachelor / Master / PhD with normative study length | PK `id`; AK `code` |
| 6 | `specialties` | Specialties (e.g. 121 Software Engineering) per degree level | PK `id`; AK (`code`, `degree_level_id`); -> departments, degree_levels |
| 7 | `student_groups` | Academic groups (КН-21) | PK `id`; AK `code`; -> specialties; `curator_id` -> employees (0..1) |
| 8 | `students` | Students | PK `id`; AK `record_book_no`, `email`; -> student_groups |

## Teaching

| # | Table | What it stores | Keys and relations |
|---|-------|----------------|--------------------|
| 9 | `courses` | Disciplines from the curriculum | PK `id`; AK `code`; -> departments |
| 10 | `course_prerequisites` | "Course A requires course B" | composite PK (`course_id`, `prerequisite_id`); both -> courses (recursive M:N) |
| 11 | `academic_terms` | Semesters of an academic year | PK `id`; AK (`academic_year`, `semester`) |
| 12 | `course_offerings` | A course taught to a group in a term by a lecturer | PK `id`; AK (`course_id`, `term_id`, `group_id`); -> courses, academic_terms, student_groups, employees |
| 13 | `enrollments` | Student registered for an offering, final result | PK `id`; AK (`student_id`, `offering_id`); students <-> course_offerings M:N |
| 14 | `assessments` | Control points of an offering: modules, labs, exam | PK `id`; -> course_offerings |
| 15 | `grades` | Points a student got for an assessment | PK `id`; AK (`assessment_id`, `student_id`); -> assessments, students, employees (`graded_by`) |

## Campus and schedule

| # | Table | What it stores | Keys and relations |
|---|-------|----------------|--------------------|
| 16 | `buildings` | University buildings | PK `id`; AK `code` |
| 17 | `classrooms` | Rooms with capacity and type | PK `id`; AK (`building_id`, `room_number`); -> buildings |
| 18 | `schedule_slots` | Weekly timetable: offering, room, day, pair, odd/even week | PK `id`; -> course_offerings, classrooms |
| 19 | `attendance` | Was the student at a particular lesson | PK `id`; AK (`slot_id`, `student_id`, `lesson_date`); -> schedule_slots, students |

## Finance

| # | Table | What it stores | Keys and relations |
|---|-------|----------------|--------------------|
| 20 | `tuition_payments` | Contract students' payments per term | PK `id`; AK `reference`; -> students, academic_terms |

## Security and history

| # | Table | What it stores | Keys and relations |
|---|-------|----------------|--------------------|
| 21 | `app_users` | Accounts and roles; source of `created_by` / `updated_by` / `deleted_by` | PK `id`; AK `username`; `employee_id` -> employees (1:1), `student_id` -> students (1:1) |
| 22 | `audit_log` | Row history as old/new `jsonb` | PK `id`; `changed_by` -> app_users |

Audit columns and soft delete are described in [requirements.md](requirements.md) (NFR-01..03).
In the DBML they are declared once as `TablePartial audit_fields` / `soft_delete` and injected into tables.

## Relationship types used

- **1:N** - the majority, e.g. `faculties` -> `departments` -> `employees`.
- **0..1:N (optional)** - `dean_id`, `head_id`, `curator_id`: the position can be vacant.
- **M:N through an associative entity** - `enrollments` (students × offerings), `grades` (students × assessments),
  `attendance` (students × schedule slots).
- **1:1** - `app_users.employee_id` / `student_id` (unique FK).
- **Recursive M:N** - `course_prerequisites` (courses × courses).
- **Circular reference** - `departments.head_id -> employees` while `employees.department_id -> departments`;
  handled by making the head nullable and filling it after the employee exists.

## Normalisation

The schema is in 3NF/BCNF: every non-key attribute depends on the whole key and nothing but the key.
Examples of deliberate decisions:

- Faculty of a student is **not** stored in `students`; it follows from group -> specialty -> department -> faculty
  (storing it would be a transitive dependency and an update anomaly).
- Position titles and degree levels are separate tables, not free text, to avoid modification anomalies.
- `enrollments.final_points` is the only derived value that is stored: it is the officially signed result
  of the exam sheet and must not change when an individual grade is later corrected.
