# Архитектурный Блюпринт: SaaS-система автоматизированного аудита и редизайна сайтов локального бизнеса (Revamp SaaS)

---

## 1. Введение и концепция системы

### 1.1. Назначение системы
Платформа предназначена для автоматизации B2B-лидогенерации и предпродажной подготовки (cold outreach) для веб-агентств, дизайн-студий и фрилансеров. Система находит или принимает на вход сайты локальных бизнесов (стоматологии, автосервисы, юридические конторы, салоны красоты и др.), выполняет глубокий многоуровневый аудит, автоматически синтезирует современный интерактивный MVP-редизайн с сохранением ДНК исходного бренда и готовит гиперперсонализированное коммерческое предложение с интерактивным демо.

Ключевой дифференциатор: **Human-In-The-Loop (HITL)** — перед отправкой письма оператор видит аудит, скриншоты «до/после», сгенерированный лендинг и персонализированный текст в удобном React/MUI дашборде и может подтвердить отправку или внести правки в один клик.

```mermaid
flowchart LR
    A0[Поиск по картам: OSM / Google Places] -->|Ревью и импорт оператором| A[Лиды]
    A1[Ручной ввод URL] --> A
    A --> B[Агент аудита]
    B -->|Сырые метрики + Скриншоты + Контент сайта| C[Модуль генерации MVP]
    C -->|Готовое демо + Превью| D[React + MUI Дашборд]
    D -->|HITL: Ручной аппрув / Правка| E[Модуль аутрича]
    E -->|Персонализированный email| F[Клиент / Лид]
    F -->|Клик на демо-версию| G[Трекинг активности и конверсий]
    G --> D
```

---

## 2. Общая архитектура и стек технологий

```mermaid
graph TB
    subgraph Frontend [Клиентская часть - React Dashboard]
        UI[React 18/19 + Vite]
        MUI[Material UI v6]
        Router[React Router 6]
        Query[TanStack React Query]
        State[Zustand Store]
    end

    subgraph API [Бэкенд-инфраструктура - Node.js / Express]
        Gateway[Express REST API Gateway]
        Auth[JWT + RBAC Auth Middleware]
        Controllers[API Controllers]
        Queues[BullMQ Job Producers]
    end

    subgraph Workers [Фоновые воркеры / Очереди задач]
        W_Disc[Discovery Worker: OSM Overpass/Nominatim, Google Places]
        W_Audit[Audit Worker: Playwright + Cookie Consent + Axe + Vitals + Site Content]
        W_AI[AI Worker: MvpPageGenerator через LlmClient + checkMvpPage]
        W_Gen[Deploy Worker: finishMvpPage + проверки + S3]
        W_Page[MVP Page Worker: изменение, цвета и шрифты, восстановление]
        W_Mail[Email Worker: SMTP / Resend / DNS Health]
    end

    subgraph Data [Хранилище данных и кэш]
        Mongo[(MongoDB: Atlas / Cluster)]
        Redis[(Redis: BullMQ + LLM capabilities)]
        S3[(S3-compatible Object Storage)]
    end

    subgraph External [Внешние сервисы]
        Maps[OSM Nominatim / Overpass, Google Places API New]
        LLM[Anthropic / OpenAI / Gemini API]
        CLI[Локальный Claude Code CLI на хосте воркеров]
    end

    UI --> Gateway
    Gateway --> Controllers
    Controllers --> Queues
    Queues --> Redis
    Redis --> Workers
    Workers --> Mongo
    Workers --> S3
    Controllers --> Mongo
    W_Disc --> Maps
    W_AI --> LLM
    W_AI --> CLI
    W_Gen --> LLM
    W_Page --> LLM
    Controllers -->|reverse-geocode| Maps
```

> Воркеры раз в 60 секунд публикуют в Redis (`revamp:llm-capabilities`, TTL 180 с) список LLM-провайдеров, которые они могут запустить (есть API-ключ, найден бинарник `claude`). API читает этот ключ для `GET /mvp/providers`, поскольку ключи и CLI живут на хосте воркеров, а не API (REV-32).

### Стек технологий:
* **Backend:** Node.js (v20+ LTS, TypeScript), Express.js.
* **База данных:** MongoDB (Mongoose ODM), реплика-сет, транзакции для операций статусов. Схемы — в общем пакете `@revamp/db`, который используют API и воркеры (REV-48).
* **Очереди и кэш:** Redis (v7+) + BullMQ (для отказоустойчивой асинхронной обработки тяжелых задач браузера и LLM).
* **Headless Browser & Аудит:** Playwright (Chromium), `@axe-core/playwright`, замеры Core Web Vitals в браузере, `happy-dom` для разбора HTML сгенерированного MVP.
* **Поиск бизнесов (Discovery):** OpenStreetMap (Nominatim + Overpass, без ключа, ODbL) и Google Places API (New) Text Search (по ключу).
* **AI & LLM:** единый `LlmClient` для Anthropic, OpenAI, Gemini и локального Claude Code CLI; каталог провайдеров и моделей — в `@revamp/shared-types` (`LLM_PROVIDER_CATALOG`). Оператор выбирает провайдера и модель для каждой генерации MVP. Страницу MVP (HTML и CSS) пишет модель, но контакты подставляет, ответ проверяет и неподтвержденные факты помечает код (REV-135); метрики и контакты LLM не вычисляет.
* **Фронтенд:** React (v18+), TypeScript, Vite, Material UI (MUI v6), TanStack Query, Zustand, i18next (en, ru, be, pl, lt).
* **Email & Deliverability:** Nodemailer / Resend API / SendGrid, DKIM/SPF валидатор, генерация пикселей отслеживания и URL-редиректов.
* **Хостинг MVP-демо:** AWS S3 / Cloudflare R2 + CloudFront / Wildcard-поддомены (`*.preview.revampsaas.io`).

---

## 3. Архитектура и спецификация модулей

---

### Модуль 0: Поиск локальных бизнесов на картах (Discovery) — REV-26…REV-29

Модуль наполняет воронку лидами без ручного ввода URL: оператор задает нишу и локацию, система ищет бизнесы у картографического провайдера, а оператор выбирает, кого импортировать.

```mermaid
sequenceDiagram
    autonumber
    actor Op as Оператор
    participant UI as DiscoveryDrawer (Дашборд)
    participant API as API /discovery
    participant Q as discovery-queue
    participant W as Discovery Worker
    participant P as OSM / Google Places

    Op->>UI: Провайдер, ниша, локация, ключевое слово, лимит
    opt Кнопка «Определить местоположение» (REV-28)
        UI->>API: GET /discovery/reverse-geocode?lat&lng&lang
        API->>P: Nominatim reverse (уровень города)
        API-->>UI: "City, Country"
    end
    UI->>API: POST /discovery (StartDiscoverySchema)
    API->>Q: Задача discovery
    API-->>UI: 202 { jobId }
    Q->>W: runDiscovery()
    W->>P: Поиск (с запасом: часть листингов отсеется)
    W->>W: Нормализация сайта, дедупликация по домену, сверка с лидами
    W-->>Q: { found, candidates[] }
    loop Поллинг
        UI->>API: GET /discovery/:jobId
        API-->>UI: состояние + кандидаты (new-кандидаты перепроверяются по текущим лидам)
    end
    Op->>UI: Выбор кандидатов в таблице ревью (REV-29)
    UI->>API: POST /discovery/:jobId/import { externalIds }
    API->>API: Данные берутся только из сохраненного результата задачи
    API-->>UI: итог по каждому id (imported / existing_lead / not_importable / not_found / failed)
    Note over API: Импортированные лиды создаются в QUEUED и сразу ставятся в audit-queue
```

#### 0.1. Провайдеры
* **OpenStreetMap (по умолчанию, без ключа):** Nominatim превращает локацию в область Overpass (или радиус вокруг точки), Overpass возвращает объекты с тегами ниши (`OSM_NICHE_FILTERS`, например `real_estate` → `office=estate_agent` и `shop=estate_agent`; в Google Places — запрос `real estate agency`, REV-106) и только с сайтом. Запросы идут с идентифицирующим `User-Agent` (`DISCOVERY_USER_AGENT`), как требуют правила Nominatim/Overpass; конкурентность воркера — `1`.
* **Google Places API (New) Text Search (по ключу `GOOGLE_PLACES_API_KEY`):** официальный API вместо парсинга страниц Google Maps (парсинг нарушает ToS). Лимит Google — 20 результатов на страницу, 60 всего.

#### 0.2. Классификация кандидатов
Воркер ничего не импортирует сам: он возвращает каждый листинг со статусом `DiscoveryCandidateStatus`:

| Статус | Значение |
|---|---|
| `new` | Бизнес с собственным сайтом, которого еще нет среди лидов; только такие можно импортировать |
| `existing_lead` | Домен уже есть среди лидов (с `leadId`) |
| `duplicate` | Тот же домен уже встречался в этой выдаче |
| `no_website` | Нет сайта, либо «сайт» — профиль соцсети или каталога |
| `invalid` | Листинг не прошел валидацию `DiscoveredBusinessSchema` |

Оператору предлагается не больше `limit` новых бизнесов; пропущенные показываются с причиной.

**Повторный поиск без проверенных (REV-107).** `IDiscoveryJobData.excludeDomains` — домены, которые прошлые поиски уже предложили и проверили (до `DISCOVERY_MAX_EXCLUDED_DOMAINS` = 1000). `runDiscovery` после `classify` убирает листинги с этими доменами до сверки с лидами и оценки сайта, не засчитывает их в `limit` (поиск листает дальше) и возвращает их число в `IDiscoveryJobResult.skippedChecked`; перезапрос учитывает их (`maxResults = min((limit + исключено) × 3, 300)`). Дашборд (`searchAgainInput` в `useDiscovery.ts`) строит следующий поиск из параметров задачи: прошлые `excludeDomains` плюс домены предложенных кандидатов, новейшие 1000.

#### 0.2a. Предварительная оценка сайтов (REV-98)
Перед возвратом результата `runDiscovery` вызывает `assessCandidates` (`apps/workers/src/services/site-assessment.service.ts`) для каждого предложенного `new` кандидата: пул из `DISCOVERY_ASSESS_CONCURRENCY` (6) параллельных проверок, каждая с таймаутом `DISCOVERY_ASSESS_TIMEOUT_MS` (8000 мс).

1. `fetchHomePage`: `fetch` с `redirect: 'manual'`, до 5 редиректов, каждый хост проходит `isBlockedHost` (localhost, `.local`/`.internal`, частные IPv4, IPv6-литералы). Сбой https → повтор по http (ошибка сертификата запоминается). Не 2xx → `http_error`, не HTML → `not_html`, чтение до 2 МБ, кодировка из `Content-Type`.
2. `parseHomePage`: happy-dom `DOMParser` без загрузки и выполнения скриптов; год copyright ищется только в тексте страницы. Перед разбором из HTML убираются `<link rel="preload">` и `modulepreload` (`withoutPreloadLinks`, REV-144): у окна нет базового URL, и относительный preload (Nuxt `/_payload.json`) роняет happy-dom ошибкой `Invalid URL`.
3. `detectBadSigns` / `detectComplexitySigns` (внутренние страницы — общий `collectInternalPages` из REV-38) → `explainVerdict`: вердикт, `verdictReason`, `signScore`, `signScoreNeeded`.
4. Результат проходит `SiteAssessmentSchema` и записывается в `candidate.assessment`; сбой — `{ outcome: 'failed', failure }` без вердикта.

| Вердикт | Простой сайт | Сложный сайт |
|---|---|---|
| `good` | баллы ≥ 2 | никогда |
| `maybe` | баллы = 1 | баллы ≥ 3 |
| `poor` | баллы = 0 | баллы < 3 |

Строгие признаки (нет HTTPS, плохой сертификат, нет `viewport`, таблицы/фреймы, Flash) дают 2 балла, остальные 1. Дашборд (`utils/siteAssessment.ts`, `CandidateAssessment.tsx`) показывает вердикт, признаки и аргумент вердикта, фильтрует и сортирует по вердикту и не предвыбирает слабых кандидатов.

#### 0.3. Импорт и e-mail
* Лид создается через `LeadService.createLead` (статус `QUEUED`, теги `discovered` и `source:<provider>`) и сразу уходит в `audit-queue`.
* Если у листинга нет e-mail, лиду ставится `info@<domain>` и тег `email-guessed`; аудит заменяет его на e-mail, найденный на самом сайте.
* Ошибки конфигурации (нет ключа, локация не найдена, HTTP 400/401/403) завершают задачу как `UnrecoverableError`; таймауты Overpass ретраятся.

> **В работе (REV-35):** устойчивая идентичность лида (нормализованный домен, телефон в E.164, `source` + `externalId` листинга) и бэкфилл существующих лидов, чтобы уже импортированные бизнесы не предлагались повторно. Раздел будет обновлен после слияния.

---

### Модуль 1: Агент аудита (Audit Agent)

Агент аудита запускается в изолированном воркере и осуществляет комплексный сбор данных в четыре параллельных этапа.

```mermaid
flowchart TD
    Start[Старт аудита URL] --> BrowserLaunch[Инициализация Playwright Chromium]
    BrowserLaunch --> Vitals[Замер Core Web Vitals мобильного контекста]
    Vitals --> Consent[Закрытие cookie-баннера: CMP API, текст кнопки, скрытие оверлея]
    Consent --> Capture[Захват Viewport: Mobile 375px & Desktop 1440px + Full-page]
    Capture --> ParallelWork
    
    subgraph ParallelWork [Параллельный аудит]
        Axe[A11y Engine: axe-core WCAG 2.1 AA]
        DOM[Brand DNA: Палитра K-Means, Лого, Шрифты]
        Content[Site Content Extractor: тексты, услуги, отзывы, контакты, JSON-LD]
        SEO[Standards & SEO: OpenGraph, Meta, Viewport, SSL]
    end

    ParallelWork --> VisionAnalysis[Мультимодальный AI UX/UI Аудит]
    VisionAnalysis --> ScoreAggregator[Агрегатор взвешенных оценок 0-100]
    ScoreAggregator --> SaveDB[Сохранение в MongoDB]
    SaveDB --> Chain[Lead.status = AUDITED → задача в ai-gen-queue]
```

#### 1.1. Этапы работы агента:
1. **Эмуляция и снятие снимков (Rendering & Screen Capture):**
   * Запуск Playwright в Headless-режиме с отключением блокировок краулинга (эмуляция актуального User-Agent). Навигация с таймаутом 25 с; браузер перезапускается каждые 20 задач.
   * **Закрытие cookie-баннеров (REV-33):** после навигации и до первого скриншота в обоих контекстах `CookieConsentService` принимает согласие через известные CMP (OneTrust, Cookiebot, Didomi, Quantcast, Usercentrics, CookieYes, Complianz, Osano, iubenda, Termly, TrustArc), затем кликает кнопку «Принять» по тексту (en/pl/ru/be/lt/de/fr/uk, включая iframe), затем скрывает оставшиеся оверлеи и снимает блокировку скролла. Бюджет 3 с, шаг никогда не роняет аудит. Мобильные Vitals снимаются до закрытия баннера (не влияет на CLS), axe — после (сканируется разметка самого сайта). Результат сохраняется в `Audit.cookieBannerHandled`.
   * Снятие скриншотов первого экрана (Above-the-fold) для двух брейкпоинтов:
     - Desktop: 1440x900
     - Mobile: 375x812 (iPhone 13/14 viewport)
   * **Полностраничные скриншоты (REV-21):** перед захватом страница прокручивается (подгрузка lazy-контента), анимации появления (AOS/WOW и т. п.) принудительно показываются, высота ограничивается (12 000 / 8 000 CSS px). Ужимается только ширина (1440 / 750 px), поэтому длинные страницы остаются читаемыми. Vision LLM по-прежнему получает только первый экран.
   * Сохранение изображений в S3/MinIO: `screenshots/{leadId}/{desktop,mobile,desktop-full,mobile-full}.webp`.
   * **Контент исходного сайта (REV-23):** `site-content.extractor.ts` выполняется внутри страницы и копирует из DOM (без генерации): title, meta description, H1 и заголовки, абзацы, услуги с описаниями, пункты навигации, реальные отзывы, контентные изображения (включая lazy и CSS-фоны), адрес и часы работы из видимого текста, данные schema.org `LocalBusiness` (JSON-LD: телефон, адрес, часы, рейтинг, год основания) и язык страницы. Приоритет контактов: schema.org > текстовые эвристики > совпадения по классам DOM. Результат — `Audit.extractedContent` и `Audit.extractedContacts`.

2. **Оценка доступности (Accessibility / a11y):**
   * Инжекция `@axe-core/playwright` в контекст страницы (после закрытия cookie-баннера).
   * Тестирование по стандартам WCAG 2.1 Level AA:
     - Цветовой контраст текста и фонов (Color Contrast Ratio < 4.5:1).
     - Отсутствующие или пустые атрибуты `alt` у изображений.
     - Доступность форм (отсутствие `<label>`, некорректные `for`/`id`).
     - Семантическая иерархия заголовков (`h1`-`h6`).
     - Фокус клавиатуры и ARIA-роли для интерактивных элементов.

3. **Соответствие веб-стандартам и производительность (Lighthouse & Standards):**
   * Запуск мобильного профиля Lighthouse:
     - Core Web Vitals: LCP (Largest Contentful Paint), INP (Interaction to Next Paint), CLS (Cumulative Layout Shift).
     - Наличие корректного Viewport мета-тега, HTTPS сертификата, фавикона, robots.txt, sitemap.xml.
     - Состояние микроразметки (Schema.org / OpenGraph / Twitter Cards).
     - Скорость загрузки и размер тяжелых неоптимизированных ассетов (PNG > 2MB, некэшируемые скрипты).
   * **Реализация (REV-99, REV-102):** Lighthouse не запускается (research.md, ADR 11); метрики хранятся в `Audit.webVitals`. `VitalsService` снимает метрики в мобильном контексте Playwright (375×812, без троттлинга) через `PerformanceObserver` с `buffered: true` (`performance.getEntriesByType` не отдаёт записи LCP и `layout-shift` в Chromium):
     - LCP — `startTime` последней записи `largest-contentful-paint`, в мс. Если записи нет, LCP не подменяется FCP или временем ответа — это ошибка измерения.
     - CLS — наибольшее окно сессии Core Web Vitals (сдвиги с разрывом < 1 с, окно ≤ 5 с) без сдвигов с `hadRecentInput` (Chromium помечает так и сдвиги первых ~500 мс после навигации); считается в `VitalsService.calculateCls`.
     - Стандарты и SEO (REV-102, REV-118) — HTTPS, viewport, title, мета-описание, один `h1`, фавикон (иконка в `<link>` или `/favicon.ico` через `page.request`, 3 с), Schema.org (JSON-LD с `@type` или микроданные) и OpenGraph; читает `readStandardsInDocument` (`standards.page.ts`, самодостаточная функция: в странице через `page.evaluate`, у MVP — в happy-dom); баллы `STANDARDS_POINTS` в `@revamp/shared-types` (20/20/10/10/10/10/10/10), результат — `Audit.standardsChecks`.
     - Нарушения axe-core сохраняются в `Audit.axeViolations` (`AxeService.toStoredViolations`: селектор и HTML до 300 символов, `failureSummary` до 500, до 20 узлов на правило, `nodeCount` — полное число).

4. **Мультимодальный AI-анализ дизайна (Vision UX/UI Critique):**
   * Скриншоты отправляются в Vision LLM со специализированным системным промптом:
     - Оценка визуальной иерархии (Visual Hierarchy & Scannability).
     - Читаемость типографики на мобильных устройствах.
     - Заметность и привлекательность основного CTA (Call to Action).
     - Эффект «устаревшего сайта» (Dated Design Smell: градиенты 2010-х, неадаптивные таблицы, перегруженные меню).
     - Формирование списка из 3 критических UX-проблем и 3 очевидных точек роста (Quick Wins).
   * **Провайдеры Vision (REV-51):** `VISION_LLM_PROVIDER` (`anthropic`, `openai`, `claude-cli`) или, если он пуст, по порядку: ключ Anthropic, ключ OpenAI, локальный Claude Code CLI (если `CLAUDE_CLI_PATH` найден). CLI получает оба скриншота первого экрана (mobile и desktop WebP) как image-блоки одного сообщения через `--input-format stream-json` / `--output-format stream-json` с теми же ограничениями, что и для текста: без инструментов, MCP, настроек и сохранения сессии, во временной рабочей папке. `modelUsed` = `claude-cli:<CLAUDE_CLI_MODEL>`, токены берутся из события `result` CLI (включая кэшированный ввод). Без доступного провайдера аудит завершается ошибкой (REV-45); детерминированная критика применяется только после 3 неудачных реальных вызовов (`aiFallbackUsed: true`, событие `token_usage` не пишется); она не оценивается: критерий дизайна исключается из итоговой оценки, а в `Audit.measurementErrors` пишется `design` с причиной (REV-101).

#### 1.2. Структура скоринга (Composite Score Formula):
$$\text{Total Score} = 0.35 \times S_{\text{Design/UX}} + 0.25 \times S_{\text{Performance}} + 0.20 \times S_{\text{Accessibility}} + 0.20 \times S_{\text{Standards/SEO}}$$

Каждый критерий нормализуется от 0 до 100. **Частичная оценка (REV-100):** если детерминированное измерение не удалось (производительность, доступность или стандарты), его критерий не заполняется ни нулём, ни подставным значением, а исключается из формулы; веса оставшихся критериев масштабируются до суммы 1 (например, без производительности: $\text{Total} = (0.35 S_{D} + 0.20 S_{A} + 0.20 S_{S}) / 0.75$). Причина сохраняется в `Audit.measurementErrors`, дашборд показывает её на шаге «Аудит», а письмо не упоминает неизмеренную метрику. Шаблонная критика дизайна (сбой Vision-модели) тоже считается неизмеренным критерием `design` (REV-101); если не измерен ни один критерий, аудит завершается ошибкой.

При оценке ниже 60 система генерирует конкретные продающие тезисы для холодного письма (например: *"Ваш мобильный сайт теряет до 45% клиентов из-за медленного LCP 4.8s и нечитаемого шрифта на смартфонах"*).

---

### Модуль 2: Модуль генерации уникальных MVP с сохранением брендового стиля

Модуль решает сложную инженерную задачу: не просто сгенерировать абстрактный лендинг, а создать **премиальную версию сайта конкретного бизнеса**, сохранив его айдентику (цвета, логотип, тексты, перечень услуг), но упаковав это в современный UX-каркас с конверсионными блоками.

С REV-135 страницу MVP проектирует и пишет модель (один HTML-документ с CSS), а код держит факты: решает, что модель читает, сам подставляет каждый контакт, отклоняет небезопасный ответ, помечает факты, которых нет на исходном сайте, и измеряет результат. Перестройка оригинала, модернизация, группировка секций, Bento-макеты и слой своего дизайна удалены в REV-141.

```mermaid
flowchart TD
    AuditData[Данные аудита: контент, услуги, контакты, бренд, картинки, скриншот] --> Brief[buildMvpSourceBrief: бриф без значений контактов]
    Brief --> Gen[MvpPageGenerator: Vision LLM пишет страницу]
    Gen -->|Провайдер/модель, выбранные оператором| Gen
    Gen --> Check{checkMvpPage}
    Check -->|отклонено, один повтор с причинами| Gen
    Check -->|отклонено дважды / нет провайдера / вызов упал| Fail[MVP_PAGE_FAILURES: ничего не публикуется]
    Check -->|принято| Grounding[checkMvpGrounding: флаги фактов]
    Grounding --> Finish[finishMvpPage: контакты, SEO, цвета и шрифты оператора, форма записи, трекер]
    Finish --> Upload[S3 revamp-demos: index.html + versions/n.html]
    Upload --> Measure[Стандарты, скорость, полнота, баннер До / После]
    Measure --> Review[Lead.status = NEEDS_APPROVAL]
```

#### 2.1. Спецификация пайплайна генерации:
1. **Экстракция бренд-токенов (Brand DNA Extraction):**
   * Парсинг вычисленных стилей (`window.getComputedStyle`) ключевых элементов: кнопок, заголовков, хедера.
   * Алгоритм кластеризации цветов (K-Means по изображениям и стилям) для выделения стабильной палитры:
     - `brandColorPrimary`
     - `brandColorSecondary`
     - `brandAccent`
     - `brandBackground`
   * Извлечение логотипа: поиск `<link rel="icon">`, селекторов `header img`, `nav svg`, `a[href="/"] img`.
   * Извлечение смысловых блоков (NLP/Regex): телефон, WhatsApp, email, физический адрес, график работы, прайс-лист/услуги, блок отзывов.

2. **Бриф (`buildMvpSourceBrief`, `mvp-source-brief.ts`, чистая функция, REV-136):**
   * Единственное место, где решается, что видит модель: `business` (название, ниша, город, URL), `language` (`extractedContent.language`), `services`, `copy` (title, meta description, H1, заголовки, абзацы, пункты услуг, отзывы, рейтинг, год основания — только извлеченное), `brand` (цвета, шрифты, логотип), `images` (картинки оригинала без размеров, без логотипа, без повторов), `placeholders` (по одному на проверенный контакт, `booking` всегда). Лимиты — `MVP_BRIEF_LIMITS` (30 услуг, 40 заголовков, 60 абзацев, 30 пунктов услуг, 10 отзывов, 24 картинки, 12 000 символов текста). Значений контактов в брифе нет; `MvpSourceBriefSchema` проверяет его перед каждым вызовом.
   * **Язык сайта (REV-25, REV-116):** экстрактор читает язык от самого точного источника: `<html lang>`, затем `<meta http-equiv="content-language">`, затем детерминированная догадка по тексту (стоп-слова и буквы, только en/ru/be/pl/lt, без LLM; нет явного победителя — нет языка) и записывает источник в `extractedContent.languageSource` (`SITE_LANGUAGE_SOURCES`: `html` | `meta` | `text`). Модель ставит `<html lang>` брифа (английский — только когда язык неизвестен) и не переводит текст; текст формы записи, которую добавляет код, локализован для en, ru, be, pl, lt (для прочих языков — английский).

3. **Генерация страницы (`MvpPageGenerator`, `mvp-page-generator.ts`, `MVP_PAGE_SYSTEM_PROMPT`, REV-137):**
   * Один Vision-вызов через `LlmClient`: бриф (JSON), разрешенные плейсхолдеры и до 3 тайлов десктопного скриншота аудита. Ответ — один HTML-документ; обрамление кодом снимается. Промпт и проверки — в [`AGENTS.md`](AGENTS.md), Агент 2.
   * Модель свободно выбирает структуру, секции и вид; текст — только из брифа, без новых фактов; контакты и запись — только плейсхолдеры `MVP_PLACEHOLDERS`; все цвета и шрифты — через переменные `MVP_THEME_VARS` в `:root`; картинки — только из брифа; без скриптов, форм, iframe и внешних ресурсов, кроме Google Fonts.
   * `checkMvpPage` (`mvp-page-check.ts`) отклоняет ответ с кодами `MVP_PAGE_CHECKS`; отклоненный ответ повторяется один раз с причинами и самой страницей. Два отклонения или отсутствие провайдера окончательны (`invalid_page`, `not_configured`): `MvpPageUnavailableError` (`UnrecoverableError`), `Lead.generationFailure = { code: 'MVP_PAGE_UNAVAILABLE', reason, message, at }`. Упавшие вызовы (`call_failed`) — обычная ошибка задачи: BullMQ повторяет ее (3 попытки), после последней лид получает только `generationError`. Запасной страницы нет.
   * `checkMvpGrounding` (`mvp-grounding.ts`) извлекает из видимого текста числа и имена и помечает те, которых нет в тексте брифа (`IMvpGroundingFlag`: `kind` `number` | `name`, `text`, `context`). Флаги не отклоняют страницу; они сохраняются в `MvpProject.grounding` и показываются оператору.
   * **Выбор провайдера и модели (REV-30, REV-32):** оператор выбирает провайдера (`anthropic`, `openai`, `gemini`, `claude-cli`) и модель в диалоге генерации; выбор действует только на эту задачу, иначе `pageProvider()`: `VISION_LLM_PROVIDER`, иначе `MVP_LLM_PROVIDER` или первый найденный API-ключ, иначе локальный CLI. Провайдер с ошибкой вызова **никогда** не переключается на другой платный провайдер. `MvpProject` хранит выбранные (`requestedProvider/Model`) и фактические (`provider`, `modelUsed`) значения.
   * **Локальный Claude Code CLI (REV-30):** провайдер `claude-cli` запускает `claude -p` в headless-режиме под аккаунтом, в который залогинен CLI (без API-ключа): без инструментов, без MCP, без пользовательских настроек, во временной рабочей папке; промпт передается через stdin.
   * **Визуальная самопроверка (REV-143, за флагом `MVP_PAGE_SELF_REVIEW`, по умолчанию выключена):** принятую страницу (с первого вызова или после повтора) `pageReviewRenderer` (`mvp-page-review.ts`) завершает (`finishMvpPage` без трекера) и снимает целиком в Playwright на 1440 и 390 px (`captureHtmlScreenshot`, `fullPage`). Снимки режутся не больше чем на 2 и 3 тайла, длинная страница — более высокими тайлами, чтобы форма записи и подвал дошли до модели. Один вызов ревизии (`MVP_PAGE_REVIEW_PROMPT`, температура `0.3`) получает бриф, страницу и тайлы; ревизия проходит те же `checkMvpPage`, иначе остается первая страница. Сбой рендера или вызова тоже оставляет первую страницу и никогда не роняет генерацию. Исход (`MvpPageReview`: `revised` | `unchanged` | `rejected` | `failed`) пишется в лог и результат задачи, но не сохраняется. `change` самопроверку не проходит. Замер на 7 сайтах (комментарий в REV-143): прирост по стандартам, axe и горизонтальной прокрутке не измерен, две ревизии убрали подтвержденный текст, поэтому флаг выключен.
   * Задача `ai-gen-queue` передает принятую страницу, тему и флаги в `deploy-queue` (`IDeployJobData.page`); задача без страницы отклоняется (REV-141).

3a. **Завершение страницы (`finishMvpPage`, `mvp-page-finish.ts`, чистая функция, REV-138):** выполняется при каждой публикации из сохраненной сырой страницы:
   * плейсхолдеры заполняются проверенными контактами (`tel:`, `mailto:`, поиск в Google Maps, `#booking`);
   * поисковые теги модели (мета-описание, `og:*`, `twitter:*`, canonical, иконки) заменяются тегами `buildMvpSeo` (REV-118) и иконкой: логотип сайта, иначе монограмма как `data:image/svg+xml` URI (REV-56), поэтому MVP не запрашивает `/favicon.ico` с корня хранилища (MinIO отвечает 403);
   * цвета и шрифты оператора (`MvpProject.controls` поверх `theme`) — завершающий `<style id="rv-controls">:root{…}</style>` и ссылка Google Fonts для выбранной пары;
   * форма записи (`templates/shared/booking.ts`) в конце `<main>` (иначе перед подвалом, иначе в конце `<body>`), ее стили на переменных `--rv-*`, ее скрипт, трекер и скрипт превью (`previewScript`: по `REVAMP_SHOW_TEXT` из дашборда прокручивает к тексту и обводит его, REV-140).

4. **Проверка полноты MVP (REV-36, REV-37):**
   * После рендеринга `MvpCompletenessService` разбирает HTML (`happy-dom`, без нового краулинга) и сверяет его с данными, извлеченными на аудите.
   * Поля и уровни: **critical** — `businessName`, `phone`, `email`, `address`; **important** — `workingHours`, `services`, `socialLinks`; **informational** — `logo`, `images`, `testimonials`, `rating`, `foundingYear`.
   * Статусы: `present`, `missing`, `altered` (есть, но другое), `not_in_source` (на исходном сайте нет), `unsourced` (контакт в MVP, которого нет на исходном сайте — вероятно, выдуман).
   * Если LLM настроен (`MVP_COMPLETENESS_LLM=true`), поля судит LLM: каждый вердикт должен дословно цитировать MVP. Код принимает вердикт, только если цитата есть в тексте, ссылках или URL изображений MVP, телефон/e-mail совпадают с источником после нормализации и имеют `tel:`/`mailto:`-ссылку, а «missing» не перекрывает найденное кодом совпадение. `not_in_source` и итоговый балл (веса 3/2/1 по уровням) всегда считает код.
   * При отсутствии провайдера, таймауте (`MVP_COMPLETENESS_LLM_TIMEOUT_MS`), ошибке или невалидном ответе после одного повтора используется сравнение только кодом; причина сохраняется в `llmError`. Сбой самого сравнения дает отчет `unverified` и никогда не роняет задачу.
   * Отчет валидируется Zod, сохраняется в `MvpProject.completenessReport` и пересчитывается при каждой генерации, а при каждой повторной публикации (изменение, цвета и шрифты, восстановление версии) — кодом без LLM, чтобы описывать опубликованную страницу. Отчет носит рекомендательный характер: он ничего не одобряет, не блокирует и не отправляет.

5. **Компиляция, изоляция и деплой:**
   * Сборка страницы в один оптимизированный бандл (HTML + inline CSS/JS).
   * Инжекция аналитического скрипта трекинга (`revamp-tracker.js`): регистрирует факт входа владельца, скролл, клики по кнопкам демо.
   * MVP раздается с хоста хранилища (MinIO / `PREVIEW_DOMAIN`), поэтому скрипт подключается по абсолютному адресу API (REV-52): `<script src="{PUBLIC_API_URL}/track/revamp-tracker.js" data-api="{origin PUBLIC_API_URL}" data-token="…">`, и события уходят на `{PUBLIC_API_URL}/track/mvp-event`. Относительный путь `/api/v1/...` разрешился бы в хранилище (403). Без `PUBLIC_API_URL` скрипт не встраивается. Адрес фиксируется при генерации: после его смены MVP нужно перегенерировать.
   * Публикация в бакет `revamp-demos` по ключу `v/{previewSlug}/index.html` (slug — транслитерированное название бизнеса + 6 последних символов `leadId`).
   * **Версии (REV-138):** каждая генерация, изменение и восстановление сохраняет сырую страницу (плейсхолдеры не заполнены) как `v/{previewSlug}/versions/{n}.html` и запись `MvpProject.versions` (`n`, `kind` `generate` | `change` | `restore`, `instruction?`, `from?`, `jobId?`, `provider?`, `model?`, `storagePath`, `createdAt`). Хранится не больше `MVP_MAX_VERSIONS` (20): самая старая удаляется из хранилища и записи. `index.html` перезаписывается, адрес превью не меняется. Стандарты, скорость, полнота, флаги, `editedAt` и новая версия пишутся одним обновлением.
   * Автоматический снимок созданного лендинга через Playwright для формирования баннера «До/После» (Split-screen Comparison, 1200x630). На баннере только измеренные значения (REV-126): LCP, нарушения axe и балл стандартов оригинала (`comparableStandardsScore`), балл стандартов MVP (`checkMvpStandards` до выгрузки, тот же, что пишется в `MvpProject.standards`); неизмеренное опускается, без скриншота оригинала — надпись «not available».

6. **Перегенерация (REV-31):**
   * Правила `mvpGenerationMode` (`@revamp/validation`): из `AUDITED` — первая генерация; из `NEEDS_APPROVAL` — только с `forceRegenerate`; после постановки письма в отправку (`SCHEDULED` и далее) и во время генерации — запрещено (409).
   * Существующий проект сохраняет `previewSlug`: объекты в бакете перезаписываются (`Cache-Control: no-cache`), уже отправленная ссылка остается рабочей. `MvpProject` один на лид; обновляются `generatedAt` и `generationCount`, а превью в дашборде сбрасывает кэш по `Lead.mvpGeneratedAt`.
   * Лид остается в `GENERATING`, пока деплой не опубликует новое превью. После исчерпания ретраев (или сразу при окончательной ошибке `UnrecoverableError`) лид возвращается в `AUDITED` (первая генерация) или `NEEDS_APPROVAL` (предыдущий MVP цел), а причина пишется в `Lead.generationError`; если страницу не дала модель — еще и код `MVP_PAGE_UNAVAILABLE` с причиной (`MVP_PAGE_FAILURES`) в `Lead.generationFailure`.
   * Дашборд (REV-53): `MvpPreviewFrame` закрывает превью оверлеем от клика «Перегенерировать» до загрузки новой версии в iframe. Мутация генерации имеет ключ `['generate-mvp']` и остается в ожидании, пока список лидов не покажет `GENERATING` (`useIsMvpGenerationPending`), поэтому разрыва между кликом и оверлеем нет. Если URL превью не изменился (сбой), оверлей снимается сразу, а если новая версия не загрузилась, то через 20 с. `sandbox` iframe не меняется.


7. **Изменения опубликованной страницы (REV-139, `mvp-page-queue`):** только в `NEEDS_APPROVAL` и только у страницы модели (есть `page`/`theme`; MVP прежнего генератора — `409 MVP_PREVIOUS_GENERATOR`, только перегенерация).
   * `change` (`POST /mvp/:id/edit`): генератор в режиме `change` получает текущую сырую страницу и слова оператора и возвращает всю страницу; те же проверки и повтор. Неудача ничего не публикует (`502 MVP_EDIT_FAILED` с причиной).
   * `controls` (`PATCH /mvp/:id/tokens`): цвета (пять ролей, текст на фоне и на поверхности не ниже `MVP_MIN_CONTRAST` 4,5:1) и пара шрифтов из `MVP_FONT_CHOICES` сохраняются в `controls` и публикуются без вызова модели и без новой версии.
   * `restore` (`POST /mvp/:id/versions/:n/restore`): сырая страница версии `n` проверяется по текущему аудиту и публикуется с текущими `controls` как новая версия `restore`.
   * API ждет задачу до 420 с (изменение) или 120 с (цвета, шрифты, восстановление) и передает воркеру срок (`deadline`); воркер начинает публикацию, только если до срока осталось больше `PUBLISH_MARGIN_MS` (90 с), иначе задача ничего не публикует, и API, который еще ждет, отвечает `502 MVP_EDIT_FAILED` (для `change` генератор сам останавливается на этом сроке с `call_failed`). `504 MVP_EDIT_TIMEOUT` — только если задача не завершилась за время ожидания (стояла в очереди или публикация затянулась); если она уже выполнялась, `message` говорит, что изменение еще может быть опубликовано.
---

### Модуль 3: Модуль персонализированных писем (Email Outreach)

Модуль отвечает за упаковку результатов аудита и созданного MVP в персональное письмо, исключающее ощущение шаблонного спама.

```mermaid
sequenceDiagram
    autonumber
    actor Lead as Владелец бизнеса
    participant MailWorker as Email Worker
    participant Dashboard as React Дашборд (HITL)
    participant PreviewEngine as Сервер демо-MVP
    participant Tracking as Tracking & Webhook API

    MailWorker->>Dashboard: Создание черновика письма (Draft)
    Note over Dashboard: Оператор проверяет аудит, MVP и текст письма
    Dashboard->>MailWorker: Ручной аппрув [Approve & Send]
    MailWorker->>Lead: Доставка персонализированного письма (HTML + PlainText)
    Lead->>MailWorker: Открытие письма (Срабатывает Tracking Pixel)
    MailWorker->>Dashboard: Статус: Email Opened
    Lead->>PreviewEngine: Клик по ссылке на MVP-демо
    PreviewEngine->>Tracking: POST /api/v1/track/event (click, dwell_time)
    Tracking->>Dashboard: Push-нотификация: "Лид изучает интерактивное демо (45 сек)!"
```

#### 3.1. Генератор структуры письма:
* **Тема (Subject Line):** Динамическая, персонализированная (например: *«Заметили 3 ошибки в мобильной версии {{businessName}} (и подготовили быстрый прототип)»*).
* **Тело письма:**
  1. *Персонализированное вступление:* упоминание конкретного города, специфики бизнеса.
  2. *Конкретные факты:* «Мы протестировали ваш сайт на смартфонах: оценка доступности {{a11yScore}}/100, время загрузки {{lcpTime}} сек».
  3. *Наглядная демонстрация:* Встроенный адаптивный GIF / скриншот «Старый сайт vs Новый адаптивный MVP».
  4. *Ценность без давления:* «Мы не берем денег за аудит — мы уже собрали для вас интерактивную концепцию с сохранением вашего фирменного стиля и логотипа: [Открыть прототип {{businessName}}]».
  5. *Call To Action:* Простая ссылка без сложных регистраций + предложение созвониться на 10 минут, если концепт понравился.

#### 3.2. Deliverability & Safeguards (Инфраструктура доставки):
* **Ротация доменов и почтовых ящиков:** Поддержка нескольких прогретых вторичных доменов (например, `getrevamp.co`, `revamp-audit.com`).
* **Ограничение скорости (Throttling):** Не более 15–20 писем в час с одного ящика для исключения попадания в спам-фильтры Google/Яндекс/Outlook.
* **Автоматическая валидация MX/DNS:** Предварительная проверка существования почтового ящика лида (ZeroBounce/Hunter API или встроенный SMTP handshake).
* **Соблюдение законов (CAN-SPAM / GDPR / 152-ФЗ):** Обязательный одноэтапный `Unsubscribe-Link` и физический адрес отправителя в футере.

---

### Модуль 4: Дашборд управления на React & Material UI (HITL & Analytics)

Дашборд служит единым рабочим местом оператора/менеджера по продажам.

```
+-----------------------------------------------------------------------------------------+
| [Logo] Revamp Admin       | Поиск по домену/лиду...        | [Квоты: 84/100] [Оператор v] |
+-----------------------------------------------------------------------------------------+
| [Панель]     | [Pipeline] Kanban: Воронка лидов                             [+ Новый аудит] |
| > Лиды       +--------------+--------------+--------------+--------------+--------------+
| > Аудиты     | В очереди (4)| Анализ (2)   | Ожидает (8)  | Отправлено(12| Кликнули (5) |
| > Шаблоны    | site1.ru     | site5.ru     | [!] auto.ru  | dental.ru    | VIP-law.ru   |
| > Почта      | bakery.com   | fitness.com  | law-help.ru  | clinic-spb.ru| [Демо: 3 мин]|
| > Аналитика  +--------------+--------------+--------------+--------------+--------------+
| > Настройки  |                                                                           |
|              | ДЕТАЛЬНЫЙ РЕВЬЮ-МОДАЛ (HITL APPROVAL GATE):                               |
|              | +-------------------------------+---------------------------------------+ |
|              | | ИСХОДНЫЙ САЙТ (Оценка: 38/100)| НОВЫЙ СГЕНЕРИРОВАННЫЙ MVP             | |
|              | | [Скриншот десктоп / мобайл]   | [Интерактивный фрейм: 100% отзывчивый]| |
|              | | - LCP: 5.4s (Критично)        | - Чистая палитра (Взята с логотипа)   | |
|              | | - A11y: 41/100 (Нет контраста)| - Добавлен виджет быстрой записи      | |
|              | +-------------------------------+---------------------------------------+ |
|              | | ЧЕРНОВИК ПИСЬМА ДЛЯ ОТПРАВКИ:                                         | |
|              | | Кому: director@auto.ru   | Тема: 3 проблемы в мобильной версии...     | |
|              | | [ WYSIWYG Редактор письма с подстановкой переменных ]                | |
|              | | [Перегенерировать MVP]   [Редактировать код]  [ ОДОБРИТЬ И ОТПРАВИТЬ ]| |
|              | +-----------------------------------------------------------------------+ |
+--------------+---------------------------------------------------------------------------+
```

#### 4.1. Архитектура фронтенд-приложения:
* **Компонентная система:** `@mui/material`, `@mui/icons-material`, `@mui/x-data-grid` для работы с большими таблицами лидов.
* **Темизация (REV-49):** дизайн-система в духе Hyperliquid, целиком в теме MUI (`apps/dashboard/src/theme/theme.ts`). Основной режим — тёмный: глубокий сине-зелёный почти черный фон (`#0B1418` / `#0F1A1F`) и один мятный акцент (`#97FCE4`); светлый режим использует те же оттенки, затемнённые для белого фона. Токены (`TOKENS`): фон, поверхности (`surface.sunken` / `surface.raised`), границы (`border.subtle` / `border.strong`), текст, семантические цвета с `soft`-подложкой, цвета этапов воронки (`palette.stage.*`: колонки Kanban). Формы плоские и плотные: скругления 4–10 px (`RADIUS`), рамки 1px вместо теней, компактные поля ввода, табличные цифры (`tabular-nums`, вариант типографики `metric` для KPI). Цветные чипы статусов — тонированная подложка + цвет текста того же тона. Все пары текст/фон проходят WCAG AA (≥ 4.5:1), это проверяется тестом `theme.spec.ts`. В компонентах нет захардкоженных цветов: только токены темы (исключения — пресеты цвета бренда MVP и превью письма, которое намеренно показывает светлый почтовый клиент на токенах светлой темы).
* **Управление состоянием и кэшем:**
  - `TanStack Query (React Query v5)`: инвалидация кэша списков лидов, polling для отображения прогресса аудита, генерации и поиска бизнесов.
  - `Zustand`: глобальное состояние активных фильтров; открытый лид задается маршрутом `/leads/:id` (REV-76), а черновик письма хранит само ревью лида (`useEmailDraft`, REV-77); `useDiscoveryStore` (открыт ли поиск и активная задача — переживает закрытие модалки), `useLlmChoiceStore` (последний выбранный провайдер/модель), `useLanguageStore` (язык интерфейса), `useSidebarStore` (свернуто ли боковое меню, REV-46; хранится в `localStorage`).
* **Локализация (REV-24):** `i18next` + `react-i18next` с типизированными ключами. Английский словарь — источник, словари ru/be/pl/lt проверяются по нему на этапе компиляции. Язык: сохраненный выбор → язык браузера → английский; хранится в `localStorage`, `<html lang>` следует за ним. Даты форматируются по языку (для be — `ru-BY`, где у браузера нет белорусских данных). Тексты MUI core и DataGrid локализованы для en/ru/be/pl (для lt MUI локали не поставляет).
* **Боковое меню (REV-39, REV-46):** только пункты с существующими экранами, активный пункт берется из текущего экрана. Сворачивается в полосу иконок (72px) с подсказками-названиями; выбор сохраняется между перезагрузками.

#### 4.2. Ключевые экраны:
0. **Очередь ревью (`/`, `ReviewQueuePage`, REV-79):** вкладки групп «Ждут вас», «В работе», «Аутрич», «Закрыты» со счетчиками (`LEAD_STATUS_BUCKET`), список группы 380px и ревью выбранного лида (`LeadReview`) рядом. Группа и лид — в query-параметрах `bucket` и `lead`; после одобрения или отклонения выбирается следующий лид, а выбранный лид, который воркер перевел в другую группу, остается в списке до перехода оператора к другому лиду (`keepSelectedLead`, REV-86). Быстрые фильтры списка по статусу и диапазону оценки (REV-80) — локальное состояние страницы, привязанное к группе, в URL не попадают. Порядок, выбор, фильтры и правила клавиш `J` / `K` / `Enter` — чистые функции в `utils/reviewQueue.ts` (`keepSelectedLead`, `filterQueue`, `queueStatusOptions`, `scoreBandOptions`, `scoreBand`), слушатель клавиш — `useQueueHotkeys`. Кнопка «Открыть на весь экран» в заголовке ревью (слот `headerActions` у `LeadReview`, REV-89) открывает выбранный лид на `/leads/:id` через тот же `useOpenLead`, что и `Enter`.
1. **Pipeline Kanban & DataGrid:**
   * Переключение между табличным представлением (MUI DataGrid с фильтрацией по скорингу, нише, городу) и Kanban-доской статусов.
2. **Ревью лида в три шага (`LeadReview`, `/leads/:id`, REV-77):** на экране один шаг, внизу панель действий (`ReviewActionBar`) с одним основным действием на шаг (Далее, Далее, Одобрить и отправить) и «Отклонить лид» на каждом шаге. Одобрение есть только на шаге «Письмо» и включается через 500 мс после его открытия; все шаги смонтированы, поэтому правки письма (`useEmailDraft`) и iframe переживают переходы.
   * Шаг 1 «Аудит» (`AuditStep`): скриншот исходного сайта (Desktop / Mobile), метрики LCP, a11y, мобильность; под каждым значением строка о том, как оно измерено и какие значения хорошие (LCP на телефоне 375px, хорошо до 2,5 с; число нарушенных правил WCAG 2.1 A/AA по axe-core, а не элементов; оценка мобильной версии от Vision-модели по скриншотам), REV-103. Колонка находок (380px) стоит рядом со скриншотом только с брейкпоинта `xl` (1536px, `AUDIT_ROW_BREAKPOINT`); уже — находки идут под скриншотом во всю ширину, чтобы рядом со списком очереди (380px) они не сжимались (REV-83).
   * Шаг 2 «Прототип» (`PrototypeStep`): интерактивный `<iframe sandbox="allow-scripts allow-same-origin">` со сгенерированным MVP, тулбар брейкпоинтов (Desktop / Tablet / Mobile), флаги фактов страницы со ссылкой «Показать в превью», «Что изменилось» (только измеренное) и плавающая панель «Инструменты дизайна»: изменение своими словами, цвета, шрифты, версии с восстановлением и перегенерация (REV-140).
   * Полностраничные скриншоты исходного сайта в прокручиваемом просмотрщике со ссылкой «Открыть в полном размере» (REV-21).
   * Чек-лист полноты MVP (`CompletenessChecklist`, REV-36/37): поле, значение на исходном сайте, значение в MVP, статус, кто решил (LLM или код), метод и модель проверки.
   * Кто написал страницу MVP: провайдер и модель (`MvpSourceChip`, REV-32, REV-137).
3. **Шаг 3 «Письмо» (подтверждение отправки, HITL):**
   * Быстрый предпросмотр темы и текста письма.
   * Кнопка инлайн-редактирования текста перед отправкой.
   * Кнопка «Перегенерировать MVP» с подтверждением и выбором провайдера/модели (REV-31, REV-32).
   * Если критическое поле MVP отсутствует, изменено или выдумано, одобрение требует дополнительного подтверждения (REV-36).
   * Большая акцентная кнопка «Подтвердить и отправить» (`Ctrl/Cmd + Enter`).
4. **Карточки Kanban:** кнопки «Сгенерировать MVP» (для `AUDITED`) и «Перегенерировать MVP» (для `NEEDS_APPROVAL`), чип «Пробелы в данных» при критических проблемах полноты, текст последней ошибки генерации (`generationError`). Для `AUDIT_FAILED`: чип «Аудит не удался» с причиной, кнопки «Повторить аудит» и «Отклонить» (REV-44).
5. **Поиск бизнесов (`DiscoveryDrawer` + `DiscoveryReview`, REV-27…REV-29, REV-78):** кнопка «Найти компании» в хедере и значок «Найти компании» на панели навигации открывают правую панель шириной 600px с шагами **Где → Проверка → Импорт**. Шаг не хранится отдельно, а выводится из стора (`discoveryStep`): нет активной задачи — «Где» (провайдер, город/район с автоопределением, ниша, ключевое слово, лимит); есть задача — «Проверка» (очередь/поиск с прогрессом, ошибка, результат до REV-29 или список кандидатов); есть итог импорта (`useDiscoveryStore.importResult`) — «Импорт» (сводка: импортировано / не импортировано / ошибки, «Проверить оставшиеся», «Новый поиск», «Готово»). Поэтому закрытие панели во время поиска и повторное открытие возвращают на тот же шаг. «Изменить поиск» и «Назад» возвращают на «Где» с параметрами прошлого поиска. Пока поиск идет, панель можно свернуть кнопкой «Выполнять в фоне»; тогда кнопка в хедере (`DiscoveryButton`, REV-40) сама опрашивает задачу через общий `discoveryStatusQueryOptions` и показывает спиннер, бейдж с числом новых бизнесов или ошибку, пока оператор не откроет результат (`useDiscoveryStore.resultsSeen`). Панель поиска и `DiscoveryFinishWatcher` смонтированы в `Layout`, поэтому задача отслеживается на любой странице; при завершении задачи в фоне `DiscoveryFinishWatcher` показывает уведомление (новые бизнесы / ничего нового / ошибка), клик по которому открывает панель (REV-41, один раз на задачу через `notifiedJobId`).
6. **Аналитический дашборд:**
   * Конверсионная воронка (Аудиты -> Отправлено -> Открыто -> Переходов на MVP -> Ответы).
   * График активности лидов (время нахождения на демо-сайте, клики по кнопке «Оставить заявку»).

---

## 4. Схема базы данных (MongoDB / Mongoose)

> Схемы ниже отражают фактические модели и типы `@revamp/shared-types`. Модели Mongoose определены один раз в пакете `@revamp/db` (`packages/db/src/models`); `apps/api/src/models` и `apps/workers/src/models` только реэкспортируют их (REV-48), поэтому API и воркеры всегда работают с одной схемой. Коллекция `users` и RBAC (§7) пока не реализованы.

```mermaid
erDiagram
    Lead ||--o{ Audit : has
    Lead ||--o| MvpProject : "has (one per lead)"
    Audit ||--o| MvpProject : generates
    Lead ||--o| EmailCampaign : targets
    Lead ||--o{ AnalyticsEvent : tracks
    EmailCampaign ||--o{ AnalyticsEvent : tracks

    Lead {
        ObjectId _id PK
        string businessName
        string originalUrl
        string domain
        string niche
        string city
        string contactEmail
        string contactPhone
        string ownerName
        string status
        number totalScore
        string[] tags
        string previewUrl
        string comparisonBannerUrl
        Date mvpGeneratedAt
        string generationError
        Mixed generationFailure
        string auditError
    }

    Audit {
        ObjectId _id PK
        ObjectId leadId FK
        string status
        object scores
        object webVitals
        object standardsChecks
        object a11ySummary
        array axeViolations
        array measurementErrors
        object designCritique
        object extractedBrandTokens
        object extractedContacts
        object extractedContent
        object screenshotUrls
        object cookieBannerHandled
        object siteEra
        boolean aiFallbackUsed
        Date completedAt
    }

    MvpProject {
        ObjectId _id PK
        ObjectId leadId FK
        ObjectId auditId FK
        string previewSlug
        string fullPreviewUrl
        string storageHtmlPath
        string comparisonBannerUrl
        string page
        object theme
        object controls
        array grounding
        array versions
        object standards
        object performance
        object completenessReport
        string provider
        string modelUsed
        string requestedProvider
        string requestedModel
        Date generatedAt
        number generationCount
        Date editedAt
        boolean isPublished
    }

    EmailCampaign {
        ObjectId _id PK
        ObjectId leadId FK
        ObjectId mvpProjectId FK
        string status
        string subject
        string bodyHtml
        string trackingToken
        string approvedBy
        Date approvedAt
        Date scheduledAt
        Date sentAt
        Date unsubscribedAt
        object metrics
    }

    AnalyticsEvent {
        ObjectId _id PK
        ObjectId leadId FK
        ObjectId campaignId FK
        string trackingToken
        string eventType
        number dwellTimeSeconds
        number scrollDepthPercent
        object metadata
        Date timestamp
    }
```

Результаты поиска бизнесов (Discovery) в MongoDB не хранятся: список кандидатов живет в результате BullMQ-задачи `discovery-queue` в Redis (вместе с оценкой сайта `assessment`, REV-98), и импорт читает его оттуда.

### Детальное описание коллекций:

#### 1. `leads`
```typescript
interface ILead {
  _id: Types.ObjectId;
  businessName: string;
  originalUrl: string;
  domain: string;                 // hostname без www, в нижнем регистре
  niche: 'dental' | 'auto' | 'legal' | 'beauty' | 'construction' | 'medical' | 'restaurant' | 'fitness' | 'real_estate' | 'other';
  city?: string;                  // улица сюда не пишется: полный адрес хранится в Audit.extractedContacts
  contactEmail?: string;          // необязателен (REV-45): аудит берет e-mail с сайта; для Discovery может быть info@<domain> с тегом email-guessed
  contactPhone?: string;
  ownerName?: string;
  status: LeadStatus;             // см. жизненный цикл ниже
  totalScore?: number;
  tags: string[];                 // discovered, source:osm|google, email-guessed
  previewUrl?: string;
  comparisonBannerUrl?: string;
  mvpGeneratedAt?: Date;          // сброс кэша превью после перегенерации (REV-31)
  generationError?: string;       // причина последнего сбоя генерации (REV-31)
  generationFailure?: IMvpRenderFailure;   // REV-137: { code: 'MVP_PAGE_UNAVAILABLE', reason: 'not_configured' | 'call_failed' | 'invalid_page', message?, at }, когда страницу не дала модель
  auditError?: string;            // причина окончательного сбоя аудита, одна строка (REV-44)
  createdAt: Date;
  updatedAt: Date;
}
```

**Жизненный цикл лида (фактические переходы):**

```mermaid
stateDiagram-v2
    [*] --> QUEUED: POST /leads, импорт из Discovery
    QUEUED --> AUDITING: audit worker
    AUDITING --> AUDITED: аудит завершен
    AUDITING --> AUDIT_FAILED: последняя попытка, постоянная ошибка (DNS, сертификат) или задача зависла после падений воркера (stalled, REV-145)
    AUDIT_FAILED --> QUEUED: «Повторить аудит» (POST /audits/trigger)
    AUDITED --> GENERATING: авто-цепочка или «Сгенерировать MVP»
    GENERATING --> NEEDS_APPROVAL: deploy worker опубликовал превью / сбой перегенерации (старый MVP цел)
    GENERATING --> AUDITED: сбой первой генерации
    NEEDS_APPROVAL --> GENERATING: «Перегенерировать MVP» (forceRegenerate)
    NEEDS_APPROVAL --> SCHEDULED: HITL-аппрув оператором
    SCHEDULED --> SENT: email worker
    SCHEDULED --> REJECTED: MX-проверка домена не прошла (email worker)
    SENT --> OPENED: пиксель
    SENT --> CLICKED: клик-редирект
    SENT --> ENGAGED: dwell time / CTA в демо
    OPENED --> CLICKED: клик-редирект
    OPENED --> ENGAGED: dwell time / CTA в демо
    CLICKED --> ENGAGED: dwell time / CTA в демо
    note right of REJECTED
        Оператор отклоняет лид из QUEUED, AUDITING,
        AUDIT_FAILED, AUDITED, GENERATING, NEEDS_APPROVAL
    end note
    note right of ENGAGED
        UNSUBSCRIBED: из любого статуса
        (POST /track/unsubscribe/:token), финальный
    end note
```

Диаграмма повторяет таблицу `LEAD_TRANSITIONS` из `@revamp/validation` (REV-62): `canTransition(from, to)` и `leadStatusesInto(to)` используют все места, где меняется статус лида (маршруты API, трекинг, воркеры аудита, генерации, деплоя и отправки), обычно как атомарный фильтр `findOneAndUpdate({ _id, status: { $in: leadStatusesInto(to) } })`. Повтор задачи BullMQ может заново выставить тот же статус (`includeSelf`), но устаревшая задача или поздний трекинг никогда не переводят лид назад: аудит пропускает лид, который уже не в `QUEUED`; воркер генерации пропускает лид, который не может перейти в `GENERATING`; deploy worker переводит в `NEEDS_APPROVAL` только лид в `GENERATING`; `SENT` и отказ по MX не перезаписывают отписку, пришедшую во время отправки.

`UNSUBSCRIBED` выставляет только `POST /track/unsubscribe/:token` (REV-73); одобрение и email worker такому лиду отказывают. Статусы `PENDING`, `MVP_READY`, `AWAITING_APPROVAL`, `APPROVED`, `DISPATCHED`, `REPLIED` удалены из `LeadStatus` (REV-62); `npm run migrate:lead-statuses --workspace=@revamp/api` переводит сохраненные лиды: `PENDING` → `QUEUED`, `MVP_READY`/`AWAITING_APPROVAL`/`APPROVED` → `NEEDS_APPROVAL`, `DISPATCHED` → `SENT`, `REPLIED` → `ENGAGED`. Дашборд относит каждый статус к колонке Kanban в `apps/dashboard/src/utils/leadStages.ts`.

#### 2. `audits`
```typescript
interface IAudit {
  _id: Types.ObjectId;
  leadId: Types.ObjectId;         // повторный аудит создает новый документ; воркер пишет в самый свежий
  status: 'QUEUED' | 'PROCESSING' | 'COMPLETED' | 'FAILED';
  // 0-100; неизмеренный критерий отсутствует, total взвешен по измеренным (REV-100); design нет при шаблонной критике (REV-101)
  scores: { total: number; design?: number; accessibility?: number; performance?: number; standards?: number };
  // Только измеренные в странице LCP (мс) и CLS; Speed Index и INP не хранятся — headless-загрузка их не измеряет (REV-105)
  webVitals: { lcp?: number; cls?: number };     // до REV-102 — lighthouseMetrics (migrate:audit-vitals)
  // Проверки стандартов (REV-102); отсутствуют, если страницу не удалось прочитать
  standardsChecks?: { https: boolean; viewport: boolean; title: boolean; metaDescription?: boolean; singleH1?: boolean; favicon: boolean; structuredData: boolean; openGraph: boolean };   // metaDescription, singleH1 — REV-118, у аудитов до него нет
  // Измерения, которые не удалось снять, и причина; их значения в документе отсутствуют (REV-100)
  measurementErrors?: Array<{ measurement: 'performance' | 'accessibility' | 'standards' | 'design'; message: string }>; // AUDIT_MEASUREMENTS; 'sections' (REV-113) удален в REV-141 — у старых аудитов дашборд его не показывает
  a11ySummary?: {                  // отсутствует, если сканирование axe не удалось
    violationsCount: number;
    contrastIssuesCount: number;
    missingAltCount: number;
    criticalViolations: Array<{ id: string; description: string; impact?: string; selector: string }>;
  };
  // Все нарушения axe-core с усечением (REV-102); отсутствуют, если сканирование не удалось
  axeViolations?: Array<{
    id: string; impact?: string; description: string; help: string; helpUrl: string; tags: string[];
    nodeCount: number; nodes: Array<{ target: string; html: string; failureSummary?: string }>;
  }>;
  designCritique: {
    visualHierarchyRating: number;
    mobileFriendlinessRating: number;
    primaryCtaFound: boolean;
    datedDesignFactors: string[];
    criticalFlaws: Array<{ title: string; impact: string; recommendation: string }>;
    quickWins: string[];
  };
  extractedBrandTokens: {
    primaryColor: string;
    secondaryColor: string;
    accentColor: string;
    fontFamilies: string[];
    logoUrl?: string;
    faviconUrl?: string;
  };
  extractedServices?: string[];
  siteEra?: Mixed;                // REV-114: насколько устарел вид главной страницы (SiteEraSchema): { dated, score, signs: SiteDatedSign[], contentWidth? }; dated — score >= SITE_DATED_THRESHOLD (3); из HTML и DOM, без LLM
  siteEraError?: string;          // REV-114: почему признаки не удалось прочитать; аудит при этом не падает, вердикта нет
  extractedContacts?: {           // REV-23: детерминированно с исходного сайта
    phone?: string; email?: string; address?: string; workingHours?: string;
    socialLinks: Array<{ platform: string; url: string }>;
  };
  extractedContent?: {            // REV-23: тексты и структура исходного сайта, дословно из DOM
    language?: string; title?: string; metaDescription?: string; ogImage?: string; h1?: string;
    languageSource?: 'html' | 'meta' | 'text';  // REV-116: откуда взят language
    headings: string[]; paragraphs: string[];
    serviceItems: Array<{ title: string; description?: string }>;
    navItems: string[];
    testimonials: Array<{ text: string; author?: string }>;
    images: string[];
    rating?: { value: number; count?: number };
    foundingYear?: number;
  };
  screenshotUrls: {
    desktopOriginal: string;
    mobileOriginal: string;
    desktopFull?: string;         // REV-21
    mobileFull?: string;          // REV-21
    comparisonBanner?: string;
  };
  cookieBannerHandled?: { desktop?: string; mobile?: string }; // REV-33: dismissed:cmp:<platform> | dismissed:text | ... | not_found | timeout | error
  aiFallbackUsed?: boolean;
  errorMessage?: string;
  createdAt: Date;
  completedAt?: Date;
}
```

#### 3. `mvp_projects`
```typescript
interface IMvpProject {
  _id: Types.ObjectId;
  auditId: Types.ObjectId;
  leadId: Types.ObjectId;         // один проект на лид; перегенерация обновляет его на месте
  previewSlug: string;            // e.g. "dental-art-a1b2c3"; не меняется при перегенерации
  fullPreviewUrl: string;         // <S3_ENDPOINT>/revamp-demos/v/<slug>/index.html
  storageHtmlPath: string;        // v/<slug>/index.html
  comparisonBannerUrl?: string;   // banners/<slug>.webp, 1200x630
  isPublished: boolean;
  generatedAt?: Date;             // REV-31
  generationCount?: number;       // REV-31
  editedAt?: Date;                // REV-85, REV-139: последняя опубликованная перемена (изменение, цвета и шрифты, восстановление)
  page?: string;                  // REV-138: сырая страница модели (плейсхолдеры не заполнены); нет у MVP прежнего генератора
  theme?: {                       // REV-138 (MvpThemeSchema): значения MVP_THEME_VARS из :root страницы
    primary: string; accent: string; bg: string; surface: string; text: string; fontHeading: string; fontBody: string;
  };
  controls?: Partial<IMvpTheme>;  // REV-139: цвета и шрифты оператора поверх theme; сбрасываются перегенерацией
  grounding?: Array<{             // REV-138: факты страницы, которых нет на исходном сайте; не отклоняют страницу
    kind: 'number' | 'name'; text: string; context: string;   // context — до 80 символов вокруг
  }>;
  versions?: Array<{              // REV-138: опубликованные версии, от старой к новой, не больше MVP_MAX_VERSIONS (20)
    n: number;                    // 1, 2, …; не переиспользуется
    kind: 'generate' | 'change' | 'restore';
    instruction?: string;         // слова оператора для change
    from?: number;                // версия, которую восстановил restore
    jobId?: string;               // задача, опубликовавшая версию (повтор задачи переиспользует ее)
    provider?: string; model?: string;
    storagePath: string;          // v/<slug>/versions/<n>.html
    createdAt: Date;
  }>;
  performance?: {                 // REV-119 (MvpPerformanceSchema): опубликованная страница в мобильном профиле аудита, LCP и CLS тем же кодом в странице (VitalsService.readVitalsInPage); при каждой публикации
    webVitals: { lcp?: number; cls?: number };   // lcp в мс; без LCP — error, подставного числа нет
    score?: number;               // calculatePerformanceScore, как у оригинала; только при LCP
    host: string;                 // где измерено: хост превью, а не хостинг бизнеса
    measuredAt: Date;
    error?: string;               // 'The page reported no largest-contentful-paint entry' или причина сбоя загрузки
  };
  standards?: {                   // REV-118 (MvpStandardsSchema): проверки опубликованной страницы теми же правилами, что и аудит; пересчитываются при каждой публикации
    checks: { https: boolean; viewport: boolean; title: boolean; metaDescription: boolean; singleH1: boolean; favicon: boolean; structuredData: boolean; openGraph: boolean };   // https — готовность к HTTPS: ничего не грузится по http://
    score: number;                // сумма баллов STANDARDS_POINTS пройденных проверок
  };
  completenessReport?: {          // REV-36/37
    status: 'verified' | 'unverified';
    score?: number;               // 0-100, веса critical 3 / important 2 / informational 1
    hasCriticalIssues: boolean;
    checks: Array<{
      field: CompletenessField; tier: 'critical' | 'important' | 'informational';
      status: 'present' | 'missing' | 'altered' | 'not_in_source' | 'unsourced';
      originalValue?: string; mvpValue?: string; note?: string; judgedBy?: 'llm' | 'code';
    }>;
    method?: 'llm' | 'deterministic';
    model?: string;
    llmError?: string;
    error?: string;
    checkedAt: Date;
  };
  provider?: 'anthropic' | 'openai' | 'gemini' | 'claude-cli' | 'deterministic'; // REV-32, REV-137: кто написал страницу; 'deterministic' — только у MVP прежнего генератора
  modelUsed?: string;
  requestedProvider?: 'anthropic' | 'openai' | 'gemini' | 'claude-cli';
  requestedModel?: string;
  createdAt: Date;
  updatedAt: Date;
}
```

#### 4. `email_campaigns` & `analytics_events`
```typescript
interface IEmailCampaign {
  _id: Types.ObjectId;
  leadId: Types.ObjectId;
  auditId: Types.ObjectId;
  mvpProjectId: Types.ObjectId;
  status: 'DRAFT' | 'NEEDS_APPROVAL' | 'APPROVED' | 'SCHEDULED' | 'SENDING' | 'DELIVERED' | 'BOUNCED' | 'REJECTED' | 'UNSUBSCRIBED';
  senderEmail: string;
  recipientEmail: string;
  subject: string;
  previewText?: string;
  bodyHtml: string;        // draftToHtml(body, preheader): экранированный HTML одобренного черновика (REV-72)
  bodyPlainText?: string;  // одобренный черновик как есть, без {{переменных}} (REV-72)
  trackingToken: string;
  requiresManualReview: boolean;
  approvedBy?: string;
  approvedAt?: Date;
  scheduledAt?: Date;
  sentAt?: Date;
  bouncedAt?: Date;
  bounceReason?: string;
  unsubscribedAt?: Date;   // первый POST /track/unsubscribe/:token (REV-73)
  metrics: {
    openedAt?: Date;
    openCount: number;
    clickedAt?: Date;
    clickCount: number;
    demoVisitCount: number;
    totalDwellTimeSeconds: number;
  };
}

interface IAnalyticsEvent {
  leadId?: Types.ObjectId;
  campaignId?: Types.ObjectId;
  mvpProjectId?: Types.ObjectId;
  trackingToken?: string;
  eventType: 'open' | 'click' | 'pageview' | 'dwell_time' | 'cta_click' | 'booking_intent' | 'scroll_depth' | 'token_usage' | 'unsubscribe';
  dwellTimeSeconds?: number;
  scrollDepthPercent?: number;
  ipHash?: string;
  userAgent?: string;
  metadata?: Record<string, unknown>;
  timestamp: Date;
}
```

---

## 5. Спецификация REST API (Express.js)

Базовый путь: `/api/v1`. Тела запросов и query-параметры валидируются Zod-схемами из `@revamp/validation` (`validateBody` / `validateQuery`). Ответы: `{ success: true, data }` или `{ success: false, error: { code, message, details? } }`. Эндпоинты с пометкой *(план)* описаны в первоначальном дизайне, но еще не реализованы.

**Формат ошибок (REV-63).** Все ошибки API имеют один формат: `{ success: false, error: { code, message, details? } }` (`IApiErrorResponse` из `@revamp/shared-types`). `code` — машиночитаемый код из `API_ERROR_CODES`, по нему клиент выбирает поведение; `message` — текст для оператора; `details` — необязательный контекст (например, `{ status }` лида или список ошибок Zod). Маршруты и сервисы не пишут JSON ошибок сами, а бросают `AppError(statusCode, code, message, details?)`; ответ формирует только `errorHandler`. Дашборд читает только `error.code` / `error.message` и бросает `ApiError` (`message`, `status`, `code`, `details`).

**Типы ответов в дашборде (REV-67).** Дашборд не объявляет форму ответов заново: лид, аудит и проект MVP типизированы как `Serialized<ILead>`, `Serialized<IAudit>`, `Serialized<IMvpProject>` (`Serialized<T>` из `@revamp/shared-types` превращает `Date` в ISO-строку, как в JSON). Мапперы читают только поля, которые возвращает API; лид без `_id` считается некорректным ответом. `GET /leads` не возвращает id аудита, поэтому дашборд запрашивает `GET /audits/:id` с id лида, и API отдает последний аудит лида.

| HTTP | `code` | Когда |
|---|---|---|
| `400` | `VALIDATION_ERROR` | Тело, query или params не прошли Zod-схему; `message` — первая ошибка (`path: message`), `details.issues` — все ошибки Zod |
| `400` | `INVALID_ID` | Неверный ObjectId (Mongoose `CastError` или проверка в маршрутах `/outreach`, `POST /mvp/:id/edit`, `PATCH /mvp/:id/tokens` и `POST /mvp/:id/versions/:n/restore`) |
| `400` | `INVALID_JSON` | Тело запроса — невалидный JSON |
| `413` | `PAYLOAD_TOO_LARGE` | Тело больше лимита `express.json` (10 МБ) |
| `409` | `DUPLICATE` | Нарушение уникального индекса MongoDB (код `11000`) |
| `404` | `NOT_FOUND` | Неизвестный маршрут |
| `500` | `INTERNAL` | Непредвиденная ошибка; в production `message` = `Internal server error` |
| `400` | `INVALID_URL` | `POST /leads`: `originalUrl` не разбирается как URL |
| `404` | `LEAD_NOT_FOUND` | Лид не найден (`/leads/:id`, `/audits/trigger`, `/mvp/generate`, `POST /mvp/:id/edit`, `PATCH /mvp/:id/tokens`, `POST /mvp/:id/versions/:n/restore`, `/outreach/*`) |
| `409` | `LEAD_NOT_AUDITABLE` | `POST /audits/trigger`: лид не в `QUEUED` / `AUDIT_FAILED` или изменился во время постановки; `details.status` |
| `404` | `AUDIT_NOT_FOUND` | `GET /audits/:id` |
| `400` | `LLM_PROVIDER_NOT_ALLOWED` | `POST /mvp/generate`: dev-only провайдер в production |
| `404` | `NO_COMPLETED_AUDIT` | `POST /mvp/generate`: у лида нет завершенного аудита |
| `409` | `MVP_GENERATION_NOT_ALLOWED` | `POST /mvp/generate`: статус лида не позволяет генерацию или лид изменился во время постановки; `details.status` |
| `409` | `MVP_ALREADY_GENERATED` | `POST /mvp/generate`: MVP уже есть, а `forceRegenerate` не задан; `details.status` |
| `404` | `MVP_NOT_FOUND` | `GET /mvp/:id`, `POST /mvp/:id/edit`, `PATCH /mvp/:id/tokens`, `POST /mvp/:id/versions/:n/restore` |
| `409` | `MVP_EDIT_NOT_ALLOWED` | `POST /mvp/:id/edit`, `PATCH /mvp/:id/tokens`, `POST /mvp/:id/versions/:n/restore`: лид не в `NEEDS_APPROVAL`; `details.status` (REV-85, REV-139) |
| `502` | `MVP_EDIT_FAILED` | `POST /mvp/:id/edit`, `PATCH /mvp/:id/tokens`, `POST /mvp/:id/versions/:n/restore`: ничего не опубликовано — задача упала или модель не дала страницы; `message` содержит причину, `details.reason` (`not_configured`, `call_failed`, `invalid_page`) и `details.problems` (коды `MVP_PAGE_CHECKS` с пояснениями) (REV-85, REV-139) |
| `409` | `MVP_PREVIOUS_GENERATOR` | `POST /mvp/:id/edit`, `PATCH /mvp/:id/tokens`, `POST /mvp/:id/versions/:n/restore`: MVP сделан прежним генератором (нет `page`/`theme`), к нему применима только перегенерация (REV-139) |
| `404` | `MVP_VERSION_NOT_FOUND` | `POST /mvp/:id/versions/:n/restore`: версии `n` нет в `MvpProject.versions` (REV-139) |
| `409` | `MVP_VERSION_UNUSABLE` | `POST /mvp/:id/versions/:n/restore`: версия не проходит проверку страницы по текущему аудиту (например, `{{hours}}` без часов работы); `details.problems`, ничего не опубликовано (REV-139) |
| `504` | `MVP_EDIT_TIMEOUT` | `POST /mvp/:id/edit`, `PATCH /mvp/:id/tokens`, `POST /mvp/:id/versions/:n/restore`: задача не завершилась за время ожидания (REV-85; с REV-139 — 420 с на изменение, 120 с на цвета, шрифты и восстановление). Воркер начинает публикацию, только если до конца ожидания осталось больше `PUBLISH_MARGIN_MS` (90 с), иначе ничего не публикует и API отвечает `502 MVP_EDIT_FAILED`; если задача уже выполнялась, `message` говорит, что изменение еще может быть опубликовано |
| `404` | `PREVIEW_NOT_FOUND` | `GET /mvp/preview/:slug` |
| `409` | `LEAD_NOT_AWAITING_APPROVAL` | `POST /outreach/:id/approve`: лид не в `NEEDS_APPROVAL` |
| `409` | `LEAD_NOT_REJECTABLE` | `POST /outreach/:id/reject`: outreach уже одобрен или лид закрыт |
| `409` | `NO_CONTACT_EMAIL` | `POST /outreach/:id/approve`: у лида нет e-mail |
| `503` | `EMAIL_PROVIDER_NOT_CONFIGURED` | `POST /outreach/:id/test`: `EMAIL_PROVIDER` не задан в API или у воркеров |
| `504` | `EMAIL_TEST_TIMEOUT` | `POST /outreach/:id/test`: воркеры не ответили за 30 с |
| `502` | `EMAIL_SEND_FAILED` | `POST /outreach/:id/test`: ошибка почтового провайдера |
| `404` | `DISCOVERY_JOB_NOT_FOUND` | `GET /discovery/:jobId`, `POST /discovery/:jobId/import` |
| `409` | `DISCOVERY_JOB_NOT_COMPLETED` | `POST /discovery/:jobId/import`: задача еще не завершена |
| `502` | `GEOCODING_UNAVAILABLE` | `GET /discovery/reverse-geocode`: сбой Nominatim |
| `404` | `PLACE_NOT_FOUND` | `GET /discovery/reverse-geocode`: место не найдено |

С REV-139 у страницы, написанной моделью, `PATCH /mvp/:id/tokens` принимает `UpdateMvpTokensSchema` `{ colors?: { primary, accent, bg, surface, text } | null, fonts?: { heading, body } | null }` (текст на `bg` и `surface` с контрастом не ниже 4,5:1, шрифты — пара из `MVP_FONT_CHOICES`, `null` снимает группу), а `POST /mvp/:id/edit` переписывает страницу моделью; обе задачи идут в `mvp-page-queue` (воркер по одной задаче). `PATCH /mvp/:id/layout` и `DELETE /mvp/:id/design` удалены, код `MVP_MODEL_DESIGNED` снят. Коды `MVP_LAYOUT_CHANGE_NOT_ALLOWED`, `MVP_PALETTE_CHANGE_NOT_ALLOWED`, `MVP_REBUILD_UNAVAILABLE` и `MVP_MODERNIZE_UNAVAILABLE` удалены вместе с прежним генератором (REV-141); у лидов, сгенерированных им, они могут остаться в `Lead.generationFailure`. Маршруты описаны в §5.2–5.3.

Исключения: `GET /health` отвечает `503` телом отчета о состоянии (`status: "degraded"`), а страницы отписки `/track/unsubscribe/:token` — HTML.

### 5.1. Управление лидами и аудитами (`/leads`, `/audits`)
| Метод | Эндпоинт | Описание | Body / Параметры |
|---|---|---|---|
| `POST` | `/leads` | Создать лид (`QUEUED`) и поставить аудит в очередь | `CreateLeadSchema`: `{ businessName, originalUrl, contactEmail?, niche, city?, contactPhone?, ownerName? }` (без e-mail аудит берет его с сайта, REV-45) |
| `GET` | `/leads` | Список лидов с фильтрами и пагинацией (`pagination.total`); каждый лид несет краткую сводку полноты MVP (`completeness`). `search` ищет подстроку без учета регистра (спецсимволы экранируются). Дашборд загружает все страницы по `limit=100` (REV-43) | `?status=&niche=&complexity=&search=&page=&limit=` (`limit` ≤ 100, по умолчанию 20) |
| `GET` | `/leads/stats` | Счетчики по всей воронке без учета фильтров списка → `{ total, byStatus }` (`ILeadStats`); источник KPI-карточек дашборда (REV-43) | — |
| `GET` | `/leads/:id` | Детальная карточка лида + связанный аудит | — |
| `POST` | `/audits/trigger` | Перезапуск аудита (новый документ `Audit`) для лида в `QUEUED` или `AUDIT_FAILED` (→ `QUEUED`); иначе `409 LEAD_NOT_AUDITABLE` (REV-62) | `{ leadId }` |
| `GET` | `/audits/:id` | Результаты аудита, метрики, ссылки на скриншоты | — |

### 5.2. Модуль генерации MVP (`/mvp`)
| Метод | Эндпоинт | Описание | Body / Параметры |
|---|---|---|---|
| `GET` | `/mvp/providers` | LLM-провайдеры и модели для генерации и доступность каждого по последнему отчету воркеров (REV-32) | — |
| `POST` | `/mvp/generate` | Запуск генерации/перегенерации MVP → `202 { jobId, status: 'GENERATING' }` | `GenerateMvpSchema`: `{ auditId, forceRegenerate?, provider?, model? }` |
| `GET` | `/mvp/:id` | Проект MVP по `_id`, `leadId`, `auditId` или `previewSlug` (с отчетом полноты); `404 MVP_NOT_FOUND`, если MVP нет (REV-45) | — |
| `GET` | `/mvp/preview/:slug` | Редирект на опубликованное превью с заголовками CSP / `X-Frame-Options`; `404 PREVIEW_NOT_FOUND`, если превью нет | — |
| `PATCH` | `/mvp/:id/tokens` | Цвета и шрифты оператора поверх темы страницы (REV-139) по `_id` проекта MVP: задача `controls` в `mvp-page-queue` (ожидание до 120 с) сохраняет `controls`, заново завершает сохраненную страницу и публикует ее без вызова модели и без новой версии. `200 { applied, mvp }`. `400 INVALID_ID`, `404 MVP_NOT_FOUND` / `LEAD_NOT_FOUND`, `409 MVP_PREVIOUS_GENERATOR`, `409 MVP_EDIT_NOT_ALLOWED` вне `NEEDS_APPROVAL`, `502 MVP_EDIT_FAILED`, `504 MVP_EDIT_TIMEOUT` | `UpdateMvpTokensSchema`: `{ colors?: { primary, accent, bg, surface, text } \| null, fonts?: { heading, body } \| null }` (текст на `bg` и `surface` ≥ 4,5:1, шрифты — пара `MVP_FONT_CHOICES`, `null` снимает группу) |
| `POST` | `/mvp/:id/versions/:n/restore` | Восстановление версии страницы, написанной моделью (REV-139): задача `restore` в `mvp-page-queue` (ожидание до 120 с) читает `v/<slug>/versions/<n>.html`, проверяет ее по текущему аудиту и публикует с текущими цветами и шрифтами оператора как новую версию `restore` (`from: n`). `200 { applied, version?, mvp }` (`applied: false, reason: 'unchanged'`, если страница та же). `400 VALIDATION_ERROR` / `INVALID_ID`, `404 MVP_NOT_FOUND` / `MVP_VERSION_NOT_FOUND`, `409 MVP_PREVIOUS_GENERATOR` / `MVP_EDIT_NOT_ALLOWED` / `MVP_VERSION_UNUSABLE`, `502 MVP_EDIT_FAILED`, `504 MVP_EDIT_TIMEOUT` | `MvpVersionParamsSchema`: `n` ≥ 1 |

Коды ошибок `POST /mvp/generate`: `400 VALIDATION_ERROR` (неизвестный провайдер или модель другого провайдера), `400 LLM_PROVIDER_NOT_ALLOWED` (dev-only провайдер в production; сейчас таких нет), `404 NO_COMPLETED_AUDIT` / `404 LEAD_NOT_FOUND`, `409 MVP_ALREADY_GENERATED` (MVP есть, а `forceRegenerate` не задан), `409 MVP_GENERATION_NOT_ALLOWED` (письмо уже в отправке или идет генерация).

Выбор аудита для генерации (REV-55): у лида может быть несколько аудитов (каждый повтор создает новый). `auditId` в запросе — id аудита или, если у дашборда его нет, id лида. Берется указанный аудит, если он `COMPLETED`, иначе самый новый `COMPLETED` аудит этого лида; `FAILED` или незавершенный аудит (без контента сайта) никогда не используется. API передает id найденного аудита в задачу `ai-gen-queue`, а AI- и deploy-воркеры загружают именно его (по тому же правилу, с проверкой `leadId`). Нет завершенного аудита — `404` в API и ошибка задачи в воркерах.

### 5.3. Модуль аутрича и подтверждения (HITL) (`/outreach`)
| Метод | Эндпоинт | Описание | Body / Параметры |
|---|---|---|---|
| `GET` | `/outreach/pending` | Лиды, ожидающие ручного подтверждения (`NEEDS_APPROVAL`) | — |
| `POST` | `/outreach/:id/approve`| **[HITL Action]** Одобрить: лид → `SCHEDULED`, письмо в `email-queue` с джиттером. Только из `NEEDS_APPROVAL`, атомарно (`findOneAndUpdate` с фильтром статуса); иначе `409 LEAD_NOT_AWAITING_APPROVAL` (REV-59). `409 NO_CONTACT_EMAIL`, если у лида нет e-mail (REV-45); `404 LEAD_NOT_FOUND`. Дашборд присылает черновик в том виде, как его показывает превью, с подставленными переменными (REV-72). `body` — простой текст: он сохраняется в `bodyPlainText`, а в `bodyHtml` — экранированный HTML с абзацами, переносами строк и скрытым preheader (`draftToHtml` из `@revamp/shared-types`, та же функция, что у тестовой отправки). `subject` (1–300 символов) и `body` (1–20000) обязательны, текста по умолчанию нет: без них `400` и ничего не меняется (REV-61) | `{ subject, body, preheader?, approvedBy?, scheduleTime? }` |
| `POST` | `/outreach/:id/reject` | Отклонить отправку (лид → `REJECTED`). Только до одобрения, атомарно; для `SCHEDULED` и далее, `REJECTED`, `UNSUBSCRIBED` — `409 LEAD_NOT_REJECTABLE` (REV-59); `404 LEAD_NOT_FOUND` | `{ reason: string }` |
| `POST` | `/mvp/:id/edit` | Изменение страницы своими словами (REV-85, REV-139) по `_id` проекта MVP: задача `change` в `mvp-page-queue`, API ждет до 420 с. Генератор страницы (режим `change`) получает текущую сырую страницу и слова оператора и возвращает всю страницу; `checkMvpPage` и один повтор, как у генерации; принятая страница публикуется как новая версия `change`. `200 { applied: true, version, mvp }` или `{ applied: false, reason: 'unchanged', mvp }`. `400 INVALID_ID`, `404 MVP_NOT_FOUND` / `LEAD_NOT_FOUND`, `409 MVP_PREVIOUS_GENERATOR`, `409 MVP_EDIT_NOT_ALLOWED`, `502 MVP_EDIT_FAILED` (ничего не опубликовано), `504 MVP_EDIT_TIMEOUT`. Статус лида не меняется | `EditMvpSchema`: `{ instruction: string (3–500, trim) }` |
| `POST` | `/outreach/:id/test`   | Отправляет текущий черновик (как в превью, с подставленными переменными) на почту оператора через `email-test-queue` и ждёт результата воркера до 30 с (REV-60). Не проходит HITL-гейт, не добавляет пиксель открытий и не меняет лид и `EmailCampaign`. `200` с `{ to, messageId, provider, sentAt }`; `503 EMAIL_PROVIDER_NOT_CONFIGURED`, если `EMAIL_PROVIDER` не задан в API или у воркеров; `502 EMAIL_SEND_FAILED` при ошибке провайдера; `504 EMAIL_TEST_TIMEOUT`, если воркеры не ответили (ожидающая задача удаляется); `404 LEAD_NOT_FOUND`; `400` для неверного id или тела | `{ testEmail, subject, body, preheader? }` |
| `PUT` | `/outreach/:id/draft` | *(план)* Сохранение черновика без отправки | `{ subject, bodyHtml }` |

### 5.4. Поиск локальных бизнесов (`/discovery`) — REV-26…REV-29
| Метод | Эндпоинт | Описание | Body / Параметры |
|---|---|---|---|
| `POST` | `/discovery` | Поставить поиск в `discovery-queue` → `202 { jobId }` | `StartDiscoverySchema`: `{ provider: 'osm'\|'google', niche, location, keyword?, limit (1-100, по умолч. 20), excludeDomains? (до 1000 доменов, REV-107) }` |
| `GET` | `/discovery/reverse-geocode` | Координаты браузера → `"City, Country"` через Nominatim (уровень города); `404 PLACE_NOT_FOUND` если не найдено, `502 GEOCODING_UNAVAILABLE` при сбое Nominatim | `?lat&lng&lang` |
| `GET` | `/discovery/:jobId` | Состояние задачи (`waiting`/`active`/`completed`/`failed`/…), параметры, кандидаты; `new`-кандидаты перепроверяются по текущим лидам | — |
| `POST` | `/discovery/:jobId/import` | Импорт выбранных кандидатов как лидов; данные берутся только из результата задачи; `404 DISCOVERY_JOB_NOT_FOUND` неизвестная задача, `409 DISCOVERY_JOB_NOT_COMPLETED` задача не завершена | `ImportDiscoverySchema`: `{ externalIds: string[] (1-100) }` |

### 5.5. Трекинг активности и аналитика (`/track`, `/health`)
| Метод | Эндпоинт | Описание |
|---|---|---|
| `GET` | `/track/open/:token.gif` | 1x1 прозрачный пиксель отслеживания открытия письма (лид → `OPENED`) |
| `GET` | `/track/click/:token` | Редирект на демо-сайт с логированием клика (лид → `CLICKED`) |
| `POST` | `/track/mvp-event` | Beacon API: время на странице, скролл, клики в демо (лид → `ENGAGED`) |
| `GET` | `/track/unsubscribe/:token` | HTML-страница подтверждения отписки с кнопкой (POST на тот же адрес); ничего не меняет, чтобы сканеры ссылок не отписывали получателей (RFC 8058). «Вы отписаны», если отписка уже была; `404` для неизвестного токена (REV-73) |
| `POST` | `/track/unsubscribe/:token` | One-click отписка (RFC 8058, тело `List-Unsubscribe=One-Click`) и кнопка подтверждения: лид и `EmailCampaign` → `UNSUBSCRIBED`, `unsubscribedAt`, событие `unsubscribe`; `200`, идемпотентно; `404` для неизвестного токена без изменений (REV-73) |
| `GET` | `/track/revamp-tracker.js` | Скрипт трекинга для страниц MVP (`Cross-Origin-Resource-Policy: cross-origin`, чтобы страница из хранилища могла его загрузить) |
| `GET` | `/health` | Проверка доступности API, MongoDB и Redis: `200` (`status: "ok"`), когда MongoDB `connected` и Redis `ready`/`connect`; иначе `503` с тем же телом (`status: "degraded"`, в `services` — фактические статусы), чтобы Docker `HEALTHCHECK` (`curl -f`) перезапускал контейнер без БД (REV-66) |
| `GET` | `/analytics/overview` | *(план)* Метрики воронки, open rate, CTR, средний скоринг |

**Завершение работы API (REV-66):** по `SIGTERM`/`SIGINT` сервер перестаёт принимать запросы и сразу закрывает простаивающие keep-alive сокеты; незавершённые запросы получают 5 с, после чего соединения закрываются принудительно. Затем закрываются очереди BullMQ (и `QueueEvents` тестовых писем и изменений MVP, REV-85), соединение Redis и MongoDB, процесс завершается с кодом `0`. Если шаг зависает, через 8 с (меньше 10 с по умолчанию у `docker stop`) процесс завершается с кодом `1`.

**CORS для `/track/*` (REV-52):** кроме `CORS_ORIGIN` дашборда, разрешены origin хранилища MVP (`S3_ENDPOINT` локально) и `https://{PREVIEW_DOMAIN}`. `navigator.sendBeacon` всегда отправляет запрос с `credentials: include`, поэтому ответ содержит `Access-Control-Allow-Credentials: true` при явном списке origin (не `*`). Остальные маршруты API доступны только `CORS_ORIGIN`.

---

## 6. Архитектура очередей задач (BullMQ & Redis)

Для изоляции нагрузки и предотвращения утечек памяти Playwright задачи разделены по специализированным очередям с индивидуальными лимитами конкурентности. Имена очередей — `QUEUE_NAMES` в `@revamp/shared-types` (REV-48); `queues/queue.constants.ts` API и воркеров реэкспортирует их.

```mermaid
graph LR
    subgraph Producers
        API_Disc[POST /discovery]
        API_Import[POST /discovery/:jobId/import]
        API_Post[POST /leads, POST /audits/trigger]
        API_Gen[POST /mvp/generate]
        API_Approve[POST /outreach/:id/approve]
    end

    subgraph Redis_Queues [Redis / BullMQ Queues]
        Q_Disc[(discovery-queue)]
        Q_Audit[(audit-queue)]
        Q_AI[(ai-gen-queue)]
        Q_Deploy[(deploy-queue)]
        Q_Mail[(email-queue)]
        Q_Test[(email-test-queue)]
        Q_Page[(mvp-page-queue)]
    end

    subgraph Workers_Pool [Node.js Workers]
        W0[Discovery Worker<br/>Concurrency: 1]
        W1[Audit Worker<br/>Concurrency: 2]
        W2[AI Worker<br/>Concurrency: 5]
        W3[Deploy Worker<br/>Concurrency: 5]
        W4[Email Dispatcher<br/>Concurrency: 1, 1 письмо / 180 с]
        W5[Email Test Sender<br/>Concurrency: 1, без лимита]
        W6[MVP Page Worker<br/>Concurrency: 1]
    end

    API_Disc --> Q_Disc --> W0
    W0 -.->|Кандидаты в результате задачи| API_Import
    API_Import --> Q_Audit
    API_Post --> Q_Audit
    Q_Audit --> W1
    W1 -->|Авто-цепочка| Q_AI
    API_Gen --> Q_AI
    Q_AI --> W2
    W2 --> Q_Deploy
    Q_Deploy --> W3
    W3 -.->|NEEDS_APPROVAL| HITL[Human In The Loop Approval]
    HITL --> API_Approve
    API_Approve --> Q_Mail
    Q_Mail --> W4
    HITL -->|Тест себе| Q_Test --> W5
    HITL -->|Изменение, цвета и шрифты, восстановление| Q_Page --> W6
```

### Настройки воркеров:
1. **`discovery-queue` Worker:**
   * Concurrency: `1` (правила добросовестного использования Nominatim/Overpass).
   * Ретраи: 2 попытки с экспоненциальным откатом от 10 с; ошибки конфигурации завершаются `UnrecoverableError` без повтора.
2. **`audit-queue` Worker:**
   * Concurrency: `2` (Playwright ресурсоемок).
   * Sandbox: каждый запуск в отдельном контексте браузера, таймаут навигации 25 с, перезапуск браузера каждые 20 задач.
   * Ретраи: 3 попытки, экспоненциальный откат от 3 с. Постоянные ошибки навигации (`ERR_NAME_NOT_RESOLVED`, `ERR_CERT_*`, `ERR_INVALID_URL`) завершаются `UnrecoverableError` без повтора. После последней попытки лид переходит из `AUDITING` в `AUDIT_FAILED` с причиной в `auditError` (`audit-failure.ts`, REV-44). Лиды, застрявшие до исправления, переводятся скриптом `backfill:stuck-audits`.
   * По завершении ставит задачу в `ai-gen-queue`. При старте воркеров лиды, застрявшие в `AUDITED` с завершенным аудитом, ставятся в очередь повторно (`recoverStalledAuditedLeads`).
3. **`ai-gen-queue` Worker:**
   * Concurrency: `5`. Ретраи: 3 попытки, экспоненциальный откат от 5 с; внутри задачи — генератор страницы (Агент 2 в `AGENTS.md`): до 2 обращений к модели (температура 0.7, затем 0.3 с причинами отклонения). `not_configured` и `invalid_page` — `MvpPageUnavailableError` (`UnrecoverableError`), без ретраев; `call_failed` повторяется ретраями задачи. Запасной страницы нет.
   * Принятая страница, тема и флаги фактов передаются в `deploy-queue` (`IDeployJobData.page`).
   * Payload несет `forceRegenerate`, `previousStatus` и выбор оператора (`provider`, `model`).
4. **`deploy-queue` Worker:**
   * Concurrency: `5`. Ретраи: 3 попытки, экспоненциальный откат от 5 с.
   * Публикация страницы модели (`publishFinishedPage`): `finishMvpPage`, выгрузка `index.html` и версии в `revamp-demos`, стандарты, скорость, проверка полноты, баннер «До/После», `Lead.status = NEEDS_APPROVAL`. Задача без страницы отклоняется `UnrecoverableError` (REV-141).
   * Обработчик `failed` (общий с AI-воркером, `generation-failure.ts`) после последнего ретрая — или сразу при `UnrecoverableError` — возвращает лид из `GENERATING` и пишет `generationError`, а если страницу не дала модель, еще `generationFailure` (`MVP_PAGE_UNAVAILABLE`).
5. **`email-queue` Worker:**
   * Throttling: строго 1 письмо в 3 минуты (BullMQ limiter `max: 1, duration: 180000`).
   * Jitter: случайная задержка 15–45 секунд, рассчитываемая API при постановке задачи.
   * Провайдер: `EMAIL_PROVIDER` (`resend`, `sendgrid` или `smtp`), значения по умолчанию нет. Без него задача отправки завершается ошибкой, а не помечает письмо отправленным (REV-45).
   * Содержимое: `bodyHtml` и `bodyPlainText` кампании отправляются как HTML- и текстовая части письма без изменений. Оба заполняются при одобрении из того же черновика, что видел оператор, поэтому реальное письмо совпадает с тестовым (REV-72).
   * Не больше одного письма на одобрение (REV-61). Перед отправкой воркер атомарно захватывает кампанию (`SCHEDULED`/`APPROVED` → `SENDING`, `findOneAndUpdate` с фильтром статуса). Сразу после того как провайдер принял письмо, кампания получает `DELIVERED` и `sentAt`, затем лид — `SENT`. Если провайдер вернул ошибку, захват снимается (`SENDING` → `SCHEDULED`) и ретрай отправляет письмо. Ретрай пропускает кампанию в `SENDING` (письмо могло уже уйти) и для кампании в `DELIVERED` только дописывает `SENT` у лида, без повторной отправки.
   * Только одобренный текст (REV-61): без кампании или с пустыми темой/телом задача падает с `UnrecoverableError` без ретраев и ничего не отправляет. Текста по умолчанию нет.
6. **`email-test-queue` Worker (REV-60):**
   * Тестовая отправка черновика оператору. Отдельная очередь, чтобы тест не ждал лимита аутрича и не задерживал его: concurrency `1`, без limiter, 1 попытка без ретраев (оператор ждёт ответа).
   * Тот же `emailService` и провайдер, что у `email-queue`, но без HITL-гейта, MX-проверки и пикселя открытий (`trackOpens: false`); тема с префиксом `[Test]`. Лид и `EmailCampaign` не читаются и не меняются.
   * API ждёт результата через `QueueEvents` до 30 с. Без провайдера задача падает с `EMAIL_PROVIDER_NOT_CONFIGURED`, и API отвечает `503`.
7. **`mvp-page-queue` Worker (REV-139):**
   * Изменения опубликованной страницы модели: concurrency `1` (по одной задаче, чтобы версии не пересекались), 1 попытка без ретраев (оператор ждёт ответа), API ждёт результата через `QueueEvents` до 420 с (`change`) или 120 с (`controls`, `restore`).
   * `change` — генератор страницы в режиме `change` (Агент 2): текущая сырая страница и слова оператора, `checkMvpPage`, один повтор; `controls` — сохраняет цвета и шрифты оператора без модели; `restore` — проверяет сырую страницу версии по текущему аудиту (`unusable_version` → `409 MVP_VERSION_UNUSABLE`).
   * Публикация — тот же путь, что у деплоя (`publishFinishedPage`): `finishMvpPage`, выгрузка, стандарты, скорость, полнота, флаги, баннер; новая версия (`change`, `restore`) и `editedAt` пишутся одним обновлением, не больше `MVP_MAX_VERSIONS` версий.
   * Задача несет `deadline`: воркер начинает публикацию, только если до срока осталось больше `PUBLISH_MARGIN_MS` (90 с), иначе ничего не меняет (`expired`); лид, покинувший `NEEDS_APPROVAL` за время ответа модели, тоже не меняется.
---

## 7. Безопасность, отказоустойчивость и соответствие нормам

1. **Изоляция сгенерированных MVP:**
   * Сгенерированный код размещается на отдельном домене (`*.revampdemo.com`), изолированном от основного приложения.
   * Строгая политика `Content-Security-Policy` (CSP): запрет `unsafe-eval`, ограничение подключения сторонних скриптов, песочница для `<iframe>` в дашборде (`sandbox="allow-scripts allow-same-origin"`).
2. **Защита от Abuse & Спам-блокировок:**
   * Blacklist доменов: исключение правительственных сайтов, банков, крупных корпораций, сайтов с явным указанием `no-outreach`.
   * Автоматический мониторинг репутации IP и доменов отправки (Postmaster Tools API).
3. **Аутентификация и права доступа в Дашборде:**
   * JWT Access/Refresh tokens в `httpOnly`, `Secure`, `SameSite=Strict` cookie.
   * RBAC (Role-Based Access Control):
     - `Admin`: настройка SMTP, API-ключей, управление пользователями.
     - `Operator / Reviewer`: просмотр лидов, правка писем, ручной аппрув отправки.
     - `Viewer`: просмотр аналитики без права отправки.
   * *Статус:* аутентификация и RBAC пока не реализованы; дашборд и API рассчитаны на одного оператора в закрытом окружении.
4. **Внешние источники данных и LLM (REV-26…REV-37):**
   * **Discovery:** запросы к Nominatim/Overpass идут с идентифицирующим `User-Agent` и конкурентностью 1; Google Maps не парсится, используется только официальный Places API. Импорт берет данные кандидатов только из сохраненного результата задачи, а не из тела запроса, поэтому клиент не может подменить сайт или контакты.
   * **Геолокация оператора:** обратное геокодирование проксируется через API и ограничено уровнем города, чтобы не возвращать улицу оператора.
   * **Локальный Claude Code CLI:** запуск в одноходовом headless-режиме без инструментов, MCP-серверов и пользовательских/проектных настроек, во временной рабочей папке (чтобы CLI не подхватил `CLAUDE.md`/`AGENTS.md` репозитория), с таймаутом `CLAUDE_CLI_TIMEOUT_MS`.
   * **Провайдеры LLM:** выбор оператора не переключает задачу на другой платный провайдер при сбое; у страницы MVP запасного варианта нет (`call_failed`), у критики — шаблон, который не оценивается (REV-101). Без настроенного провайдера генерация и Vision-критика завершаются ошибкой (REV-45).
   * **Grounding:** LLM никогда не выводит телефоны, e-mail и адреса; проверка полноты помечает выдуманные контакты как `unsourced`, а одобрение лида с критическими проблемами требует дополнительного подтверждения оператора.

---

## 8. Дорожная карта разработки (Implementation Roadmap)

```mermaid
gantt
    title Этапы реализации SaaS Revamp
    dateFormat  YYYY-MM-DD
    section Фаза 1: Ядро и Аудит
    Архитектура, Express, Mongo, Redis     :2026-10-01, 7d
    Playwright + Axe + Lighthouse воркер  :2026-10-08, 10d
    Снятие скриншотов и хранилище S3       :2026-10-18, 5d

    section Фаза 2: AI и Генерация MVP
    Brand Token Extractor (стили/лого)     :2026-10-23, 7d
    Библиотека Bento/Tailwind секций (заменено REV-135)       :2026-10-30, 8d
    Vision LLM интеграция & сборщик MVP    :2026-11-07, 10d

    section Фаза 3: React & MUI Дашборд
    Каркас MUI, DataGrid и Kanban          :2026-11-17, 10d
    Сплит-экран ревью (До/После) + HITL    :2026-11-27, 8d
    WYSIWYG редактор письма                :2026-12-05, 5d

    section Фаза 4: Аутрич и Аналитика
    BullMQ Email Dispatcher + Throttling   :2026-12-10, 7d
    Tracking Pixel & Beacon Analytics      :2026-12-17, 6d
    E2E Тестирование и запуск в прод       :2026-12-23, 8d
```

### Фаза 1: Фундамент и модуль аудита (Недели 1–3)
* Подготовка репозитория (Monorepo: `apps/api`, `apps/dashboard`, `packages/shared-types`).
* Настройка моделей MongoDB и базового Express API.
* Воркер аудита: Playwright + Lighthouse API + Axe-core, загрузка скриншотов в S3/MinIO.

### Фаза 2: Модуль генерации MVP (Недели 4–6)
* Парсинг CSS и извлечение палитры/логотипов.
* Шаблонизатор адаптивных лендингов на базе современных Tailwind-компонентов (исторический план; заменено REV-135 — страницу пишет модель).
* Интеграция Vision AI для оценки исходного сайта и генерации улучшенных формулировок.
* Хостинг демо-страниц и автоматическая генерация баннеров «До/После».

### Фаза 3: React + Material UI Дашборд (Недели 7–9)
* Полнофункциональный интерфейс: список лидов, фильтры, статусные пайплайны.
* Экран сравнения (Split-screen Comparison View) с живым предпросмотром MVP.
* Модальное окно оператора: HITL-подтверждение, правка текста и регенерация блоков.

### Фаза 4: Почтовый аутрич и трекинг (Недели 10–12)
* Очередь отправки писем с защитой доменов (BullMQ + Nodemailer / Resend).
* Сервер отслеживания кликов, открытий и времени нахождения на демо-сайте.
* Экран аналитики конверсий и интеграционное тестирование всего цикла.

### Фаза 5: Развитие после релиза (REV-21 — REV-41)
После закрытия первоначальной дорожной карты (REV-1 — REV-20) работа продолжается отдельными тикетами в Linear по конвейеру «тикет → код → тесты → PR → merge». Состав и статусы — в [milestones.md](./milestones.md#6-развитие-после-релиза-rev-21--rev-41):
* Качество аудита: полностраничные скриншоты (REV-21), закрытие cookie-баннеров (REV-33).
* Качество MVP: контент исходного сайта вместо шаблонов (REV-23), язык исходного сайта (REV-25), лимиты полей (REV-34), проверка полноты кодом и LLM (REV-36, REV-37).
* Генерация: локальный Claude Code CLI (REV-30), перегенерация (REV-31), выбор провайдера и модели (REV-32).
* Лидогенерация: поиск бизнесов на картах (REV-26 — REV-29), фильтрация уже существующих лидов (REV-35, в работе).
* Дашборд: английский интерфейс (REV-22) и локализация en/ru/be/pl/lt (REV-24).
