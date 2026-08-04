return {
    "RRethy/vim-illuminate",
    -- tag = "v0.3",
    event = "VeryLazy",
    config = function()
        require("illuminate").configure({
            providers = { "lsp", "treesitter", "regex" },
            under_cursor = true,
            filetypes_denylist = {
                "TelescopePrompt",
                "NvimTree",
                "lazy",
            },
        })

        vim.api.nvim_set_hl(0, "IlluminatedWordText",  { underline = true })
        vim.api.nvim_set_hl(0, "IlluminatedWordRead",  { underline = true })
        vim.api.nvim_set_hl(0, "IlluminatedWordWrite", { underline = true })
    end,
}
