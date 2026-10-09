-- =====================================================================
-- University Management System — physical model (PostgreSQL 18)
-- Naming: snake_case; pk_<table>, fk_<table>_<column>, uq_<table>_<cols>, ck_<table>_<rule>
-- =====================================================================

-- ─────────────────────────── Security ───────────────────────────
-- app_users goes first: every audited table references it.

CREATE TABLE app_users (
    id           int          GENERATED ALWAYS AS IDENTITY,
    username     varchar(50)  NOT NULL,
    role         varchar(15)  NOT NULL,
    employee_id  int,
    student_id   int,
    is_active    boolean      NOT NULL DEFAULT true,
    created_at   timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_app_users PRIMARY KEY (id),
    CONSTRAINT uq_app_users_username UNIQUE (username),
    CONSTRAINT uq_app_users_employee UNIQUE (employee_id),
    CONSTRAINT uq_app_users_student UNIQUE (student_id),
    CONSTRAINT ck_app_users_role CHECK (role IN ('admin', 'dean_office', 'teacher', 'student')),
    CONSTRAINT ck_app_users_one_person CHECK (employee_id IS NULL OR student_id IS NULL)
);

-- ─────────────────────────── Organisation ───────────────────────────

CREATE TABLE faculties (
    id          int           GENERATED ALWAYS AS IDENTITY,
    code        varchar(10)   NOT NULL,
    name        varchar(200)  NOT NULL,
    dean_id     int,
    created_at  timestamptz   NOT NULL DEFAULT now(),
    created_by  int           REFERENCES app_users (id),
    updated_at  timestamptz   NOT NULL DEFAULT now(),
    updated_by  int           REFERENCES app_users (id),
    deleted_at  timestamptz,
    deleted_by  int           REFERENCES app_users (id),
    CONSTRAINT pk_faculties PRIMARY KEY (id),
    CONSTRAINT uq_faculties_code UNIQUE (code),
    CONSTRAINT uq_faculties_name UNIQUE (name)
);

CREATE TABLE departments (
    id          int           GENERATED ALWAYS AS IDENTITY,
    faculty_id  int           NOT NULL,
    code        varchar(10)   NOT NULL,
    name        varchar(200)  NOT NULL,
    head_id     int,
    phone       varchar(20),
    created_at  timestamptz   NOT NULL DEFAULT now(),
    created_by  int           REFERENCES app_users (id),
    updated_at  timestamptz   NOT NULL DEFAULT now(),
    updated_by  int           REFERENCES app_users (id),
    deleted_at  timestamptz,
    deleted_by  int           REFERENCES app_users (id),
    CONSTRAINT pk_departments PRIMARY KEY (id),
    CONSTRAINT uq_departments_code UNIQUE (code),
    CONSTRAINT fk_departments_faculty FOREIGN KEY (faculty_id) REFERENCES faculties (id)
);

CREATE TABLE positions (
    id           smallint      GENERATED ALWAYS AS IDENTITY,
    name         varchar(100)  NOT NULL,
    is_academic  boolean       NOT NULL DEFAULT true,
    CONSTRAINT pk_positions PRIMARY KEY (id),
    CONSTRAINT uq_positions_name UNIQUE (name)
);

CREATE TABLE employees (
    id               int            GENERATED ALWAYS AS IDENTITY,
    department_id    int            NOT NULL,
    position_id      smallint       NOT NULL,
    first_name       varchar(50)    NOT NULL,
    last_name        varchar(50)    NOT NULL,
    middle_name      varchar(50),
    email            varchar(100)   NOT NULL,
    phone            varchar(20),
    academic_degree  varchar(30),
    hire_date        date           NOT NULL,
    salary           numeric(10,2)  NOT NULL,
    created_at       timestamptz    NOT NULL DEFAULT now(),
    created_by       int            REFERENCES app_users (id),
    updated_at       timestamptz    NOT NULL DEFAULT now(),
    updated_by       int            REFERENCES app_users (id),
    deleted_at       timestamptz,
    deleted_by       int            REFERENCES app_users (id),
    CONSTRAINT pk_employees PRIMARY KEY (id),
    CONSTRAINT uq_employees_email UNIQUE (email),
    CONSTRAINT fk_employees_department FOREIGN KEY (department_id) REFERENCES departments (id),
    CONSTRAINT fk_employees_position FOREIGN KEY (position_id) REFERENCES positions (id),
    CONSTRAINT ck_employees_salary CHECK (salary > 0),
    CONSTRAINT ck_employees_email CHECK (email LIKE '%_@_%')
);

-- circular references: faculty dean / department head are employees
ALTER TABLE faculties
    ADD CONSTRAINT fk_faculties_dean FOREIGN KEY (dean_id) REFERENCES employees (id);
ALTER TABLE departments
    ADD CONSTRAINT fk_departments_head FOREIGN KEY (head_id) REFERENCES employees (id);

-- ─────────────────────────── Students ───────────────────────────

CREATE TABLE degree_levels (
    id              smallint      GENERATED ALWAYS AS IDENTITY,
    code            varchar(10)   NOT NULL,
    name            varchar(50)   NOT NULL,
    duration_years  numeric(2,1)  NOT NULL,
    CONSTRAINT pk_degree_levels PRIMARY KEY (id),
    CONSTRAINT uq_degree_levels_code UNIQUE (code),
    CONSTRAINT ck_degree_levels_duration CHECK (duration_years > 0)
);

CREATE TABLE specialties (
    id               int           GENERATED ALWAYS AS IDENTITY,
    department_id    int           NOT NULL,
    degree_level_id  smallint      NOT NULL,
    code             varchar(10)   NOT NULL,
    name             varchar(200)  NOT NULL,
    CONSTRAINT pk_specialties PRIMARY KEY (id),
    CONSTRAINT uq_specialties_code_level UNIQUE (code, degree_level_id),
    CONSTRAINT fk_specialties_department FOREIGN KEY (department_id) REFERENCES departments (id),
    CONSTRAINT fk_specialties_degree_level FOREIGN KEY (degree_level_id) REFERENCES degree_levels (id)
);

CREATE TABLE student_groups (
    id               int           GENERATED ALWAYS AS IDENTITY,
    specialty_id     int           NOT NULL,
    code             varchar(20)   NOT NULL,
    enrollment_year  smallint      NOT NULL,
    curator_id       int,
    created_at       timestamptz   NOT NULL DEFAULT now(),
    created_by       int           REFERENCES app_users (id),
    updated_at       timestamptz   NOT NULL DEFAULT now(),
    updated_by       int           REFERENCES app_users (id),
    deleted_at       timestamptz,
    deleted_by       int           REFERENCES app_users (id),
    CONSTRAINT pk_student_groups PRIMARY KEY (id),
    CONSTRAINT uq_student_groups_code UNIQUE (code),
    CONSTRAINT fk_student_groups_specialty FOREIGN KEY (specialty_id) REFERENCES specialties (id),
    CONSTRAINT fk_student_groups_curator FOREIGN KEY (curator_id) REFERENCES employees (id),
    CONSTRAINT ck_student_groups_year CHECK (enrollment_year BETWEEN 1990 AND 2100)
);

CREATE TABLE students (
    id               int           GENERATED ALWAYS AS IDENTITY,
    group_id         int           NOT NULL,
    record_book_no   varchar(20)   NOT NULL,
    first_name       varchar(50)   NOT NULL,
    last_name        varchar(50)   NOT NULL,
    middle_name      varchar(50),
    birth_date       date          NOT NULL,
    email            varchar(100)  NOT NULL,
    enrollment_date  date          NOT NULL,
    funding_type     varchar(10)   NOT NULL,
    status           varchar(20)   NOT NULL DEFAULT 'active',
    created_at       timestamptz   NOT NULL DEFAULT now(),
    created_by       int           REFERENCES app_users (id),
    updated_at       timestamptz   NOT NULL DEFAULT now(),
    updated_by       int           REFERENCES app_users (id),
    deleted_at       timestamptz,
    deleted_by       int           REFERENCES app_users (id),
    CONSTRAINT pk_students PRIMARY KEY (id),
    CONSTRAINT uq_students_record_book UNIQUE (record_book_no),
    CONSTRAINT uq_students_email UNIQUE (email),
    CONSTRAINT fk_students_group FOREIGN KEY (group_id) REFERENCES student_groups (id),
    CONSTRAINT ck_students_funding CHECK (funding_type IN ('budget', 'contract')),
    CONSTRAINT ck_students_status CHECK (status IN ('active', 'academic_leave', 'expelled', 'graduated')),
    CONSTRAINT ck_students_email CHECK (email LIKE '%_@_%'),
    CONSTRAINT ck_students_age CHECK (birth_date < enrollment_date - interval '14 years')
);

ALTER TABLE app_users
    ADD CONSTRAINT fk_app_users_employee FOREIGN KEY (employee_id) REFERENCES employees (id),
    ADD CONSTRAINT fk_app_users_student FOREIGN KEY (student_id) REFERENCES students (id);

-- ─────────────────────────── Teaching ───────────────────────────

CREATE TABLE courses (
    id             int           GENERATED ALWAYS AS IDENTITY,
    department_id  int           NOT NULL,
    code           varchar(20)   NOT NULL,
    name           varchar(200)  NOT NULL,
    description    text,
    ects_credits   numeric(4,1)  NOT NULL,
    hours_total    smallint      NOT NULL,
    created_at     timestamptz   NOT NULL DEFAULT now(),
    created_by     int           REFERENCES app_users (id),
    updated_at     timestamptz   NOT NULL DEFAULT now(),
    updated_by     int           REFERENCES app_users (id),
    deleted_at     timestamptz,
    deleted_by     int           REFERENCES app_users (id),
    CONSTRAINT pk_courses PRIMARY KEY (id),
    CONSTRAINT uq_courses_code UNIQUE (code),
    CONSTRAINT fk_courses_department FOREIGN KEY (department_id) REFERENCES departments (id),
    CONSTRAINT ck_courses_ects CHECK (ects_credits > 0 AND ects_credits <= 30),
    CONSTRAINT ck_courses_hours CHECK (hours_total > 0)
);

CREATE TABLE course_prerequisites (
    course_id        int  NOT NULL,
    prerequisite_id  int  NOT NULL,
    CONSTRAINT pk_course_prerequisites PRIMARY KEY (course_id, prerequisite_id),
    CONSTRAINT fk_course_prerequisites_course FOREIGN KEY (course_id) REFERENCES courses (id),
    CONSTRAINT fk_course_prerequisites_prereq FOREIGN KEY (prerequisite_id) REFERENCES courses (id),
    CONSTRAINT ck_course_prerequisites_self CHECK (course_id <> prerequisite_id)
);

CREATE TABLE academic_terms (
    id             int          GENERATED ALWAYS AS IDENTITY,
    academic_year  varchar(9)   NOT NULL,
    semester       smallint     NOT NULL,
    start_date     date         NOT NULL,
    end_date       date         NOT NULL,
    CONSTRAINT pk_academic_terms PRIMARY KEY (id),
    CONSTRAINT uq_academic_terms_year_sem UNIQUE (academic_year, semester),
    CONSTRAINT ck_academic_terms_year CHECK (academic_year ~ '^\d{4}/\d{4}$'),
    CONSTRAINT ck_academic_terms_semester CHECK (semester IN (1, 2)),
    CONSTRAINT ck_academic_terms_dates CHECK (end_date > start_date)
);

CREATE TABLE course_offerings (
    id           int          GENERATED ALWAYS AS IDENTITY,
    course_id    int          NOT NULL,
    term_id      int          NOT NULL,
    group_id     int          NOT NULL,
    lecturer_id  int          NOT NULL,
    created_at   timestamptz  NOT NULL DEFAULT now(),
    created_by   int          REFERENCES app_users (id),
    updated_at   timestamptz  NOT NULL DEFAULT now(),
    updated_by   int          REFERENCES app_users (id),
    CONSTRAINT pk_course_offerings PRIMARY KEY (id),
    CONSTRAINT uq_course_offerings UNIQUE (course_id, term_id, group_id),
    CONSTRAINT fk_course_offerings_course FOREIGN KEY (course_id) REFERENCES courses (id),
    CONSTRAINT fk_course_offerings_term FOREIGN KEY (term_id) REFERENCES academic_terms (id),
    CONSTRAINT fk_course_offerings_group FOREIGN KEY (group_id) REFERENCES student_groups (id),
    CONSTRAINT fk_course_offerings_lecturer FOREIGN KEY (lecturer_id) REFERENCES employees (id)
);

CREATE TABLE enrollments (
    id            int           GENERATED ALWAYS AS IDENTITY,
    student_id    int           NOT NULL,
    offering_id   int           NOT NULL,
    enrolled_at   timestamptz   NOT NULL DEFAULT now(),
    status        varchar(15)   NOT NULL DEFAULT 'enrolled',
    final_points  numeric(5,2),
    created_at    timestamptz   NOT NULL DEFAULT now(),
    created_by    int           REFERENCES app_users (id),
    updated_at    timestamptz   NOT NULL DEFAULT now(),
    updated_by    int           REFERENCES app_users (id),
    CONSTRAINT pk_enrollments PRIMARY KEY (id),
    CONSTRAINT uq_enrollments UNIQUE (student_id, offering_id),
    CONSTRAINT fk_enrollments_student FOREIGN KEY (student_id) REFERENCES students (id),
    CONSTRAINT fk_enrollments_offering FOREIGN KEY (offering_id) REFERENCES course_offerings (id) ON DELETE CASCADE,
    CONSTRAINT ck_enrollments_status CHECK (status IN ('enrolled', 'completed', 'failed', 'withdrawn')),
    CONSTRAINT ck_enrollments_points CHECK (final_points BETWEEN 0 AND 100)
);

CREATE TABLE assessments (
    id               int           GENERATED ALWAYS AS IDENTITY,
    offering_id      int           NOT NULL,
    title            varchar(100)  NOT NULL,
    assessment_type  varchar(15)   NOT NULL,
    max_points       numeric(5,2)  NOT NULL,
    due_date         date,
    created_at       timestamptz   NOT NULL DEFAULT now(),
    created_by       int           REFERENCES app_users (id),
    updated_at       timestamptz   NOT NULL DEFAULT now(),
    updated_by       int           REFERENCES app_users (id),
    CONSTRAINT pk_assessments PRIMARY KEY (id),
    CONSTRAINT fk_assessments_offering FOREIGN KEY (offering_id) REFERENCES course_offerings (id) ON DELETE CASCADE,
    CONSTRAINT ck_assessments_type CHECK (assessment_type IN ('module', 'exam', 'lab', 'test', 'coursework')),
    CONSTRAINT ck_assessments_max_points CHECK (max_points > 0 AND max_points <= 100)
);

CREATE TABLE grades (
    id             int           GENERATED ALWAYS AS IDENTITY,
    assessment_id  int           NOT NULL,
    student_id     int           NOT NULL,
    points         numeric(5,2)  NOT NULL,
    graded_by      int           NOT NULL,
    graded_at      timestamptz   NOT NULL DEFAULT now(),
    created_at     timestamptz   NOT NULL DEFAULT now(),
    created_by     int           REFERENCES app_users (id),
    updated_at     timestamptz   NOT NULL DEFAULT now(),
    updated_by     int           REFERENCES app_users (id),
    CONSTRAINT pk_grades PRIMARY KEY (id),
    CONSTRAINT uq_grades UNIQUE (assessment_id, student_id),
    CONSTRAINT fk_grades_assessment FOREIGN KEY (assessment_id) REFERENCES assessments (id) ON DELETE CASCADE,
    CONSTRAINT fk_grades_student FOREIGN KEY (student_id) REFERENCES students (id),
    CONSTRAINT fk_grades_graded_by FOREIGN KEY (graded_by) REFERENCES employees (id),
    CONSTRAINT ck_grades_points CHECK (points >= 0)
);

-- ─────────────────────────── Campus & schedule ───────────────────────────

CREATE TABLE buildings (
    id       smallint      GENERATED ALWAYS AS IDENTITY,
    code     varchar(10)   NOT NULL,
    name     varchar(100)  NOT NULL,
    address  varchar(200)  NOT NULL,
    CONSTRAINT pk_buildings PRIMARY KEY (id),
    CONSTRAINT uq_buildings_code UNIQUE (code)
);

CREATE TABLE classrooms (
    id           int          GENERATED ALWAYS AS IDENTITY,
    building_id  smallint     NOT NULL,
    room_number  varchar(10)  NOT NULL,
    capacity     smallint     NOT NULL,
    room_type    varchar(15)  NOT NULL,
    CONSTRAINT pk_classrooms PRIMARY KEY (id),
    CONSTRAINT uq_classrooms_room UNIQUE (building_id, room_number),
    CONSTRAINT fk_classrooms_building FOREIGN KEY (building_id) REFERENCES buildings (id),
    CONSTRAINT ck_classrooms_capacity CHECK (capacity > 0),
    CONSTRAINT ck_classrooms_type CHECK (room_type IN ('lecture', 'seminar', 'lab', 'computer'))
);

CREATE TABLE schedule_slots (
    id            int          GENERATED ALWAYS AS IDENTITY,
    offering_id   int          NOT NULL,
    classroom_id  int          NOT NULL,
    day_of_week   smallint     NOT NULL,
    pair_number   smallint     NOT NULL,
    lesson_type   varchar(10)  NOT NULL,
    week_parity   varchar(4)   NOT NULL DEFAULT 'all',
    CONSTRAINT pk_schedule_slots PRIMARY KEY (id),
    CONSTRAINT fk_schedule_slots_offering FOREIGN KEY (offering_id) REFERENCES course_offerings (id) ON DELETE CASCADE,
    CONSTRAINT fk_schedule_slots_classroom FOREIGN KEY (classroom_id) REFERENCES classrooms (id),
    CONSTRAINT ck_schedule_slots_day CHECK (day_of_week BETWEEN 1 AND 6),
    CONSTRAINT ck_schedule_slots_pair CHECK (pair_number BETWEEN 1 AND 8),
    CONSTRAINT ck_schedule_slots_type CHECK (lesson_type IN ('lecture', 'practice', 'lab')),
    CONSTRAINT ck_schedule_slots_parity CHECK (week_parity IN ('all', 'odd', 'even'))
);

CREATE TABLE attendance (
    id           bigint       GENERATED ALWAYS AS IDENTITY,
    slot_id      int          NOT NULL,
    student_id   int          NOT NULL,
    lesson_date  date         NOT NULL,
    status       varchar(10)  NOT NULL,
    CONSTRAINT pk_attendance PRIMARY KEY (id),
    CONSTRAINT uq_attendance UNIQUE (slot_id, student_id, lesson_date),
    CONSTRAINT fk_attendance_slot FOREIGN KEY (slot_id) REFERENCES schedule_slots (id) ON DELETE CASCADE,
    CONSTRAINT fk_attendance_student FOREIGN KEY (student_id) REFERENCES students (id),
    CONSTRAINT ck_attendance_status CHECK (status IN ('present', 'absent', 'late', 'excused'))
);

-- ─────────────────────────── Finance ───────────────────────────

CREATE TABLE tuition_payments (
    id              int            GENERATED ALWAYS AS IDENTITY,
    student_id      int            NOT NULL,
    term_id         int            NOT NULL,
    amount          numeric(10,2)  NOT NULL,
    paid_at         timestamptz    NOT NULL DEFAULT now(),
    payment_method  varchar(10)    NOT NULL,
    reference       varchar(50),
    created_at      timestamptz    NOT NULL DEFAULT now(),
    created_by      int            REFERENCES app_users (id),
    updated_at      timestamptz    NOT NULL DEFAULT now(),
    updated_by      int            REFERENCES app_users (id),
    CONSTRAINT pk_tuition_payments PRIMARY KEY (id),
    CONSTRAINT uq_tuition_payments_reference UNIQUE (reference),
    CONSTRAINT fk_tuition_payments_student FOREIGN KEY (student_id) REFERENCES students (id),
    CONSTRAINT fk_tuition_payments_term FOREIGN KEY (term_id) REFERENCES academic_terms (id),
    CONSTRAINT ck_tuition_payments_amount CHECK (amount > 0),
    CONSTRAINT ck_tuition_payments_method CHECK (payment_method IN ('card', 'bank', 'cash'))
);

-- ─────────────────────────── History ───────────────────────────

CREATE TABLE audit_log (
    id          bigint       GENERATED ALWAYS AS IDENTITY,
    table_name  varchar(63)  NOT NULL,
    record_id   bigint       NOT NULL,
    operation   varchar(11)  NOT NULL,
    old_data    jsonb,
    new_data    jsonb,
    changed_by  int,
    changed_at  timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_audit_log PRIMARY KEY (id),
    CONSTRAINT fk_audit_log_user FOREIGN KEY (changed_by) REFERENCES app_users (id),
    CONSTRAINT ck_audit_log_operation CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE', 'SOFT_DELETE', 'RESTORE'))
);

-- ─────────────────────────── Comments (shown in DataGrip / \d+) ───────────────────────────

COMMENT ON TABLE students IS 'Students. Soft delete: deleted_at IS NOT NULL means deleted.';
COMMENT ON COLUMN students.record_book_no IS 'Record book (залікова книжка) number — natural alternate key';
COMMENT ON COLUMN students.updated_by IS 'Last user who changed the row; set by trigger from app.user_id';
COMMENT ON TABLE enrollments IS 'Student registration for a course offering and the final result';
COMMENT ON COLUMN enrollments.final_points IS 'Signed result on 100-point scale (ECTS letter is computed)';
COMMENT ON TABLE audit_log IS 'Row-level change history written by triggers';
COMMENT ON TABLE schedule_slots IS 'Weekly timetable; week_parity = all | odd | even';
