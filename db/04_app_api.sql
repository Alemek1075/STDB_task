-- =====================================================================
-- Read views used only by the application (stage 7).
-- The C# repositories never query tables directly: reads go through
-- v_* views / fn_* functions, writes through sp_* procedures.
-- =====================================================================

CREATE VIEW v_course_offerings AS
SELECT o.id,
       o.course_id,
       c.code                                     AS course_code,
       c.name                                     AS course_name,
       c.ects_credits,
       o.term_id,
       t.academic_year || ' / ' || t.semester     AS term,
       (o.term_id = fn_current_term_id())         AS is_current,
       o.group_id,
       g.code                                     AS group_code,
       o.lecturer_id,
       concat_ws(' ', l.last_name, l.first_name)  AS lecturer_name
FROM course_offerings o
JOIN courses c        ON c.id = o.course_id
JOIN academic_terms t ON t.id = o.term_id
JOIN student_groups g ON g.id = o.group_id
JOIN employees l      ON l.id = o.lecturer_id;

CREATE VIEW v_offering_assessments AS
SELECT a.id,
       a.offering_id,
       a.title,
       a.assessment_type,
       a.max_points,
       a.due_date
FROM assessments a;

-- Accounts the demo can act as
CREATE VIEW v_app_users AS
SELECT u.id,
       u.username,
       u.role,
       u.employee_id,
       u.student_id,
       coalesce(concat_ws(' ', e.last_name, e.first_name), concat_ws(' ', s.last_name, s.first_name)) AS person_name
FROM app_users u
LEFT JOIN employees e ON e.id = u.employee_id
LEFT JOIN students s  ON s.id = u.student_id
WHERE u.is_active;
