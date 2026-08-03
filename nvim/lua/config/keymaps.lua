local map = vim.keymap.set
local opts = { noremap = true, silent = true }

-- Использовать <leader><Tab> вместо <Esc>
map({"i", "v"}, "<leader><Tab>", "<Esc>")

-- Навигация между окнами (Ctrl + hjkl)
map("n", "<C-h>", "<C-w>h", opts)
map("n", "<C-j>", "<C-w>j", opts)
map("n", "<C-k>", "<C-w>k", opts)
map("n", "<C-l>", "<C-w>l", opts)

map("n", "<M-Up>", "<cmd>resize +2<CR>", opts)
map("n", "<M-Down>", "<cmd>resize -2<CR>", opts)
map("n", "<M-Left>", "<cmd>vertical resize -2<CR>", opts)
map("n", "<M-Right>", "<cmd>vertical resize +2<CR>", opts)

-- Буферы
map("n", "<Tab>", "<cmd>bnext<CR>", opts)
map("n", "<S-Tab>", "<cmd>bprev<CR>", opts)

-- Терминал
map("n", "<leader>t", "<cmd>tabnew | terminal<CR>", opts)
map("t", "<Esc>", "<C-\\><C-n>", opts)

-- Редактирование
map("n", "<leader>s", "<cmd>w<CR>", opts)  -- сохранить
map("n", "<leader>S", "<cmd>w!<CR>", opts)  -- принудительно сохранить
map({"i", "v"}, "<leader>s", "<Esc>:w<CR>", opts)  -- перейти в нормальный режим и сохранить
map({"i", "v"}, "<leader>S", "<Esc>:w!<CR>", opts)  -- перейти в нормальный режим и принудительно сохранить
map("n", "<leader>a", "ggVG", opts)  -- выделить всё
map("n", "<leader>?", vim.diagnostic.open_float, opts)  -- чтение диагностики под курсором

-- Индентация (сохраняет выделение)
map("v", "<", "<gv", opts)
map("v", ">", ">gv", opts)

-- Поиск и замена слова под курсором
map("n", "<leader>r", "<cmd>%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left><CR>", opts)

-- Выключить подсветку результатов поиска
map("n", "<Esc>", "<cmd>nohl<CR>", opts)

-- Переключить claude code
map("n", "<leader>cc", "<cmd>ClaudeCode<CR>", opts)
