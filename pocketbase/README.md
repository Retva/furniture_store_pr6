# PocketBase для «МебельДом»

PocketBase — база с готовым REST API и админкой в одном файле.
`flutter run` его **не** запускает: сервер должен работать в отдельном терминале.

## Запуск

1. Исполняемый файл уже лежит здесь: `pocketbase.exe` (Windows).
   В репозиторий его можно не коммитить — у каждого свой; `pb_data/` в `.gitignore`.

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

PocketBase молча игнорирует поля, которых нет в коллекции: если в приложении
пустое поле — сверьте имя с `схема.md` и перезалейте с `--reset`.

## Запуск Flutter с сервером

```bash
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5555 --dart-define=API_BASE_URL=http://127.0.0.1:8090
```

Адрес API по умолчанию в коде тот же (`lib/core/config.dart`), ключ можно не
писать. `--web-hostname` и `--web-port` фиксируют origin, чтобы localStorage
(сессия) не «терялся» при смене порта.

Вход в приложение после seed:

| Email | Пароль | Роль |
| --- | --- | --- |
| admin@mebeldom.ru | mebel12345 | admin |
| manager@mebeldom.ru | mebel12345 | manager |
| viewer@mebeldom.ru | mebel12345 | viewer |

## Где лежат данные

Папка `pb_data` рядом с `pocketbase.exe`. Если всё сломалось — удалите `pb_data`,
снова `./pocketbase serve`, затем `node seed.mjs --reset`.

## Если приложение не видит сервер

1. Сервер запущен, в консоли нет ошибок.  
2. В браузере откройте  
   http://127.0.0.1:8090/api/collections/products/records  
   (нужен вход; без токена после ролевых правил будет 403 — это нормально).  
3. Проверка здоровья: http://127.0.0.1:8090/api/health  
4. Не смешивайте `localhost` и `127.0.0.1` — для браузера это разные origin.

## Содержательная особенность (п. 20 итога)

Хук `pb_hooks/orders.pb.js`: при создании заказа проверяет остаток на складе
(конфликт 409), применяет скидку по карте покупателя и списывает `stock`.

## Деплой на Railway (HTTPS для GitHub Pages)

Локальный туннель (cloudflared) нестабилен из‑за VPN/DNS. Railway даёт
постоянный `https://….up.railway.app` — с ним сайт на github.io логинится без
смешанного контента.

1. Аккаунт на [railway.app](https://railway.app), **New Project → Deploy from GitHub**
   (репозиторий `furniture_store_pr6`), root directory: `pocketbase`.
2. В сервисе: **Variables** → `PORT=8080` (или оставить авто; Dockerfile слушает 8080).
3. **Volumes → Add Volume**, mount path: `/pb/pb_data` (обязательно, иначе база
   пропадёт при redeploy).
4. После деплоя откройте `https://ВАШ-ДОМЕН.up.railway.app/api/health` —
   должен быть `{"message":"API is healthy.",…}`.
5. Админка: `https://ВАШ-ДОМЕН.up.railway.app/_/`  
   Суперпользователь из миграции: `admin@mebeldom.local` / `mebel-admin-8090`.
6. Seed на облачный API (из папки `pocketbase`):

```bash
$env:PB_URL="https://ВАШ-ДОМЕН.up.railway.app"; node seed.mjs --reset
```

7. В GitHub → Settings → Secrets and variables → Actions → Variables:
   `API_BASE_URL` = `https://ВАШ-ДОМЕН.up.railway.app` (без слэша в конце).
8. Перезапустите workflow **Deploy to GitHub Pages** — сайт
   https://retva.github.io/furniture_store_pr6/ начнёт ходить на Railway.
