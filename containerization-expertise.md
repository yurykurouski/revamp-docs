# Containerization expertise: Revamp — контейнеризация

22 ноября 2026

Документ для экспертной оценки критерия **Containerization** (`04e-infrastructure/containerization.md`). Состояние на `main` (`ece9e8f`); цифры измерены локально командой `docker build` (Docker 29.7.2, холодная сборка с кэшем базовых образов). Закрытие пробелов ведётся тикетами REV-217…220; после их закрытия раздел 7 нужно перемерить.

## 1. Что есть

| Артефакт | Файл | Назначение |
| --- | --- | --- |
| Dockerfile API | `apps/api/Dockerfile` | Multi-stage, `node:22-alpine`, `npm prune --production`, `USER node`, `HEALTHCHECK` |
| Dockerfile workers | `apps/workers/Dockerfile` | Multi-stage, финальный слой `mcr.microsoft.com/playwright:v1.49.0-noble` (Chromium для аудита) |
| Dockerfile dashboard | `apps/dashboard/Dockerfile` | Сборка Vite, раздача `nginx:1.27-alpine`, `HEALTHCHECK` |
| Compose для разработки | `docker-compose.yml` | MongoDB 7.0 (replica set, ключ в томе), Redis 7.0, MinIO + `minio-init`; тома, healthcheck, `restart` |
| Compose для продакшена | `docker-compose.prod.yml` | api, workers, dashboard, nginx (TLS), certbot; сеть `revamp-prod-net`; БД, очередь и хранилище — управляемые облачные сервисы |
| Скрипт развёртывания | `deploy/deploy.sh` | Проверки, сборка, запуск, проба `/api/v1/health` |
| CI | `.github/workflows/ci.yml` | Сборка образов и деплой после зелёных проверок (REV-177) |
| Переменные | `.env.example`, `.env.production.example` | Образцы значений без секретов |

## 2. Размеры и время

| Образ | До (22.11) | После REV-217 | Лимит критерия | Пользователь после |
| --- | --- | --- | --- | --- |
| api | 198 MB, 60 с | 192 MB, 22 с | < 1 GB | `node` (1000) |
| dashboard | 57.6 MB, 64 с (root) | 57.6 MB, 29 с | < 500 MB | `nginx` (101), порт 8080 |
| workers | **3.27 GB**, 100 с (root) | **958 MB**, 90 с | < 1 GB | `node` (1000) |

Время — холодная сборка с кэшем базовых образов на загруженной машине (load average 14–50), поэтому цифры ориентировочные. Workers: `node:22-bookworm-slim` + один headless-shell Chromium версии установленного Playwright (раньше — образ Playwright 1.49 и вторая установка браузера для 1.63). Проверено в образе под пользователем `node`: Chromium запускается с флагами приложения и делает снимок, `sharp` загружается, healthcheck (файл heartbeat, `apps/workers/src/services/heartbeat.ts`) проходит со свежим файлом и падает без него.

## 3. Соответствие минимальным требованиям (оценка 5)

| Требование | Статус | Комментарий |
| --- | --- | --- |
| Отдельный Dockerfile на сервис | Есть | три приложения; БД, Redis, MinIO — официальные образы |
| Порядок слоёв | Есть | сначала `package*.json` и `npm ci`, затем исходники |
| `.dockerignore` | Есть (REV-217) | корневой файл исключает `node_modules`, `dist`, `.git`, `.env*`, тесты, документы; тест в `deployment.spec.ts` |
| ENV вместо хардкода | Есть (REV-218) | приложения читают `.env`; MinIO в dev-файле берёт `S3_ACCESS_KEY`/`S3_SECRET_KEY` из `.env`, в `docker-compose.full.yml` все секреты обязательны (`:?`), без значений по умолчанию |
| Тома для данных | Есть | `mongo_data`, `mongo_config`, `redis_data`, `minio_data`, тома certbot |
| EXPOSE | Частично | есть у api (4000) и dashboard (80), нет у workers (порта нет — допустимо, но не указано) |
| Размер образов | Есть (REV-217) | workers 958 MB при лимите 1 GB, запас небольшой |
| Очистка кэша, без лишних инструментов | Есть (REV-217) | `curl` убран из API (healthcheck на Node), Chromium ставится один раз, apt-списки удаляются в том же слое |
| Multi-stage | Есть | во всех трёх |
| Нет секретов в образах | Есть | секреты — только через `env_file` / `.env` (не в git) |
| Non-root | Есть (REV-217) | api и workers — `node`, dashboard — `nginx` (unprivileged, порт 8080) |
| Версии образов, не `latest` | Есть (REV-217) | MinIO и mc закреплены по digest, certbot `v5.10.0`, свои образы `revamp-<app>:<коммит>` через `IMAGE_TAG` в `deploy.sh`; тест запрещает `latest` |
| `docker-compose.yml`, всё поднимается одной командой | Есть (REV-218) | `docker-compose.full.yml` (проект `revamp-stack`): mongo, mongo-init, redis, minio, minio-init, api, workers, dashboard; `npm run stack:up` |
| `depends_on` | Есть | `workers` ждёт здоровый `api`, `minio-init` ждёт `minio` |
| Изолированные сети | Есть (REV-218) | `frontend` (dashboard, api) и `backend` (api, workers, mongo, redis, minio); БД без портов на хосте, api и dashboard — только на 127.0.0.1; dev-файл с открытыми портами остаётся для `npm run dev` |
| Тома для БД и загрузок | Есть | |
| `.env` и `.env.example` | Есть | |
| README: запуск | Есть | `npm run setup`, `npm run dev`, `docker:up` |
| Описание образов, таблица ENV, диаграмма, ресурсы | Есть (REV-219) | раздел «Containers» в README репозитория: диаграмма Mermaid, таблицы образов и контейнеров, таблица всех переменных окружения (тест `deploy/__tests__/container-docs.spec.ts` падает при расхождении с `.env.example`, `.env.production.example` и полным стеком), ресурсы, кэш слоёв, `npm run docker:prune`. Не измерено: память и CPU во время аудита |

## 4. Максимальные требования (оценка 10)

| Пункт | Статус |
| --- | --- |
| Healthcheck у каждого контейнера | Почти: mongo, redis, minio, api, dashboard, workers (REV-217) есть; nginx, certbot — нет |
| Лимиты ресурсов | Есть в `docker-compose.full.yml` (REV-218): api 512 MB/1 CPU, workers 2 GB/2, dashboard 128 MB/0.5, mongo 1 GB/1, minio 512 MB/0.5, redis 256 MB/0.5; в prod-файле — только workers |
| Graceful shutdown | **Есть:** API (`apps/api/src/shutdown.ts`, лимит 8 с под 10 с Docker, закрывает сервер, очереди, Redis, MongoDB, тесты) и workers (`SIGINT`/`SIGTERM`) |
| Автоперезапуск | Есть: `restart: always` / `unless-stopped` |
| JSON-логи | Нет: `console.*`; зато логи пишутся в stdout и ротируются драйвером `json-file` (20 MB × 5) |
| Alpine/distroless | Частично: api и dashboard на Alpine, workers нужен glibc и Chromium |
| Кастомный базовый образ, условное кэширование, очистка старых образов | Нет (кэш слоёв по порядку `COPY` есть, но не описан) |
| Compose для dev/test/prod, override | Частично: dev-файл и prod-файл есть, override нет |
| Secrets (Docker secrets / vault) | Нет: `env_file` |
| Network policies | Частично: prod-сеть изолирована, `expose` вместо `ports` для api и dashboard |
| Prometheus, централизованные логи, debug-режим | Нет → REV-220 |

## 5. Известные риски

* Dev-файл `docker-compose.yml` без обёртки `npm run docker:up` оставляет MongoDB без пользователей и replica set (README, AGENTS.md); полный стек `docker-compose.full.yml` делает это init-сервисом `mongo-init`.
* В полном стеке ссылки предпросмотра MVP используют адрес MinIO внутри сети (`http://minio:9000`) и недоступны из браузера без публичного `S3_ENDPOINT`.
* В prod-файле нет Mongo/Redis/MinIO: управляемые сервисы (Atlas, Upstash, R2) — осознанный выбор, но на защите нужно показать и полный локальный стек.
* `OPERATOR_NOTIFY_EMAIL` и `TRACKING_BASE_URL` есть в шаблонах окружения, но код их не читает (отмечено в таблице README).
* Продакшен-сервера нет (REV-211): деплой собирает образы, но SSH-шаг пропускается.

## 6. План закрытия

| Тикет | Что закрывает | Влияние на оценку |
| --- | --- | --- |
| REV-217 (сделано, PR #138) | `.dockerignore`, non-root, workers < 1 GB, healthcheck workers, закреплённые версии | убирает нарушения минимума (критично) |
| REV-218 (сделано, PR #139) | один `npm run stack:up`, сети, секреты из `.env`, лимиты | убирает нарушение минимума |
| REV-219 (сделано, PR #140) | README: образы, ENV, диаграмма, ресурсы, метрики | закрывает пункт документации минимума |
| REV-220 | JSON-логи, `/metrics`, override-файлы, Docker secrets, debug | путь к 8–10 |

## 7. Метрики для защиты

Полный стек (`npm run stack:up`, измерено 22.11.2026): первый запуск с тремя сборками образов при тёплом кэше слоёв — 123 с; запуск с пустых томов при готовых образах — 31 с; в простое все контейнеры вместе около 390 MB (workers 125, mongo 125, minio 73, api 41, dashboard 12, redis 10 MB); остановка workers и api по SIGTERM — код выхода 0 за 0.3 с.

Размеры и время сборки до — в разделе 2. После тикетов добавить: размеры после, холодный старт всего стека, `docker stats` под аудитом (RAM/CPU), повторную сборку без изменений кода (кэш слоёв).
