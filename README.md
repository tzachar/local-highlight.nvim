# local-highlight.nvim

Using a combination of treesitter and regexes to highligh uses of word under the
cursor.

# Performance

This plugin replaces `nvim-treesitter/nvim-treesitter-refactor`
highligh-definitions which performs poorly on large files.

# install

Using Lazy:
```lua
  {
      'tzachar/local-highlight.nvim',
      dependencies = 'nvim-treesitter/nvim-treesitter',
      config = function()
        require('nvim-treesitter.configs').setup({
          local_highlight = {
            enable = true,
          },
        })
      end
  },
```
