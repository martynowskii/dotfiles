return {
    {
        "olimorris/onedarkpro.nvim",
        lazy = false,
        priority = 1000,
        config = function()
            local onedarkpro = require("onedarkpro")
            onedarkpro.setup({
                options = {
                    transparency = true,
                    terminal_colors = true,
                    highlight_inactive_windows = true,
                    cursorline = true,
                },
                styles = {
                    variables = "italic",
                    keywords = "italic",
                    parameters = "italic",
                },
            })
            -- vim.cmd("colorscheme onedark_dark")
            vim.cmd("colorscheme onedark")
        end,
    }
}
-- return {
--     {
--         "bluz71/vim-moonfly-colors",
--         name = "moonfly",
--         lazy = false,
--         priority = 1000,
--         config = function()
--             vim.opt.termguicolors = true
--             vim.g.moonflyItalics = true
--
--             vim.cmd("colorscheme moonfly")
--         end,
--     },
-- }

-- return {
--     {
--         "loctvl842/monokai-pro.nvim",
--         lazy = false,
--         priority = 1000,
--         config = function()
--             local monokai = require("monokai-pro")
--             monokai.setup({
--                 italics = true, -- Включаем курсив (для комментариев, ключевых слов и т.д.)
--             })
--             vim.cmd("colorscheme monokai-pro-classic")
--         end,
--     },
-- }
