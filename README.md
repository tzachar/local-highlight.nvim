# local-highlight.nvim

Using regexes and extmarks to highligh uses of word under the cursor.
Keeps updates local to currently visible lines, thus enabling blazingly fast performance.
# In Action

![recording](https://user-images.githubusercontent.com/4946827/217664452-eb79ff0c-fa91-4d24-adcd-519faf4a2785.gif)

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
            file_types = {'python', 'cpp'},
            hlgroup = 'TSDefinitionUsage',
        })
      end
  },
```

Make sure to specify file types to attach to, or use the `attach` interface
documented below. 

By default, `local-highlight` will also use the `TSDefinitionUsage` highlighting
group.

# Why Another Highlight plugin?

Multiple plugins to highlight the word under the cursor exist. However, none of them solved all of the following issues for me:
1. Performance (especially on large files)
2. Highlight mechanics: by using extmarks, the current format of each highlighted word remains the same (e.g., italics, treesitter highlights)

# Setup

The plugin works out of the box if you want to use `FileType`s to attach to
buffers. However, you can use any `autocommand` to attach an event to your liking. For
example, to attach to *any* buffer:

```lua
vim.api.nvim_create_autocmd('BufEnter', {
  pattern = {'*.*'},
  callback = function(data)
    require('local-highlight').attach(data.buf)
  end
})
```

The plugin will take care not to reattach and to delete the autocommands when
the buffer is closed.
