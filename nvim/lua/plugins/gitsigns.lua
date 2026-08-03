local uv = vim.uv or vim.loop
local gitsigns_dir = "/home/martynovsky/arcadia/contrib/tier1/gitsigns.arc.nvim"

local spec

if uv.fs_stat(gitsigns_dir) then
    spec = {
        dir = gitsigns_dir,
        name = "gitsigns.nvim",
    }
    print("arc is used")
else
    spec = {
        "lewis6991/gitsigns.nvim",
    }
end

spec.dependencies = { "nvim-lua/plenary.nvim" }
spec.config = function()
    event = { "BufReadPre", "BufNewFile" },
    require("gitsigns").setup({
        signcolumn = true,  -- Показывать полоску слева
        current_line_blame = false, -- Можно включить (true), чтобы показывать кто написал строку (git blame)
    })
end

return { spec }
