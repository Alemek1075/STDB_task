# STDB_task

Варіант 1, система управління університетом (PostgreSQL + C# .NET 8).

1. Запуск: потрібні PostgreSQL і .NET 8, далі `./scripts/db.ps1 init`, `./scripts/db.ps1 start`, `./scripts/db.ps1 deploy` і `dotnet run --project src/University.Demo` (база піднімається окремим кластером на localhost:5433 без пароля, свій рядок підключення можна задати через `UNIVERSITY_DB`).
2. Діаграма схеми в `docs/er-diagram.md`, її DBML у `docs/schema.dbml`.
3. Опис 20 сутностей у `docs/entities.md`.
4. Вимоги, soft delete і поля аудиту в `docs/requirements.md`.
5. Таблиці в `db/01_schema.sql`, тестові дані в `db/90_seed.sql`.
6. Процедури, функції, тригери й view в `db/02_programmability.sql`, перевірка через `./scripts/db.ps1 run db/demo/05_programmability_demo.sql`.
7. Індекси в `db/03_indexes.sql`, а `db/demo/06_indexes_demo.sql` показує їхні EXPLAIN-плани на великому обсязі даних.
8. Repository і Unit of Work у `src/University.Data` (читання через view з `db/04_app_api.sql`, запис через процедури), консольне демо в `src/University.Demo`.
