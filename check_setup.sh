#!/bin/bash

echo "=== Проверка настройки проекта ==="
echo ""

# Проверка бэкенда
echo "1. Проверка бэкенда..."
if curl -s http://localhost:3000/health > /dev/null 2>&1; then
    echo "   ✓ Бэкенд запущен на порту 3000"
else
    echo "   ✗ Бэкенд НЕ запущен. Запустите: cd backend && npm start"
fi

# Проверка .env файла
echo ""
echo "2. Проверка .env файла..."
if [ -f "backend/.env" ]; then
    if grep -q "DEEPSEEK_API_KEY" backend/.env && ! grep -q "your_deepseek_api_key_here" backend/.env; then
        echo "   ✓ .env файл существует и содержит API ключ"
    else
        echo "   ⚠ .env файл существует, но API ключ не настроен"
        echo "      Отредактируйте backend/.env и добавьте ваш DEEPSEEK_API_KEY"
    fi
else
    echo "   ✗ .env файл не найден"
    echo "      Создайте файл backend/.env на основе backend/.env.example"
fi

# Проверка зависимостей
echo ""
echo "3. Проверка зависимостей..."
if [ -d "backend/node_modules" ]; then
    echo "   ✓ Node.js зависимости установлены"
else
    echo "   ✗ Node.js зависимости не установлены"
    echo "      Запустите: cd backend && npm install"
fi

echo ""
echo "=== Готово ==="
