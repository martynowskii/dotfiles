local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- Убрать trailing spaces при сохранении
autocmd("BufWritePre", {
    group = augroup("trim_whitespace", { clear = true }),
    pattern = "*",
    command = "%s/\\s\\+$//e",
})

-- Вернуться на последнюю позицию при открытии файла
autocmd("BufReadPost", {
    group = augroup("last_position", { clear = true }),
    callback = function()
        local mark = vim.api.nvim_buf_get_mark(0, '"')
        local lcount = vim.api.nvim_buf_line_count(0)
        if mark[1] > 0 and mark[1] <= lcount then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
        end
    end,
})

-- Мигание при копировании
autocmd("TextYankPost", {
    group = augroup("highlight_yank", { clear = true }),
    callback = function()
        vim.highlight.on_yank({ timeout = 200 })
    end,
})

-- Терминал: убрать нумерацию и сразу в режим ввода
autocmd("TermOpen", {
    group = augroup("terminal_settings", { clear = true }),
    callback = function()
        vim.opt_local.number = false
        vim.opt_local.relativenumber = false
        vim.opt_local.signcolumn = "no"
        -- vim.cmd("startinsert")
    end,
})

-- Открыть терминал при запуске без файла
autocmd("VimEnter", {
    group = augroup("startup_terminal", { clear = true }),
    once = true,
    callback = function()
        vim.schedule(function()
            -- vim.cmd("terminal")   -- терминал в главном окне
            -- vim.cmd("NvimTreeOpen")   -- дерево слева
            -- vim.cmd("ClaudeCode")     -- клод код
        end)
    end,
})

-- Добавить автоперенос для списка форматов
vim.api.nvim_create_autocmd("FileType", {
    group = augroup("TextWrap", {clear = true}),
    pattern = {
        "latex",
        "log",
        "markdown",
        "plaintex",
        "text",
        "tex",
    },
    callback = function()
        vim.opt_local.wrap = true
        vim.opt_local.linebreak = true
        vim.opt_local.breakindent = true
        vim.opt_local.showbreak = "    "
    end,
})
