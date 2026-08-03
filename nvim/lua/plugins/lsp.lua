return {
    -- Менеджер внешних инструментов
    {"mason-org/mason.nvim", opts = {}},

    -- Установка LSP-серверов через Mason
    {
        "mason-org/mason-lspconfig.nvim",
        dependencies = {
            "mason-org/mason.nvim",
            "neovim/nvim-lspconfig",
            "hrsh7th/cmp-nvim-lsp",
        },
        config = function()
            require("mason-lspconfig").setup({
                ensure_installed = {
                    "pyright",
                    "yamlls",
                    "clangd",
                },
                automatic_enable = false,
            })

            local capabilities = vim.lsp.protocol.make_client_capabilities()
            capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)

            vim.lsp.config("pyright", {
                capabilities = capabilities,
            })
            vim.lsp.enable("pyright")

            vim.lsp.config("yamlls", {
                capabilities = capabilities,
            })
            vim.lsp.enable("yamlls")

            vim.lsp.config("clangd", {
                capabilities = capabilities,

                cmd = {
                    "clangd",
                    "--background-index",
                    "--clang-tidy",
                    "--completion-style=detailed",
                    "--header-insertion=iwyu",
                },
            })
            vim.lsp.enable("clangd")
        end,
    },

    -- Коллекция готовых LSP-конфигов
    {
        "neovim/nvim-lspconfig",
    },
}
