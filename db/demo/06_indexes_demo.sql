-- =====================================================================
-- Demo of stage 6 indexes: EXPLAIN plans on realistic volumes.
-- Adds bulk data inside a transaction and rolls back at the end.
--   ./scripts/db.ps1 run db/demo/06_indexes_demo.sql
-- =====================================================================
\pset footer off
\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('app.user_id', '1', true) AS acting_user_id;

\echo
\echo '=== 0. All indexes by access method ==='
SELECT am.amname AS type, count(*) AS indexes,
       count(*) FILTER (WHERE c.relname ~ '^(pk|uq)_') AS from_pk_or_unique_constraints
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_am am   ON am.oid = c.relam
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
GROUP BY am.amname ORDER BY indexes DESC;

\echo 'Indexes created in 03_indexes.sql:'
SELECT am.amname AS type, t.relname AS "table", c.relname AS index,
       regexp_replace(pg_get_indexdef(i.indexrelid), '^.* USING \w+ ', '') AS definition
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_class t ON t.oid = i.indrelid
JOIN pg_am am   ON am.oid = c.relam
WHERE c.relname ~ '^(ix|ux|ex)_' AND c.relname <> 'ux_mv_faculty_statistics'
ORDER BY am.amname, t.relname;

\echo
\echo '--- generating bulk data: 30 000 students, 300 000 audit records ---'
INSERT INTO students (group_id, record_book_no, first_name, last_name, birth_date, email, enrollment_date, funding_type)
SELECT 1 + i % 4, 'B-' || i, 'Bulk', initcap(substr(md5(i::text), 1, 10)), '2005-01-01',
       'bulk' || i || '@stud.uni.edu.ua', '2025-09-01', 'budget'
FROM generate_series(1, 30000) AS i;

INSERT INTO audit_log (table_name, record_id, operation, new_data, changed_by, changed_at)
SELECT 'grades', i, 'UPDATE', jsonb_build_object('id', i, 'points', i % 101), 1,
       timestamptz '2020-01-01' + i * interval '5 minutes'
FROM generate_series(1, 300000) AS i;

ANALYZE students;
ANALYZE audit_log;

\echo
\echo '=== 1. Partial B-tree: active students of a group (ix_students_group_active) ==='
EXPLAIN (COSTS OFF) SELECT * FROM v_active_students WHERE group_id = 5;

\echo
\echo '=== 2. Partial UNIQUE on lower(email): soft-deleted e-mail can be reused, active cannot ==='
DELETE FROM students WHERE record_book_no = '2025-0101';          -- soft delete
DO $$
DECLARE v_email text; v_id int;
BEGIN
    SELECT email INTO v_email FROM students WHERE record_book_no = '2025-0101';
    CALL sp_student_create(1, '2025-7778', 'Тарас', 'Мороз', NULL, '2008-01-01', upper(v_email), 'budget', NULL, v_id);
    RAISE NOTICE 'E-mail % of the deleted student reused by new student %', v_email, v_id;
    BEGIN
        CALL sp_student_create(1, '2025-7779', 'Копія', 'Мороз', NULL, '2008-01-01', v_email, 'budget', NULL, v_id);
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'Second active student with the same e-mail rejected: %', SQLERRM;
    END;
END $$;
EXPLAIN (COSTS OFF) SELECT id FROM students WHERE lower(email) = 'bulk77@stud.uni.edu.ua' AND deleted_at IS NULL;

\echo
\echo '=== 3. Expression B-tree: prefix search by full name (ix_students_full_name_lower) ==='
EXPLAIN (COSTS OFF)
SELECT id, last_name, first_name FROM students
WHERE lower(last_name || ' ' || first_name) LIKE 'a1b%' AND deleted_at IS NULL;

\echo
\echo '=== 4. GIN trigram: substring search anywhere in the surname (ix_students_last_name_trgm) ==='
EXPLAIN (COSTS OFF) SELECT id, last_name FROM students WHERE last_name ILIKE '%c4ca%';
SELECT id, last_name FROM students WHERE last_name ILIKE '%c4ca%' LIMIT 3;

\echo
\echo '=== 5. GIN jsonb: history records where points were set to 100 (ix_audit_log_new_data) ==='
EXPLAIN (COSTS OFF) SELECT count(*) FROM audit_log WHERE new_data @> '{"points": 100}';

\echo
\echo '=== 6. BRIN: time range in the append-only log (ix_audit_log_changed_at_brin) ==='
EXPLAIN (COSTS OFF)
SELECT count(*) FROM audit_log WHERE changed_at BETWEEN '2021-03-01' AND '2021-03-02';
CREATE INDEX tmp_btree_changed_at ON audit_log (changed_at);
SELECT pg_size_pretty(pg_relation_size('ix_audit_log_changed_at_brin')) AS brin_size,
       pg_size_pretty(pg_relation_size('tmp_btree_changed_at'))         AS same_column_btree_size;

\echo
\echo '=== 7. Hash: equality lookup of a record history (ix_audit_log_record_hash) ==='
EXPLAIN (COSTS OFF) SELECT * FROM audit_log WHERE record_id = 123456;

\echo
\echo '--- the next tables are small; sequential scan is disabled to show which index would be used ---'
SET LOCAL enable_seqscan = off;

\echo
\echo '=== 8. Covering index: points of a student without visiting the table (ix_grades_student_covering) ==='
SET LOCAL enable_bitmapscan = off;
EXPLAIN (COSTS OFF) SELECT assessment_id, points FROM grades WHERE student_id = 11;
RESET enable_bitmapscan;

\echo
\echo '=== 9. GIN full-text search over course names and descriptions (ix_courses_fts) ==='
EXPLAIN (COSTS OFF)
SELECT code, name FROM courses
WHERE to_tsvector('simple', name || ' ' || coalesce(description, '')) @@ plainto_tsquery('simple', 'PostgreSQL');
SELECT code, name FROM courses
WHERE to_tsvector('simple', name || ' ' || coalesce(description, '')) @@ plainto_tsquery('simple', 'PostgreSQL');

\echo
\echo '=== 10. Composite B-tree: enrollments of an offering by status (ix_enrollments_offering_status) ==='
EXPLAIN (COSTS OFF) SELECT student_id FROM enrollments WHERE offering_id = 12 AND status = 'enrolled';

\echo
\echo '=== 11. GiST exclusion constraint: overlapping academic term is rejected ==='
DO $$
BEGIN
    INSERT INTO academic_terms (academic_year, semester, start_date, end_date)
    VALUES ('2027/2028', 1, '2026-12-01', '2027-01-31');
EXCEPTION WHEN exclusion_violation THEN
    RAISE NOTICE 'Rejected as expected: %', SQLERRM;
END $$;

ROLLBACK;
\echo 'Rolled back: database is unchanged.'
