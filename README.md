# dotfiles

### 1. Клонировать репозиторий

```bash
git clone git@github.com:martynowskii/dotfiles.git ~/dotfiles
```

Используется SSH — доступ должен быть уже настроен через `~/.ssh/config`.

### 2. Создать `~/.config`, если его ещё нет

```bash
mkdir -p ~/.config
```

### 3. Слинковать nvim

```bash
ln -s ~/dotfiles/nvim ~/.config/nvim
```

Если там уже что-то есть — сначала уберите с дороги:

```bash
mv ~/.config/nvim ~/.config/nvim.bak 2>/dev/null
ln -s ~/dotfiles/nvim ~/.config/nvim
```

### 4. Слинковать zsh

Зависит от того, как организован конфиг в репозитории.

**Вариант А — обычный `.zshrc` (не XDG-стиль):**

```bash
ln -s ~/dotfiles/zsh/.zshrc ~/.zshrc
```

**Вариант Б — XDG-подход (`ZDOTDIR`):**

```bash
ln -s ~/dotfiles/zsh ~/.config/zsh
echo 'export ZDOTDIR="$HOME/.config/zsh"' >> ~/.zshenv
```

### 5. Проверить результат

```bash
ls -la ~/.config
```

Симлинки должны указывать на `~/dotfiles/...`.
