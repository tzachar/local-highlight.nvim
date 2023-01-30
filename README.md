# local-highlight.nvim

Using regexes and extmarks to highligh uses of word under the cursor.

# Performance

This plugin replaces `nvim-treesitter/nvim-treesitter-refactor`
highligh-definitions which performs poorly on large files.

# install

Using Lazy:

```lua
  {
      'tzachar/local-highlight.nvim',
      config = function()
        require('local-highlight').setup({
            file_types = {'python', 'cpp'}
        })
      end
  },
```

Make sure to specify file types to attach to.
