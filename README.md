# Bitlab LMS — Infrastructure

Инфраструктурный репозиторий платформы Bitlab LMS. Отвечает за оркестрацию локального окружения — поднимает через Docker Compose все инфраструктурные компоненты, которые используются сервисами платформы (`main-service`, а в будущем `user-service`, `file-service`).

## Содержание

- [Сервисы](#сервисы)
- [Быстрый старт](#быстрый-старт)
- [Переменные окружения](#переменные-окружения)
- [Keycloak](#keycloak)
- [Известные проблемы](#известные-проблемы)

## Сервисы

| Сервис | Назначение | Порт (хост) |
|---|---|---|
| `postgres` (`lms-db`) | БД для `main-service` — курсы, главы, уроки | `5432` |
| `keycloak-db` | БД для Keycloak — пользователи, роли, клиенты | не проброшен наружу |
| `keycloak` | Identity and Access Management (аутентификация/авторизация) | `8081` |

## Быстрый старт

### Требования

- Docker и Docker Compose

### Настройка окружения

Создай файл `.env` в корне репозитория со следующими переменными:

```
DB_PASSWORD=...

KEYCLOAK_DB_PASSWORD=...
KC_BOOTSTRAP_ADMIN_USERNAME=...
KC_BOOTSTRAP_ADMIN_PASSWORD=...
```

### Запуск

```bash
docker compose up -d
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
(данные в volume сохранятся; чтобы удалить и данные — добавь флаг `-v`)

## Переменные окружения

| Переменная | Описание |
|---|---|
| `DB_PASSWORD` | Пароль для `lms-db` (используется `main-service`) |
| `KEYCLOAK_DB_PASSWORD` | Пароль для БД Keycloak |
| `KC_BOOTSTRAP_ADMIN_USERNAME` | Логин администратора Keycloak (создаётся при первом запуске) |
| `KC_BOOTSTRAP_ADMIN_PASSWORD` | Пароль администратора Keycloak |

Реальные значения — только в `.env` (не коммитится, см. `.gitignore`).

## Keycloak

### Admin-консоль

После запуска доступна по адресу:
```
http://localhost:8081
```
Логин/пароль — значения `KC_BOOTSTRAP_ADMIN_USERNAME` / `KC_BOOTSTRAP_ADMIN_PASSWORD` из `.env`.

### Режим запуска

Keycloak поднят в режиме `start-dev` — это режим разработки, без строгих проверок и без HTTPS. **Не использовать в продакшене** в таком виде.

### База данных

Keycloak хранит пользователей, роли, реалмы и клиентов в собственной, отдельной БД (`keycloak-db`) — она не связана с `lms-db` (принцип database-per-service).

## Известные проблемы

### "HTTPS required" при первом входе в admin-консоль

Если при заходе на `http://localhost:8081` вместо экрана логина появляется страница **"We are sorry... HTTPS required"** — Keycloak посчитал соединение "внешним" по IP запроса (это может происходить из-за особенностей локальной сети/прокси, даже при обращении с `localhost`).

**Решение** — явно отключить требование SSL для `master` realm через встроенную admin CLI:

```bash
docker exec -it keycloak bash

/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user admin --password <ПАРОЛЬ_АДМИНА>

/opt/keycloak/bin/kcadm.sh update realms/master -s sslRequired=NONE

exit
```

После этого `http://localhost:8081` должен открываться нормально.