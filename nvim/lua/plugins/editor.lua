return {
    -- Автозакрытие скобок и кавычек
    {
        "windwp/nvim-autopairs",
        event = "InsertEnter",
        opts = {
            check_ts = true,    -- использовать treesitter
        },
    },

    -- Комментирование (gcc - строка, gc - выделение)
    {
        "numToStr/Comment.nvim",
        main = "Comment",
        keys = {
            { "gc", mode = { "n", "v" } },
            { "gb", mode = { "n", "v" } },
        },
        opts = {},
    },

    -- Направляющие линии отступов (как в VSCode)
    {
        "lukas-reineke/indent-blankline.nvim",
        main = "ibl",
        event = { "BufReadPost", "BufNewFile" },
        opts = {
            indent = {
                char = "│",
                tab_char = "│",
            },
            scope = { enabled = true },
            exclude = {
                filetypes = { "NvimTree", "lazy", "help", "terminal" },
            },
        },
    },
}

