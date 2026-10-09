-- =====================================================================
-- Demo data. Deterministic (setseed), consistent with the business rules:
-- prerequisites passed, max points per offering = 100, no room conflicts.
-- Previous term: 2025/2026 sem 2 (finished). Current term: 2026/2027 sem 1.
-- =====================================================================


-- the seed acts as the admin user (id 1); audit triggers read this setting
INSERT INTO app_users (username, role) VALUES ('admin', 'admin');
DO $$ BEGIN PERFORM setseed(0.42); PERFORM set_config('app.user_id', '1', false); END $$;

-- ─────────────────────────── Reference data ───────────────────────────

INSERT INTO positions (name, is_academic) VALUES
    ('Асистент', true), ('Старший викладач', true), ('Доцент', true),
    ('Професор', true), ('Методист', false);

INSERT INTO degree_levels (code, name, duration_years) VALUES
    ('BSc', 'Бакалавр', 4.0), ('MSc', 'Магістр', 1.5), ('PhD', 'Доктор філософії', 4.0);

INSERT INTO buildings (code, name, address) VALUES
    ('B1', 'Головний корпус', 'вул. Університетська, 1'),
    ('B2', 'Корпус ІТ', 'вул. Наукова, 5');

INSERT INTO classrooms (building_id, room_number, capacity, room_type) VALUES
    (1, '101', 120, 'lecture'), (1, '205', 40, 'seminar'), (1, '310', 30, 'seminar'),
    (2, '12', 100, 'lecture'),  (2, '201', 24, 'computer'), (2, '202', 24, 'computer'),
    (2, '305', 20, 'lab');

-- ─────────────────────────── Organisation ───────────────────────────

INSERT INTO faculties (code, name) VALUES
    ('FIT', 'Факультет інформаційних технологій'),
    ('FEC', 'Економічний факультет');

INSERT INTO departments (faculty_id, code, name, phone) VALUES
    (1, 'SE',   'Кафедра програмної інженерії',  '+380441110001'),
    (1, 'CS',   'Кафедра комп''ютерних наук',     '+380441110002'),
    (1, 'MATH', 'Кафедра вищої математики',      '+380441110003'),
    (2, 'ECON', 'Кафедра економічної теорії',    '+380441110004');

INSERT INTO employees (department_id, position_id, first_name, last_name, middle_name, email, phone, academic_degree, hire_date, salary) VALUES
    (1, 4, 'Олександр', 'Коваленко',  'Петрович',    'o.kovalenko@uni.edu.ua',  '+380501000001', 'DSc', '2005-09-01', 42000),
    (1, 3, 'Ірина',     'Шевченко',   'Василівна',   'i.shevchenko@uni.edu.ua', '+380501000002', 'PhD', '2012-09-01', 32000),
    (1, 2, 'Андрій',    'Бондаренко', 'Олегович',    'a.bondarenko@uni.edu.ua', '+380501000003', NULL,  '2019-09-01', 24000),
    (2, 4, 'Наталія',   'Ткаченко',   'Іванівна',    'n.tkachenko@uni.edu.ua',  '+380501000004', 'DSc', '2003-09-01', 43000),
    (2, 3, 'Дмитро',    'Кравченко',  'Сергійович',  'd.kravchenko@uni.edu.ua', '+380501000005', 'PhD', '2014-09-01', 31000),
    (2, 1, 'Марія',     'Олійник',    'Андріївна',   'm.oliinyk@uni.edu.ua',    '+380501000006', NULL,  '2023-09-01', 18000),
    (3, 4, 'Віктор',    'Мельник',    'Григорович',  'v.melnyk@uni.edu.ua',     '+380501000007', 'DSc', '1999-09-01', 44000),
    (3, 3, 'Оксана',    'Савченко',   'Миколаївна',  'o.savchenko@uni.edu.ua',  '+380501000008', 'PhD', '2010-09-01', 30000),
    (3, 2, 'Юрій',      'Руденко',    'Павлович',    'y.rudenko@uni.edu.ua',    '+380501000009', NULL,  '2018-09-01', 23000),
    (4, 4, 'Тетяна',    'Лисенко',    'Олександрівна','t.lysenko@uni.edu.ua',   '+380501000010', 'DSc', '2001-09-01', 41000),
    (4, 3, 'Сергій',    'Гончаренко', 'Вікторович',  's.honcharenko@uni.edu.ua','+380501000011', 'PhD', '2015-09-01', 29000),
    (1, 5, 'Людмила',   'Марченко',   'Йосипівна',   'l.marchenko@uni.edu.ua',  '+380501000012', NULL,  '2016-09-01', 17000);

UPDATE faculties   SET dean_id = 1  WHERE code = 'FIT';
UPDATE faculties   SET dean_id = 10 WHERE code = 'FEC';
UPDATE departments SET head_id = CASE code WHEN 'SE' THEN 1 WHEN 'CS' THEN 4 WHEN 'MATH' THEN 7 WHEN 'ECON' THEN 10 END;

-- ─────────────────────────── Specialties & groups ───────────────────────────

INSERT INTO specialties (department_id, degree_level_id, code, name) VALUES
    (1, 1, '121', 'Інженерія програмного забезпечення'),
    (2, 1, '122', 'Комп''ютерні науки'),
    (2, 2, '122', 'Комп''ютерні науки'),
    (4, 1, '051', 'Економіка');

INSERT INTO student_groups (specialty_id, code, enrollment_year, curator_id) VALUES
    (1, 'ІПЗ-25',   2025, 3),
    (2, 'КН-25-1',  2025, 5),
    (2, 'КН-25-2',  2025, 6),
    (4, 'ЕК-25',    2025, 11),
    (3, 'КН-м-26',  2026, 4);

-- 10 students per group, names combined from lists
INSERT INTO students (group_id, record_book_no, first_name, last_name, middle_name, birth_date, email,
                      enrollment_date, funding_type, status)
SELECT g.id,
       format('%s-%s', g.enrollment_year, lpad((g.id * 100 + n)::text, 4, '0')),
       (ARRAY['Артем','Софія','Максим','Анна','Богдан','Вікторія','Денис','Катерина','Євген','Олена',
              'Тарас','Юлія','Назар','Дарина','Роман'])[1 + (g.id * 7 + n * 3) % 15],
       (ARRAY['Гриценко','Петренко','Іваненко','Захарченко','Поліщук','Литвиненко','Мороз','Кузьменко',
              'Павленко','Кравець','Левченко','Остапенко','Симоненко','Тимошенко','Яковенко'])[1 + (g.id * 5 + n) % 15],
       (ARRAY['Олегович','Іванівна','Петрович','Андріївна','Сергійович'])[1 + n % 5],
       make_date(g.enrollment_year - CASE WHEN g.code LIKE '%-м-%' THEN 21 ELSE 17 END, 1 + (n * 5) % 12, 1 + (n * 3) % 28),
       format('st%s.%s@stud.uni.edu.ua', g.enrollment_year, g.id * 100 + n),
       make_date(g.enrollment_year, 9, 1),
       CASE WHEN n % 3 = 0 THEN 'contract' ELSE 'budget' END,
       'active'
FROM student_groups g
CROSS JOIN generate_series(1, 10) AS n;

UPDATE students SET status = 'academic_leave' WHERE record_book_no = '2025-0209';

-- ─────────────────────────── Courses ───────────────────────────

INSERT INTO courses (department_id, code, name, description, ects_credits, hours_total) VALUES
    (1, 'SE101',  'Основи програмування',          'Змінні, цикли, функції, базові структури даних мовою C#. Вступ до алгоритмічного мислення.', 6, 180),
    (3, 'MA101',  'Дискретна математика',          'Множини, логіка, комбінаторика, теорія графів, відношення.', 5, 150),
    (3, 'MA102',  'Математичний аналіз',           'Границі, похідні, інтеграли, ряди.', 6, 180),
    (1, 'SE201',  'Об''єктно-орієнтоване програмування', 'Класи, наслідування, поліморфізм, інтерфейси, патерни проєктування.', 5, 150),
    (2, 'CS201',  'Бази даних',                    'Реляційна модель, SQL, нормалізація, індекси, транзакції, збережені процедури, PostgreSQL.', 5, 150),
    (2, 'CS202',  'Алгоритми та структури даних',  'Сортування, пошук, дерева, графи, динамічне програмування, складність алгоритмів.', 5, 150),
    (4, 'EC101',  'Мікроекономіка',                'Попит і пропозиція, еластичність, поведінка споживача та фірми.', 5, 150),
    (4, 'EC201',  'Макроекономіка',                'ВВП, інфляція, безробіття, монетарна та фіскальна політика.', 5, 150),
    (3, 'MA201',  'Статистика',                    'Описова статистика, ймовірність, перевірка гіпотез, регресія.', 4, 120),
    (2, 'CS501',  'Машинне навчання',              'Регресія, класифікація, нейронні мережі, оцінювання моделей.', 6, 180),
    (2, 'CS502',  'Розподілені системи',           'Реплікація, консенсус, мікросервіси, черги повідомлень.', 5, 150);

INSERT INTO course_prerequisites (course_id, prerequisite_id) VALUES
    (4, 1),          -- OOP           <- Programming basics
    (5, 1), (5, 2),  -- Databases     <- Programming basics, Discrete math
    (6, 1), (6, 2),  -- Algorithms    <- Programming basics, Discrete math
    (8, 7),          -- Macro         <- Micro
    (9, 3);          -- Statistics    <- Calculus

INSERT INTO academic_terms (academic_year, semester, start_date, end_date) VALUES
    ('2025/2026', 2, '2026-02-02', '2026-06-30'),
    ('2026/2027', 1, '2026-09-01', '2026-12-30');

-- ─────────────────────────── Offerings ───────────────────────────
-- term 1 (finished): first-year courses; term 2 (current): their continuation

INSERT INTO course_offerings (course_id, term_id, group_id, lecturer_id)
SELECT c.id, v.term_id, g.id, v.lecturer_id
FROM (VALUES
        -- course, term, lecturer, groups
        ('SE101', 1, 2, ARRAY['ІПЗ-25','КН-25-1','КН-25-2']),
        ('MA101', 1, 8, ARRAY['ІПЗ-25','КН-25-1','КН-25-2']),
        ('MA102', 1, 7, ARRAY['ІПЗ-25','КН-25-1','КН-25-2','ЕК-25']),
        ('EC101', 1, 11, ARRAY['ЕК-25']),
        ('SE201', 2, 2, ARRAY['ІПЗ-25','КН-25-1','КН-25-2']),
        ('CS201', 2, 5, ARRAY['ІПЗ-25','КН-25-1','КН-25-2']),
        ('CS202', 2, 4, ARRAY['КН-25-1','КН-25-2']),
        ('EC201', 2, 10, ARRAY['ЕК-25']),
        ('MA201', 2, 9, ARRAY['ЕК-25']),
        ('CS501', 2, 4, ARRAY['КН-м-26']),
        ('CS502', 2, 5, ARRAY['КН-м-26'])
     ) AS v(course_code, term_id, lecturer_id, group_codes)
JOIN courses c ON c.code = v.course_code
JOIN student_groups g ON g.code = ANY (v.group_codes);

-- every offering: two modules (30 + 30) and an exam (40) = 100
INSERT INTO assessments (offering_id, title, assessment_type, max_points, due_date)
SELECT o.id, a.title, a.kind, a.max_points, t.start_date + a.offset_days
FROM course_offerings o
JOIN academic_terms t ON t.id = o.term_id
CROSS JOIN (VALUES ('Модуль 1', 'module', 30, 56),
                   ('Модуль 2', 'module', 30, 105),
                   ('Екзамен',  'exam',   40, 140)) AS a(title, kind, max_points, offset_days);

-- ─────────────────────────── Term 1: enrolments, grades, results ───────────────────────────

INSERT INTO enrollments (student_id, offering_id, enrolled_at)
SELECT s.id, o.id, '2026-02-02'
FROM course_offerings o
JOIN students s ON s.group_id = o.group_id
WHERE o.term_id = 1;

INSERT INTO grades (assessment_id, student_id, points, graded_by, graded_at)
SELECT a.id, e.student_id,
       round((a.max_points * (0.45 + random() * 0.55))::numeric, 0),
       o.lecturer_id, a.due_date + 2
FROM enrollments e
JOIN course_offerings o ON o.id = e.offering_id
JOIN assessments a ON a.offering_id = o.id
WHERE o.term_id = 1;

UPDATE enrollments e
SET final_points = g.total,
    status = CASE WHEN g.total >= 60 THEN 'completed' ELSE 'failed' END
FROM (SELECT gr.student_id, a.offering_id, sum(gr.points) AS total
      FROM grades gr JOIN assessments a ON a.id = gr.assessment_id
      GROUP BY gr.student_id, a.offering_id) g
WHERE g.student_id = e.student_id AND g.offering_id = e.offering_id;

-- ─────────────────────────── Term 2 (current): only students who passed prerequisites ───────────────────────────

INSERT INTO enrollments (student_id, offering_id, enrolled_at)
SELECT s.id, o.id, '2026-09-01'
FROM course_offerings o
JOIN students s ON s.group_id = o.group_id AND s.status = 'active'
WHERE o.term_id = 2
  AND NOT EXISTS (
        SELECT 1
        FROM course_prerequisites p
        WHERE p.course_id = o.course_id
          AND NOT EXISTS (SELECT 1
                          FROM enrollments pe
                          JOIN course_offerings po ON po.id = pe.offering_id
                          WHERE pe.student_id = s.id
                            AND po.course_id = p.prerequisite_id
                            AND pe.status = 'completed'));

-- only "Модуль 1" is graded so far in the current term
INSERT INTO grades (assessment_id, student_id, points, graded_by, graded_at)
SELECT a.id, e.student_id,
       round((a.max_points * (0.4 + random() * 0.6))::numeric, 0),
       o.lecturer_id, a.due_date + 3
FROM enrollments e
JOIN course_offerings o ON o.id = e.offering_id
JOIN assessments a ON a.offering_id = o.id AND a.title = 'Модуль 1'
WHERE o.term_id = 2;

-- ─────────────────────────── Schedule & attendance (current term) ───────────────────────────

-- one lecture + one practice per offering; (day, pair) pairs are unique, so no room/group conflicts
INSERT INTO schedule_slots (offering_id, classroom_id, day_of_week, pair_number, lesson_type, week_parity)
SELECT o.id,
       CASE k WHEN 0 THEN 1 + (rn % 2) * 3 ELSE (ARRAY[2, 3, 5, 6, 7])[1 + rn % 5] END,
       1 + ((rn * 2 + k) % 5),
       1 + ((rn * 2 + k) / 5),
       CASE k WHEN 0 THEN 'lecture' ELSE 'practice' END,
       'all'
FROM (SELECT id, row_number() OVER (ORDER BY id) - 1 AS rn FROM course_offerings WHERE term_id = 2) o
CROSS JOIN generate_series(0, 1) AS k;

-- five weeks of attendance: 85% present, rest absent / late / excused
INSERT INTO attendance (slot_id, student_id, lesson_date, status)
SELECT sl.id, e.student_id,
       t.start_date + (sl.day_of_week - 1) + 7 * w,
       CASE WHEN r < 0.85 THEN 'present' WHEN r < 0.93 THEN 'absent' WHEN r < 0.97 THEN 'late' ELSE 'excused' END
FROM schedule_slots sl
JOIN course_offerings o ON o.id = sl.offering_id
JOIN academic_terms t ON t.id = o.term_id
JOIN enrollments e ON e.offering_id = o.id
CROSS JOIN generate_series(0, 4) AS w
CROSS JOIN LATERAL (SELECT random() + 0 * e.student_id + 0 * w AS r) rr;

-- ─────────────────────────── Payments: contract students, 18 000 per term ───────────────────────────

INSERT INTO tuition_payments (student_id, term_id, amount, paid_at, payment_method, reference)
SELECT s.id, t.id, 18000, t.start_date - 10,
       (ARRAY['card', 'bank', 'cash'])[1 + s.id % 3],
       format('TX-%s-%s', t.id, s.id)
FROM students s
JOIN student_groups g ON g.id = s.group_id
CROSS JOIN academic_terms t
WHERE s.funding_type = 'contract'
  AND make_date(g.enrollment_year, 9, 1) <= t.end_date
  AND NOT (t.id = 2 AND s.id % 4 = 0);   -- a few have not paid for the current term yet

-- ─────────────────────────── Application users ───────────────────────────

INSERT INTO app_users (username, role, employee_id) VALUES
    ('marchenko', 'dean_office', 12),
    ('shevchenko', 'teacher', 2),
    ('kravchenko', 'teacher', 5),
    ('tkachenko', 'teacher', 4);

INSERT INTO app_users (username, role, student_id)
SELECT 'student' || s.id, 'student', s.id FROM students s WHERE s.id IN (1, 11);

DO $$ BEGIN PERFORM set_config('app.user_id', '', false); END $$;
