-- ============================================
-- insert.sql
-- Начальные данные для Keycloak: роли и админы
-- Выполняется автоматически при первом старте
-- keycloak-db (через docker-entrypoint-initdb.d)
-- ============================================

-- 1. Роли (ROLE_ADMIN уже создана через JSON-импорт realm — не дублируем)
INSERT INTO keycloak_role (id, client_role, description, name, realm_id, realm)
SELECT
    gen_random_uuid()::text,
    false,
    'Teacher role',
    'ROLE_TEACHER',
    r.id,
    r.id
FROM realm r
WHERE r.name = 'bitlab-lms';

INSERT INTO keycloak_role (id, client_role, description, name, realm_id, realm)
SELECT
    gen_random_uuid()::text,
    false,
    'Regular user role',
    'ROLE_USER',
    r.id,
    r.id
FROM realm r
WHERE r.name = 'bitlab-lms';

-- 2. Пользователи-администраторы (пароли задаются вручную через Keycloak UI)
INSERT INTO user_entity (id, email, email_verified, enabled, realm_id, username, first_name, last_name, created_timestamp, not_before)
SELECT
    gen_random_uuid()::text,
    'admin1@mail.ru',
    true,
    true,
    r.id,
    'admin1',
    'Admin',
    'One',
    extract(epoch from now()) * 1000,
    0
FROM realm r
WHERE r.name = 'bitlab-lms';

INSERT INTO user_entity (id, email, email_verified, enabled, realm_id, username, first_name, last_name, created_timestamp, not_before)
SELECT
    gen_random_uuid()::text,
    'admin2@mail.ru',
    true,
    true,
    r.id,
    'admin2',
    'Admin',
    'Two',
    extract(epoch from now()) * 1000,
    0
FROM realm r
WHERE r.name = 'bitlab-lms';

-- 3. Назначение роли ROLE_ADMIN обоим администраторам
INSERT INTO user_role_mapping (role_id, user_id)
SELECT
    kr.id,
    ue.id
FROM keycloak_role kr, user_entity ue, realm r
WHERE kr.name = 'ROLE_ADMIN'
  AND kr.realm_id = r.id
  AND ue.realm_id = r.id
  AND r.name = 'bitlab-lms'
  AND ue.username IN ('admin1', 'admin2');