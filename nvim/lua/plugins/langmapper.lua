return {
    "Wansmer/langmapper.nvim",
    lazy = false,
    priority = 1000,
    config = function()
        require("langmapper").setup({})
    end,
}
