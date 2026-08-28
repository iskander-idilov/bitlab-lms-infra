# Bitlab LMS — Infrastructure

Инфраструктурный репозиторий платформы Bitlab LMS. Отвечает за оркестрацию локального окружения — поднимает через Docker Compose все инфраструктурные компоненты, которые используются сервисами платформы (`main-service`, а в будущем `user-service`, `file-service`).

## Содержание

- [Сервисы](#сервисы)
- [Быстрый старт](#быстрый-старт)
- [Переменные окружения](#переменные-окружения)
- [Keycloak](#keycloak)
- [Seed-данные (роли и администраторы)](#seed-данные-роли-и-администраторы)
- [⚠️ Известная проблема: после запуска всё падает / HTTPS required](#известная-проблема-после-запуска-всё-падает--https-required)

## Сервисы

| Сервис | Назначение | Порт (хост) |
|---|---|---|
| `postgres` (`lms-db`) | БД для `main-service` — курсы, главы, уроки | `5432` |
| `keycloak-db` | БД для Keycloak — пользователи, роли, клиенты | не проброшен наружу |
| `keycloak` | Identity and Access Management (аутентификация/авторизация) | `8081` |
| `keycloak-seed-data` | Одноразовый сервис — заполняет `keycloak-db` начальными данными (роли, админы) после старта Keycloak; завершается после выполнения | — |

## Быстрый старт

### Требования

- Docker и Docker Compose
- `envsubst` (обычно уже есть на macOS/Linux)

### Настройка окружения

Создай файл `.env` в корне репозитория:

```
DB_PASSWORD=...

KEYCLOAK_DB_PASSWORD=...
KC_BOOTSTRAP_ADMIN_USERNAME=...
KC_BOOTSTRAP_ADMIN_PASSWORD=...
KEYCLOAK_CLIENT_SECRET=...
TEST_STUDENT_PASSWORD=...
```

### Запуск (полная последовательность — читай до конца перед первым запуском)

```bash
# 1. Сгенерировать realm-конфиг из шаблона (подставит секреты из .env)
export $(grep -v '^#' .env | xargs) && envsubst < bitlab-lms-realm.template.json > bitlab-lms-realm.json

# 2. Поднять все сервисы
docker compose up -d

# 3. ОБЯЗАТЕЛЬНО: см. раздел "Известная проблема" ниже — без этого шага
#    Keycloak откажет в логине с ошибкой "HTTPS required"

# 4. ОБЯЗАТЕЛЬНО: задать пароли admin1 / admin2 вручную через UI
#    (см. раздел "Seed-данные" ниже — пароли не создаются автоматически)
```

Проверить, что всё поднялось:
```bash
docker ps
```
Ожидается контейнеры `lms-db`, `keycloak-db`, `keycloak` в статусе `Up`. `keycloak-seed-data` завершится и перейдёт в статус `Exited (0)` — это нормально, он одноразовый.

Проверить, что seed-данные применились:
```bash
docker logs keycloak-seed-data
```
Ожидается несколько строк `Still waiting...` (пока Keycloak не создал таблицы и realm), затем `Realm found, running insert.sql...` и пять строк `INSERT 0 N`.

### Остановка

```bash
docker compose down
```
Данные в volume сохранятся. Если нужно **полностью** сбросить состояние — добавь `-v`:
```bash
docker compose down -v --remove-orphans
```
⚠️ После `-v` нужно **заново** пройти шаги 3 и 4 из "Быстрого старта" — фикс `master` realm и пароли `admin1`/`admin2` не переживают сброс volume.

## Переменные окружения

| Переменная | Описание |
|---|---|
| `DB_PASSWORD` | Пароль для `lms-db` (используется `main-service`) |
| `KEYCLOAK_DB_PASSWORD` | Пароль для БД Keycloak |
| `KC_BOOTSTRAP_ADMIN_USERNAME` | Логин администратора Keycloak (создаётся при первом запуске) |
| `KC_BOOTSTRAP_ADMIN_PASSWORD` | Пароль администратора Keycloak |
| `KEYCLOAK_CLIENT_SECRET` | Секрет OAuth2-клиента `main-service` в Keycloak |
| `TEST_STUDENT_PASSWORD` | Пароль тестового пользователя `test.student` (роль `ROLE_STUDENT`) |

Реальные значения — только в `.env` (не коммитится, см. `.gitignore`).

## Keycloak

### Конфигурация — декларативная, через JSON

Realm, роли (`ROLE_STUDENT`, `ROLE_INSTRUCTOR`, `ROLE_ADMIN`), client (`main-service`) и тестовый пользователь (`test.student`) описаны в `bitlab-lms-realm.template.json` и импортируются **автоматически** при первом старте контейнера (`--import-realm`).

`bitlab-lms-realm.template.json` коммитится в репозиторий (содержит только плейсхолдеры `${...}`). `bitlab-lms-realm.json` — сгенерированный файл с реальными значениями, в `.gitignore`.

### Именование ролей

Все роли называются с префиксом `ROLE_` (`ROLE_STUDENT`, `ROLE_ADMIN` и т.д.) — единый стиль для всей системы. `main-service` (в `SecurityConfig`/`JwtAuthenticationConverter`) читает роль из `realm_access.roles` токена **без** добавления префикса — он уже есть в самом имени роли.

### Admin-консоль

```
http://localhost:8081
```
Логин/пароль — значения `KC_BOOTSTRAP_ADMIN_USERNAME` / `KC_BOOTSTRAP_ADMIN_PASSWORD` из `.env`.

### Получение JWT-токена для тестирования (Postman/curl)

```
POST http://localhost:8081/realms/bitlab-lms/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=password
client_id=main-service
client_secret=<KEYCLOAK_CLIENT_SECRET>
username=test.student  (или admin1 / admin2)
password=<пароль>
```
Ответ содержит `access_token` (живёт 5 минут) и `refresh_token`.

### Режим запуска

Keycloak поднят в режиме `start-dev` — без строгих проверок и без HTTPS. **Не использовать в продакшене** в таком виде.

### База данных

Keycloak хранит пользователей, роли, реалмы и клиентов в собственной, отдельной БД (`keycloak-db`) — не связана с `lms-db` (принцип database-per-service). Это же значит, что `main-service` **не может** использовать свой Liquibase для управления данными Keycloak — отсюда отдельный механизм ниже.

## Seed-данные (роли и администраторы)

Помимо того, что создаётся через JSON-импорт realm, часть данных добавляется **напрямую SQL-запросами** в `insert.sql` — это осознанное учебное решение (в реальном продакшене для Keycloak предпочтительнее декларативные механизмы: Admin API, Terraform, `keycloak-config-cli`; прямые INSERT в служебную БД стороннего приложения — не рекомендуемая практика, схема таблиц Keycloak официально не документирована как стабильный контракт).

### Что создаёт `insert.sql`

- Роли: `ROLE_TEACHER`, `ROLE_USER` (`ROLE_ADMIN` уже создана через JSON — не дублируется)
- Пользователи: `admin1` (admin1@mail.ru), `admin2` (admin2@mail.ru) — оба с ролью `ROLE_ADMIN`

### Пароли для `admin1` / `admin2` — задаются вручную

**Важно:** `insert.sql` создаёт учётные записи **без пароля** — прямая генерация хеша пароля через SQL слишком рискованна (нужно точно повторить алгоритм хеширования Keycloak — Argon2/PBKDF2 с солью — иначе логин не сработает).

После каждого запуска "с нуля" (`docker compose down -v` + `up`):
1. Зайди в Keycloak UI → realm `bitlab-lms` → **Users**
2. Открой `admin1` → **Credentials** → **Set password**
3. Задай пароль, **Temporary: Off** (иначе Keycloak потребует смену пароля при первом входе, что сломает `grant_type=password`)
4. Повтори для `admin2`

### Как это работает автоматически (`keycloak-seed-data`)

`insert.sql` **зависит** от того, что Keycloak уже создал таблицы и realm `bitlab-lms` — а это происходит **позже**, чем стартует сама БД `keycloak-db`. Обычный механизм `docker-entrypoint-initdb.d` тут не подходит (он выполняется до того, как Keycloak вообще запустился).

Решение — отдельный сервис `keycloak-seed-data` (на основе образа `postgres:16`, используется только ради `psql`), который **сам, циклически** проверяет наличие realm `bitlab-lms` в БД и, как только он появляется, выполняет `insert.sql`:

```yaml
keycloak-seed-data:
  image: postgres:16
  depends_on:
    - keycloak
  volumes:
    - ./insert.sql:/insert.sql
  entrypoint: >
    sh -c "
    until psql -h keycloak-db -U keycloak_user -d keycloak -c \"SELECT 1 FROM realm WHERE name = 'bitlab-lms'\" | grep -q '1 row'; do
      sleep 3;
    done;
    psql -h keycloak-db -U keycloak_user -d keycloak -f /insert.sql
    "
```

Сервис завершает работу после успешного выполнения SQL (статус `Exited (0)` в `docker ps` — это ожидаемо, не ошибка).

## ⚠️ Известная проблема: после запуска всё падает / "HTTPS required"

**Симптом:** после `docker compose up -d` (особенно после `down -v`) — заход в `http://localhost:8081` показывает страницу **"We are sorry... HTTPS required"** вместо экрана логина. Запросы на получение токена тоже отваливаются с `{"error":"invalid_request","error_description":"HTTPS required"}`.

**Причина:** Keycloak по умолчанию требует HTTPS для запросов, которые он считает "внешними" — в некоторых локальных сетевых конфигурациях он ошибочно относит к этой категории даже `localhost`-запросы. Это относится конкретно к **`master`** realm (наш `bitlab-lms` уже настроен с `sslRequired: none` через JSON — но `master` управляется отдельно и пересоздаётся с дефолтными настройками при каждом `down -v`).

**Обязательный фикс — выполнять после каждого `docker compose down -v`:**

```bash
docker exec -it keycloak bash

/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password <KC_BOOTSTRAP_ADMIN_PASSWORD>

/opt/keycloak/bin/kcadm.sh update realms/master -s sslRequired=NONE

exit
```

После этого `http://localhost:8081` и запросы на получение токена должны работать нормально.

**Важно:** если ты не сносил volume (`docker compose down` **без** `-v`), этот фикс сохраняется между перезапусками — повторять не нужно.