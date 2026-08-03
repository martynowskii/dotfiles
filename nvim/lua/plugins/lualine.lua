return {
    {
        "nvim-lualine/lualine.nvim",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("lualine").setup({
                options = {
                    globalstatus = true,
                    component_separators = { left = "", right = "" },
                    section_separators   = { left = "", right = "" },
                    disabled_filetypes = {
                        statusline = { "NvimTree", "lazy" },
                    },
                },
                sections = {
                    lualine_a = { "mode" },
                    lualine_b = { "branch", "diff", "diagnostics" },
                    lualine_c = {
                        {
                            "filename",
                            path = 1,       -- показывать относительный путь
                            symbols = {
                                modified  = "  ",
                                readonly  = "  ",
                                unnamed   = "  ",
                            },
                        }
                    },
                    lualine_x = { "encoding", "fileformat", "filetype" },
                    lualine_y = { "progress" },
                    lualine_z = { "location" },
                },
                extensions = { "nvim-tree", "lazy", "quickfix" },
            })
        end,
    },
}

