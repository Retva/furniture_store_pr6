# PocketBase для «МебельДом»

PocketBase — база с готовым REST API и админкой в одном файле.
`flutter run` его **не** запускает: сервер должен работать отдельно
(локально или на Railway).

## Локальный запуск

1. Исполняемый файл: `pocketbase.exe` (Windows). В репозиторий не коммитится;
   `pb_data/` в `.gitignore`.

2. Из этой папки:

```bash
./pocketbase serve
```

Адреса:

- API — http://127.0.0.1:8090  
- Админка — http://127.0.0.1:8090/_/  

Суперпользователь (создаётся миграцией):  
`admin@mebeldom.local` / `mebel-admin-8090`

3. Миграции из `pb_migrations/` применяются сами при `serve`.
   Описание полей — в [схема.md](схема.md).

4. Демонстрационные данные (Node.js 18+):

```bash
node seed.mjs
```

Повторная заливка:

```bash
node seed.mjs --reset
```

## Запуск Flutter с локальным сервером

```bash
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5555 --dart-define=API_BASE_URL=http://127.0.0.1:8090
```

Вход после seed:

| Email | Пароль | Роль |
| --- | --- | --- |
| admin@mebeldom.ru | mebel12345 | admin |
| manager@mebeldom.ru | mebel12345 | manager |
| viewer@mebeldom.ru | mebel12345 | viewer |

## GitHub Pages → Railway

Сайт https://retva.github.io/furniture_store_pr6/ ходит на PocketBase на Railway
по HTTPS (переменная Actions `API_BASE_URL`).

Деплой бэкенда (если ещё не сделан):

1. Railway → Deploy from GitHub → репозиторий `furniture_store_pr6`,
   root directory: `pocketbase`.
2. **Volume**, mount path: `/pb/pb_data`.
3. **Settings → Networking → Generate Domain**
   (без домена сервис «Unexposed» и с github.io недоступен).
4. Проверка: `https://furniturestorepr6-production.up.railway.app/api/health`
5. Seed:

```bash
$env:PB_URL="https://furniturestorepr6-production.up.railway.app"; node seed.mjs --reset
```

6. GitHub → Settings → Secrets and variables → Actions → Variables:
   `API_BASE_URL` = `https://furniturestorepr6-production.up.railway.app` (без `/` в конце).
7. Workflow **Build and deploy** — пересборка Pages.

Админка: `https://furniturestorepr6-production.up.railway.app/_/`  
Суперпользователь: `admin@mebeldom.local` / `mebel-admin-8090`

Файлы деплоя: `Dockerfile`, `railway.toml`.

## Содержательная особенность (п. 20 итога)

Хук `pb_hooks/orders.pb.js`: при создании заказа проверяет остаток на складе
(конфликт 409), применяет скидку по карте покупателя и списывает `stock`.
