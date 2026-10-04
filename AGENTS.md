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
* **Обработка ошибок:** Никогда не глушите ошибки пустым `catch {}`. Используйте глобальный обработчик `ErrorHandlerMiddleware` и `AppError(statusCode, code, message, details?)` с кодом из `API_ERROR_CODES` (`@revamp/shared-types`). Маршруты не пишут JSON ошибок сами: единый формат `{ success: false, error: { code, message, details? } }` формирует только `errorHandler` (REV-63).

### 3.3. Правила написания фронтенда (`apps/dashboard`)
* **Стек:** React (v18+), TypeScript, Material UI (MUI v6), `@mui/x-data-grid`, TanStack Query (v5), Zustand.
* **Стилизация:** Используйте только тему MUI (`theme.palette`, `sx={{ ... }}`) или `styled` из `@mui/material/styles`. Никаких инлайн-стилей `style={{ ... }}` и хаотичных CSS-файлов.
* **Управление состоянием:**
  - Серверные данные (списки лидов, аудиты) — строго через `useQuery` и `useMutation` из TanStack Query.
  - Локальное состояние экранов (активные фильтры, открытые модалки) — через `Zustand` сторы (`useLeadFilterStore`); открытый лид — маршрут `/leads/:id`, его ревью — `LeadReview` (REV-77).
* **Side-by-Side инспектор:** Компонент предпросмотра сгенерированного MVP должен отображать `<iframe>` с адаптивным переключателем ширины: `375px` (Mobile), `768px` (Tablet), `100%` (Desktop).

### 3.4. Фоновые очереди и воркеры (`apps/workers`)
* Все задачи изолируются по очередям BullMQ: `discovery-queue`, `audit-queue`, `ai-gen-queue`, `deploy-queue`, `email-queue`.
* Управление памятью Chromium: принудительно закрывайте контексты `browserContext.close()` после каждого аудита. Браузер перезапускается каждые 20 прогонов.
* Функции для `page.evaluate()` (например, `extractSiteContentInPage`) должны быть самодостаточными: без импортов и ссылок на значения модуля. В каждом контексте установлен no-op shim `__name`, так как tsx/esbuild оборачивают вложенные функции в `__name()` (REV-21).
* Экспоненциальный откат: для сетевых запросов и API нейросетей задавайте `{ attempts: 3, backoff: { type: 'exponential', delay: 3000..5000 } }`. Ошибки, которые повтор не исправит (нет ключа, неверная конфигурация), бросайте как `UnrecoverableError`.
* Сбои генерации MVP после последнего ретрая обрабатывает `generation-failure.ts`: лид не должен застревать в `GENERATING`.
* Тесты не должны вызывать реальных LLM: в окружении Vitest `MVP_LLM_PROVIDER` и `VISION_LLM_PROVIDER` пустые, а `CLAUDE_CLI_PATH` указывает на несуществующий файл, чтобы Vision-критика не нашла CLI (REV-30, REV-51).

---

## 4. Спецификации и системные промпты встроенных ИИ-агентов

Система включает 3 работающих ИИ-агента и 1 запланированный. Промпты хранятся в коде воркеров (источник истины) и с REV-22 написаны на английском; ниже они приведены дословно на момент REV-37.

| Агент | Где вызывается | Модель | Статус |
|---|---|---|---|
| 1. Design & UX Critique | `AuditWorker` → `design-critique.service.ts` | Vision LLM (Anthropic / OpenAI / Claude Code CLI) | Работает |
| 2. MVP Content & Copywriting | `AiWorker` → `mvp-content.service.ts` | Выбор оператора из каталога (§4.5) | Работает |
| 3. Outreach Personalizer | — | — | Запланирован; письмо сейчас собирается шаблоном в дашборде |
| 4. MVP Completeness Judge | `DeployWorker` → `mvp-completeness-judge.ts` | Провайдер по умолчанию воркера | Работает (REV-37) |
| 6. Section Grouping | `AuditWorker` → `site-grouping.service.ts` (`readPageSections`) | Vision через `LlmClient` (`VISION_LLM_PROVIDER`, иначе провайдер по умолчанию, иначе CLI) | Работает (REV-113), только id |

---

### Агент 1: Агент аудита дизайна (Design & UX Critique Agent)
* **Назначение:** Оценка визуальной привлекательности первого экрана, иерархии и выявление устаревших UI-паттернов на основе скриншота.
* **Модель:** Мультимодальная (Vision LLM: Anthropic Claude / OpenAI GPT-4o / локальный Claude Code CLI).
* **Выбор провайдера (REV-51):** `VISION_LLM_PROVIDER` (`anthropic` | `openai` | `claude-cli`); если пуст — ключ Anthropic, затем ключ OpenAI, затем `claude-cli`, если бинарник `CLAUDE_CLI_PATH` найден. Без провайдера аудит завершается ошибкой, критика не выдумывается (REV-45). CLI получает оба скриншота как image-блоки через `stream-json` (без инструментов, MCP, настроек и сессии), модель — `CLAUDE_CLI_MODEL`, `modelUsed` = `claude-cli:<модель>`; температуры у CLI нет, повторы просто перезапускают вызов.
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

Output format (use exactly these keys and types):
{
  "visualHierarchyRating": <integer 0-100>,
  "mobileFriendlinessRating": <integer 0-100>,
  "primaryCtaFound": <true if a clear primary call to action is visible above the fold, else false>,
  "datedDesignFactors": [<up to 5 short kebab-case strings, e.g. "low-contrast-typography">],
  "criticalFlaws": [
    { "title": "<max 80 characters>", "impact": "<max 200 characters>", "recommendation": "<max 200 characters>" }
  ] (exactly 3 items),
  "quickWins": ["<max 150 characters>"] (exactly 3 plain strings)
}
```

Блок `Output format` добавлен в REV-51: без него модель возвращала JSON своей структуры, и каждый аудит уходил в детерминированный fallback.

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

### Агент 5: Агент правок MVP (MVP Edit Agent) — REV-85
* **Назначение:** Применить изменение, описанное оператором своими словами («сделай заголовок ярче», «теплее цвет», «отзывы выше услуг, темный первый экран»), к текстам, основному цвету, макету и/или своему дизайну (REV-92) готового MVP.
* **Модель:** провайдер и модель по умолчанию воркера (`MVP_LLM_PROVIDER`), `temperature: 0.2`, таймаут HTTP-провайдеров 90 с, одна попытка (оператор ждет ответа).
* **Главное правило:** Strict Grounding как у генерации. Модель может переписать, сократить, переставить или убрать уже имеющееся, но не добавлять факты. Код проверяет ответ после Zod: каждое число, e-mail и ссылка в новых текстах должны быть в исходном сайте (`buildGroundingCorpus`) или в текущих текстах; цвет — из списка `allowedColors` (текущий, цвета бренда, `MVP_COLOR_PRESETS`); тексты проходят `enforceStrictGrounding`. Нарушение — ошибка, ничего не применяется частично; без провайдера — ошибка без запасного варианта (REV-45).
* **Код:** `apps/workers/src/services/mvp-edit.service.ts` (`MVP_EDIT_SYSTEM_PROMPT`), воркер — `apps/workers/src/workers/mvp-edit.worker.ts`.

#### Системный промпт (System Prompt):
```text
You are the editor of a generated one-page landing page (MVP) for a local business.
The operator describes, in their own words, a change they want. Apply it to the MVP's current copy, primary color and layout, and change nothing else.

FUNDAMENTAL GROUNDING RULES:
- Every fact (services, products, locations, numbers, years, ratings, prices, staff, awards) must come from "originalSite" or the current copy. Never invent any of them, even when the operator asks for one.
- Never output phone numbers, email addresses, street addresses or links; they are rendered separately from verified data.
- You may rephrase, shorten, reorder, restyle or drop what is already there.
- primaryColor must be one of the hex values in "allowedColors". layout must be one of "allowedLayouts".
- When the request cannot be met within these rules, change nothing and say why in the summary.

Output:
- summary: one sentence (up to 300 characters) telling the operator what you changed, or why you changed nothing. Write it in the language of the operator's instruction.
- content: the complete revised copy in exactly the shape of "current.content", written in "outputLanguage", with the same length limits: hero.badge 40, hero.headline 90, hero.subheadline 180, hero CTA texts 35 each, about.heading 80, about.body 700, servicesHeading 80, 1-6 services (title 50, description 120, a Lucide icon name), at most 3 trustSignals (metric 20, label 50), offerNotice 100. Use null when the copy should stay as it is.
- primaryColor: the new primary color, or null to keep the current one.
- layout: the new layout, or null to keep the current one.

Respond with a raw JSON object only, with no preamble and no markdown, in exactly this shape:
{"summary":string,"content":object|null,"primaryColor":string|null,"layout":string|null}
```

#### Схема валидации выхода (Zod Schema):
```typescript
export const MvpEditOutputSchema = z.object({
  summary: z.string().trim().min(1).max(300),        // что изменено или почему ничего
  content: MvpContentOutputSchema.nullable().optional(), // весь исправленный текст; null — без изменений
  primaryColor: z.string().regex(/^#[A-Fa-f0-9]{6}$/).nullable().optional(),
  layout: MvpLayoutVariantSchema.nullable().optional(),
  design: MvpDesignSchema.nullable().optional()        // REV-92: весь новый дизайн; {} — сбросить
});
```

#### Словарь дизайна (REV-92)
Промпт получает словарь из тех же констант, что схема и шаблон (`MVP_DESIGN_*` в `@revamp/shared-types`), поэтому они не расходятся: секции и блоки для `sectionOrder`, скрываемое (`hidden`), части первого экрана, 11 элементов и токены стилей, шрифты, плотность, скругления, стиль первого экрана, типы и стили блоков, список поддерживаемых иконок. Агент получает `current.design` и возвращает полный новый дизайн, сохраняя прежние решения оператора, которых не касается просьба. Ответ вне словаря не проходит `MvpDesignSchema`, и изменение не применяется.

Для того, что словарь не выражает, агент может вернуть `design.customCss` (REV-93): промпт перечисляет разрешенные хуки и классы (`MVP_CSS_HOOKS`) и правила, и требует предпочитать токены. `sanitizeMvpCss` проверяет CSS в коде; нарушение отклоняет все изменение целиком, а слишком длинный CSS (больше 4 КБ) не обрезается, а отклоняется.

### Агент 6: Агент группировки секций (Section Grouping Agent) — REV-113
* **Назначение:** Разбить главную страницу оригинала на шапку, секции и подвал там, где правила читателя REV-109 не справляются (табличные и конструкторские верстки), чтобы MVP перестраивал страницу (REV-110), а не уходил в Bento (`rebuild:flat`, REV-112).
* **Главное правило:** модель может группировать и классифицировать куски страницы только по id; она никогда не пишет текст или разметку. В схеме ответа нет строковых полей, неизвестные ключи отбрасываются, а весь текст, ссылки и фото копируются со страницы по id (`assembleGroupedBlocks`).
* **Вход:** контур страницы `RawPageOutline` (`collectSiteSectionsInPage` → `outline`, до 600 кусков `OUTLINE_LIMITS.pieces` в порядке документа): заголовки (`h1`–`h6` или «стилевые» — строка 1–120 знаков одна в строке, жирная, ≥ 1,2× основного кегля или прописная), текст, разрезанный по `<br>` и границам блоков, списки, строки ссылок, фото от 40 px, фоновые фото от 200×100, встраивания; у каждого — рамка, шрифт, фон, `hidden` для сохраненного скрытого текста и `slide` для куска на слайде. Связанные карточки (`<a>` вокруг заголовка и абзацев) читаются как заголовки и текст, форма на всю страницу (ASP.NET) — как страница, клоны слайдов не читаются. Промпт показывает первые 160 знаков текста; плюс до 6 тайлов desktop-скриншота 1440×1800 (`ImageService.tilesForVision`, WebP 1024 px), ниша и URL.
* **Модель:** `VISION_LLM_PROVIDER`, иначе `MVP_LLM_PROVIDER`, иначе первый ключ API, иначе локальный CLI, через `LlmClient` с картинками (Anthropic `image`, OpenAI `image_url`, Gemini `inline_data`, CLI stream-json). `temperature` 0.1, потом 0; 2 попытки; `maxTokens` 8000; таймаут HTTP 120 с; во второй попытке модели сообщают, почему первый ответ отклонен.
* **Бюджет (замер на claude-cli sonnet):** anident.pl ≈ 12k входа / 0,6k выхода, falcodent.pl ≈ 19,5k / 1,2k; верхняя граница ≈ 25k входа и 4k выхода на вызов. Событие `token_usage` со стадией `audit_section_grouping`. Вызов идет параллельно с критикой дизайна.
* **Проверка ответа** (`checkGrouping`): известные id, каждый не больше одного раза, у каждой секции заголовок — кусок `heading` или `text` до 120 знаков, логотип — `image`, хотя бы одна секция. Сборка: слайдер получает по элементу на слайд того слайдера, где текст (начиная со слайда на экране), галерея без элементов — по элементу на фото, любая другая секция без элементов — по элементу на строку ее первого куска `list` и списков сразу за ним (REV-122: модель называет список одним id и не может назвать его строки; ссылка списка идет со строкой, где есть ее текст, текст до списка остается вступлением, после — дополнительным блоком); затем `readSiteSections(raw, [], 'llm')` чистит, ограничивает, считает покрытие и валидирует `SiteSectionsSchema`. Куски, которые модель никуда не положила, — `skipped` с причиной `unassigned`, они не считаются захваченными.
* **Fallback** (`readPageSections`): если провайдер не настроен, вызов упал, ответ дважды невалиден, сборка упала или чтение модели не проходит `rebuildEligibility`, когда чтение правилами проходит, — сохраняется чтение правилами (`source: 'rules'`), а причина пишется в `Audit.measurementErrors` как `sections` (не оценивается, дашборд показывает ее отдельной строкой). Аудит из-за группировки не падает.
* **Код:** `apps/workers/src/services/site-grouping.service.ts` (`SITE_GROUPING_SYSTEM_PROMPT`, `SiteGroupingService`, `readPageSections`), `site-grouping.ts` (`checkGrouping`, `assembleGroupedBlocks`, `readGroupedSections`, `outlinePrompt`); проверка на реальных сайтах — `npx tsx scripts/read_site_sections.ts --llm <url>`, запись ответов для тестов — `--record <dir>`. Тесты используют только записанные ответы.

#### Системный промпт (System Prompt):
```text
You organise a business's home page into sections. You never write text.

Inputs: screenshots of the desktop page (1440px wide) in order, each with its page range, and an outline:
one line per numbered piece of the page (heading, text, list, links, image, background, embed) with its
font size, bold (b), position (y = px from the top of the page, x) and size, and the start of its text.
"styled" headings are short bold, large or uppercase lines that are not HTML headings. "hidden" pieces are
kept page text that is not shown until clicked (an accordion answer, a tab). "slide=S.N" marks a piece on
slide N of slider S; slides other than the current one sit outside the screenshots (x beyond the page width).

Group the pieces as a visitor sees the page:
- header: the logo image (logo) and the menu and top-bar pieces (pieces).
- sections, in page order: each starts at its heading and holds every piece that belongs to that heading
  until the next section: its text, lists, buttons and the photos shown with it. A photo floated beside or
  between paragraphs belongs to that paragraph's section, never to a separate gallery.
- heading: the section's main title. A short label right above a larger title (a small "O NAS" over
  "Poznaj nasz gabinet") is the eyebrow, and the larger title is the heading.
- a box with its own heading (a "Questions? Write to us" box beside a text, a contact form with a title)
  is its own section, not part of the text next to it.
- items, only for repeated cards or entries (services, people, reviews, questions): each item's title id and pieces.
- a slider (pieces marked slide=S.N) is one section with arrangement slider; its heading is the first slide's
  heading and its pieces are every piece of every slide (the slides become its items).
- a gallery of photos is one section with arrangement gallery; its photos go in its pieces.
- footer: the pieces at the bottom (address, hours, links, copyright).
- kind, one of: services, pricing, gallery, about, team, reviews, faq, contact, map, features, other.
- arrangement, how the section shows its content, one of: banner, media-beside-text, text, card-grid, list,
  accordion, tabs, slider, gallery, embed.

Rules:
- Use only ids from the outline. Use each id at most once in the whole answer: a piece that is a section's
  heading or an item's title is not listed again in pieces.
- Every section needs a heading id: a heading piece, or a text piece of at most 120 characters that reads
  as a title. Never an image, a list, links or a longer text: when a block has no such title, add it to
  the section before it.
- Place every piece that is part of the page, including link lists inside sections (they are the page's
  own copy). Leave a piece out only when it is not content: a second copy of the header menu (for example a
  hidden mobile menu with the same links), a hit counter, an empty spacer.
- Respond with one raw JSON object, no prose, no markdown:
{"header":{"logo":<id>,"pieces":[<id>...]},"sections":[{"heading":<id>,"eyebrow":<id, optional>,"pieces":[<id>...],
"items":[{"title":<id>,"pieces":[<id>...]}] (optional),"kind":"<kind>","arrangement":"<arrangement>"}],"footer":{"pieces":[<id>...]}}
```

#### Схема валидации выхода (Zod Schema):
```typescript
const pieceId = z.number().int().min(1).max(OUTLINE_LIMITS.pieces);
const pieceIds = z.array(pieceId).max(OUTLINE_LIMITS.pieces);

export const SiteGroupingAnswerSchema = z.object({
  header: z.object({ logo: pieceId.optional(), pieces: pieceIds }).optional(),
  sections: z.array(z.object({
    heading: pieceId,
    eyebrow: pieceId.optional(),
    pieces: pieceIds,
    items: z.array(z.object({ title: pieceId.optional(), pieces: pieceIds })).max(OUTLINE_LIMITS.items).optional(),
    kind: z.enum(SITE_SECTION_KINDS),
    arrangement: z.enum(SITE_SECTION_ARRANGEMENTS),
  })).min(1).max(OUTLINE_LIMITS.sections),
  footer: z.object({ pieces: pieceIds }).optional(),
}); // ни одного строкового поля: текст модели не может попасть в чтение
```

---

### Агент 7: Агент правки перестройки (Rebuild Edit Agent) — REV-111
* **Назначение:** Применить изменение, описанное оператором своими словами, к перестроенному MVP (макет `original`): переставить, скрыть, перекрасить секции оригинальной страницы, убрать абзацы или элементы, выбрать цвет или шаблонный макет, написать CSS.
* **Модель:** провайдер и модель по умолчанию воркера (`MVP_LLM_PROVIDER`), `temperature: 0.2`, таймаут HTTP-провайдеров 90 с, одна попытка.
* **Главное правило:** модель не пишет текст страницы — ни заголовков, ни фраз, ни чисел, ни контактов. Ответ содержит только id из контура страницы (`buildRebuildOutline`: секции `hero`/`content` с id `s-<index>`, видом, расположением, заголовком и кусками `s-<i>.t<n>` / `.i<n>` / `.x<n>` с превью до 160 знаков), фиксированные значения, цвет из `allowedColors`, макет и CSS. Просьба, требующая нового текста, ничего не меняет, причина — в `summary` (видит только оператор).
* **Проверка:** `RebuildEditOutputSchema` (Zod, строгие объекты, без строковых полей кроме `customCss`), затем `checkRebuildEdit` (известные id, без повторов, не все секции скрыты, секция с `h1` не скрыта и, если открывает страницу, остается первой), затем `sanitizeMvpCss`, затем цвет из кандидатов. Нарушение — ошибка `502 MVP_EDIT_FAILED`, ничего не применяется частично.
* **Код:** `apps/workers/src/services/rebuild-edit.service.ts` (`REBUILD_EDIT_SYSTEM_PROMPT` строится из `REBUILD_EDIT_BACKGROUNDS`, `REBUILD_EDIT_ALIGNS`, `MVP_DESIGN_FONTS` / `DENSITIES` / `CORNERS`, `REBUILD_CSS_HOOKS`), воркер — `mvp-edit.worker.ts`, применение — `planRebuild`.

#### Схема валидации выхода (Zod Schema):
```typescript
export const RebuildEditAnswerSchema = z.object({
  order: z.array(SectionId).max(45).optional(),       // 's-<index>'
  hidden: z.array(SectionId).max(45).optional(),
  dropped: z.array(PieceId).max(200).optional(),      // 's-<i>.t<n>' | 's-<i>.i<n>' | 's-<i>.x<n>'
  sections: z.record(SectionId, z.object({
    background: z.enum(['original', 'page', 'tinted', 'brand', 'dark']).optional(),
    align: z.enum(['left', 'center']).optional(),
    density: z.enum(MVP_DESIGN_DENSITIES).optional(),
  }).strict()).optional(),
  theme: z.object({
    font: z.enum(MVP_DESIGN_FONTS).optional(),
    density: z.enum(MVP_DESIGN_DENSITIES).optional(),
    corners: z.enum(MVP_DESIGN_CORNERS).optional(),
    headingCase: z.enum(['none', 'uppercase']).optional(),
  }).strict().optional(),
  customCss: z.string().max(4096).optional(),         // только через sanitizeMvpCss
}).strict();

export const RebuildEditOutputSchema = z.object({
  summary: z.string().trim().min(1).max(300),
  edit: RebuildEditAnswerSchema.nullable().optional(),  // вся новая правка; {} — сбросить; null — оставить
  primaryColor: z.string().regex(/^#[A-Fa-f0-9]{6}$/).nullable().optional(),
  layout: MvpLayoutVariantSchema.nullable().optional(), // шаблонный макет заменяет перестройку
});
```

### Агент 8: Агент модернизации перестройки (Rebuild Modernize Agent) — REV-114
* **Назначение:** Выбрать современный вид перестройки устаревшего сайта (уровень `modern`): первый экран из `h1` и фото, фото на всю колонку с чередованием сторон, карточки из серий коротких абзацев и списков, фоны и шкалу шрифтов. Работает как арт-директор: решает только расположение и стиль секций, которые уже есть на странице.
* **Модель:** провайдер копирайтинга по умолчанию (`MVP_LLM_PROVIDER`, локально `claude-cli`) через `LlmClient`, только текст — без скриншотов, `temperature: 0.2`, таймаут `EDIT_LLM_TIMEOUT_MS`, не больше двух попыток. Вызывается один раз на аудит при первой отрисовке на уровне `modern` (генерация или первое переключение оператором) и не вызывается, если `rebuildEligibility` не проходит.
* **Главное правило:** модель ничего не удаляет, не скрывает и не переставляет и не пишет текст страницы — ни заголовков, ни фраз, ни подписей, ни чисел, ни контактов, ни ссылок. Ответ содержит только id из контура страницы и фиксированные значения. Вход — `page` (контур `buildRebuildOutline`, дополненный для каждой секции полями `arrangeAs` — какие расположения подходят ее содержимому — и `photoBeside`), `brandColors` (цвета самого сайта) и `start` — разумный вид по умолчанию (`defaultModernDesign`), который модель оставляет как есть или меняет только где страница этого требует. Промпт `REBUILD_MODERNIZE_SYSTEM_PROMPT` строится из тех же констант, что и схема: `hero { photo, style }` (фото — id вида `s-<i>.m<n>` из `images` следующих секций, только если у первой секции нет своего фото; `banner` — для фото не уже `REBUILD_BANNER_MIN_WIDTH` = 1000 px), `sections[id]` (`arrangement` только из `arrangeAs`, `mediaSide` и `media` только для секции с `photoBeside`, `background`, `align`, `density`), `theme` (`typeScale`, `font`, `density`, `corners`). Просит ответ сырым JSON `{"design": …}` без пояснений.
* **Проверка:** `RebuildModernizeAnswerSchema` (Zod, строгая: `RebuildEditAnswerSchema` без `order`, `hidden`, `dropped`, `customCss`, строковых полей нет), затем `checkRebuildEdit` (известные id, правила посадки: `arrangement` только там, где подходит серия от 3 абзацев до `REBUILD_CARD_MAX_CHARS` = 300 знаков, список от 3 элементов или от 3 элементов рядом с фото (`rebuildItemsFitCards`, REV-122: карточки на всю ширину, фото после них), `mediaSide` / `media` только у `media-beside-text` с фото, фото первого экрана существует после секции с `h1`, а у нее своего фото нет). Отклоненный первый ответ повторяется один раз с причиной (`previousAnswerRejected`).
* **Fallback:** метод `choose` не бросает исключений при сбое модели. Нет провайдера или он не настроен — `{ source: 'default', design: defaultModernDesign(...), error: 'not_configured' }`; сбой вызова — `error: 'call_failed: …'`; два отклоненных ответа — `error: 'invalid: <причина>'`. Запасной вид сохраняется в `MvpProject.modernize` и помечается причиной `modernize:default`; если он получен из-за `call_failed` или `not_configured`, при следующей отрисовке вычисляется заново. Успех — `{ source: 'llm', design }`.
* **Код:** `apps/workers/src/services/rebuild-modernize.service.ts` (`RebuildModernizeService`, `REBUILD_MODERNIZE_SYSTEM_PROMPT`), запасной вид и `modernizeForAudit` — `rebuild-modernize.ts`, вызов — `deploy.worker.ts` (генерация и `relayout-mvp`), применение — `planRebuild` (`mergeRebuildEdits`, правка оператора важнее). Проверка на реальных сайтах: `npx tsx scripts/render_rebuild.ts --llm --level modern --record <dir> <out-dir> <url>`.

#### Схема валидации выхода (Zod Schema):
```typescript
// RebuildEditAnswerSchema (Агент 7) с полями REV-114, без order, hidden, dropped, customCss
export const RebuildModernizeAnswerSchema = RebuildEditAnswerSchema.omit({ order: true, hidden: true, dropped: true, customCss: true }).strict();
// sections[id]: { background?, align?, density?,
//                 arrangement?: 'card-grid' | 'list', mediaSide?: 'left' | 'right', media?: 'natural' | 'fill' }
// hero?: { photo: 's-<i>.m<n>', style: 'split' | 'banner' }
// theme?: { font?, density?, corners?, headingCase?, typeScale?: 'original' | 'modern' }
// Ответ модели: { design: RebuildModernizeAnswerSchema }
```

---

### 4.5. LLM-провайдеры и `LlmClient` (REV-30, REV-32, REV-37)
* Все вызовы LLM из воркеров (кроме Vision-критики) идут через `LlmClient`; с REV-113 он принимает картинки (`images`) и возвращает расход токенов (`completeWithUsage`) — так работает группировка секций (Агент 6) (`apps/workers/src/services/llm-client.ts`): Anthropic, OpenAI, Gemini и локальный Claude Code CLI. Вызывающий код передает system/user prompt и получает сырой текст; разбор и Zod-валидация остаются у вызывающего.
* Каталог провайдеров и моделей — `LLM_PROVIDER_CATALOG` в `@revamp/shared-types` (первая модель — модель по умолчанию):

| Провайдер | Модели | Особенности |
|---|---|---|
| `anthropic` | `claude-opus-5`, `claude-sonnet-5`, `claude-haiku-4-5` | Нужен `ANTHROPIC_API_KEY`; `temperature` не передается; ответ читается из текстового блока после блока мышления |
| `openai` | `gpt-4o`, `gpt-4o-mini` | Нужен `OPENAI_API_KEY` |
| `gemini` | `gemini-1.5-pro`, `gemini-1.5-flash` | Нужен `GEMINI_API_KEY` |
| `claude-cli` | `sonnet`, `opus`, `haiku` | Локальный `claude -p` под залогиненным аккаунтом, без API-ключа; без инструментов, MCP и настроек, во временной папке; таймаут `CLAUDE_CLI_TIMEOUT_MS` |

* Провайдер без своего ключа или отсутствие провайдера — ошибка задачи с понятным сообщением (REV-45): тексты не выдумываются. Упавший при вызове провайдер дает детерминированный fallback и никогда не переключается на другой платный провайдер.
* Vision-критика (Агент 1) без `ANTHROPIC_API_KEY` или `OPENAI_API_KEY` тоже завершается ошибкой, и аудит получает статус `AUDIT_FAILED` с причиной. При старте воркеры пишут предупреждение о каждом ненастроенном провайдере.
* Воркеры публикуют доступность провайдеров в Redis (`revamp:llm-capabilities`), API отдает ее в `GET /api/v1/mvp/providers`; дашборд показывает только доступные варианты.

---

## 5. Политика отказоустойчивости и защита от галлюцинаций (Guardrails)

1. **Strict Fallback Policy (Политика откатов):**
   * Перед валидацией строки ответа обрезаются до лимитов схемы (REV-34), чтобы одно слишком длинное поле не отбрасывало весь ответ.
   * Если ответ модели падает при валидации через `ZodSchema.safeParse()`, задача повторяется до 2 раз со снижением `temperature` до `0.0`.
   * При повторном падении вызова система активирует **детерминированный Fallback** (переключения на другой платный провайдер нет). Fallback срабатывает только после реального сбоя настроенного провайдера; если провайдер не настроен или у него нет ключа, задача завершается ошибкой (REV-45):
     - Hero, «О нас», услуги и плашки доверия собираются из контента исходного сайта: H1 или title (общие заголовки вроде «Главная» пропускаются), meta description, реальные услуги и только проверяемые метрики (рейтинг, год основания, число отзывов), на языке сайта.
     - Письмо собирается по статическому шаблону в дашборде.
     - В базу выставляется флаг `aiFallbackUsed: true`, `MvpProject.provider = 'deterministic'`, а в дашборде оператора отображается, кто написал тексты.
   * Критика дизайна (`DesignCritiqueAgent`) после 3 неудачных вызовов заменяется шаблоном, который не оценивается: критерий дизайна выпадает из итоговой оценки, в `Audit.measurementErrors` пишется `design` с причиной, а дашборд помечает критику как шаблон (REV-101).
   * Группировка секций (Агент 6) при сбое, невалидном ответе или чтении хуже правил по воротам перестройки откатывается на чтение правилами REV-109; в `Audit.measurementErrors` пишется `sections` с причиной (REV-113).
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
