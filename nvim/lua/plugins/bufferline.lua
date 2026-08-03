return {
    {
        "akinsho/bufferline.nvim",
        version = "*",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("bufferline").setup({
                options = {
                    mode = "buffers",
                    numbers = "none",
                    close_command = "bdelete! %d",
                    right_mouse_command = "bdelete! %d",
                    left_mouse_command  = "buffer %d",
                    indicator = {
                        style = "underline", -- подчеркивание активной вкладки
                    },
                    buffer_close_icon    = "󰅖",
                    modified_icon        = "●",
                    close_icon           = "",
                    left_trunc_marker    = "",
                    right_trunc_marker   = "",
                    diagnostics          = false,
                    separator_style      = "square",  -- slant / slope / thick / thin
                    always_show_bufferline = true,
                    -- Смещение для дерева файлов
                    offsets = {
                        {
                            filetype   = "NvimTree",
                            text       = "  File Explorer",
                            text_align = "left",
                            separator  = true,
                        },
                    },
                },
            })

            -- Переключение между буферами
            local map = vim.keymap.set
            local o = { noremap = true, silent = true }

            map("n", "<Tab>",   "<cmd>BufferLineCycleNext<CR>", o)
            map("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<CR>", o)

            -- Перейти к буферу по позиции (как Ctrl+1..9 в VSCode)
            for i = 1, 9 do
                map("n", "<leader>" .. i,
                    "<cmd>BufferLineGoToBuffer " .. i .. "<CR>", o)
            end
        end,
    },
}

