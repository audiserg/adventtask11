# Инструкция по отправке на GitLab

## Текущий статус:
- ✅ Remote `gitlab` добавлен: `git@gitlab.com:audiserg/adventTask2.git`
- ✅ Коммит готов к отправке
- ⚠️  Нужно создать репозиторий на GitLab и/или настроить доступ

## Шаги для отправки:

### 1. Создайте репозиторий на GitLab:
- Перейдите на https://gitlab.com/audiserg/adventTask2
- Или создайте новый репозиторий с именем `adventTask2`

### 2. Если репозиторий уже создан, отправьте код:
```bash
cd /Users/audiserg/StudioProjects/adventChallege/adventTask1
git push -u gitlab main
```

### 3. Если нужна аутентификация через HTTPS:
```bash
git remote set-url gitlab https://gitlab.com/audiserg/adventTask2.git
git push -u gitlab main
# Введите ваш GitLab username и personal access token
```

### 4. Если SSH ключ не добавлен в GitLab:
- Скопируйте публичный ключ: `cat ~/.ssh/id_rsa.pub`
- Добавьте его в GitLab: Settings → SSH Keys

## Текущие remotes:
- `origin` → GitHub (https://github.com/audiserg/adventTask1.git)
- `gitlab` → GitLab (git@gitlab.com:audiserg/adventTask2.git)
