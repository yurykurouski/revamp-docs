# РУКОВОДСТВО И СИСТЕМНЫЕ ИНСТРУКЦИИ ДЛЯ ИИ-АГЕНТОВ (AGENTS.md)
## Проект: Revamp SaaS — Автоматизированный аудит сайтов и генерация MVP

---

## 1. Введение и назначение документа

Настоящий документ определяет операционные правила, контекст предметной области, инженерные стандарты и системные промпты для двух категорий ИИ-агентов:
1. **Coding Agent (ИИ-разработчик):** Автономный ассистент (Antigravity, Cursor, Claude Code, Copilot), создающий, изменяющий и тестирующий кодовую базу проекта.
2. **In-App Autonomous Agents (Встроенные агенты SaaS):** Специализированные ИИ-агенты внутри бэкенда платформы (Агент аудита дизайна, Агент копирайтинга MVP, Агент персонализации холодных писем).

Связанные проектные документы:
* Архитектура и стек: [blueprint.md](./blueprint.md)
* Спецификация требований: [spec.md](./spec.md)
* Исследования, сценарии и ADR: [research.md](./research.md)

---

## 2. Общие принципы и фундаментальные ограничения проекта

Каждый ИИ-агент обязан строго соблюдать следующие ограничения архитектуры:
1. **Принцип Human-In-The-Loop (HITL):**  
   Никакой агент или фоновый воркер не имеет права отправлять внешние письма клиентам автоматически. Любое действие генерации завершается переводом сущности в статус `NEEDS_APPROVAL`. Отправка возможна **только** после явного подтверждения оператором в UI дашборда.
2. **Детерминизм метрик (Strict Grounding):**  
   Замеры доступности (WCAG 2.1 AA), скорости загрузки (Lighthouse Core Web Vitals) и парсинг фактических данных (телефоны, адреса, цены) выполняются **детерминированным кодом** (axe-core, Lighthouse, DOM-парсеры). Запрещено доверять нейросетям расчет численных метрик или выдумывание контактных данных.
3. **Изоляция сгенерированных MVP:**  
   Сгенерированные сайты — это статичные бандлы (HTML + Tailwind CSS), размещаемые на изолированном домене (`*.preview.revampdemo.com`) в песочнице Cloudflare R2 / S3. В дашборде они встраиваются строго через `<iframe>` с директивой `sandbox="allow-scripts allow-same-origin"`.
4. **Валидация через Zod:**  
   Любой ответ внешней модели (LLM) и любой входящий HTTP-запрос должен валидироваться строгой схемой Zod перед сохранением в базу данных.
5. **Проверяемость суждений LLM (REV-37):**  
   Когда LLM что-то оценивает (например, полноту MVP), он обязан цитировать проверяемый источник, а код принимает вердикт только после проверки цитаты. Баллы и числовые метрики всегда считает код.
6. **Контент только с исходного сайта (REV-23):**  
   MVP строится исключительно из данных, извлеченных с сайта бизнеса. Никаких шаблонных отзывов, адресов, часов работы, телефонов и метрик «по умолчанию».

---

## 3. Инструкции для ИИ-разработчика (Coding Agent Guidelines)

Если вы действуете в роли ИИ-ассистента, пишущего код для репозитория Revamp, соблюдайте следующие правила:

### 3.1. Структура проекта (Monorepo)
```
/
├── apps/
│   ├── api/             # Express.js REST API Gateway (Node.js + TypeScript)
│   ├── workers/         # BullMQ фоновые воркеры (Playwright, AI, Deploy, Mail)
│   └── dashboard/       # Фронтенд оператора (React 18+, Material UI v6, Vite)
├── packages/
│   ├── shared-types/    # Общие TypeScript интерфейсы и DTO
│   └── validation/      # Общие схемы Zod для фронтенда и бэкенда
├── deploy/              # Продакшен-деплой (Docker, Nginx, скрипты)
├── scripts/             # Сервисные скрипты (напр. e2e_live_scenarios.ts)
├── docker-compose.yml   # MongoDB 7.0, Redis 7.0, MinIO + minio-init
├── .env.example
└── AGENTS.md            # Правила для ИИ-разработчика в кодовом репозитории
```
Документация (`blueprint.md`, `spec.md`, `research.md`, `milestones.md`, этот файл) хранится в отдельном репозитории [`revamp-docs`](https://github.com/yurykurouski/revamp-docs), локально — `../Revamp-docs`.

### 3.2. Архитектурные слои бэкенда (`apps/api`)
Соблюдайте строгое разделение ответственности:
`Route -> Middleware (Auth/Validation) -> Controller -> Service -> Model (Mongoose)`
* **Controllers:** Принимают `req`, вызывают методы сервиса, возвращают типизированный `res`. Запрещено помещать бизнес-логику и тяжелые вычисления в контроллеры.
* **Services:** Содержат бизнес-логику, вызывают Mongoose-модели и пушат задачи в очереди BullMQ.
* **DTOs & Schemas:** Для всех запросов на создание/изменение обязательны валидаторы `validateBody(CreateLeadSchema)`.
* **Обработка ошибок:** Никогда не глушите ошибки пустым `catch {}`. Используйте глобальный обработчик `ErrorHandlerMiddleware` и кастомные классы `AppError(message, statusCode)`.

### 3.3. Правила написания фронтенда (`apps/dashboard`)
* **Стек:** React (v18+), TypeScript, Material UI (MUI v6), `@mui/x-data-grid`, TanStack Query (v5), Zustand.
* **Стилизация:** Используйте только тему MUI (`theme.palette`, `sx={{ ... }}`) или `styled` из `@mui/material/styles`. Никаких инлайн-стилей `style={{ ... }}` и хаотичных CSS-файлов.
* **Управление состоянием:**
  - Серверные данные (списки лидов, аудиты) — строго через `useQuery` и `useMutation` из TanStack Query.
  - Локальное состояние экранов (активные фильтры, открытые модалки) — через `Zustand` сторы (`useLeadFilterStore`, `useHitlModalStore`).
* **Side-by-Side инспектор:** Компонент предпросмотра сгенерированного MVP должен отображать `<iframe>` с адаптивным переключателем ширины: `375px` (Mobile), `768px` (Tablet), `100%` (Desktop).

### 3.4. Фоновые очереди и воркеры (`apps/workers`)
* Все задачи изолируются по очередям BullMQ: `discovery-queue`, `audit-queue`, `ai-gen-queue`, `deploy-queue`, `email-queue`.
* Управление памятью Chromium: принудительно закрывайте контексты `browserContext.close()` после каждого аудита. Браузер перезапускается каждые 20 прогонов.
* Функции для `page.evaluate()` (например, `extractSiteContentInPage`) должны быть самодостаточными: без импортов и ссылок на значения модуля. В каждом контексте установлен no-op shim `__name`, так как tsx/esbuild оборачивают вложенные функции в `__name()` (REV-21).
* Экспоненциальный откат: для сетевых запросов и API нейросетей задавайте `{ attempts: 3, backoff: { type: 'exponential', delay: 3000..5000 } }`. Ошибки, которые повтор не исправит (нет ключа, неверная конфигурация), бросайте как `UnrecoverableError`.
* Сбои генерации MVP после последнего ретрая обрабатывает `generation-failure.ts`: лид не должен застревать в `GENERATING`.
* Тесты не должны вызывать реальных LLM: в окружении Vitest `MVP_LLM_PROVIDER` пустой (REV-30).

---

## 4. Спецификации и системные промпты встроенных ИИ-агентов

Система включает 3 работающих ИИ-агента и 1 запланированный. Промпты хранятся в коде воркеров (источник истины) и с REV-22 написаны на английском; ниже они приведены дословно на момент REV-37.

| Агент | Где вызывается | Модель | Статус |
|---|---|---|---|
| 1. Design & UX Critique | `AuditWorker` → `design-critique.service.ts` | Vision LLM (Anthropic / OpenAI) | Работает |
| 2. MVP Content & Copywriting | `AiWorker` → `mvp-content.service.ts` | Выбор оператора из каталога (§4.5) | Работает |
| 3. Outreach Personalizer | — | — | Запланирован; письмо сейчас собирается шаблоном в дашборде |
| 4. MVP Completeness Judge | `DeployWorker` → `mvp-completeness-judge.ts` | Провайдер по умолчанию воркера | Работает (REV-37) |

---

### Агент 1: Агент аудита дизайна (Design & UX Critique Agent)
* **Назначение:** Оценка визуальной привлекательности первого экрана, иерархии и выявление устаревших UI-паттернов на основе скриншота.
* **Модель:** Мультимодальная (Vision LLM: Anthropic Claude / OpenAI GPT-4o).
* **Параметры запуска:** температура `0.2`, затем 2 повтора с `0.0`; сжатие изображения в WebP до 1024px; на вход идут только скриншоты первого экрана (не полностраничные).
* **Код:** `apps/workers/src/services/design-critique.service.ts` (`DESIGN_CRITIQUE_SYSTEM_PROMPT`).

#### Системный промпт (System Prompt):
```text
You are a lead UX/UI art director and conversion expert for local-business websites.
Your task is to objectively assess the first screen of a website (above the fold) from screenshots and give constructive critique for a redesign proposal.

Inputs:
1. Screenshots of the mobile (375px) and desktop (1440px) versions of the site.
2. The business niche (e.g. dental clinic, auto repair, law firm).
3. Numeric metrics: accessibility score (0-100) and LCP (seconds).

Analysis rules:
- Judge the design strictly from the point of view of a modern mobile visitor (Nielsen heuristics, readability, CTA visibility).
- List exactly 3 Critical Flaws that reduce trust or stop a visitor from getting in touch.
- List exactly 3 Quick Wins that a modern redesign would deliver.
- Write all text in English.
- Respond with a raw JSON object only, with no preamble and no markdown around the JSON.
```

#### Схема валидации выхода (Zod Schema):
```typescript
export const DesignCritiqueOutputSchema = z.object({
  visualHierarchyRating: z.number().min(0).max(100),
  mobileFriendlinessRating: z.number().min(0).max(100),
  primaryCtaFound: z.boolean(),
  datedDesignFactors: z.array(z.string()).max(5),
  criticalFlaws: z.array(
    z.object({
      title: z.string().max(80),
      impact: z.string().max(200),
      recommendation: z.string().max(200)
    })
  ).length(3),
  quickWins: z.array(z.string().max(150)).length(3)
});
```

---

### Агент 2: Агент синтеза контента MVP (MVP Content & Copywriting Agent)
* **Назначение:** Переписать тексты исходного сайта в сильные офферы для Bento-лендинга **на языке исходного сайта**, сохранив 100% исходной фактуры (REV-23, REV-25).
* **Модель:** выбирается оператором для каждой генерации (REV-32) из каталога `LLM_PROVIDER_CATALOG`; по умолчанию — `MVP_LLM_PROVIDER` воркера или первый провайдер с API-ключом.
* **Параметры запуска:** температура `0.3`, затем 2 повтора с `0.0` (у Claude Code CLI температуры нет, повторы просто перезапускают его; современные модели Anthropic отклоняют `temperature`, и она не передается). Лимит ответа: 2000 токенов (OpenAI, Gemini), 16 000 для Anthropic (адаптивное мышление расходует тот же лимит).
* **Вход (user prompt, JSON):** название, `outputLanguage`, ниша, город, исходный URL, выжимка контента сайта (`Audit.extractedContent`: язык, title, meta description, H1, до 12 заголовков, до 8 абзацев, до 10 услуг, навигация, число отзывов, рейтинг, год основания), извлеченные услуги, флаги `hasPhone`/`hasAddress` и Quick Wins аудита. Сами контакты в промпт не передаются: их подставляет шаблон из проверенных данных.
* **Постобработка:** строки обрезаются до лимитов схемы (REV-34) → Zod → `enforceStrictGrounding` (удаляются плашки доверия с числами, которых нет в контексте; короткий список услуг дополняется только извлеченными услугами).
* **Код:** `apps/workers/src/services/mvp-content.service.ts` (`MVP_CONTENT_SYSTEM_PROMPT`).

#### Системный промпт (System Prompt):
```text
You are a professional Senior Conversion Copywriter.
You receive the content scraped from a local business's current website. Rewrite it into the copy for a modern, high-converting one-page Bento landing page for THAT specific business: keep everything the original site says, but make it clearer, more persuasive and better structured.

FUNDAMENTAL GROUNDING RULES:
- Every fact (services, products, locations, numbers, years, ratings, prices, staff, awards) must come from the provided context. Never invent any of them.
- Never output phone numbers, email addresses or street addresses; they are rendered separately from verified data.
- Use the business's own specifics (its name, what it actually offers, its wording and its selling points) so the copy could not belong to any other business.
- trustSignals: include at most 3, and only metrics whose numbers literally appear in the context (e.g. a rating or a founding year). Return an empty array when there are none.

Language:
- Write all copy in the language named in "outputLanguage" - the original site's own language. Never translate the copy into English or any other language.
- Keep the business's own terms, service names and proper nouns exactly as the original site spells them.

Style requirements:
- hero.badge: a short label for the business, e.g. its location or specialty (up to 40 characters).
- hero.headline: customer benefit + what makes this business specific (up to 90 characters).
- hero.subheadline: how the business solves the customer's problem, based on its own description (up to 180 characters).
- about: a heading (up to 80 characters) and 2-4 sentences (up to 700 characters) retelling the business's own story and strengths.
- servicesHeading: a heading for the services section (up to 80 characters).
- services: 1-6 cards built from the services the site lists, each with a title (up to 50 characters), a concise, persuasive description (up to 15 words) and a matching Lucide icon (e.g. 'wrench', 'shield-check', 'sparkles', 'calendar', 'phone', 'award', 'activity', 'truck', 'heart', 'smile', 'zap', 'car', 'clock', 'star', 'stethoscope').
- trustSignals: metric up to 20 characters, label up to 50 characters.
- CTA buttons (primaryCtaText, secondaryCtaText): a concrete action that fits this business (up to 35 characters each).
- offerNotice: one short line inviting the customer to get in touch (up to 100 characters).
- Every length limit is a hard maximum; stay well under it.

Respond with a raw JSON object only, with no preamble and no markdown, in exactly this shape:
{"hero":{"badge":string,"headline":string,"subheadline":string,"primaryCtaText":string,"secondaryCtaText":string},"about":{"heading":string,"body":string},"servicesHeading":string,"services":[{"title":string,"description":string,"lucideIconName":string}],"trustSignals":[{"metric":string,"label":string}],"offerNotice":string}
```

#### Схема валидации выхода (Zod Schema):
```typescript
export const MvpContentOutputSchema = z.object({
  hero: z.object({
    badge: z.string().max(40),
    headline: z.string().max(90),
    subheadline: z.string().max(180),
    primaryCtaText: z.string().max(35),
    secondaryCtaText: z.string().max(35)
  }),
  about: z.object({
    heading: z.string().max(80),
    body: z.string().max(700)
  }).optional(),
  servicesHeading: z.string().max(80).optional(),
  services: z.array(
    z.object({
      title: z.string().max(50),
      description: z.string().max(120),
      lucideIconName: z.string()
    })
  ).min(1).max(6),
  // Только метрики, которые есть на исходном сайте; может быть пустым (Strict Grounding)
  trustSignals: z.array(
    z.object({
      metric: z.string().max(20), // например, "12 years", "4.9"
      label: z.string().max(50)   // например, "in business", "map rating"
    })
  ).max(3),
  offerNotice: z.string().max(100)
});
```

---

### Агент 3: Агент персонализации холодных писем (Outreach Personalizer Agent)
> **Статус: не реализован как LLM-агент.** Сейчас черновик письма собирается в дашборде (`EmailDraftEditor`) по английскому шаблону с подстановкой переменных (название бизнеса, ссылка на демо и т. п.), оператор редактирует его и одобряет. Схема `EmailDraftOutputSchema` уже есть в `@revamp/validation`. Спецификация ниже — целевая.

* **Назначение:** Формирование убедительного, персонализированного черновика холодного письма для владельца сайта на основе результатов аудита и ссылки на сгенерированное MVP-демо.
* **Модель:** из каталога провайдеров (§4.5).
* **Параметры запуска:** `temperature: 0.4`, `max_tokens: 1000`.

#### Системный промпт (System Prompt, целевой):
```markdown
Ты — эксперт по B2B cold outreach в сфере веб-разработки.
Твоя цель — составить короткое, уважительное и гиперперсонализированное письмо для владельца сайта с предложением взглянуть на уже готовый бесплатный интерактивный прототип.

Входные данные:
- Название бизнеса: {{businessName}}
- Имя владельца (если найдено): {{ownerName}}
- Город: {{city}}
- Найденные ошибки аудита: {{criticalFlaws}}
- Метрики: скорость LCP {{lcp}}s, доступность a11y {{a11yScore}}/100
- Ссылка на демо: {{demoUrl}}

Правила составления:
1. Тема письма: должна быть лаконичной, интригующей и содержать название компании (без спам-слов: "СКИДКА", "АКЦИЯ", "КУПИТЕ", капслока и восклицательных знаков).
2. Объем: не более 120-150 слов. Предприниматели не читают длинные тексты.
3. Структура:
   - Приветствие + конкретика (почему пишем именно им).
   - 2 конкретных факта из аудита (почему мобильные клиенты уходят).
   - Демонстрация ценности: "Мы уже бесплатно собрали для вас адаптивный прототип с вашим логотипом и услугами".
   - Мягкий CTA: ссылка на демо + предложение созвониться на 10 минут, если понравится.
4. Обязательное условие: дружелюбный, экспертный тон без токсичной критики.
```

#### Схема валидации выхода (Zod Schema):
```typescript
export const EmailDraftOutputSchema = z.object({
  subject: z.string().max(80),
  previewText: z.string().max(100),
  bodyHtml: z.string(),
  bodyPlainText: z.string()
});
```

---

### Агент 4: Судья полноты MVP (MVP Completeness Judge) — REV-37
* **Назначение:** Проверить, что сгенерированный MVP по-прежнему показывает данные бизнеса с исходного сайта, и найти контакты, которых на исходном сайте нет.
* **Модель:** провайдер и модель по умолчанию воркера (`MVP_LLM_PROVIDER`); включается `MVP_COMPLETENESS_LLM=true` (по умолчанию).
* **Параметры запуска:** `temperature: 0`, лимит ответа 3000 токенов, 2 попытки при невалидном ответе, таймаут `MVP_COMPLETENESS_LLM_TIMEOUT_MS` (90 с). Текст MVP в промпте ограничен 12 000 символов.
* **Главное правило:** LLM не считает баллы и не решает окончательно. Каждый вердикт `present`/`altered` содержит дословную цитату из MVP, и `MvpCompletenessService` принимает его, только если цитата действительно есть в тексте, ссылках или URL изображений MVP, а телефон/e-mail совпадают с источником после нормализации и имеют `tel:`/`mailto:`-ссылку. `not_in_source` и балл вычисляет код. При любом сбое используется сравнение только кодом, причина пишется в `llmError`.
* **Код:** `apps/workers/src/services/mvp-completeness-judge.ts` (`COMPLETENESS_JUDGE_SYSTEM_PROMPT`), проверка — `mvp-completeness.service.ts`.

#### Системный промпт (System Prompt):
```text
You are a meticulous QA reviewer. A redesigned landing page ("MVP") was generated for a local business from its original website. Check whether the MVP still shows the business's own data from the original site.

You get JSON with:
- "source": the fields the original site has. Each has a "value" or a list of "items".
- "mvp": the MVP's visible text, its tel: and mailto: links, other links and image URLs.

For EVERY field in "source", return one verdict:
- "present": the MVP shows the same information. Wording, formatting, abbreviations, language and order may differ ("Mon–Fri 9–18" = "Monday to Friday 9:00-18:00"; "Dental implants" = "Implantology").
- "altered": the MVP shows this kind of information but with different content (another phone number, other hours, another street).
- "missing": the MVP doesn't show it.

Rules:
- "mvpQuote" must be copied EXACTLY, character for character, from the MVP text, a link or an image URL. Give it for every "present" or "altered" verdict. Never paraphrase or invent a quote. If you can't quote it, the verdict is "missing".
- phone: "present" only when the same number is shown as text AND a tel: link calls it. Quote the number as shown in the text.
- email: "present" only when the same address is shown as text AND a mailto: link uses it. Quote the address as shown in the text.
- services and socialLinks: judge each source item in "items" separately ({"value": <the source item, copied>, "found": true|false, "mvpQuote": ...}). "status" is "present" only when every item is found.
- logo: quote the matching image URL.
- images and testimonials: "present" when AT LEAST ONE source item is reused (quote one of them); "missing" when none is. Never use "altered" for them.
- Also list, in "unsourced", every phone number, email address or street address the MVP shows that is NOT in the source data. Quote it exactly. Leave the list empty when there are none.
- Never output numbers, scores or percentages.

Return ONLY this JSON object, with no other text:
{"fields":[{"field":"<field>","status":"present|missing|altered","mvpQuote":"<exact quote>","reason":"<short reason>","items":[{"value":"<item>","found":true,"mvpQuote":"<exact quote>"}]}],"unsourced":[{"field":"phone|email|address","mvpQuote":"<exact quote>"}]}
```

#### Схема валидации выхода (Zod Schema, сокращенно):
```typescript
export const CompletenessJudgeOutputSchema = z.object({
  fields: z.array(z.object({
    field: CompletenessFieldSchema,                  // businessName | phone | email | address | workingHours | services | ...
    status: z.enum(['present', 'missing', 'altered']),
    mvpQuote: optionalJudgeText(300),                // "" и null считаются отсутствием цитаты
    reason: optionalJudgeText(300),
    items: z.array(z.object({                        // услуги и соцсети — по одному
      value: z.string().min(1).max(300),
      found: z.boolean(),
      mvpQuote: optionalJudgeText(300)
    })).max(20).optional()
  })).max(20),
  // Записи без цитаты нельзя проверить, поэтому они отбрасываются, а не валят ответ
  unsourced: z.array(z.object({
    field: z.enum(['phone', 'email', 'address']),
    mvpQuote: optionalJudgeText(300)
  })).max(20).default([])
});
```

---

### 4.5. LLM-провайдеры и `LlmClient` (REV-30, REV-32, REV-37)
* Все вызовы LLM из воркеров (кроме Vision-критики) идут через `LlmClient` (`apps/workers/src/services/llm-client.ts`): Anthropic, OpenAI, Gemini и локальный Claude Code CLI. Вызывающий код передает system/user prompt и получает сырой текст; разбор и Zod-валидация остаются у вызывающего.
* Каталог провайдеров и моделей — `LLM_PROVIDER_CATALOG` в `@revamp/shared-types` (первая модель — модель по умолчанию):

| Провайдер | Модели | Особенности |
|---|---|---|
| `anthropic` | `claude-opus-5`, `claude-sonnet-5`, `claude-haiku-4-5` | Нужен `ANTHROPIC_API_KEY`; `temperature` не передается; ответ читается из текстового блока после блока мышления |
| `openai` | `gpt-4o`, `gpt-4o-mini` | Нужен `OPENAI_API_KEY` |
| `gemini` | `gemini-1.5-pro`, `gemini-1.5-flash` | Нужен `GEMINI_API_KEY` |
| `claude-cli` | `sonnet`, `opus`, `haiku` | Локальный `claude -p` под залогиненным аккаунтом, без API-ключа; без инструментов, MCP и настроек, во временной папке; таймаут `CLAUDE_CLI_TIMEOUT_MS` |
| `mock` | `mock` | Детерминированные тексты; только вне production |

* Провайдер без своего ключа (или упавший) дает детерминированный fallback и никогда не переключается на другой платный провайдер.
* Воркеры публикуют доступность провайдеров в Redis (`revamp:llm-capabilities`), API отдает ее в `GET /api/v1/mvp/providers`; дашборд показывает только доступные варианты.

---

## 5. Политика отказоустойчивости и защита от галлюцинаций (Guardrails)

1. **Strict Fallback Policy (Политика откатов):**
   * Перед валидацией строки ответа обрезаются до лимитов схемы (REV-34), чтобы одно слишком длинное поле не отбрасывало весь ответ.
   * Если ответ модели падает при валидации через `ZodSchema.safeParse()`, задача повторяется до 2 раз со снижением `temperature` до `0.0`.
   * При повторном падении или отсутствии ключа выбранного провайдера система активирует **детерминированный Fallback** (переключения на другой платный провайдер нет):
     - Hero, «О нас», услуги и плашки доверия собираются из контента исходного сайта: H1 или title (общие заголовки вроде «Главная» пропускаются), meta description, реальные услуги и только проверяемые метрики (рейтинг, год основания, число отзывов), на языке сайта.
     - Письмо собирается по статическому шаблону в дашборде.
     - В базу выставляется флаг `aiFallbackUsed: true`, `MvpProject.provider = 'deterministic'`, а в дашборде оператора отображается, кто написал тексты.
   * Судья полноты (Агент 4) при сбое откатывается на сравнение только кодом; отчет сохраняет `method`, `model` и `llmError`.
2. **Защита конфиденциальности (Data Privacy):**
   * Запрещено передавать в промпты нейросетей персональные пароли, сессионные куки или внутренние ключи доступа.
   * Изображения скриншотов очищаются от метаданных перед отправкой в Vision API.
3. **Мониторинг квот и расходов:**
   * Каждый вызов LLM логирует количество потраченных `input_tokens` и `output_tokens` в таблицу `analytics_events`.
   * При достижении дневного лимита ($50/сутки) вызовы блокируются, а операторам выводится предупреждение.

---

## 6. Чек-лист проверки кода для ИИ-агента (Definition of Done)

Перед тем как зафиксировать изменения в кодовой базе, ИИ-агент обязан проверить:
* [ ] Код компилируется без ошибок TypeScript (`tsc --noEmit`).
* [ ] Все публичные эндпоинты Express валидируют тело запроса через Zod.
* [ ] Для всех тяжелых операций используются очереди BullMQ, а не синхронные вызовы.
* [ ] Воркеры корректно освобождают инстансы браузера Playwright (`browser.close()`).
* [ ] Нет прямых обращений фронтенда к внешним AI-провайдерам (только через API Gateway).
* [ ] Соблюдено правило Human-In-The-Loop: письма не отправляются без флага `approvedBy`.
* [ ] Добавлены необходимые модульные тесты Vitest или E2E-тесты Playwright.
* [ ] Новые строки интерфейса дашборда добавлены во все словари: en, ru, be, pl, lt.
* [ ] LLM не выводит контактные данные и не считает метрики; суждения LLM подтверждены цитатами, проверенными кодом.
* [ ] Работа прошла конвейер из `AGENTS.md` кодового репозитория: тикет в Linear → ветка → тесты и гейты (`build:packages`, `typecheck`, `lint`, `test`, `build`, проверка в Chrome) → PR → merge → закрытие тикета.
