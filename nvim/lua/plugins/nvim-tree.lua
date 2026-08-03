return {
    {
        "nvim-tree/nvim-tree.lua",
        version = "*",
        lazy = false,
        dependencies = { "nvim-tree/nvim-web-devicons" },
        keys = {
            { "<leader>e",  "<cmd>NvimTreeToggle<CR>",   desc = "Toggle file tree" },
            { "<leader>ef", "<cmd>NvimTreeFocus<CR>",    desc = "Focus file tree" },
            { "<leader>er", "<cmd>NvimTreeRefresh<CR>",  desc = "Refresh file tree" },
        },
        config = function()
            -- Отключаем встроенный netrw
            vim.g.loaded_netrw = 1
            vim.g.loaded_netrwPlugin = 1

            require("nvim-tree").setup({
                sort = { sorter = "case_sensitive" },
                view = {
                    width = 42,
                    side = "left",
                },
                renderer = {
                    group_empty = true,
                    highlight_git = true,
                    icons = {
                        show = {
                            file = true,
                            folder = true,
                            folder_arrow = true,
                            git = true,
                        },
                    },
                },
                filters = {
                    dotfiles = false,           -- показывать dotfiles
                    custom = { "^.git$" },      -- скрыть папку .git
                },
                git = { enable = true },
                actions = {
                    open_file = {
                        quit_on_open = false,   -- не закрывать дерево при открытии файла
                        window_picker = { enable = true },
                    },
                },
                -- Горячие клавиши внутри дерева
                -- a - создать файл/папку
                -- d - удалить
                -- r - переименовать
                -- c - копировать
                -- x - вырезать
                -- p - вставить
                -- Enter / o - открыть
                -- I - показать скрытые файлы
            })
        end,
    },
}

