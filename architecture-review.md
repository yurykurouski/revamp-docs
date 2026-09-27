# Архитектурный обзор монорепозитория Revamp-dev (REV-48)

**Дата:** 27.09.2026 · **Состояние кода:** `main` после REV-54 (коммит `93497f3`) · **Тикет:** [REV-48](https://linear.app/revamp-proect/issue/REV-48)

Обзор охватывает `apps/api`, `apps/workers`, `apps/dashboard`, `packages/shared-types`, `packages/validation` и сверку с [`blueprint.md`](./blueprint.md) и [`spec.md`](./spec.md). На каждую находку, требующую действия, заведен отдельный тикет. Самая важная структурная находка (дублирование схем Mongoose) исправлена в рамках REV-48 без изменения поведения.

---

## 1. Итоги

| # | Находка | Влияние | Трудоемкость | Тикет |
|---|---|---|---|---|
| 1 | Схемы Mongoose и `QUEUE_NAMES` продублированы в API и воркерах, копии разошлись (в API нет `cookieBannerHandled` из REV-33) | Высокое | M | **Исправлено в REV-48** (`@revamp/db`) |
| 2 | `POST /outreach/:id/approve` и `/reject` не проверяют статус лида: можно одобрить лид без MVP или повторно отправить письмо | Высокое | S | **Исправлено в [REV-59](https://linear.app/revamp-proect/issue/REV-59)** |
| 3 | `POST /outreach/:id/test` отвечает «письмо отправлено», ничего не отправляя (нарушение REV-45) | Высокое | M | [REV-60](https://linear.app/revamp-proect/issue/REV-60) |
| 4 | Отправка письма неидемпотентна при ретраях; воркер и API подставляют текст письма, который оператор не видел | Среднее | M | [REV-61](https://linear.app/revamp-proect/issue/REV-61) |
| 5 | Правила переходов статусов лида разбросаны по 7 местам; 7 из 19 значений `LeadStatus` никогда не записываются; `SENT` в коде против `DISPATCHED` в spec | Среднее | M | [REV-62](https://linear.app/revamp-proect/issue/REV-62) |
| 6 | Четыре разных формата ошибок API; документирован только один | Среднее | M | [REV-63](https://linear.app/revamp-proect/issue/REV-63) |
| 7 | `/health` отвечает 200 при недоступных MongoDB/Redis; при остановке API Redis и очереди не закрываются | Среднее | S | [REV-66](https://linear.app/revamp-proect/issue/REV-66) |
| 8 | Бизнес-логика `audit`, `mvp`, `outreach` живет прямо в файлах маршрутов | Низкое | M | [REV-64](https://linear.app/revamp-proect/issue/REV-64) |
| 9 | `PATCH /mvp/:id/tokens` отвечает 200 для несуществующего MVP | Низкое | S | [REV-65](https://linear.app/revamp-proect/issue/REV-65) |
| 10 | Клиент дашборда заново объявляет DTO, читает устаревшие поля, генерирует случайный id | Низкое | M | [REV-67](https://linear.app/revamp-proect/issue/REV-67) |
| 11 | Две разошедшиеся копии `findGenerationAudit` (REV-55) | Низкое | S | [REV-68](https://linear.app/revamp-proect/issue/REV-68) |
| 12 | `ai-gen-queue` объявлена в API и воркерах с разными ретраями | Низкое | S | [REV-70](https://linear.app/revamp-proect/issue/REV-70) |
| 13 | Нет компонентных тестов основных экранов дашборда | Низкое | L | [REV-69](https://linear.app/revamp-proect/issue/REV-69) |

Порядок работ: сначала REV-59, REV-60, REV-61 (HITL и отсутствие выдуманных результатов), затем REV-62 и REV-63 (они меняют контракты, от которых зависит REV-64), остальное — по мере возможности. Уже известные нестабильные тесты: REV-42, REV-57.

---

## 2. Соответствие `blueprint.md` / `spec.md`

* **Очереди.** Пять очередей (`discovery`, `audit`, `ai-gen`, `deploy`, `email`), их конкурентность и лимитер email (1 письмо / 180 с) соответствуют §6. Расхождение: опции ретраев `ai-gen-queue` у продюсера API (откат 3 с) и воркеров (5 с) → REV-70.
* **Схемы Mongoose.** Поля соответствуют §4. До REV-48 у API была устаревшая копия схемы `Audit` (без `cookieBannerHandled`); теперь схема одна.
* **Статусы лида.** Жизненный цикл в spec (`… APPROVED ➔ DISPATCHED ➔ OPENED …`) не совпадает с кодом: одобрение пишет `SCHEDULED`, отправка — `SENT`; `PENDING`, `MVP_READY`, `AWAITING_APPROVAL`, `APPROVED`, `DISPATCHED`, `UNSUBSCRIBED`, `REPLIED` никогда не записываются → REV-62.
* **API и DTO.** Все эндпоинты §5 реализованы, тела запросов валидируются Zod. Расхождение: формат ошибок `{ success: false, error: { code, message } }` используют только маршруты outreach → REV-63. `POST /outreach/:id/test` описан как отправка, но ничего не отправляет → REV-60.
* **Агенты LLM.** `DesignCritiqueAgent` и `MvpContentAgent` реализованы. `OutreachPersonalizerAgent` из `AGENTS.md` не реализован: письмо собирает детерминированный шаблон дашборда (`utils/emailTemplate.ts`), а `EmailDraftOutputSchema` используется только в тестах. Это осознанное упрощение, а не ошибка; при реализации агента схема уже готова.

## 3. Границы модулей и слои

* **API.** Слои routes → controllers → services → models соблюдены только для `/leads` и `/discovery`. В `audit.routes.ts`, `mvp.routes.ts`, `outreach.routes.ts` маршруты сами читают модели, меняют статус и ставят задачи → REV-64. `AppError` + `errorHandler` централизованы, но маршруты outreach формируют ответы об ошибках сами → REV-63.
* **Воркеры.** Хорошее разделение: `workers/*.worker.ts` оркеструют, `services/*` содержат логику (браузер, извлечение, LLM, хранилище, шаблоны). Обработка финального сбоя вынесена в `audit-failure.ts` и `generation-failure.ts`.
* **Общие пакеты.** `shared-types` (интерфейсы, каталоги, константы) и `validation` (Zod, чистые функции идентичности лида, режим генерации) разделены правильно. Новый пакет `@revamp/db` добавляет третий уровень — схемы Mongoose для обоих серверных приложений; дашборд от него не зависит.

## 4. Дублирование типов и логики

* **Исправлено:** модели `Lead`, `Audit`, `MvpProject`, `EmailCampaign`, `AnalyticsEvent` (≈ 640 строк × 2) и `QUEUE_NAMES`.
* **Осталось:** `findGenerationAudit` (REV-68), объявления очередей (REV-70), подключение Redis (`queues/connection.ts` в обоих приложениях совпадает, но зависит от env каждого приложения — оставлено как есть), DTO в клиенте дашборда (REV-67), списки статусов (REV-62).

## 5. Покрытие Zod

* **HTTP.** Все тела `POST`/`PATCH` и query `GET /leads`, `/discovery/reverse-geocode` проходят `validateBody` / `validateQuery`. Параметры пути (`:id`) проверяются вручную (`isValidObjectId`) или ловятся `CastError` → 400; это приемлемо.
* **LLM.** Ответы Vision-критики (`DesignCritiqueOutputSchema`), копирайта MVP (`MvpContentOutputSchema`) и судьи полноты (`CompletenessJudgeOutputSchema`) валидируются до сохранения; отчет полноты и данные шаблона (`BentoTemplateDataSchema`) — тоже.
* **Внешние данные.** Кандидаты discovery валидируются `DiscoveredBusinessSchema`; env обоих приложений — Zod-схемой при старте.

## 6. Жизненный цикл ресурсов и ретраи

* **Playwright.** Отдельный контекст на задачу, закрытие в `finally`, перезапуск браузера каждые 20 задач, закрытие браузера при остановке воркеров — соответствует NFR.
* **BullMQ.** Ретраи с экспоненциальным откатом, `UnrecoverableError` для постоянных ошибок аудита и конфигурации discovery, финальные обработчики сбоя возвращают лид из `AUDITING`/`GENERATING`. Риск — повторная отправка письма при ретрае → REV-61.
* **Подключения.** Воркеры при остановке закрывают все воркеры, браузер, Redis и MongoDB. API закрывает только HTTP-сервер и MongoDB → REV-66. `/health` не отражает реальное состояние зависимостей → REV-66.

## 7. Дашборд

* **Структура.** `api/client.ts` (fetch + маппинг), хуки React Query (`useLeads`, `useDiscovery`), 7 небольших Zustand-сторов по одной ответственности, компоненты, одна страница. Сторы и хуки покрыты тестами.
* **i18n.** 5 словарей типизированы по `Translation` из `en.ts`, отсутствующий ключ ломает сборку; есть тест словарей. Замечаний нет.
* **Замечания.** Клиент дублирует типы сервера и сохраняет устаревшие поля (REV-67). Крупные компоненты (`SideBySideInspectorModal` — 790 строк, `EmailDraftEditor`, `KanbanBoard`) не покрыты тестами (REV-69). Визуальный редизайн — отдельный тикет REV-49.

## 8. Соблюдение HITL

* Ни один воркер не ставит задачи в `email-queue`; ее наполняет только `POST /outreach/:id/approve`. Воркер отправки дополнительно проверяет статус `SCHEDULED`/`APPROVED`. Конвейер генерации останавливается на `NEEDS_APPROVAL`.
* **Слабые места:** одобрение не проверяет исходный статус (REV-59), ретраи могут отправить письмо дважды, а воркер может отправить текст по умолчанию, который оператор не видел (REV-61). Формально действие оператора обязательно, но содержание и момент отправки не полностью под его контролем — поэтому это находки высокого приоритета.

## 9. Пробелы в тестах

* 77 файлов, 1132 теста; зеленые, кроме известных нестабильных REV-42 и REV-57.
* API: маршруты покрыты интеграционными тестами Supertest (`api.routes.spec.ts`), но случаи недопустимого статуса для outreach добавлены в REV-59.
* Воркеры: все воркеры и сервисы имеют тесты, включая сквозной прогон на 20 сайтах.
* Дашборд: сторы, хуки, утилиты, клиент — да; большинство компонентов — нет (REV-69).
* После REV-48: тест `packages/db/__tests__/shared-models.spec.ts` проверяет, что оба приложения получают одни и те же модели и имена очередей.

---

## 10. Выполненный рефакторинг (REV-48)

**`@revamp/db` (`packages/db`)** — единственное место определения схем Mongoose:

```
packages/db/
├── src/models/{Lead,Audit,MvpProject,EmailCampaign,AnalyticsEvent}.model.ts
├── src/index.ts
└── __tests__/{models,shared-models}.spec.ts
```

* За основу взяты схемы воркеров (надмножество): API получил `Audit.cookieBannerHandled`. Данные в MongoDB не меняются.
* `apps/api/src/models/*.model.ts` и `apps/workers/src/models/*.model.ts` стали однострочными реэкспортами, поэтому импорты и `vi.mock(...)` в тестах не изменились — это подтверждает, что поведение сохранено (все существующие тесты проходят без правок).
* `QUEUE_NAMES` перенесены в `@revamp/shared-types`; `queues/queue.constants.ts` в обоих приложениях реэкспортирует их.
* `npm run build:packages` собирает `shared-types` → `validation` → `db`; Dockerfile API и воркеров копируют и собирают `packages/db`.
* Решение зафиксировано в [`research.md`](./research.md), ADR 10.
