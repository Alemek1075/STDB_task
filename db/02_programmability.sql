-- =====================================================================
-- Programmability: functions, triggers, views, procedures
-- Focus: soft delete, last-change audit fields and change history (stage 3 requirements),
-- plus business rules and the API that the C# repositories use.
--
--  Functions (10)  fn_current_user_id, fn_current_term_id, fn_ects_grade, fn_national_grade,
--                  fn_tuition_fee, fn_student_points, fn_student_gpa, fn_attendance_rate,
--                  fn_prerequisites_met, fn_group_students
--  Triggers (8)    audit fields, soft delete, audit log, grade check, assessment total,
--                  prerequisites, schedule conflicts, prerequisite cycles
--  Views (13)      v_active_students, v_deleted_students, v_active_groups, v_active_employees,
--                  v_enrollment_details, v_grade_details, v_student_transcript, v_group_performance,
--                  v_teacher_workload, v_timetable, v_payment_debts, v_audit_trail,
--                  mv_faculty_statistics (materialized)
--  Procedures (14) students: create/update/soft delete/restore/transfer;
--                  groups: create/update/soft delete; enrollments: create/withdraw;
--                  grades: set/delete; sp_finalize_offering; sp_refresh_statistics
-- =====================================================================


-- ═════════════════════════════ FUNCTIONS ═════════════════════════════

-- Who is working now. The application sets it per transaction:
--   SELECT set_config('app.user_id', '5', true);
CREATE FUNCTION fn_current_user_id() RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT nullif(current_setting('app.user_id', true), '')::int;
$$;

-- Term that contains today; if we are between terms, the latest started one.
CREATE FUNCTION fn_current_term_id() RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT id FROM academic_terms
    WHERE start_date <= current_date
    ORDER BY (current_date <= end_date) DESC, start_date DESC
    LIMIT 1;
$$;

-- 100-point scale -> ECTS letter (Ukrainian grading scale)
CREATE FUNCTION fn_ects_grade(p_points numeric) RETURNS varchar(2)
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE
        WHEN p_points IS NULL THEN NULL
        WHEN p_points >= 90 THEN 'A'
        WHEN p_points >= 82 THEN 'B'
        WHEN p_points >= 74 THEN 'C'
        WHEN p_points >= 64 THEN 'D'
        WHEN p_points >= 60 THEN 'E'
        WHEN p_points >= 35 THEN 'FX'
        ELSE 'F'
    END;
$$;

-- 100-point scale -> national 4-point scale
CREATE FUNCTION fn_national_grade(p_points numeric) RETURNS varchar(20)
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE
        WHEN p_points IS NULL THEN NULL
        WHEN p_points >= 90 THEN 'відмінно'
        WHEN p_points >= 74 THEN 'добре'
        WHEN p_points >= 60 THEN 'задовільно'
        ELSE 'незадовільно'
    END;
$$;

-- Contract price of one term
CREATE FUNCTION fn_tuition_fee(p_term_id int) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
    SELECT 18000::numeric;
$$;

-- Points a student has collected in an offering so far
CREATE FUNCTION fn_student_points(p_student_id int, p_offering_id int) RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(g.points), 0)
    FROM grades g
    JOIN assessments a ON a.id = g.assessment_id
    WHERE g.student_id = p_student_id AND a.offering_id = p_offering_id;
$$;

-- Credit-weighted average of final results (100-point scale)
-- search_path is fixed because REFRESH MATERIALIZED VIEW runs with a restricted search_path (PG 17+)
CREATE FUNCTION fn_student_gpa(p_student_id int) RETURNS numeric
LANGUAGE sql STABLE SET search_path = public AS $$
    SELECT round(sum(e.final_points * c.ects_credits) / nullif(sum(c.ects_credits), 0), 2)
    FROM enrollments e
    JOIN course_offerings o ON o.id = e.offering_id
    JOIN courses c ON c.id = o.course_id
    WHERE e.student_id = p_student_id
      AND e.status IN ('completed', 'failed');
$$;

-- Attendance in percent (present + late count as attended); NULL offering = all offerings
CREATE FUNCTION fn_attendance_rate(p_student_id int, p_offering_id int DEFAULT NULL) RETURNS numeric
LANGUAGE sql STABLE AS $$
    SELECT round(100.0 * count(*) FILTER (WHERE a.status IN ('present', 'late')) / nullif(count(*), 0), 1)
    FROM attendance a
    JOIN schedule_slots s ON s.id = a.slot_id
    WHERE a.student_id = p_student_id
      AND (p_offering_id IS NULL OR s.offering_id = p_offering_id);
$$;

-- Has the student completed every prerequisite of the course?
CREATE FUNCTION fn_prerequisites_met(p_student_id int, p_course_id int) RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM course_prerequisites p
        WHERE p.course_id = p_course_id
          AND NOT EXISTS (
                SELECT 1
                FROM enrollments e
                JOIN course_offerings o ON o.id = e.offering_id
                WHERE e.student_id = p_student_id
                  AND o.course_id = p.prerequisite_id
                  AND e.status = 'completed'));
$$;


-- ═════════════════════════════ TRIGGERS ═════════════════════════════

-- T1. created_* / updated_* are always set by the database, never trusted from the client
CREATE FUNCTION trg_fn_set_audit_fields() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := now();
        NEW.created_by := fn_current_user_id();
    ELSE
        NEW.created_at := OLD.created_at;
        NEW.created_by := OLD.created_by;
    END IF;
    NEW.updated_at := now();
    NEW.updated_by := fn_current_user_id();
    RETURN NEW;
END;
$$;

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['faculties', 'departments', 'employees', 'student_groups', 'students', 'courses',
                             'course_offerings', 'enrollments', 'assessments', 'grades', 'tuition_payments']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%1$s_audit_fields BEFORE INSERT OR UPDATE ON %1$I
                        FOR EACH ROW EXECUTE FUNCTION trg_fn_set_audit_fields()', t);
    END LOOP;
END $$;

-- T2. DELETE on a soft-deletable table becomes UPDATE ... SET deleted_at.
--     A real delete is only possible with SET app.hard_delete = 'on' (maintenance).
CREATE FUNCTION trg_fn_soft_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('app.hard_delete', true) = 'on' THEN
        RETURN OLD;
    END IF;
    EXECUTE format('UPDATE %I.%I SET deleted_at = now(), deleted_by = $1 WHERE id = $2 AND deleted_at IS NULL',
                   TG_TABLE_SCHEMA, TG_TABLE_NAME)
        USING fn_current_user_id(), OLD.id;
    RETURN NULL;   -- cancel the physical delete
END;
$$;

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['faculties', 'departments', 'employees', 'student_groups', 'students', 'courses']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%1$s_soft_delete BEFORE DELETE ON %1$I
                        FOR EACH ROW EXECUTE FUNCTION trg_fn_soft_delete()', t);
    END LOOP;
END $$;

-- T3. Row history into audit_log (old/new row as jsonb)
CREATE FUNCTION trg_fn_audit_log() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_old jsonb := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
    v_new jsonb := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
    v_op  text  := TG_OP;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        -- ignore no-op updates
        IF (v_old - 'updated_at' - 'updated_by') = (v_new - 'updated_at' - 'updated_by') THEN
            RETURN NULL;
        END IF;
        IF v_old ? 'deleted_at' THEN
            IF v_old->>'deleted_at' IS NULL AND v_new->>'deleted_at' IS NOT NULL THEN
                v_op := 'SOFT_DELETE';
            ELSIF v_old->>'deleted_at' IS NOT NULL AND v_new->>'deleted_at' IS NULL THEN
                v_op := 'RESTORE';
            END IF;
        END IF;
    END IF;

    INSERT INTO audit_log (table_name, record_id, operation, old_data, new_data, changed_by)
    VALUES (TG_TABLE_NAME, (coalesce(v_new, v_old)->>'id')::bigint, v_op, v_old, v_new, fn_current_user_id());
    RETURN NULL;
END;
$$;

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['students', 'employees', 'enrollments', 'grades']
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%1$s_audit_log AFTER INSERT OR UPDATE OR DELETE ON %1$I
                        FOR EACH ROW EXECUTE FUNCTION trg_fn_audit_log()', t);
    END LOOP;
END $$;

-- T4. A grade must fit the assessment's max points and the student must be enrolled in the offering
CREATE FUNCTION trg_fn_check_grade() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_max      numeric;
    v_offering int;
BEGIN
    SELECT max_points, offering_id INTO v_max, v_offering FROM assessments WHERE id = NEW.assessment_id;

    IF NEW.points > v_max THEN
        RAISE EXCEPTION 'Points % exceed the maximum % for assessment %', NEW.points, v_max, NEW.assessment_id
            USING ERRCODE = 'check_violation';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM enrollments
                   WHERE student_id = NEW.student_id AND offering_id = v_offering AND status <> 'withdrawn') THEN
        RAISE EXCEPTION 'Student % is not enrolled in offering %', NEW.student_id, v_offering
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_grades_check BEFORE INSERT OR UPDATE OF points, assessment_id, student_id ON grades
    FOR EACH ROW EXECUTE FUNCTION trg_fn_check_grade();

-- T5. Sum of max points of all assessments of one offering must not exceed 100
CREATE FUNCTION trg_fn_check_assessment_total() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_total numeric;
BEGIN
    SELECT coalesce(sum(max_points), 0) + NEW.max_points INTO v_total
    FROM assessments
    WHERE offering_id = NEW.offering_id AND id IS DISTINCT FROM NEW.id;

    IF v_total > 100 THEN
        RAISE EXCEPTION 'Total max points of offering % would be % (limit 100)', NEW.offering_id, v_total
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_assessments_total BEFORE INSERT OR UPDATE OF max_points, offering_id ON assessments
    FOR EACH ROW EXECUTE FUNCTION trg_fn_check_assessment_total();

-- T6. Enrollment: student must be active and have passed all prerequisites
CREATE FUNCTION trg_fn_check_enrollment() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_course int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM students WHERE id = NEW.student_id AND status = 'active' AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Student % is not active', NEW.student_id USING ERRCODE = 'check_violation';
    END IF;

    SELECT course_id INTO v_course FROM course_offerings WHERE id = NEW.offering_id;
    IF NOT fn_prerequisites_met(NEW.student_id, v_course) THEN
        RAISE EXCEPTION 'Student % has not completed the prerequisites of course %', NEW.student_id, v_course
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enrollments_check BEFORE INSERT ON enrollments
    FOR EACH ROW EXECUTE FUNCTION trg_fn_check_enrollment();

-- T7. Timetable: no room and no group may have two lessons at the same time.
--     'all' weeks overlap with everything, 'odd' and 'even' do not overlap with each other.
CREATE FUNCTION trg_fn_check_schedule() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_conflict int;
    v_group    int;
    v_term     int;
BEGIN
    SELECT group_id, term_id INTO v_group, v_term FROM course_offerings WHERE id = NEW.offering_id;

    SELECT s.id INTO v_conflict
    FROM schedule_slots s
    JOIN course_offerings o ON o.id = s.offering_id
    WHERE s.id IS DISTINCT FROM NEW.id
      AND o.term_id = v_term
      AND s.day_of_week = NEW.day_of_week
      AND s.pair_number = NEW.pair_number
      AND (s.week_parity = 'all' OR NEW.week_parity = 'all' OR s.week_parity = NEW.week_parity)
      AND (s.classroom_id = NEW.classroom_id OR o.group_id = v_group)
    LIMIT 1;

    IF v_conflict IS NOT NULL THEN
        RAISE EXCEPTION 'Schedule conflict with slot % (same room or same group at day %, pair %)',
            v_conflict, NEW.day_of_week, NEW.pair_number USING ERRCODE = 'exclusion_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_schedule_slots_check BEFORE INSERT OR UPDATE ON schedule_slots
    FOR EACH ROW EXECUTE FUNCTION trg_fn_check_schedule();

-- T8. Prerequisites must not form a cycle (A needs B, B needs A)
CREATE FUNCTION trg_fn_check_prerequisite_cycle() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        WITH RECURSIVE chain(course_id) AS (
            SELECT prerequisite_id FROM course_prerequisites WHERE course_id = NEW.prerequisite_id
            UNION
            SELECT p.prerequisite_id FROM course_prerequisites p JOIN chain c ON p.course_id = c.course_id
        )
        SELECT 1 FROM chain WHERE course_id = NEW.course_id
    ) OR NEW.prerequisite_id = NEW.course_id THEN
        RAISE EXCEPTION 'Prerequisite % -> % would create a cycle', NEW.course_id, NEW.prerequisite_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_course_prerequisites_cycle BEFORE INSERT OR UPDATE ON course_prerequisites
    FOR EACH ROW EXECUTE FUNCTION trg_fn_check_prerequisite_cycle();


-- ═════════════════════════════ VIEWS ═════════════════════════════

CREATE VIEW v_active_students AS
SELECT s.id,
       s.group_id,
       g.code                                         AS group_code,
       s.record_book_no,
       s.first_name,
       s.last_name,
       s.middle_name,
       concat_ws(' ', s.last_name, s.first_name, s.middle_name) AS full_name,
       s.birth_date,
       s.email,
       s.enrollment_date,
       s.funding_type,
       s.status,
       sp.code || ' ' || sp.name                      AS specialty,
       f.code                                         AS faculty_code,
       s.created_at,
       s.updated_at,
       u.username                                     AS updated_by
FROM students s
JOIN student_groups g ON g.id = s.group_id
JOIN specialties sp   ON sp.id = g.specialty_id
JOIN departments d    ON d.id = sp.department_id
JOIN faculties f      ON f.id = d.faculty_id
LEFT JOIN app_users u ON u.id = s.updated_by
WHERE s.deleted_at IS NULL;

CREATE VIEW v_deleted_students AS
SELECT s.id, s.record_book_no, concat_ws(' ', s.last_name, s.first_name, s.middle_name) AS full_name,
       g.code AS group_code, s.deleted_at, u.username AS deleted_by
FROM students s
JOIN student_groups g ON g.id = s.group_id
LEFT JOIN app_users u ON u.id = s.deleted_by
WHERE s.deleted_at IS NOT NULL;

CREATE VIEW v_active_groups AS
SELECT g.id,
       g.code,
       g.specialty_id,
       sp.code || ' ' || sp.name                                 AS specialty,
       dl.code                                                   AS degree_level,
       g.enrollment_year,
       g.curator_id,
       concat_ws(' ', e.last_name, e.first_name)                 AS curator_name,
       (SELECT count(*) FROM students s
        WHERE s.group_id = g.id AND s.deleted_at IS NULL AND s.status = 'active') AS active_students,
       g.updated_at,
       u.username                                                AS updated_by
FROM student_groups g
JOIN specialties sp    ON sp.id = g.specialty_id
JOIN degree_levels dl  ON dl.id = sp.degree_level_id
LEFT JOIN employees e  ON e.id = g.curator_id
LEFT JOIN app_users u  ON u.id = g.updated_by
WHERE g.deleted_at IS NULL;

CREATE VIEW v_active_employees AS
SELECT e.id,
       concat_ws(' ', e.last_name, e.first_name, e.middle_name) AS full_name,
       p.name   AS position,
       e.academic_degree,
       d.code   AS department_code,
       d.name   AS department,
       f.code   AS faculty_code,
       e.email,
       e.hire_date,
       e.salary
FROM employees e
JOIN positions p   ON p.id = e.position_id
JOIN departments d ON d.id = e.department_id
JOIN faculties f   ON f.id = d.faculty_id
WHERE e.deleted_at IS NULL;

CREATE VIEW v_enrollment_details AS
SELECT e.id,
       e.student_id,
       concat_ws(' ', s.last_name, s.first_name)  AS student_name,
       e.offering_id,
       c.code                                     AS course_code,
       c.name                                     AS course_name,
       c.ects_credits,
       o.term_id,
       t.academic_year || ' / ' || t.semester     AS term,
       g.code                                     AS group_code,
       concat_ws(' ', l.last_name, l.first_name)  AS lecturer_name,
       e.status,
       fn_student_points(e.student_id, e.offering_id) AS current_points,
       e.final_points,
       fn_ects_grade(e.final_points)              AS ects_grade,
       e.enrolled_at,
       e.updated_at,
       u.username                                 AS updated_by
FROM enrollments e
JOIN students s          ON s.id = e.student_id
JOIN course_offerings o  ON o.id = e.offering_id
JOIN courses c           ON c.id = o.course_id
JOIN academic_terms t    ON t.id = o.term_id
JOIN student_groups g    ON g.id = o.group_id
JOIN employees l         ON l.id = o.lecturer_id
LEFT JOIN app_users u    ON u.id = e.updated_by;

CREATE VIEW v_grade_details AS
SELECT gr.id,
       gr.assessment_id,
       a.title                                    AS assessment_title,
       a.assessment_type,
       a.max_points,
       a.offering_id,
       c.name                                     AS course_name,
       gr.student_id,
       concat_ws(' ', s.last_name, s.first_name)  AS student_name,
       gr.points,
       gr.graded_by,
       concat_ws(' ', t.last_name, t.first_name)  AS graded_by_name,
       gr.graded_at,
       gr.updated_at,
       u.username                                 AS updated_by
FROM grades gr
JOIN assessments a       ON a.id = gr.assessment_id
JOIN course_offerings o  ON o.id = a.offering_id
JOIN courses c           ON c.id = o.course_id
JOIN students s          ON s.id = gr.student_id
JOIN employees t         ON t.id = gr.graded_by
LEFT JOIN app_users u    ON u.id = gr.updated_by;

CREATE VIEW v_student_transcript AS
SELECT s.id                                       AS student_id,
       s.record_book_no,
       concat_ws(' ', s.last_name, s.first_name)  AS student_name,
       t.academic_year,
       t.semester,
       c.code                                     AS course_code,
       c.name                                     AS course_name,
       c.ects_credits,
       e.status,
       e.final_points,
       fn_ects_grade(e.final_points)              AS ects_grade,
       fn_national_grade(e.final_points)          AS national_grade
FROM enrollments e
JOIN students s          ON s.id = e.student_id
JOIN course_offerings o  ON o.id = e.offering_id
JOIN courses c           ON c.id = o.course_id
JOIN academic_terms t    ON t.id = o.term_id
WHERE e.status IN ('completed', 'failed');

CREATE VIEW v_group_performance AS
SELECT g.code                                                   AS group_code,
       t.academic_year || ' / ' || t.semester                   AS term,
       count(DISTINCT e.student_id)                             AS students,
       round(avg(coalesce(e.final_points,
                          fn_student_points(e.student_id, e.offering_id))), 2) AS avg_points,
       count(*) FILTER (WHERE e.status = 'failed')              AS failed_results,
       round(100.0 * count(*) FILTER (WHERE e.final_points >= 90)
             / nullif(count(e.final_points), 0), 1)             AS excellent_pct
FROM enrollments e
JOIN course_offerings o ON o.id = e.offering_id
JOIN student_groups g   ON g.id = o.group_id
JOIN academic_terms t   ON t.id = o.term_id
WHERE e.status <> 'withdrawn'
GROUP BY g.code, t.id, t.academic_year, t.semester;

CREATE VIEW v_teacher_workload AS
SELECT l.id                                         AS lecturer_id,
       concat_ws(' ', l.last_name, l.first_name)    AS lecturer_name,
       t.academic_year || ' / ' || t.semester       AS term,
       count(DISTINCT o.id)                         AS offerings,
       count(DISTINCT o.group_id)                   AS groups,
       (SELECT count(*) FROM enrollments e
        JOIN course_offerings o2 ON o2.id = e.offering_id
        WHERE o2.lecturer_id = l.id AND o2.term_id = t.id AND e.status <> 'withdrawn') AS students,
       (SELECT count(*) FROM schedule_slots s
        JOIN course_offerings o3 ON o3.id = s.offering_id
        WHERE o3.lecturer_id = l.id AND o3.term_id = t.id) AS pairs_per_week,
       sum(c.hours_total)                           AS total_hours
FROM course_offerings o
JOIN employees l       ON l.id = o.lecturer_id
JOIN courses c         ON c.id = o.course_id
JOIN academic_terms t  ON t.id = o.term_id
GROUP BY l.id, l.last_name, l.first_name, t.id, t.academic_year, t.semester;

CREATE VIEW v_timetable AS
SELECT t.academic_year || ' / ' || t.semester AS term,
       g.code                                 AS group_code,
       s.day_of_week,
       (ARRAY['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'])[s.day_of_week] AS day_name,
       s.pair_number,
       (ARRAY['08:30', '10:05', '11:40', '13:15', '14:50', '16:25', '18:00', '19:35'])[s.pair_number] AS starts_at,
       s.week_parity,
       c.name                                 AS course_name,
       s.lesson_type,
       b.code || '-' || r.room_number         AS room,
       concat_ws(' ', l.last_name, l.first_name) AS lecturer_name
FROM schedule_slots s
JOIN course_offerings o ON o.id = s.offering_id
JOIN academic_terms t   ON t.id = o.term_id
JOIN student_groups g   ON g.id = o.group_id
JOIN courses c          ON c.id = o.course_id
JOIN classrooms r       ON r.id = s.classroom_id
JOIN buildings b        ON b.id = r.building_id
JOIN employees l        ON l.id = o.lecturer_id;

CREATE VIEW v_payment_debts AS
SELECT s.id                                        AS student_id,
       s.record_book_no,
       concat_ws(' ', s.last_name, s.first_name)   AS student_name,
       g.code                                      AS group_code,
       t.academic_year || ' / ' || t.semester      AS term,
       fn_tuition_fee(t.id)                        AS fee,
       coalesce(p.paid, 0)                         AS paid,
       fn_tuition_fee(t.id) - coalesce(p.paid, 0)  AS debt
FROM students s
JOIN student_groups g  ON g.id = s.group_id
JOIN academic_terms t  ON t.start_date >= make_date(g.enrollment_year, 9, 1) - 1
                      AND t.start_date <= current_date
LEFT JOIN (SELECT student_id, term_id, sum(amount) AS paid
           FROM tuition_payments GROUP BY student_id, term_id) p
       ON p.student_id = s.id AND p.term_id = t.id
WHERE s.funding_type = 'contract'
  AND s.deleted_at IS NULL
  AND s.status = 'active'
  AND fn_tuition_fee(t.id) > coalesce(p.paid, 0);

CREATE VIEW v_audit_trail AS
SELECT l.id,
       l.changed_at,
       coalesce(u.username, '(system)') AS changed_by,
       l.table_name,
       l.record_id,
       l.operation,
       -- only the columns that actually changed
       (SELECT jsonb_object_agg(n.key, jsonb_build_object('old', l.old_data -> n.key, 'new', n.value))
        FROM jsonb_each(l.new_data) n
        WHERE l.operation <> 'INSERT'
          AND n.key NOT IN ('updated_at', 'updated_by')
          AND n.value IS DISTINCT FROM l.old_data -> n.key) AS changes
FROM audit_log l
LEFT JOIN app_users u ON u.id = l.changed_by;

-- Materialized: heavy aggregate for dashboards, refreshed by sp_refresh_statistics
CREATE MATERIALIZED VIEW mv_faculty_statistics AS
SELECT f.id                                                         AS faculty_id,
       f.code                                                       AS faculty_code,
       f.name                                                       AS faculty_name,
       count(DISTINCT g.id)                                         AS groups,
       count(DISTINCT s.id)                                         AS students,
       count(DISTINCT s.id) FILTER (WHERE s.funding_type = 'budget')   AS budget_students,
       count(DISTINCT s.id) FILTER (WHERE s.funding_type = 'contract') AS contract_students,
       round(avg(fn_student_gpa(s.id)), 2)                          AS avg_gpa,
       (SELECT count(*) FROM employees e JOIN departments d2 ON d2.id = e.department_id
        WHERE d2.faculty_id = f.id AND e.deleted_at IS NULL)        AS employees,
       now()                                                        AS refreshed_at
FROM faculties f
LEFT JOIN departments d     ON d.faculty_id = f.id
LEFT JOIN specialties sp    ON sp.department_id = d.id
LEFT JOIN student_groups g  ON g.specialty_id = sp.id AND g.deleted_at IS NULL
LEFT JOIN students s        ON s.group_id = g.id AND s.deleted_at IS NULL AND s.status = 'active'
WHERE f.deleted_at IS NULL
GROUP BY f.id, f.code, f.name;

CREATE UNIQUE INDEX ux_mv_faculty_statistics ON mv_faculty_statistics (faculty_id);  -- allows CONCURRENTLY

-- Table function used by the group repository: active students of one group
CREATE FUNCTION fn_group_students(p_group_id int) RETURNS SETOF v_active_students
LANGUAGE sql STABLE AS $$
    SELECT * FROM v_active_students WHERE group_id = p_group_id ORDER BY last_name, first_name;
$$;


-- ═════════════════════════════ PROCEDURES ═════════════════════════════
-- All writes from the application go through these. They never COMMIT:
-- the caller (Unit of Work) owns the transaction.

-- ── students ──

CREATE PROCEDURE sp_student_create(
    p_group_id        int,
    p_record_book_no  varchar,
    p_first_name      varchar,
    p_last_name       varchar,
    p_middle_name     varchar,
    p_birth_date      date,
    p_email           varchar,
    p_funding_type    varchar,
    p_enrollment_date date,
    OUT p_id          int)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM student_groups WHERE id = p_group_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Group % does not exist or is deleted', p_group_id USING ERRCODE = 'foreign_key_violation';
    END IF;

    INSERT INTO students (group_id, record_book_no, first_name, last_name, middle_name, birth_date, email,
                          enrollment_date, funding_type)
    VALUES (p_group_id, p_record_book_no, p_first_name, p_last_name, p_middle_name, p_birth_date, lower(p_email),
            coalesce(p_enrollment_date, current_date), p_funding_type)
    RETURNING id INTO p_id;
END;
$$;

CREATE PROCEDURE sp_student_update(
    p_id            int,
    p_first_name    varchar,
    p_last_name     varchar,
    p_middle_name   varchar,
    p_birth_date    date,
    p_email         varchar,
    p_funding_type  varchar,
    p_status        varchar)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE students
    SET first_name   = p_first_name,
        last_name    = p_last_name,
        middle_name  = p_middle_name,
        birth_date   = p_birth_date,
        email        = lower(p_email),
        funding_type = p_funding_type,
        status       = p_status
    WHERE id = p_id AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Student % not found', p_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

CREATE PROCEDURE sp_student_soft_delete(p_id int)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Student % not found', p_id USING ERRCODE = 'no_data_found';
    END IF;
    DELETE FROM students WHERE id = p_id;   -- trg_students_soft_delete turns this into an UPDATE
END;
$$;

CREATE PROCEDURE sp_student_restore(p_id int)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE students SET deleted_at = NULL, deleted_by = NULL
    WHERE id = p_id AND deleted_at IS NOT NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deleted student % not found', p_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

-- Move a student to another group: withdraw from the old group's current-term courses
-- that are not graded yet, enrol into the new group's current-term courses (if prerequisites are met).
CREATE PROCEDURE sp_student_transfer(p_student_id int, p_new_group_id int, OUT p_withdrawn int, OUT p_enrolled int)
LANGUAGE plpgsql AS $$
DECLARE
    v_old_group int;
    v_term      int := fn_current_term_id();
BEGIN
    SELECT group_id INTO v_old_group FROM students WHERE id = p_student_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Student % not found', p_student_id USING ERRCODE = 'no_data_found';
    END IF;
    IF v_old_group = p_new_group_id THEN
        RAISE EXCEPTION 'Student % is already in group %', p_student_id, p_new_group_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM student_groups WHERE id = p_new_group_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Group % does not exist or is deleted', p_new_group_id USING ERRCODE = 'foreign_key_violation';
    END IF;

    UPDATE students SET group_id = p_new_group_id WHERE id = p_student_id;

    UPDATE enrollments e
    SET status = 'withdrawn'
    FROM course_offerings o
    WHERE o.id = e.offering_id
      AND e.student_id = p_student_id
      AND o.group_id = v_old_group
      AND o.term_id = v_term
      AND e.status = 'enrolled';
    GET DIAGNOSTICS p_withdrawn = ROW_COUNT;

    INSERT INTO enrollments (student_id, offering_id)
    SELECT p_student_id, o.id
    FROM course_offerings o
    WHERE o.group_id = p_new_group_id
      AND o.term_id = v_term
      AND fn_prerequisites_met(p_student_id, o.course_id)
    ON CONFLICT (student_id, offering_id) DO UPDATE SET status = 'enrolled'
        WHERE enrollments.status = 'withdrawn';
    GET DIAGNOSTICS p_enrolled = ROW_COUNT;
END;
$$;

-- ── groups ──

CREATE PROCEDURE sp_group_create(p_specialty_id int, p_code varchar, p_enrollment_year smallint,
                                 p_curator_id int, OUT p_id int)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO student_groups (specialty_id, code, enrollment_year, curator_id)
    VALUES (p_specialty_id, p_code, p_enrollment_year, p_curator_id)
    RETURNING id INTO p_id;
END;
$$;

CREATE PROCEDURE sp_group_update(p_id int, p_code varchar, p_curator_id int)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE student_groups SET code = p_code, curator_id = p_curator_id
    WHERE id = p_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Group % not found', p_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

CREATE PROCEDURE sp_group_soft_delete(p_id int)
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM students WHERE group_id = p_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Group % still has students; transfer or delete them first', p_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    DELETE FROM student_groups WHERE id = p_id;   -- soft delete via trigger
END;
$$;

-- ── enrollments ──

CREATE PROCEDURE sp_enrollment_create(p_student_id int, p_offering_id int, OUT p_id int)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO enrollments (student_id, offering_id)
    VALUES (p_student_id, p_offering_id)
    ON CONFLICT (student_id, offering_id) DO UPDATE SET status = 'enrolled', enrolled_at = now()
        WHERE enrollments.status = 'withdrawn'
    RETURNING id INTO p_id;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'Student % is already enrolled in offering %', p_student_id, p_offering_id
            USING ERRCODE = 'unique_violation';
    END IF;
END;
$$;

CREATE PROCEDURE sp_enrollment_withdraw(p_id int)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE enrollments SET status = 'withdrawn' WHERE id = p_id AND status = 'enrolled';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Enrollment % not found or already finished', p_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

-- ── grades ──

-- insert or correct a grade (one grade per student per assessment)
CREATE PROCEDURE sp_grade_set(p_assessment_id int, p_student_id int, p_points numeric, p_graded_by int, OUT p_id int)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO grades (assessment_id, student_id, points, graded_by)
    VALUES (p_assessment_id, p_student_id, p_points, p_graded_by)
    ON CONFLICT (assessment_id, student_id)
        DO UPDATE SET points = EXCLUDED.points, graded_by = EXCLUDED.graded_by, graded_at = now()
    RETURNING id INTO p_id;
END;
$$;

CREATE PROCEDURE sp_grade_delete(p_id int)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM grades WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Grade % not found', p_id USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

-- Close the exam sheet: final points = sum of grades; >= 60 completed, otherwise failed
CREATE PROCEDURE sp_finalize_offering(p_offering_id int, OUT p_completed int, OUT p_failed int)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE enrollments e
    SET final_points = fn_student_points(e.student_id, e.offering_id),
        status = CASE WHEN fn_student_points(e.student_id, e.offering_id) >= 60 THEN 'completed' ELSE 'failed' END
    WHERE e.offering_id = p_offering_id AND e.status = 'enrolled';

    SELECT count(*) FILTER (WHERE status = 'completed'), count(*) FILTER (WHERE status = 'failed')
    INTO p_completed, p_failed
    FROM enrollments WHERE offering_id = p_offering_id;
END;
$$;

-- ── maintenance ──

CREATE PROCEDURE sp_refresh_statistics()
LANGUAGE sql AS $$
    REFRESH MATERIALIZED VIEW mv_faculty_statistics;
$$;
