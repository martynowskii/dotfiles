-- ~/.config/nvim/lua/plugins/bufremove.lua
return {
    {
        "echasnovski/mini.bufremove",
        version = "*",
        keys = {
            {
                "<leader>w",
                function() require("mini.bufremove").delete(0, false) end,
                desc = "Закрыть буфер (вкладку)",
            },
            {
                "<leader>W",
                function() require("mini.bufremove").delete(0, true) end,
                desc = "Принудительно закрыть буфер",
            },
        },
    }
}
