return {
  {
    "lifepillar/vim-solarized8",
    "frankier/neovim-colors-solarized-truecolor-only",
    "rose-pine/neovim",
    {
      "neanias/everforest-nvim",
      config = function()
        local everforest = require("everforest")
        everforest.setup({
          background = "medium",
          style = "storm",
        })
        everforest.load()
      end,
    },
  },

  -- Configure LazyVim to load gruvbox
  {
    "LazyVim/LazyVim",
    opts = {
      -- colorscheme = "solarized8_flat",
      --colorscheme = "solarized",
      colorscheme = "everforest",
    },
  },
}
