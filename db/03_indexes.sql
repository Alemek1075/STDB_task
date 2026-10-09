-- =====================================================================
-- Indexes. Primary keys and UNIQUE constraints from 01_schema.sql already
-- created B-tree indexes; this file adds the ones driven by queries and
-- by the soft-delete requirement.
--
-- Types used: B-tree (simple, composite, partial, expression, covering/INCLUDE, unique),
--             Hash, GIN (full-text, trigram, jsonb), BRIN, GiST (exclusion constraint).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ───────────── Partial UNIQUE + expression (soft delete aware) ─────────────
-- Uniqueness of e-mail must hold among *active* rows only, otherwise a deleted
-- student blocks his e-mail forever. Case-insensitive via lower().
ALTER TABLE students  DROP CONSTRAINT uq_students_email;
ALTER TABLE employees DROP CONSTRAINT uq_employees_email;

CREATE UNIQUE INDEX ux_students_email_active  ON students  (lower(email)) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX ux_employees_email_active ON employees (lower(email)) WHERE deleted_at IS NULL;

-- ───────────── Partial B-tree: foreign keys filtered to active rows ─────────────
-- v_active_students / fn_group_students always filter deleted_at IS NULL.
CREATE INDEX ix_students_group_active     ON students (group_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_employees_department      ON employees (department_id) WHERE deleted_at IS NULL;
CREATE INDEX ix_student_groups_specialty  ON student_groups (specialty_id) WHERE deleted_at IS NULL;

-- ───────────── Composite B-tree on foreign keys and frequent filters ─────────────
CREATE INDEX ix_course_offerings_term_group ON course_offerings (term_id, group_id);
CREATE INDEX ix_course_offerings_lecturer   ON course_offerings (lecturer_id, term_id);
CREATE INDEX ix_enrollments_offering_status ON enrollments (offering_id, status);
CREATE INDEX ix_assessments_offering        ON assessments (offering_id);
CREATE INDEX ix_schedule_slots_offering     ON schedule_slots (offering_id);
CREATE INDEX ix_schedule_slots_time         ON schedule_slots (day_of_week, pair_number);
CREATE INDEX ix_tuition_payments_student    ON tuition_payments (student_id, term_id);
CREATE INDEX ix_courses_department          ON courses (department_id);

-- ───────────── Covering index (INCLUDE) ─────────────
-- fn_student_points / transcript: "all points of a student" is answered from the index alone
-- (Index Only Scan), the table is not touched.
CREATE INDEX ix_grades_student_covering ON grades (student_id, assessment_id) INCLUDE (points);

-- ───────────── Expression B-tree ─────────────
-- Search by full name, case-insensitive: WHERE lower(last_name || ' ' || first_name) LIKE 'кравець%'
CREATE INDEX ix_students_full_name_lower ON students (lower(last_name || ' ' || first_name) text_pattern_ops)
    WHERE deleted_at IS NULL;

-- ───────────── Hash ─────────────
-- Only equality lookups, never ranges: attendance of one student.
CREATE INDEX ix_attendance_student_hash ON attendance USING hash (student_id);
CREATE INDEX ix_audit_log_record_hash   ON audit_log  USING hash (record_id);

-- ───────────── GIN: full-text search over courses ─────────────
CREATE INDEX ix_courses_fts ON courses
    USING gin (to_tsvector('simple', name || ' ' || coalesce(description, '')));

-- ───────────── GIN: trigram for fuzzy / substring search of surnames ─────────────
CREATE INDEX ix_students_last_name_trgm ON students USING gin (last_name gin_trgm_ops);

-- ───────────── GIN: jsonb history search ─────────────
-- "find every audit record where points were set to 100": new_data @> '{"points": 100}'
CREATE INDEX ix_audit_log_new_data ON audit_log USING gin (new_data jsonb_path_ops);

-- ───────────── BRIN: append-only log ordered by time ─────────────
-- Tiny index (a few pages for millions of rows) because changed_at grows with physical order.
CREATE INDEX ix_audit_log_changed_at_brin ON audit_log USING brin (changed_at);

-- ───────────── GiST: exclusion constraint ─────────────
-- Two academic terms must not overlap in time. A GiST index on a date range enforces it.
ALTER TABLE academic_terms
    ADD CONSTRAINT ex_academic_terms_no_overlap
    EXCLUDE USING gist (daterange(start_date, end_date, '[]') WITH &&);
