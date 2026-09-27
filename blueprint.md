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
        W_AI[AI Worker: MvpContentAgent через LlmClient]
        W_Gen[Deploy Worker: Bento-сборка + проверка полноты + S3]
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
    Controllers -->|reverse-geocode| Maps
```

> Воркеры раз в 60 секунд публикуют в Redis (`revamp:llm-capabilities`, TTL 180 с) список LLM-провайдеров, которые они могут запустить (есть API-ключ, найден бинарник `claude`). API читает этот ключ для `GET /mvp/providers`, поскольку ключи и CLI живут на хосте воркеров, а не API (REV-32).

### Стек технологий:
* **Backend:** Node.js (v20+ LTS, TypeScript), Express.js.
* **База данных:** MongoDB (Mongoose ODM), реплика-сет, транзакции для операций статусов. Схемы — в общем пакете `@revamp/db`, который используют API и воркеры (REV-48).
* **Очереди и кэш:** Redis (v7+) + BullMQ (для отказоустойчивой асинхронной обработки тяжелых задач браузера и LLM).
* **Headless Browser & Аудит:** Playwright (Chromium), `@axe-core/playwright`, замеры Core Web Vitals в браузере, `happy-dom` для разбора HTML сгенерированного MVP.
* **Поиск бизнесов (Discovery):** OpenStreetMap (Nominatim + Overpass, без ключа, ODbL) и Google Places API (New) Text Search (по ключу).
* **AI & LLM:** единый `LlmClient` для Anthropic, OpenAI, Gemini и локального Claude Code CLI; каталог провайдеров и моделей — в `@revamp/shared-types` (`LLM_PROVIDER_CATALOG`). Оператор выбирает провайдера и модель для каждой генерации MVP. LLM пишет только тексты и суждения; HTML строится детерминированным шаблоном.
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
    participant UI as DiscoveryModal (Дашборд)
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
* **OpenStreetMap (по умолчанию, без ключа):** Nominatim превращает локацию в область Overpass (или радиус вокруг точки), Overpass возвращает объекты с тегами ниши (`OSM_NICHE_FILTERS`) и только с сайтом. Запросы идут с идентифицирующим `User-Agent` (`DISCOVERY_USER_AGENT`), как требуют правила Nominatim/Overpass; конкурентность воркера — `1`.
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

4. **Мультимодальный AI-анализ дизайна (Vision UX/UI Critique):**
   * Скриншоты отправляются в Vision LLM со специализированным системным промптом:
     - Оценка визуальной иерархии (Visual Hierarchy & Scannability).
     - Читаемость типографики на мобильных устройствах.
     - Заметность и привлекательность основного CTA (Call to Action).
     - Эффект «устаревшего сайта» (Dated Design Smell: градиенты 2010-х, неадаптивные таблицы, перегруженные меню).
     - Формирование списка из 3 критических UX-проблем и 3 очевидных точек роста (Quick Wins).
   * **Провайдеры Vision (REV-51):** `VISION_LLM_PROVIDER` (`anthropic`, `openai`, `claude-cli`) или, если он пуст, по порядку: ключ Anthropic, ключ OpenAI, локальный Claude Code CLI (если `CLAUDE_CLI_PATH` найден). CLI получает оба скриншота первого экрана (mobile и desktop WebP) как image-блоки одного сообщения через `--input-format stream-json` / `--output-format stream-json` с теми же ограничениями, что и для текста: без инструментов, MCP, настроек и сохранения сессии, во временной рабочей папке. `modelUsed` = `claude-cli:<CLAUDE_CLI_MODEL>`, токены берутся из события `result` CLI (включая кэшированный ввод). Без доступного провайдера аудит завершается ошибкой (REV-45); детерминированная критика применяется только после 3 неудачных реальных вызовов (`aiFallbackUsed: true`, событие `token_usage` не пишется).

#### 1.2. Структура скоринга (Composite Score Formula):
$$\text{Total Score} = 0.35 \times S_{\text{Design/UX}} + 0.25 \times S_{\text{Performance}} + 0.20 \times S_{\text{Accessibility}} + 0.20 \times S_{\text{Standards/SEO}}$$

Каждый критерий нормализуется от 0 до 100. При оценке ниже 60 система генерирует конкретные продающие тезисы для холодного письма (например: *"Ваш мобильный сайт теряет до 45% клиентов из-за медленного LCP 4.8s и нечитаемого шрифта на смартфонах"*).

---

### Модуль 2: Модуль генерации уникальных MVP с сохранением брендового стиля

Модуль решает сложную инженерную задачу: не просто сгенерировать абстрактный лендинг, а создать **премиальную версию сайта конкретного бизнеса**, сохранив его айдентику (цвета, логотип, тексты, перечень услуг), но упаковав это в современный UX-каркас с конверсионными блоками.

```mermaid
flowchart TD
    AuditData[Данные аудита + DOM] --> TokenExtractor[Brand Token Extractor]
    
    subgraph TokenExtractor [Экстрактор ДНК бренда]
        Pal[Доминирующие цвета: Primary, Secondary, Accent]
        Logo[Логотип: SVG/High-res PNG]
        Copy[Контент: Телефон, Адрес, Список услуг, УТП]
        Fonts[Семейства шрифтов: Засечки / Без засечек]
    end

    TokenExtractor --> AICodeGen[MvpContentAgent: тексты на языке сайта, Strict Grounding]
    AICodeGen -->|Провайдер/модель, выбранные оператором| AICodeGen
    AICodeGen --> CodeAssembly[Bento-шаблон: HTML + локализованный UI-текст]
    CodeAssembly --> Completeness[Проверка полноты: MVP против данных исходного сайта]
    Completeness --> StaticDeploy[Деплой в S3 revamp-demos по постоянному previewSlug]
    StaticDeploy --> OpenGraph[Генерация превью-скриншота До / После]
    OpenGraph --> Review[Lead.status = NEEDS_APPROVAL]
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

2. **Выбор компонентной сетки (Design System & Bento Layout):**
   * Используется модульная библиотека современных адаптивных секций на Tailwind CSS:
     - **Sticky Modern Header:** Логотип + Кнопка быстрого вызова + CTA «Записаться».
     - **Hero Section:** Усиленное УТП (переписанное через AI под формулу боли/выгоды) + форма мгновенного захвата контактов + социальные доказательства (бейджи Яндекс/Google карт).
     - **Bento Grid Services:** Карточки ключевых услуг бизнеса с современными иконками (Lucide/Heroicons).
     - **Trust & Reviews Block:** Интерактивная карусель отзывов клиентов.
     - **Interactive Booking Widget:** Интерактивное модальное окно для записи на прием / расчета стоимости.
     - **Footer & Location Map:** График работы, кликабельная интерактивная карта.

   * **Только реальные данные (REV-23):** шаблон не содержит выдуманных значений по умолчанию. Кнопка звонка, полоса доверия, отзывы, часы работы и контакты отображаются только при наличии извлеченных данных. Добавлены секции «О нас», hero-изображение, галерея и соцсети; адрес ведет на Google Maps. Бледный основной цвет заменяется читаемым фирменным или затемняется до контраста 3:1.
   * **Язык сайта (REV-25):** `<html lang>` получает BCP 47-тег исходного сайта, фиксированный UI-текст шаблона (подписи секций, форма, футер) и детерминированный fallback локализованы для en, ru, be, pl, lt (для прочих языков — английский UI при корректном `lang`).
   * **Варианты макета (REV-54):** вместо одной Bento-структуры шаблон рендерит один из четырех макетов (`MVP_LAYOUT_VARIANTS`): `bento` (исходный, по умолчанию и для старых MVP), `split` (hero из текста и фото, галерея сразу после hero, услуги плитками), `editorial` (типографический, заголовки с засечками, сначала «О нас», услуги нумерованным списком) и `compact` (короткая визитка: темный hero с проверенными контактами рядом с заголовком, компактные плитки услуг). Все макеты выводят одни и те же проверенные данные; меняются только разметка, CSS (в бандл встраивается CSS только выбранного макета) и порядок секций.
   * **Выбор макета** детерминирован (`layout-selection.service.ts`, без LLM) и делается в `deploy-queue` по данным аудита: сайт с ≤2 услугами или одностраничная визитка с ≤4 услугами → `compact`; визуальные ниши (`restaurant`, `beauty`, `fitness`, `construction`, `auto`) с hero-фото и ≥2 изображениями → `split`; экспертные ниши (`legal`, `medical`, `dental`) с ≥6 абзацами текста → `editorial`; прочие сайты с hero-фото и ≥6 изображениями → `split`; блок «О нас», ≥8 абзацев и <4 изображений → `editorial`; иначе `bento`. Результат валидируется `MvpLayoutSelectionSchema` и сохраняется в `MvpProject.layout` (`variant` + коды причин, например `rule:visual_niche`, `images:8`); перегенерация по тому же аудиту дает тот же макет. Дашборд показывает макет чипом в инспекторе.

3. **AI-адаптация контента (Copywriting Uplift):**
   * LLM переписывает тексты исходного сайта (`Audit.extractedContent`) в емкие, продающие офферы на **языке исходного сайта** (`outputLanguage`), сохраняя 100% фактической информации. Телефоны, e-mail и адреса LLM не выводит вовсе: они подставляются из проверенных данных.
   * Каждый запуск генерирует новые тексты; сохраненные ранее на аудите не переиспользуются.
   * Перед Zod-валидацией строки обрезаются до лимитов схемы (REV-34), поэтому одно слишком длинное поле не отбрасывает весь ответ.
   * **Выбор провайдера и модели (REV-30, REV-32):** оператор выбирает провайдера (`anthropic`, `openai`, `gemini`, `claude-cli`) и модель в диалоге генерации; выбор действует только на эту задачу, иначе используется значение по умолчанию воркера (`MVP_LLM_PROVIDER`, либо первый найденный API-ключ). Провайдер с ошибкой вызова откатывается на детерминированные тексты и **никогда** не переключается на другой платный провайдер. Провайдер без ключа или отсутствие провайдера — ошибка задачи (REV-45). `MvpProject` хранит выбранные (`requestedProvider/Model`) и фактические (`provider`, `modelUsed`) значения.
   * **Локальный Claude Code CLI (REV-30):** провайдер `claude-cli` запускает `claude -p` в headless-режиме под аккаунтом, в который залогинен CLI (без API-ключа): без инструментов, без MCP, без пользовательских настроек, во временной рабочей папке; промпт передается через stdin.

4. **Проверка полноты MVP (REV-36, REV-37):**
   * После рендеринга `MvpCompletenessService` разбирает HTML (`happy-dom`, без нового краулинга) и сверяет его с данными, извлеченными на аудите.
   * Поля и уровни: **critical** — `businessName`, `phone`, `email`, `address`; **important** — `workingHours`, `services`, `socialLinks`; **informational** — `logo`, `images`, `testimonials`, `rating`, `foundingYear`.
   * Статусы: `present`, `missing`, `altered` (есть, но другое), `not_in_source` (на исходном сайте нет), `unsourced` (контакт в MVP, которого нет на исходном сайте — вероятно, выдуман).
   * Если LLM настроен (`MVP_COMPLETENESS_LLM=true`), поля судит LLM: каждый вердикт должен дословно цитировать MVP. Код принимает вердикт, только если цитата есть в тексте, ссылках или URL изображений MVP, телефон/e-mail совпадают с источником после нормализации и имеют `tel:`/`mailto:`-ссылку, а «missing» не перекрывает найденное кодом совпадение. `not_in_source` и итоговый балл (веса 3/2/1 по уровням) всегда считает код.
   * При отсутствии провайдера, таймауте (`MVP_COMPLETENESS_LLM_TIMEOUT_MS`), ошибке или невалидном ответе после одного повтора используется сравнение только кодом; причина сохраняется в `llmError`. Сбой самого сравнения дает отчет `unverified` и никогда не роняет задачу.
   * Отчет валидируется Zod, сохраняется в `MvpProject.completenessReport` и пересчитывается при каждой генерации. Отчет носит рекомендательный характер: он ничего не одобряет, не блокирует и не отправляет.

5. **Компиляция, изоляция и деплой:**
   * Сборка страницы в один оптимизированный бандл (HTML + inline CSS/JS).
   * Инжекция аналитического скрипта трекинга (`revamp-tracker.js`): регистрирует факт входа владельца, скролл, клики по кнопкам демо.
   * MVP раздается с хоста хранилища (MinIO / `PREVIEW_DOMAIN`), поэтому скрипт подключается по абсолютному адресу API (REV-52): `<script src="{PUBLIC_API_URL}/track/revamp-tracker.js" data-api="{origin PUBLIC_API_URL}" data-token="…">`, и события уходят на `{PUBLIC_API_URL}/track/mvp-event`. Относительный путь `/api/v1/...` разрешился бы в хранилище (403). Без `PUBLIC_API_URL` скрипт не встраивается. Адрес фиксируется при генерации: после его смены MVP нужно перегенерировать.
   * Публикация в бакет `revamp-demos` по ключу `v/{previewSlug}/index.html` (slug — транслитерированное название бизнеса + 6 последних символов `leadId`).
   * Автоматический снимок созданного лендинга через Playwright для формирования баннера «До/После» (Split-screen Comparison, 1200x630).

6. **Перегенерация (REV-31):**
   * Правила `mvpGenerationMode` (`@revamp/validation`): из `AUDITED` — первая генерация; из `MVP_READY`, `NEEDS_APPROVAL`, `AWAITING_APPROVAL`, `APPROVED` — только с `forceRegenerate`; после постановки письма в отправку (`SCHEDULED` и далее) и во время генерации — запрещено (409).
   * Существующий проект сохраняет `previewSlug`: объекты в бакете перезаписываются (`Cache-Control: no-cache`), уже отправленная ссылка остается рабочей. `MvpProject` один на лид; обновляются `generatedAt` и `generationCount`, а превью в дашборде сбрасывает кэш по `Lead.mvpGeneratedAt`.
   * Лид остается в `GENERATING`, пока деплой не опубликует новое превью. После исчерпания ретраев лид возвращается в `AUDITED` (первая генерация) или `NEEDS_APPROVAL` (предыдущий MVP цел), а причина пишется в `Lead.generationError`.
   * Дашборд (REV-53): `MvpPreviewFrame` закрывает превью оверлеем от клика «Перегенерировать» до загрузки новой версии в iframe. Мутация генерации имеет ключ `['generate-mvp']` и остается в ожидании, пока список лидов не покажет `GENERATING` (`useIsMvpGenerationPending`), поэтому разрыва между кликом и оверлеем нет. Если URL превью не изменился (сбой), оверлей снимается сразу, а если новая версия не загрузилась, то через 20 с. `sandbox` iframe не меняется.

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
  - `Zustand`: глобальное состояние активных фильтров, модальных окон предпросмотра и текущего выбранного лида; `useDiscoveryStore` (открыт ли поиск и активная задача — переживает закрытие модалки), `useLlmChoiceStore` (последний выбранный провайдер/модель), `useLanguageStore` (язык интерфейса), `useSidebarStore` (свернуто ли боковое меню, REV-46; хранится в `localStorage`).
* **Локализация (REV-24):** `i18next` + `react-i18next` с типизированными ключами. Английский словарь — источник, словари ru/be/pl/lt проверяются по нему на этапе компиляции. Язык: сохраненный выбор → язык браузера → английский; хранится в `localStorage`, `<html lang>` следует за ним. Даты форматируются по языку (для be — `ru-BY`, где у браузера нет белорусских данных). Тексты MUI core и DataGrid локализованы для en/ru/be/pl (для lt MUI локали не поставляет).
* **Боковое меню (REV-39, REV-46):** только пункты с существующими экранами, активный пункт берется из текущего экрана. Сворачивается в полосу иконок (72px) с подсказками-названиями; выбор сохраняется между перезагрузками.

#### 4.2. Ключевые экраны:
1. **Pipeline Kanban & DataGrid:**
   * Переключение между табличным представлением (MUI DataGrid с фильтрацией по скорингу, нише, городу) и Kanban-доской статусов.
2. **Side-by-Side Audit & Comparison Inspector:**
   * Сплит-экран: Слева старый сайт с маркерами ошибок (красные оверлеи на элементах с низким контрастом или плохой версткой).
   * Справа: Интерактивный `<iframe>` со сгенерированным MVP с тулбаром смены брейкпоинтов (Desktop / Tablet / Mobile).
   * Полностраничные скриншоты исходного сайта в прокручиваемом просмотрщике со ссылкой «Открыть в полном размере» (REV-21).
   * Чек-лист полноты MVP (`CompletenessChecklist`, REV-36/37): поле, значение на исходном сайте, значение в MVP, статус, кто решил (LLM или код), метод и модель проверки.
   * Кто написал тексты MVP: провайдер и модель (`MvpSourceChip`, REV-32).
3. **HITL Review Modal (Окно подтверждения отправки):**
   * Быстрый предпросмотр темы и текста письма.
   * Кнопка инлайн-редактирования текста перед отправкой.
   * Кнопка «Перегенерировать MVP» с подтверждением и выбором провайдера/модели (REV-31, REV-32).
   * Если критическое поле MVP отсутствует, изменено или выдумано, одобрение требует дополнительного подтверждения (REV-36).
   * Большая акцентная кнопка «Подтвердить и отправить» (`Ctrl/Cmd + Enter`).
4. **Карточки Kanban:** кнопки «Сгенерировать MVP» (для `AUDITED`) и «Перегенерировать MVP» (для `NEEDS_APPROVAL`, `MVP_READY`, `AWAITING_APPROVAL`, `APPROVED`), чип «Пробелы в данных» при критических проблемах полноты, текст последней ошибки генерации (`generationError`). Для `AUDIT_FAILED`: чип «Аудит не удался» с причиной, кнопки «Повторить аудит» и «Отклонить» (REV-44).
5. **Поиск бизнесов (`DiscoveryModal` + `DiscoveryReview`, REV-27…REV-29):** кнопка в хедере открывает форму (провайдер, ниша, локация с автоопределением, ключевое слово, лимит). После отправки модалка опрашивает задачу; ее можно свернуть кнопкой «Выполнять в фоне»; тогда кнопка в хедере (`DiscoveryButton`, REV-40) сама опрашивает задачу через общий `discoveryStatusQueryOptions` и показывает спиннер, бейдж с числом новых бизнесов или ошибку, пока оператор не откроет результат (`useDiscoveryStore.resultsSeen`). Окно поиска и `DiscoveryFinishWatcher` смонтированы в `Layout`, поэтому задача отслеживается на любой странице; при завершении задачи в фоне `DiscoveryFinishWatcher` показывает уведомление (новые бизнесы / ничего нового / ошибка), клик по которому открывает окно (REV-41, один раз на задачу через `notifiedJobId`). По завершении показывается таблица кандидатов с предвыбранными новыми бизнесами, переключателем «Показать пропущенные» и итогом импорта.
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
        string auditError
    }

    Audit {
        ObjectId _id PK
        ObjectId leadId FK
        string status
        object scores
        object lighthouseMetrics
        object a11ySummary
        object designCritique
        object extractedBrandTokens
        object extractedContacts
        object extractedContent
        object screenshotUrls
        object cookieBannerHandled
        object generatedContent
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
        object generatedContent
        object colorPalette
        object completenessReport
        object layout
        string provider
        string modelUsed
        string requestedProvider
        string requestedModel
        Date generatedAt
        number generationCount
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

Результаты поиска бизнесов (Discovery) в MongoDB не хранятся: список кандидатов живет в результате BullMQ-задачи `discovery-queue` в Redis, и импорт читает его оттуда.

### Детальное описание коллекций:

#### 1. `leads`
```typescript
interface ILead {
  _id: Types.ObjectId;
  businessName: string;
  originalUrl: string;
  domain: string;                 // hostname без www, в нижнем регистре
  niche: 'dental' | 'auto' | 'legal' | 'beauty' | 'construction' | 'medical' | 'restaurant' | 'fitness' | 'other';
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
  auditError?: string;            // причина окончательного сбоя аудита, одна строка (REV-44)
  createdAt: Date;
  updatedAt: Date;
}
```

**Жизненный цикл лида (фактические переходы):**

```mermaid
stateDiagram-v2
    [*] --> QUEUED: POST /leads, импорт из Discovery, POST /audits/trigger
    QUEUED --> AUDITING: audit worker
    AUDITING --> AUDITED: аудит завершен
    AUDITING --> AUDIT_FAILED: последняя попытка или постоянная ошибка (DNS, сертификат)
    AUDIT_FAILED --> QUEUED: «Повторить аудит» (POST /audits/trigger)
    AUDIT_FAILED --> REJECTED: отклонение оператором
    AUDITED --> GENERATING: авто-цепочка или «Сгенерировать MVP»
    GENERATING --> NEEDS_APPROVAL: deploy worker опубликовал превью
    GENERATING --> AUDITED: сбой первой генерации
    GENERATING --> NEEDS_APPROVAL: сбой перегенерации (старый MVP цел)
    NEEDS_APPROVAL --> GENERATING: «Перегенерировать MVP» (forceRegenerate)
    NEEDS_APPROVAL --> SCHEDULED: HITL-аппрув оператором
    NEEDS_APPROVAL --> REJECTED: отклонение оператором
    SCHEDULED --> SENT: email worker
    SENT --> OPENED: пиксель
    OPENED --> CLICKED: клик-редирект
    CLICKED --> ENGAGED: dwell time / CTA в демо
    SENT --> UNSUBSCRIBED: POST /track/unsubscribe/:token
    OPENED --> UNSUBSCRIBED: POST /track/unsubscribe/:token
    CLICKED --> UNSUBSCRIBED: POST /track/unsubscribe/:token
    ENGAGED --> UNSUBSCRIBED: POST /track/unsubscribe/:token
```

`UNSUBSCRIBED` выставляет только `POST /track/unsubscribe/:token` (REV-73), из любого статуса после отправки; одобрение и email worker такому лиду отказывают. Статусы `PENDING`, `MVP_READY`, `AWAITING_APPROVAL`, `APPROVED`, `DISPATCHED`, `REPLIED` остаются в типе `LeadStatus` для совместимости и группируются дашбордом с соседними колонками Kanban, но воркеры их не выставляют.

#### 2. `audits`
```typescript
interface IAudit {
  _id: Types.ObjectId;
  leadId: Types.ObjectId;         // повторный аудит создает новый документ; воркер пишет в самый свежий
  status: 'QUEUED' | 'PROCESSING' | 'COMPLETED' | 'FAILED';
  scores: { total: number; design: number; accessibility: number; performance: number; standards: number }; // 0-100
  lighthouseMetrics: { lcp: number; fidOrInp?: number; cls: number; speedIndex?: number };
  a11ySummary: {
    violationsCount: number;
    contrastIssuesCount: number;
    missingAltCount: number;
    criticalViolations: Array<{ id: string; description: string; impact?: string; selector: string }>;
  };
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
  extractedContacts?: {           // REV-23: детерминированно с исходного сайта
    phone?: string; email?: string; address?: string; workingHours?: string;
    socialLinks: Array<{ platform: string; url: string }>;
  };
  extractedContent?: {            // REV-23: тексты и структура исходного сайта, дословно из DOM
    language?: string; title?: string; metaDescription?: string; ogImage?: string; h1?: string;
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
  generatedContent?: IMvpGeneratedContent; // последние тексты MvpContentAgent
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
  generatedContent: {
    hero: { badge: string; headline: string; subheadline: string; primaryCtaText: string; secondaryCtaText: string };
    about?: { heading: string; body: string };
    servicesHeading?: string;
    services: Array<{ title: string; description: string; lucideIconName: string }>;
    trustSignals: Array<{ metric: string; label: string }>;
    offerNotice: string;
  };
  colorPalette: { primary: string; secondary: string; accent: string };
  isPublished: boolean;
  generatedAt?: Date;             // REV-31
  generationCount?: number;       // REV-31
  layout?: {                      // REV-54; нет у MVP, созданных до REV-54 (Bento)
    variant: 'bento' | 'split' | 'editorial' | 'compact';
    reasons: string[];            // коды причин выбора: 'rule:image_rich', 'niche:dental', 'images:8'
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
  provider?: 'anthropic' | 'openai' | 'gemini' | 'claude-cli' | 'deterministic'; // REV-32
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

Базовый путь: `/api/v1`. Тела запросов и query-параметры валидируются Zod-схемами из `@revamp/validation` (`validateBody` / `validateQuery`). Ответы: `{ success: true, data }` или `{ success: false, error: { code, message } }`. Эндпоинты с пометкой *(план)* описаны в первоначальном дизайне, но еще не реализованы.

### 5.1. Управление лидами и аудитами (`/leads`, `/audits`)
| Метод | Эндпоинт | Описание | Body / Параметры |
|---|---|---|---|
| `POST` | `/leads` | Создать лид (`QUEUED`) и поставить аудит в очередь | `CreateLeadSchema`: `{ businessName, originalUrl, contactEmail?, niche, city?, contactPhone?, ownerName? }` (без e-mail аудит берет его с сайта, REV-45) |
| `GET` | `/leads` | Список лидов с фильтрами и пагинацией (`pagination.total`); каждый лид несет краткую сводку полноты MVP (`completeness`). `search` ищет подстроку без учета регистра (спецсимволы экранируются). Дашборд загружает все страницы по `limit=100` (REV-43) | `?status=&niche=&complexity=&search=&page=&limit=` (`limit` ≤ 100, по умолчанию 20) |
| `GET` | `/leads/stats` | Счетчики по всей воронке без учета фильтров списка → `{ total, byStatus }` (`ILeadStats`); источник KPI-карточек дашборда (REV-43) | — |
| `GET` | `/leads/:id` | Детальная карточка лида + связанный аудит | — |
| `POST` | `/audits/trigger` | Принудительный перезапуск аудита (новый документ `Audit`) | `{ leadId }` |
| `GET` | `/audits/:id` | Результаты аудита, метрики, ссылки на скриншоты | — |

### 5.2. Модуль генерации MVP (`/mvp`)
| Метод | Эндпоинт | Описание | Body / Параметры |
|---|---|---|---|
| `GET` | `/mvp/providers` | LLM-провайдеры и модели для генерации и доступность каждого по последнему отчету воркеров (REV-32) | — |
| `POST` | `/mvp/generate` | Запуск генерации/перегенерации MVP → `202 { jobId, status: 'GENERATING' }` | `GenerateMvpSchema`: `{ auditId, forceRegenerate?, provider?, model? }` |
| `GET` | `/mvp/:id` | Проект MVP по `_id`, `leadId`, `auditId` или `previewSlug` (с отчетом полноты); `404`, если MVP нет (REV-45) | — |
| `GET` | `/mvp/preview/:slug` | Редирект на опубликованное превью с заголовками CSP / `X-Frame-Options` | — |
| `PATCH` | `/mvp/:id/tokens` | Ручная коррекция палитры оператором | `UpdateMvpTokensSchema`: `{ primaryColor?, secondaryColor?, accentColor?, headline?, subheadline?, services? }` (сейчас сохраняется только палитра) |
| `POST` | `/mvp/:id/rebuild` | *(план)* Пересборка статики после правок оператора | — |

Коды ошибок `POST /mvp/generate`: `400` ошибка валидации (неизвестный провайдер или модель другого провайдера), `400 LLM_PROVIDER_NOT_ALLOWED` (dev-only провайдер в production; сейчас таких нет), `404` (нет завершенного аудита или лида), `409 MVP_ALREADY_GENERATED` (MVP есть, а `forceRegenerate` не задан), `409 MVP_GENERATION_NOT_ALLOWED` (письмо уже в отправке или идет генерация).

Выбор аудита для генерации (REV-55): у лида может быть несколько аудитов (каждый повтор создает новый). `auditId` в запросе — id аудита или, если у дашборда его нет, id лида. Берется указанный аудит, если он `COMPLETED`, иначе самый новый `COMPLETED` аудит этого лида; `FAILED` или незавершенный аудит (без контента сайта) никогда не используется. API передает id найденного аудита в задачу `ai-gen-queue`, а AI- и deploy-воркеры загружают именно его (по тому же правилу, с проверкой `leadId`). Нет завершенного аудита — `404` в API и ошибка задачи в воркерах.

### 5.3. Модуль аутрича и подтверждения (HITL) (`/outreach`)
| Метод | Эндпоинт | Описание | Body / Параметры |
|---|---|---|---|
| `GET` | `/outreach/pending` | Лиды, ожидающие ручного подтверждения (`NEEDS_APPROVAL`) | — |
| `POST` | `/outreach/:id/approve`| **[HITL Action]** Одобрить: лид → `SCHEDULED`, письмо в `email-queue` с джиттером. Только из `NEEDS_APPROVAL`/`AWAITING_APPROVAL`, атомарно (`findOneAndUpdate` с фильтром статуса); иначе `409 LEAD_NOT_AWAITING_APPROVAL` (REV-59). `409 NO_CONTACT_EMAIL`, если у лида нет e-mail (REV-45); `404 LEAD_NOT_FOUND`. Дашборд присылает черновик в том виде, как его показывает превью, с подставленными переменными (REV-72). `body` — простой текст: он сохраняется в `bodyPlainText`, а в `bodyHtml` — экранированный HTML с абзацами, переносами строк и скрытым preheader (`draftToHtml` из `@revamp/shared-types`, та же функция, что у тестовой отправки) | `{ subject?, body?, preheader?, approvedBy?, scheduleTime? }` |
| `POST` | `/outreach/:id/reject` | Отклонить отправку (лид → `REJECTED`). Только до одобрения, атомарно; для `APPROVED`, `SCHEDULED` и далее, `REJECTED`, `UNSUBSCRIBED` — `409 LEAD_NOT_REJECTABLE` (REV-59); `404 LEAD_NOT_FOUND` | `{ reason: string }` |
| `POST` | `/outreach/:id/test`   | Отправляет текущий черновик (как в превью, с подставленными переменными) на почту оператора через `email-test-queue` и ждёт результата воркера до 30 с (REV-60). Не проходит HITL-гейт, не добавляет пиксель открытий и не меняет лид и `EmailCampaign`. `200` с `{ to, messageId, provider, sentAt }`; `503 EMAIL_PROVIDER_NOT_CONFIGURED`, если `EMAIL_PROVIDER` не задан в API или у воркеров; `502 EMAIL_SEND_FAILED` при ошибке провайдера; `504 EMAIL_TEST_TIMEOUT`, если воркеры не ответили (ожидающая задача удаляется); `404 LEAD_NOT_FOUND`; `400` для неверного id или тела | `{ testEmail, subject, body, preheader? }` |
| `PUT` | `/outreach/:id/draft` | *(план)* Сохранение черновика без отправки | `{ subject, bodyHtml }` |

### 5.4. Поиск локальных бизнесов (`/discovery`) — REV-26…REV-29
| Метод | Эндпоинт | Описание | Body / Параметры |
|---|---|---|---|
| `POST` | `/discovery` | Поставить поиск в `discovery-queue` → `202 { jobId }` | `StartDiscoverySchema`: `{ provider: 'osm'\|'google', niche, location, keyword?, limit (1-100, по умолч. 20) }` |
| `GET` | `/discovery/reverse-geocode` | Координаты браузера → `"City, Country"` через Nominatim (уровень города); `404` если не найдено, `502` при сбое Nominatim | `?lat&lng&lang` |
| `GET` | `/discovery/:jobId` | Состояние задачи (`waiting`/`active`/`completed`/`failed`/…), параметры, кандидаты; `new`-кандидаты перепроверяются по текущим лидам | — |
| `POST` | `/discovery/:jobId/import` | Импорт выбранных кандидатов как лидов; данные берутся только из результата задачи; `404` неизвестная задача, `409` задача не завершена | `ImportDiscoverySchema`: `{ externalIds: string[] (1-100) }` |

### 5.5. Трекинг активности и аналитика (`/track`, `/health`)
| Метод | Эндпоинт | Описание |
|---|---|---|
| `GET` | `/track/open/:token.gif` | 1x1 прозрачный пиксель отслеживания открытия письма (лид → `OPENED`) |
| `GET` | `/track/click/:token` | Редирект на демо-сайт с логированием клика (лид → `CLICKED`) |
| `POST` | `/track/mvp-event` | Beacon API: время на странице, скролл, клики в демо (лид → `ENGAGED`) |
| `GET` | `/track/unsubscribe/:token` | HTML-страница подтверждения отписки с кнопкой (POST на тот же адрес); ничего не меняет, чтобы сканеры ссылок не отписывали получателей (RFC 8058). «Вы отписаны», если отписка уже была; `404` для неизвестного токена (REV-73) |
| `POST` | `/track/unsubscribe/:token` | One-click отписка (RFC 8058, тело `List-Unsubscribe=One-Click`) и кнопка подтверждения: лид и `EmailCampaign` → `UNSUBSCRIBED`, `unsubscribedAt`, событие `unsubscribe`; `200`, идемпотентно; `404` для неизвестного токена без изменений (REV-73) |
| `GET` | `/track/revamp-tracker.js` | Скрипт трекинга для страниц MVP (`Cross-Origin-Resource-Policy: cross-origin`, чтобы страница из хранилища могла его загрузить) |
| `GET` | `/health` | Проверка доступности API, MongoDB и Redis |
| `GET` | `/analytics/overview` | *(план)* Метрики воронки, open rate, CTR, средний скоринг |

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
    end

    subgraph Workers_Pool [Node.js Workers]
        W0[Discovery Worker<br/>Concurrency: 1]
        W1[Audit Worker<br/>Concurrency: 2]
        W2[AI Worker<br/>Concurrency: 5]
        W3[Deploy Worker<br/>Concurrency: 5]
        W4[Email Dispatcher<br/>Concurrency: 1, 1 письмо / 180 с]
        W5[Email Test Sender<br/>Concurrency: 1, без лимита]
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
   * Concurrency: `5`. Ретраи: 3 попытки, экспоненциальный откат от 5 с; внутри задачи — до 3 обращений к LLM (температура 0.3 → 0.0 → 0.0), затем детерминированный fallback.
   * Payload несет `forceRegenerate`, `previousStatus` и выбор оператора (`provider`, `model`).
4. **`deploy-queue` Worker:**
   * Concurrency: `5`. Ретраи: 3 попытки, экспоненциальный откат от 5 с.
   * Рендер Bento, проверка полноты, выгрузка в `revamp-demos`, баннер «До/После», `Lead.status = NEEDS_APPROVAL`.
   * Обработчик `failed` (общий с AI-воркером, `generation-failure.ts`) после последнего ретрая возвращает лид из `GENERATING` и пишет `generationError`.
5. **`email-queue` Worker:**
   * Throttling: строго 1 письмо в 3 минуты (BullMQ limiter `max: 1, duration: 180000`).
   * Jitter: случайная задержка 15–45 секунд, рассчитываемая API при постановке задачи.
   * Провайдер: `EMAIL_PROVIDER` (`resend`, `sendgrid` или `smtp`), значения по умолчанию нет. Без него задача отправки завершается ошибкой, а не помечает письмо отправленным (REV-45).
   * Содержимое: `bodyHtml` и `bodyPlainText` кампании отправляются как HTML- и текстовая части письма без изменений. Оба заполняются при одобрении из того же черновика, что видел оператор, поэтому реальное письмо совпадает с тестовым (REV-72).
6. **`email-test-queue` Worker (REV-60):**
   * Тестовая отправка черновика оператору. Отдельная очередь, чтобы тест не ждал лимита аутрича и не задерживал его: concurrency `1`, без limiter, 1 попытка без ретраев (оператор ждёт ответа).
   * Тот же `emailService` и провайдер, что у `email-queue`, но без HITL-гейта, MX-проверки и пикселя открытий (`trackOpens: false`); тема с префиксом `[Test]`. Лид и `EmailCampaign` не читаются и не меняются.
   * API ждёт результата через `QueueEvents` до 30 с. Без провайдера задача падает с `EMAIL_PROVIDER_NOT_CONFIGURED`, и API отвечает `503`.

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
   * **Провайдеры LLM:** выбор оператора не переключает задачу на другой платный провайдер при сбое — только на детерминированный fallback. Без настроенного провайдера генерация и Vision-критика завершаются ошибкой (REV-45).
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
    Библиотека Bento/Tailwind секций       :2026-10-30, 8d
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
* Шаблонизатор адаптивных лендингов на базе современных Tailwind-компонентов.
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
