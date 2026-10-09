# ER diagram

> Generated from [`schema.dbml`](schema.dbml) by `python tools/dbml2mermaid.py`.
> The same DBML can be pasted into <https://dbdiagram.io/d> for an interactive view.

Entities: **12**, relationships: **19**.

```mermaid
erDiagram
    employees |o--o{ faculties : "dean_id"
    faculties ||--o{ departments : "faculty_id"
    employees |o--o{ departments : "head_id"
    departments ||--o{ employees : "department_id"
    departments ||--o{ specialties : "department_id"
    specialties ||--o{ student_groups : "specialty_id"
    employees |o--o{ student_groups : "curator_id"
    student_groups ||--o{ students : "group_id"
    departments ||--o{ courses : "department_id"
    courses ||--o{ course_offerings : "course_id"
    academic_terms ||--o{ course_offerings : "term_id"
    student_groups ||--o{ course_offerings : "group_id"
    employees ||--o{ course_offerings : "lecturer_id"
    students ||--o{ enrollments : "student_id"
    course_offerings ||--o{ enrollments : "offering_id"
    course_offerings ||--o{ assessments : "offering_id"
    assessments ||--o{ grades : "assessment_id"
    students ||--o{ grades : "student_id"
    employees ||--o{ grades : "graded_by"
    faculties {
        int id PK
        varchar code UK "e.g. FCS"
        varchar name UK
        int dean_id FK "nullable: faculty may have no dean yet"
    }
    departments {
        int id PK
        int faculty_id FK
        varchar code UK
        varchar name
        int head_id FK
        varchar phone
    }
    employees {
        int id PK
        int department_id FK
        varchar first_name
        varchar last_name
        varchar middle_name
        varchar email UK
        varchar phone
        date hire_date
        numeric salary "CHECK salary > 0"
    }
    specialties {
        int id PK
        int department_id FK "graduating department"
        varchar code "state code, e.g. 121"
        varchar name
    }
    student_groups {
        int id PK
        int specialty_id FK
        varchar code UK "e.g. КН-21"
        smallint enrollment_year
        int curator_id FK
    }
    students {
        int id PK
        int group_id FK
        varchar record_book_no UK "natural key (alternate key)"
        varchar first_name
        varchar last_name
        varchar middle_name
        date birth_date
        varchar email UK
        date enrollment_date
        varchar funding_type "budget | contract"
        varchar status "active | academic_leave | expelled | graduated"
    }
    courses {
        int id PK
        int department_id FK
        varchar code UK
        varchar name
        text description
        numeric ects_credits
    }
    academic_terms {
        int id PK
        varchar academic_year "2025/2026"
        smallint semester "1 | 2"
        date start_date
        date end_date
    }
    course_offerings {
        int id PK
        int course_id FK
        int term_id FK
        int group_id FK
        int lecturer_id FK
    }
    enrollments {
        int id PK
        int student_id FK
        int offering_id FK
        timestamptz enrolled_at
        varchar status "enrolled | completed | failed | withdrawn"
        numeric final_points
    }
    assessments {
        int id PK
        int offering_id FK
        varchar title
        varchar assessment_type "module | exam | lab | test | coursework"
        numeric max_points
        date due_date
    }
    grades {
        int id PK
        int assessment_id FK
        int student_id FK
        numeric points
        int graded_by FK
        timestamptz graded_at
    }
```
