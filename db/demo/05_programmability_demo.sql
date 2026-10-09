-- =====================================================================
-- Demo of stage 5 objects. Runs inside one transaction and rolls back,
-- so it can be repeated any number of times.
--   ./scripts/db.ps1 run db/demo/05_programmability_demo.sql
-- =====================================================================
\pset footer off
\set ON_ERROR_STOP on
BEGIN;

-- act as the dean office user (marchenko, id 2); triggers will record this id
SELECT set_config('app.user_id', '2', true) AS acting_user_id;

\echo
\echo '=== 1. Functions ==='
SELECT p AS points, fn_ects_grade(p) AS ects, fn_national_grade(p) AS national
FROM unnest(ARRAY[95, 85, 76, 65, 61, 50, 20]) AS p;

SELECT s.id, s.full_name, fn_student_gpa(s.id) AS gpa, fn_attendance_rate(s.id) AS attendance_pct
FROM v_active_students s WHERE s.group_code = 'КН-25-1' ORDER BY gpa DESC NULLS LAST LIMIT 5;

SELECT id, academic_year, semester FROM academic_terms WHERE id = fn_current_term_id();

\echo
\echo '=== 2. Procedure: create a student (audit fields are set by trigger) ==='
CALL sp_student_create(2, '2025-9999', 'Іван', 'Демченко', 'Петрович', '2008-04-12',
                       'I.Demchenko@stud.uni.edu.ua', 'budget', '2025-09-01', NULL);
SELECT id, full_name, email, created_at::time(0), updated_by
FROM v_active_students WHERE record_book_no = '2025-9999';

\echo
\echo '=== 3. Trigger: prerequisites. Enrolling a student who has not passed a prerequisite ==='
DO $$
DECLARE v_student int; v_offering int; v_course text; v_id int;
BEGIN
    -- an active student + a current-term offering of their group whose prerequisites they failed
    SELECT s.id, o.id, c.code INTO v_student, v_offering, v_course
    FROM students s
    JOIN course_offerings o ON o.group_id = s.group_id AND o.term_id = fn_current_term_id()
    JOIN courses c ON c.id = o.course_id
    WHERE s.status = 'active' AND NOT fn_prerequisites_met(s.id, o.course_id)
    LIMIT 1;
    RAISE NOTICE 'Trying to enrol student % into %', v_student, v_course;
    CALL sp_enrollment_create(v_student, v_offering, v_id);
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Rejected as expected: %', SQLERRM;
END $$;

\echo
\echo '=== 4. Trigger: grade above maximum ==='
DO $$
DECLARE v_assessment int; v_id int;
BEGIN
    SELECT a.id INTO v_assessment
    FROM enrollments e JOIN assessments a ON a.offering_id = e.offering_id
    WHERE e.student_id = 11 AND e.status = 'enrolled' AND a.title = 'Модуль 2' LIMIT 1;
    CALL sp_grade_set(v_assessment, 11, 45, 2, v_id);   -- max is 30
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Rejected as expected: %', SQLERRM;
END $$;

\echo
\echo '=== 5. Procedure sp_grade_set: correct a grade; audit_log keeps old and new value ==='
DO $$
DECLARE v_assessment int; v_id int;
BEGIN
    SELECT g.assessment_id INTO v_assessment FROM grades g WHERE g.student_id = 11 ORDER BY g.id DESC LIMIT 1;
    CALL sp_grade_set(v_assessment, 11, 29, 2, v_id);
END $$;
SELECT changed_by, table_name, record_id, operation, changes
FROM v_audit_trail WHERE table_name = 'grades' ORDER BY id DESC LIMIT 1;

\echo
\echo '=== 6. Soft delete: plain DELETE is turned into UPDATE by trigger ==='
DELETE FROM students WHERE record_book_no = '2025-9999';
SELECT id, record_book_no, deleted_at IS NOT NULL AS is_deleted, deleted_by FROM students WHERE record_book_no = '2025-9999';
SELECT count(*) AS still_visible_in_v_active_students FROM v_active_students WHERE record_book_no = '2025-9999';
SELECT * FROM v_deleted_students;

\echo
\echo '=== 7. Restore ==='
SELECT id AS new_student_id FROM students WHERE record_book_no = '2025-9999' \gset
CALL sp_student_restore(:new_student_id);
SELECT changed_at::time(0), changed_by, operation, changes FROM v_audit_trail
WHERE table_name = 'students' AND record_id = :new_student_id ORDER BY id;

\echo
\echo '=== 8. Transfer a student to another group (multi-table procedure) ==='
SELECT s.id AS transfer_student_id
FROM v_active_students s
WHERE s.group_code = 'КН-25-1'
  AND EXISTS (SELECT 1 FROM enrollments e WHERE e.student_id = s.id AND e.status = 'enrolled')
ORDER BY s.id LIMIT 1 \gset
SELECT id AS target_group_id FROM student_groups WHERE code = 'КН-25-2' \gset
\echo 'Before:'
SELECT student_name, course_code, group_code, status FROM v_enrollment_details
WHERE student_id = :transfer_student_id AND term_id = fn_current_term_id() ORDER BY course_code;
CALL sp_student_transfer(:transfer_student_id, :target_group_id, NULL, NULL);
\echo 'After:'
SELECT student_name, course_code, group_code, status FROM v_enrollment_details
WHERE student_id = :transfer_student_id AND term_id = fn_current_term_id() ORDER BY group_code, course_code;

\echo
\echo '=== 9. Trigger: schedule conflict (same room, same time) ==='
DO $$
BEGIN
    INSERT INTO schedule_slots (offering_id, classroom_id, day_of_week, pair_number, lesson_type)
    SELECT (SELECT id FROM course_offerings WHERE term_id = 2 ORDER BY id DESC LIMIT 1),
           classroom_id, day_of_week, pair_number, 'lab'
    FROM schedule_slots ORDER BY id LIMIT 1;
EXCEPTION WHEN exclusion_violation THEN
    RAISE NOTICE 'Rejected as expected: %', SQLERRM;
END $$;

\echo
\echo '=== 10. Trigger: prerequisite cycle ==='
DO $$
BEGIN
    INSERT INTO course_prerequisites VALUES (1, 4);   -- SE101 requires SE201, but SE201 requires SE101
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Rejected as expected: %', SQLERRM;
END $$;

\echo
\echo '=== 11. Trigger: assessments of one offering above 100 points ==='
DO $$
BEGIN
    INSERT INTO assessments (offering_id, title, assessment_type, max_points) VALUES (1, 'Бонус', 'test', 10);
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Rejected as expected: %', SQLERRM;
END $$;

\echo
\echo '=== 12. Procedure: finish the exam sheet of one current-term offering ==='
SELECT id AS offering_id FROM course_offerings WHERE term_id = fn_current_term_id() ORDER BY id LIMIT 1 \gset
SELECT set_config('demo.offering', :'offering_id', true) \gset
-- put the remaining grades (module 2, exam) through the procedure, then close the sheet
DO $$
DECLARE r record; v_id int;
BEGIN
    FOR r IN SELECT a.id AS assessment_id, a.max_points, e.student_id, o.lecturer_id
             FROM assessments a
             JOIN course_offerings o ON o.id = a.offering_id
             JOIN enrollments e ON e.offering_id = o.id AND e.status = 'enrolled'
             WHERE o.id = current_setting('demo.offering')::int AND a.title <> 'Модуль 1'
    LOOP
        CALL sp_grade_set(r.assessment_id, r.student_id, round(r.max_points * (0.5 + random() * 0.5)::numeric), r.lecturer_id, v_id);
    END LOOP;
END $$;
CALL sp_finalize_offering(:offering_id, NULL, NULL);
SELECT student_name, course_code, final_points, ects_grade, status FROM v_enrollment_details
WHERE offering_id = :offering_id ORDER BY final_points DESC;

\echo
\echo '=== 13. Views ==='
SELECT * FROM v_group_performance ORDER BY term, group_code;
SELECT * FROM v_teacher_workload WHERE term = '2026/2027 / 1' ORDER BY total_hours DESC LIMIT 5;
SELECT group_code, day_name, starts_at, course_name, lesson_type, room FROM v_timetable
WHERE group_code = 'ІПЗ-25' ORDER BY day_of_week, pair_number;
SELECT * FROM v_student_transcript WHERE student_id = 1;
SELECT * FROM v_payment_debts;
CALL sp_refresh_statistics();
SELECT faculty_code, groups, students, avg_gpa, employees FROM mv_faculty_statistics;

ROLLBACK;
\echo 'Rolled back: database is unchanged.'
