# local-highlight.nvim

Using regexes and extmarks to highlight uses of word under the cursor.
Keeps updates local to currently visible lines, thus enabling blazingly fast performance.
# In Action

![recording](https://user-images.githubusercontent.com/4946827/217664452-eb79ff0c-fa91-4d24-adcd-519faf4a2785.gif)

# Performance

This plugin replaces `nvim-treesitter/nvim-treesitter-refactor`
highlight-definitions which performs poorly on large files.

# install

Using Lazy:

```lua
  {
      'tzachar/local-highlight.nvim',
      config = function()
        require('local-highlight').setup()
      end
  },
```

Make sure to specify file types to attach to, or use the `attach` interface
documented below. 

# Why Another Highlight Plugin?

Multiple plugins to highlight the word under the cursor exist. However, none of them solved all of the following issues for me:
1. Performance (especially on large files)
2. Highlight mechanics: by using extmarks, the current format of each highlighted word remains the same (e.g., italics, treesitter highlights)

# Setup

You can setup local-highlight` as follows:`

```lua
require('local-highlight').setup({
    file_types = {'python', 'cpp'},
    hlgroup = 'TSDefinitionUsage',
    cw_hlgroup = nil,
})
```

## `hlgroup`

Specify the highlighting group to use.

By default, `local-highlight` will use the `LocalHighlight` highlighting
group, defined upon startup. You can use any other group you desire.

## `cw_hlgroup`

Specify the highlighting group to use for the word under the cursor. Defaults to
`nil`, which means "Do not apply any highlighting".

## `file_types`

The plugin works out of the box if you want to use `FileType`s to attach to
buffers. 

If you do not supply the `file_types` configuration option, `local-highlight` will
attach by default to all buffers using the `BufRead` autocommand event.

## API

If you want to directly attach the plugin to your buffers, you can use any
`autocommand` to attach an event to your liking. For
example, to attach to *any* buffer:

```lua
vim.api.nvim_create_autocmd('BufRead', {
  pattern = {'*.*'},
  callback = function(data)
    require('local-highlight').attach(data.buf)
  end
})
```

The plugin will take care not to reattach and to delete the autocommands when
the buffer is closed.

# User Commands

## LocalHighlightToggle

Toggle local highlighting for the current buffer.

## LocalHighlightOff

Turn local highlighting off for the current buffer.

## LocalHighlightOn

Turn local highlighting on for the current buffer.

## LocalHighlightStats

Echo timing information: total number of invocations and the average running
time in milliseconds.

# How the Plugin Works

`local-highlight` will attach to a buffer and register an autocommand for the
`CursorHold` event. Once the event fires, `local-highlight` will grab the word
under the cursor and will highlight all of the usages of the same word in the
visible lines of the buffer.

One implication of using `CursorHold` is that interactivity depends on
`updatetime`, which is 4000 by default. A good advice is to set it to something
more reasonable, like 500, to get good interactivity.
