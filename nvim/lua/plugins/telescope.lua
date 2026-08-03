
return {
    {
        "nvim-telescope/telescope.nvim",
        dependencies = {
            "nvim-lua/plenary.nvim",
            {
                "nvim-telescope/telescope-fzf-native.nvim",
                build = "make",
                cond = function()
                    return vim.fn.executable("make") == 1
                end,
            },
        },
        keys = {
            { "<leader>ff", "<cmd>Telescope find_files<CR>",                desc = "Find files" },
            { "<leader>fg", "<cmd>Telescope live_grep<CR>",                 desc = "Live grep" },
            { "<leader>fb", "<cmd>Telescope buffers<CR>",                   desc = "Buffers" },
            { "<leader>fr", "<cmd>Telescope oldfiles<CR>",                  desc = "Recent files" },
            { "<leader>fs", "<cmd>Telescope grep_string<CR>",               desc = "Word under cursor" },
            { "<leader>fh", "<cmd>Telescope help_tags<CR>",                 desc = "Help tags" },
            { "<leader>f",  "<cmd>Telescope current_buffer_fuzzy_find<CR>", desc = "Search in file" },
        },
        config = function()
            local telescope = require("telescope")
            local actions = require("telescope.actions")

            telescope.setup({
                defaults = {
                    path_display = { "smart" },

                    -- Вот это меняет общую компоновку
                    layout_strategy = "vertical",
                    sorting_strategy = "ascending",
                    layout_config = {
                        prompt_position = "top",
                        vertical = {
                            width = 0.70,
                            height = 0.95,
                            preview_height = 0.55,
                            mirror = false,
                        },
                    },

                    mappings = {
                        i = {
                            ["<C-j>"] = actions.move_selection_next,
                            ["<C-k>"] = actions.move_selection_previous,
                            ["<C-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
                            ["<Esc>"] = actions.close,
                        },
                    },
                },

                pickers = {
                    find_files = {
                        hidden = true,
                    },
                },
            })

            pcall(telescope.load_extension, "fzf")
        end,
    },
}

