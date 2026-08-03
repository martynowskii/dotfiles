-- lua/plugins/treesitter.lua
return {
    "nvim-treesitter/nvim-treesitter",
    -- Явно указываем использовать старую стабильную ветку
    branch = "master",
    build = ":TSUpdate",
    -- Плагин не поддерживает ленивую загрузку
    lazy = false,
    config = function()
        require("nvim-treesitter.configs").setup({
            -- Список языков, для которых нужно установить парсеры
            ensure_installed = {
                "bash", "cpp", "go", "json", "lua", "markdown",
                "python", "vim", "vimdoc", "yaml",
            },
            -- Автоматически устанавливать парсеры для новых типов файлов
            auto_install = true,
            -- Модуль подсветки синтаксиса
            highlight = {
                enable = true,
            },
            -- Модуль автоматических отступов (очень удобно)
            indent = {
                enable = true,
            },
            -- Другие модули можно включить по желанию
            -- incremental_selection = { enable = true },
            -- textobjects = { enable = true },
        })
    end,
}
