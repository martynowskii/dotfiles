-- Leader ОБЯЗАТЕЛЬНО до загрузки плагинов
vim.g.mapleader = "\\"

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({
        "git", "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- Загружаем базовые настройки
require("config.options")
require("config.keymaps")
require("config.autocmds")

-- Загружаем все файлы из lua/plugins/ автоматически
require("lazy").setup("plugins", {
    checker = { enabled = false },        -- не проверять обновления автоматически
    change_detection = { notify = false },
    performance = {
        rtp = {
            -- отключаем ненужные встроенные плагины
            disabled_plugins = {
                "gzip", "matchit", "matchparen",
                "netrwplugin", "tarplugin",
                "tohtml", "tutor", "zipplugin",
            },
        },
    },
})

-- langmapper: перевести заданные маппинги под кириллицу и пропатчить чтение
-- маппингов (для which-key). После загрузки всех плагинов и установки биндингов.
vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    callback = function()
        local langmapper = require("langmapper")
        langmapper.automapping({ global = true, buffer = true })
        langmapper.hack_get_keymap()
    end,
})
