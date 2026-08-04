local opt = vim.opt

-- Нумерация строк
opt.number = true
opt.relativenumber = true

-- Табы и отступы
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true

-- Внешний вид
opt.wrap = false
opt.termguicolors = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.signcolumn = "yes"
opt.cursorline = true
opt.colorcolumn = "100"
opt.pumheight = 10          -- высота popup-меню
opt.showmode = false        -- режим отображает lualine
opt.laststatus = 3          -- единая статусная строка (нужно для lualine)
opt.list = true
opt.listchars = {
    space = "·",
    tab = "→ ",
}

-- Поиск
opt.hlsearch = true
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true        -- учитывать регистр если есть заглавные

-- Файлы
opt.swapfile = false
opt.backup = false
opt.undofile = true
opt.undodir = vim.fn.stdpath("data") .. "/undodir"
opt.fileencoding = "utf-8"

-- Производительность
opt.updatetime = 250
opt.timeoutlen = 500

-- Буфер обмена
opt.clipboard = "unnamedplus"

-- На удалённой VM нет X-сервера, а установленный xclip падает без DISPLAY.
-- Шлём yank в системный буфер через OSC 52 — терминал (iTerm2, в т.ч. сквозь tmux)
-- сам кладёт текст в буфер обмена Mac.
local osc52 = require("vim.ui.clipboard.osc52")

-- Обратное направление (OSC 52 read) терминалы не поддерживают из соображений
-- безопасности, и с unnamedplus каждый `p` вис бы на 10 секунд в ожидании ответа.
-- Читаем из безымянного регистра; текст, скопированный на маке, вставляем Cmd+V.
local function paste_from_unnamed()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
end

vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste_from_unnamed, ["*"] = paste_from_unnamed },
}

-- Мышь
opt.mouse = "a"

-- Сплиты
opt.splitright = true
opt.splitbelow = true

-- Автодополнение
opt.completeopt = { "menuone", "noselect" }

-- Раскладка: команды Normal/Visual работают и на кириллице (ЙЦУКЕН)
local function escape(str)
    return vim.fn.escape(str, [[;,."|\]])
end

local en = [[`qwertyuiop[]asdfghjkl;'zxcvbnm]]
local ru = [[ёйцукенгшщзхъфывапролджэячсмить]]
local en_shift = [[~QWERTYUIOP{}ASDFGHJKL:"ZXCVBNM<>]]
local ru_shift = [[ËЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ]]

vim.opt.langmap = vim.fn.join({
    escape(ru_shift) .. ";" .. escape(en_shift),
    escape(ru) .. ";" .. escape(en),
}, ",")

