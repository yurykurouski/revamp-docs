# Revamp SaaS — Автоматизированный аудит сайтов и генерация MVP

<p align="center">
  <b>Комплексная SaaS-платформа для автоматизированного B2B-аутрича, глубокого аудита сайтов локального бизнеса и мгновенной генерации современных MVP-лендингов с Human-in-the-Loop контролем.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Node.js-v20%20LTS-339933?logo=node.js&logoColor=white" alt="Node.js" />
  <img src="https://img.shields.io/badge/TypeScript-5.x-3178C6?logo=typescript&logoColor=white" alt="TypeScript" />
  <img src="https://img.shields.io/badge/React-18%2B%20%7C%20Vite-61DAFB?logo=react&logoColor=black" alt="React" />
  <img src="https://img.shields.io/badge/MUI-v6-007FFF?logo=mui&logoColor=white" alt="Material UI" />
  <img src="https://img.shields.io/badge/BullMQ-Redis-DC382D?logo=redis&logoColor=white" alt="BullMQ" />
  <img src="https://img.shields.io/badge/Playwright-Chromium-2EAD33?logo=playwright&logoColor=white" alt="Playwright" />
  <img src="https://img.shields.io/badge/TailwindCSS-3.x-06B6D4?logo=tailwindcss&logoColor=white" alt="Tailwind CSS" />
  <img src="https://img.shields.io/badge/MongoDB-7.0-47A248?logo=mongodb&logoColor=white" alt="MongoDB" />
</p>

---

## 📌 Оглавление

1. [О проекте](#-о-проекте)
2. [Ключевые возможности](#-ключевые-возможности)
3. [Архитектура и пайплайн работы](#-архитектура-и-пайплайн-работы)
4. [Фундаментальные инженерные принципы](#-фундаментальные-инженерные-принципы)
5. [Структура проекта (Monorepo)](#-структура-проекта-monorepo)
6. [Стек технологий](#-стек-технологий)
7. [Документация проекта](#-документация-проекта)
8. [Быстрый старт (Локальное окружение)](#-быстрый-старт-локальное-окружение)
9. [Дорожная карта реализации (4-недельный план)](#-дорожная-карта-реализации-4-недельный-план)
10. [Контакты и вклад](#-контакты-и-вклад)

---

## 💡 О проекте

Веб-студии, агентства и фрилансеры тратят десятки часов в неделю на ручной поиск устаревших сайтов, ручной аудит доступности и верстку коммерческих предложений с конверсией в ответ менее 2–3%.

**Revamp SaaS** трансформирует процесс cold outreach в полностью автоматизированный конвейер:
0. **Находит** локальные бизнесы с сайтами по нише и городу на OpenStreetMap или Google Places; оператор выбирает, кого взять в работу.
1. **Анализирует** устаревший сайт за 40 секунд (замеры Core Web Vitals, доступность WCAG 2.1 AA, скриншоты и мультимодальный AI-аудит первого экрана).
2. **Извлекает айдентику и контент** (палитра K-Means, логотип, телефоны, услуги, тексты, отзывы, schema.org).
3. **Генерирует готовый адаптивный Bento-лендинг** на языке исходного сайта и только из его данных, проверяет его полноту и размещает в песочнице на публичном URL.
4. **Предоставляет оператору удобный дашборд (Side-by-Side)** для моментальной инспекции «До / После» и корректировки палитры/текста в 1 клик.
5. **Отправляет персонализированное письмо** владельцу сайта с интерактивным прототипом и собирает полную телеметрию (открытия, клики, время на сайте).

---

## 🚀 Ключевые возможности

* 🗺️ **Поиск бизнесов на картах (Discovery):**
  * OpenStreetMap (Nominatim + Overpass, без ключа) или Google Places API (New).
  * Автоопределение города оператора, классификация кандидатов (новые, уже в лидах, дубли, без сайта) и импорт только выбранных.
* 🔍 **Многоуровневый детерминированный аудит:**
  * **WCAG 2.1 AA Accessibility:** `@axe-core/playwright` проверяет контрастность, метки форм, alt-теги изображений.
  * **Core Web Vitals:** замеры LCP, CLS, скорости ответа и наличия SSL в браузере.
  * **Скриншоты:** первый экран и полная страница (десктоп и мобайл), cookie-баннеры закрываются автоматически.
  * **Vision LLM Critique:** Мультимодальный ИИ выявляет 3 критические ошибки в дизайне первого экрана и 3 Quick Wins.
* 🎨 **Универсальный модульный Bento-каркас:**
  * Сверхлегкий адаптивный HTML + Tailwind CSS бандл (< 300 Кб).
  * Контент, контакты и отзывы только с исходного сайта; тексты на языке сайта (UI шаблона на en, ru, be, pl, lt).
  * Автоматический подбор иконок Lucide под список услуг.
* 🤖 **Гибкий выбор LLM:** Anthropic, OpenAI, Gemini или локальный Claude Code CLI; провайдер и модель выбираются на каждую генерацию, перегенерация — в один клик.
* ✅ **Проверка полноты MVP:** сравнение с данными исходного сайта (код + LLM с проверяемыми цитатами), балл, чек-лист в инспекторе и предупреждение о выдуманных контактах.
* 🛡️ **Human-In-The-Loop (HITL) Gate:**
  * Никаких автоматических отправок писем без проверки человеком.
  * Дашборд на 5 языках (en, ru, be, pl, lt).
  * Утверждение отправки за 20 секунд с помощью горячих клавиш (`Cmd/Ctrl + Enter`).
  * Быстрый Color Picker для моментальной смены палитры во фрейме предпросмотра.
* 📬 **Умный Email-аутрич и троттлинг:**
  * Интеграция с Resend / SendGrid API.
  * Джиттер-троттлинг (1 письмо в 3 минуты с рандомизацией 15–45 сек) для максимальной защиты репутации домена.
  * DNS-проверка валидности MX-записей перед отправкой и заголовки `List-Unsubscribe`.
* 📊 **Телеметрия в реальном времени:**
  * Невидимый $1\times1$ GIF-пиксель для трекинга открытия писем.
  * Проксирование кликов по ссылке на прототип.
  * Встроенный скрипт трекинга `revamp-tracker.js`: замер времени нахождения на демо (Dwell Time) через Beacon API и кликов по CTA-кнопкам.

---

## 🏗 Архитектура и пайплайн работы

```mermaid
flowchart LR
    Z["0. Поиск на картах<br/>+ ревью оператором"] --> A
    A["1. Ввод URL / База"] --> B["2. Playwright + Axe + Vitals<br/>+ контент сайта"]
    B --> C["3. Vision LLM & K-Means"]
    C --> D["4. Генерация Bento MVP<br/>+ проверка полноты & S3"]
    D --> E["5. React + MUI Дашборд<br/><b>HITL Gate</b>"]
    E -->|Аппрув оператора| F["6. BullMQ Email Dispatcher"]
    F --> G["7. Доставка клиенту"]
    G -->|Клик / Просмотр| H["8. Телеметрия & Dwell Time"]
    H --> E

    style E fill:#dcfce7,stroke:#15803d,stroke-width:2px
    style D fill:#ede9fe,stroke:#6d28d9,stroke-width:2px
    style B fill:#dbeafe,stroke:#1d4ed8,stroke-width:2px
```

---

## 🔒 Фундаментальные инженерные принципы

1. **Human-In-The-Loop (HITL):** Фоновые воркеры переводят сущности в статус `NEEDS_APPROVAL`. Отправка писем клиентам возможна **исключительно** после явного подтверждения оператором.
2. **Детерминизм метрик (Strict Grounding):** Замеры LCP, доступности a11y, извлечение номеров телефонов, адресов и цен осуществляются детерминированным кодом, а не нейросетями.
3. **Строгая валидация (Zod):** Все ответы LLM и входящие HTTP-запросы валидируются через схемы Zod перед записью в базу данных.
4. **Только данные исходного сайта:** MVP не содержит выдуманных контактов, отзывов и метрик; суждения LLM о полноте принимаются только с дословной цитатой, проверенной кодом.
5. **Изоляция сгенерированных MVP:** Сгенерированные прототипы запускаются на изолированном домене (`*.preview.revamp.io`) и встраиваются в дашборд через `<iframe sandbox="allow-scripts allow-same-origin">`.

---

## 📁 Структура проекта (Monorepo)

```text
/
├── apps/
│   ├── api/             # Express.js REST API Gateway (Node.js + TypeScript)
│   ├── workers/         # Фоновые воркеры BullMQ (Playwright, AI, Deploy, Email)
│   └── dashboard/       # Рабочее место оператора (React 18+, Vite, MUI v6, DataGrid)
├── packages/
│   ├── shared-types/    # Общие TypeScript интерфейсы и DTO
│   └── validation/      # Общие Zod-схемы для валидации данных
├── deploy/              # Продакшен-деплой (Docker, Nginx, скрипты)
├── scripts/             # Сервисные скрипты
├── docker-compose.yml   # MongoDB 7.0, Redis 7.0, MinIO
└── AGENTS.md            # Правила для ИИ-разработчика (конвейер тикетов, гейты)
```

Документация (этот репозиторий, `revamp-docs`) лежит рядом с кодом как `../Revamp-docs`: `blueprint.md`, `spec.md`, `research.md`, `milestones.md`, `AGENTS.md`, `PROJECT_COMPLETION_REPORT.md`.

---

## 🛠 Стек технологий

| Область | Технологии |
|---|---|
| **Ядро & Бэкенд** | Node.js (v20+ LTS), Express.js, TypeScript |
| **Базы данных & Очереди** | MongoDB 7.0 (Mongoose), Redis 7.0, BullMQ |
| **Краулинг & Метрики** | Playwright Chromium, `@axe-core/playwright`, Core Web Vitals, Sharp, happy-dom |
| **Поиск бизнесов** | OpenStreetMap Nominatim + Overpass, Google Places API (New) |
| **AI & LLM** | Anthropic (Claude Opus 5 / Sonnet 5 / Haiku 4.5), OpenAI GPT-4o / GPT-4o-mini, Google Gemini 1.5, локальный Claude Code CLI |
| **Фронтенд дашборда** | React 18+, Vite, Material UI (MUI v6), `@mui/x-data-grid`, TanStack Query v5, Zustand, i18next |
| **Сгенерированный MVP** | HTML5, Tailwind CSS, Lucide Icons, Vanilla JS Tracker |
| **Хранилище & Хостинг** | MinIO (локально), Cloudflare R2 / AWS S3, Cloudflare Pages |
| **Email-инфраструктура** | Resend API / SendGrid API, Nodemailer, DNS MX Validator |

---

## 📚 Документация проекта

В репозитории собрана детальная инженерная документация:

* 🏆 [**`PROJECT_COMPLETION_REPORT.md`**](./PROJECT_COMPLETION_REPORT.md) — **Итоговый отчет о завершении первоначальной дорожной карты** (`REV-1` — `REV-20`): архитектура на тот момент, результаты E2E-тестирования 20 сайтов и инструкция по развертыванию на VPS Hetzner / Cloudflare.
* 📐 [**`blueprint.md`**](./blueprint.md) — Системный архитектурный блюпринт: описание слоев, очередей BullMQ, схемы MongoDB и диаграммы взаимодействия.
* 📋 [**`spec.md`**](./spec.md) — Спецификация требований (SRS): функциональные требования, жизненный цикл лида, REST API эндпоинты.
* 🔬 [**`research.md`**](./research.md) — Архитектурные исследования, ключевые решения (ADR), пользовательские сценарии (CJM) и конкурентный анализ.
* ⏱️ [**`milestones.md`**](./milestones.md) — 4-недельная ускоренная дорожная карта с детализацией по дням, а также развитие после релиза (`REV-21` — `REV-41`) со статусами.
* 🤖 [**`AGENTS.md`**](./AGENTS.md) — Руководство и системные промпты для автономных ИИ-агентов платформы и ИИ-разработчика.

---

## ⚡ Быстрый старт (Локальное окружение)

### Требования
* Node.js >= 20.x
* Docker и Docker Compose
* npm или pnpm

### 1. Клонирование и установка зависимостей
```bash
git clone https://github.com/revamp-saas/revamp.git
cd revamp
npm install
```

### 2. Запуск инфраструктуры (MongoDB, Redis, MinIO)
```bash
docker compose up -d
```

### 3. Настройка переменных окружения
Создайте файл `.env` в корне проекта на основе `.env.example`:
```env
PORT=4000
MONGODB_URI=mongodb://localhost:27017/revamp
REDIS_HOST=localhost
REDIS_PORT=6379

# AI Providers
ANTHROPIC_API_KEY=your_claude_key
OPENAI_API_KEY=your_openai_key
GEMINI_API_KEY=
# anthropic | openai | gemini | claude-cli | mock (пусто = первый найденный ключ)
MVP_LLM_PROVIDER=
# claude-cli: локальный Claude Code CLI под залогиненным аккаунтом
CLAUDE_CLI_PATH=claude
CLAUDE_CLI_MODEL=sonnet
CLAUDE_CLI_TIMEOUT_MS=120000
# Проверка полноты MVP через LLM (false = только кодом)
MVP_COMPLETENESS_LLM=true
MVP_COMPLETENESS_LLM_TIMEOUT_MS=90000

# Object Storage (MinIO / S3)
S3_ENDPOINT=http://localhost:9000
S3_BUCKET_ASSETS=revamp-assets
S3_BUCKET_DEMOS=revamp-demos
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin

# Email Outreach
EMAIL_PROVIDER=mock
RESEND_API_KEY=re_your_api_key
EMAIL_FROM="Revamp Team <outreach@revampdemo.com>"

# Local Business Discovery (OpenStreetMap работает без ключа)
GOOGLE_PLACES_API_KEY=
DISCOVERY_USER_AGENT="RevampBot/0.1 (+https://revampdemo.com)"
```
Полный список переменных — в `.env.example` кодового репозитория.

### 4. Запуск сервисов в режиме разработки
```bash
# Запуск всех приложений (API, Workers, Dashboard)
npm run dev

# Либо раздельный запуск:
npm run dev:api         # http://localhost:4000
npm run dev:workers     # BullMQ воркеры аудита и генерации
npm run dev:dashboard   # http://localhost:5173
```

---

## 🗓 Дорожная карта реализации (4-недельный план)

Спринты и задачи зафиксированы в Linear-проекте [**Revamp**](https://linear.app/revamp-proect/project/revamp-992fa5274adb):

* 🔹 **Спринт 1 (Дни 1–7):** Инфраструктура, краулер Playwright, замеры Axe/Lighthouse, Vision LLM и скоринг (`POST /api/v1/leads`).
* 🔹 **Спринт 2 (Дни 8–14):** K-Means экстрактор палитры, модульный Bento-шаблон Tailwind, ИИ-копирайтинг и хостинг MVP в R2/S3.
* 🔹 **Спринт 3 (Дни 15–21):** React + Material UI v6 дашборд, Kanban-доска, Side-by-Side инспектор и HITL-шлюз аппрува.
* 🔹 **Спринт 4 (Дни 22–28):** Почтовый диспетчер с троттлингом, трекинг Dwell Time, E2E-тесты на 20 реальных сайтах и боевой деплой.
* 🔸 **После релиза (`REV-21` — `REV-41`):** поиск бизнесов на картах, контент и язык исходного сайта в MVP, проверка полноты, выбор LLM-провайдера и перегенерация, закрытие cookie-баннеров, локализация дашборда. Статусы — в [`milestones.md`](./milestones.md#6-развитие-после-релиза-rev-21--rev-41).

---

## 📄 Лицензия

Проект распространяется под лицензией **MIT**. Подробности в файле `LICENSE`.
