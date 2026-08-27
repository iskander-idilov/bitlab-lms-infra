# Bitlab LMS — Infrastructure

Инфраструктурный репозиторий платформы Bitlab LMS. Отвечает за оркестрацию локального окружения — поднимает через Docker Compose все инфраструктурные компоненты, которые используются сервисами платформы (`main-service`, а в будущем `user-service`, `file-service`).

## Содержание

- [Сервисы](#сервисы)
- [Быстрый старт](#быстрый-старт)
- [Переменные окружения](#переменные-окружения)
- [Keycloak](#keycloak)
- [⚠️ Известная проблема: после запуска всё падает / HTTPS required](#известная-проблема-после-запуска-всё-падает--https-required)

## Сервисы

| Сервис | Назначение | Порт (хост) |
|---|---|---|
| `postgres` (`lms-db`) | БД для `main-service` — курсы, главы, уроки | `5432` |
| `keycloak-db` | БД для Keycloak — пользователи, роли, клиенты | не проброшен наружу |
| `keycloak` | Identity and Access Management (аутентификация/авторизация) | `8081` |

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
```

Проверить, что всё поднялось:
```bash
docker ps
```
Ожидается три контейнера: `lms-db`, `keycloak-db`, `keycloak` — все в статусе `Up`.

### Остановка

```bash
docker compose down
```
Данные в volume сохранятся. Если нужно **полностью** сбросить состояние (включая Keycloak realm) — добавь `-v`:
```bash
docker compose down -v --remove-orphans
```
⚠️ После `-v` нужно **заново** пройти шаг 3 (см. ниже) — фикс `master` realm не переживает сброс volume.

## Переменные окружения

| Переменная | Описание |
|---|---|
| `DB_PASSWORD` | Пароль для `lms-db` (используется `main-service`) |
| `KEYCLOAK_DB_PASSWORD` | Пароль для БД Keycloak |
| `KC_BOOTSTRAP_ADMIN_USERNAME` | Логин администратора Keycloak (создаётся при первом запуске) |
| `KC_BOOTSTRAP_ADMIN_PASSWORD` | Пароль администратора Keycloak |
| `KEYCLOAK_CLIENT_SECRET` | Секрет OAuth2-клиента `main-service` в Keycloak |
| `TEST_STUDENT_PASSWORD` | Пароль тестового пользователя `test.student` (роль `STUDENT`) |

Реальные значения — только в `.env` (не коммитится, см. `.gitignore`).

## Keycloak

### Конфигурация — декларативная, через JSON

Realm, роли (`STUDENT`, `INSTRUCTOR`, `ADMIN`), client (`main-service`) и тестовый пользователь (`test.student`) описаны в `bitlab-lms-realm.template.json` и импортируются **автоматически** при первом старте контейнера (`--import-realm`). Не нужно ничего настраивать руками через UI — весь realm создаётся из файла.

`bitlab-lms-realm.template.json` коммитится в репозиторий (содержит только плейсхолдеры `${...}`, не реальные секреты). `bitlab-lms-realm.json` — сгенерированный файл с реальными значениями, в `.gitignore`, генерируется командой `envsubst` (см. "Быстрый старт").

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
username=test.student
password=<TEST_STUDENT_PASSWORD>
```
Ответ содержит `access_token` (живёт 5 минут) и `refresh_token`. Используй `access_token` в заголовке `Authorization: Bearer <token>` при запросах к `main-service`.

### Режим запуска

Keycloak поднят в режиме `start-dev` — без строгих проверок и без HTTPS. **Не использовать в продакшене** в таком виде.

### База данных

Keycloak хранит пользователей, роли, реалмы и клиентов в собственной, отдельной БД (`keycloak-db`) — не связана с `lms-db` (принцип database-per-service).

## ⚠️ Известная проблема: после запуска всё падает / "HTTPS required"

**Симптом:** после `docker compose up -d` (особенно после `down -v`, то есть "с нуля") — заход в `http://localhost:8081` показывает страницу **"We are sorry... HTTPS required"** вместо экрана логина. Запросы на получение токена (`POST /realms/bitlab-lms/protocol/openid-connect/token`) тоже отваливаются с `{"error":"invalid_request","error_description":"HTTPS required"}`.

**Причина:** Keycloak по умолчанию требует HTTPS для запросов, которые он считает "внешними" (не с `127.0.0.1`) — в некоторых локальных сетевых конфигурациях он ошибочно относит даже `localhost`-запросы к этой категории. Это относится конкретно к **`master`** realm (наш `bitlab-lms` realm уже настроен с `sslRequired: none` через JSON — но `master` управляется отдельно и пересоздаётся с дефолтными настройками при каждом `down -v`).

**Обязательный фикс — выполнять после каждого `docker compose down -v`:**

```bash
docker exec -it keycloak bash

/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password <KC_BOOTSTRAP_ADMIN_PASSWORD>

/opt/keycloak/bin/kcadm.sh update realms/master -s sslRequired=NONE

exit
```

После этого `http://localhost:8081` и запросы на получение токена должны работать нормально.

**Важно:** если ты не сносил volume (`docker compose down` **без** `-v`), этот фикс сохраняется между перезапусками — повторять не нужно.