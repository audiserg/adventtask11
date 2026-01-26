# Устранение неполадок

## Как проверить ошибки в Chrome

1. Откройте приложение в Chrome
2. Нажмите `F12` или `Cmd+Option+I` (Mac) / `Ctrl+Shift+I` (Windows/Linux)
3. Перейдите на вкладку **Console** (Консоль)
4. Попробуйте отправить сообщение
5. Посмотрите на ошибки в консоли

## Типичные ошибки и решения

### 1. "Failed to connect to server" / "Connection refused"
**Проблема:** Бэкенд не запущен или недоступен

**Решение:**
```bash
cd backend
npm start
```

### 2. "Server configuration error" / "500 Internal Server Error"
**Проблема:** API ключ не настроен в .env файле

**Решение:**
1. Создайте файл `backend/.env`:
```bash
cd backend
cp .env.example .env
```

2. Откройте `.env` и добавьте ваш DeepSeek API ключ:
```
DEEPSEEK_API_KEY=sk-your-actual-api-key-here
PORT=3000
```

3. Перезапустите бэкенд:
```bash
npm start
```

### 3. CORS ошибки в консоли
**Проблема:** Браузер блокирует запросы из-за CORS политики

**Решение:** Убедитесь, что в `backend/server.js` настроен CORS:
```javascript
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));
```

### 4. "Network error" / "Request timeout"
**Проблема:** Проблемы с сетью или DeepSeek API недоступен

**Решение:**
- Проверьте интернет соединение
- Убедитесь, что API ключ валидный
- Проверьте логи бэкенда

### 5. Проверка в Network tab

1. Откройте DevTools (F12)
2. Перейдите на вкладку **Network**
3. Попробуйте отправить сообщение
4. Найдите запрос к `/api/chat`
5. Проверьте:
   - **Status:** должен быть 200
   - **Response:** должен содержать JSON с ответом от ИИ
   - Если статус 500 - проблема на сервере (проверьте .env)
   - Если статус 400 - проблема с форматом запроса

## Быстрая проверка

Запустите скрипт проверки:
```bash
./check_setup.sh
```

## Проверка логов бэкенда

Если бэкенд запущен через PM2:
```bash
pm2 logs deepseek-proxy
```

Если запущен напрямую:
```bash
cd backend
npm start
# Логи будут в консоли
```

## Тестирование API напрямую

Проверьте, что бэкенд работает:
```bash
curl http://localhost:3000/health
```

Должен вернуть: `{"status":"ok"}`

Проверьте API endpoint:
```bash
curl -X POST http://localhost:3000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}]}'
```

Если вернется ошибка 500 - проблема с API ключом в .env
