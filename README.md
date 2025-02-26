# local-highlight.nvim

Using regexes and `extmarks` to highlight uses of the word under the cursor.
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

In my initial search for a plugin of this kind, I found myself consistently frustrated. Nothing I encountered truly satisfied my need for both high performance and formatting options. This plugin, however, excels in the following:

* Exceptional Performance, even on large files.
* Highlight mechanics: by using `extmarks`, the current format of each highlighted word remains the same (e.g., italics, treesitter highlights)
* By being implemented programmatically in `lua`, this plugin can support
  animations.

# How the Plugin Works

`local-highlight` will attach to a buffer and register an autocommand for the
`CursorMoved` event. Once the event fires, and after `debounce_timeout`
milliseconds, `local-highlight` will grab the word
under the cursor and will highlight all of the usages of the same word in the
visible lines of the buffer.

# Setup

You can setup local-highlight `as follows:`

```lua
require('local-highlight').setup({
    file_types = {'python', 'cpp'}, -- If this is given only attach to this
    -- OR attach to every filetype except:
    disable_file_types = {'tex'},
    hlgroup = 'LocalHighlight',
    cw_hlgroup = nil,
    -- Whether to display highlights in INSERT mode or not
    insert_mode = false,
    min_match_len = 1,
    max_match_len = math.huge,
    highlight_single_match = true,
    animate = {
      enabled = true,
      char_by_char = true,
      easing = "linear",
      duration = {
        step = 10, -- ms per step
        total = 100, -- maximum duration
      },
    },
    debounce_timeout = 200,
})
```

## `hlgroup`

Specify the highlighting group to use.

By default, `local-highlight` will use the `LocalHighlight` highlight group, which it defines upon startup. If the group is already defined elsewhere in your config then it will not be overwritten. You can also use any other group you desire.

## `cw_hlgroup`

Specify the highlighting group to use for the word under the cursor. Defaults to
`nil`, which means "Do not apply any highlighting".

## `debounce_timeout`

The number of milliseconds to wait after a `CursorMoved` event fires to start
the highlighting process. The default is `200`, meaning that we will only start
highligting `200` milliseconds after the last `CursorMoved` event (last meaning
all other events were less than `200` milliseconds apart).

## `file_types` and `disable_file_types`

The plugin works out of the box if you want to use `FileType`s to attach to
buffers.

To control this behavior, you have the option of setting the following options:
`file_types`: `nil` by default, meaning attach to all file types. If set to a
table, should contain file types relevant to the `FileType` autocommand, and
will instruct the plugin to attach only to the specified fule types.
`disable_file_types`: `nil` by default, meaning no exceptions when attaching to
buffers. If set to a table, each fie type specified in the table will be skipped
when attaching to buffers.

If you set `file_types` to an empty table, `{}`, `local-highlight` will not
attach to any buffer on its own, and will leave all attach logic to the user.

## `insert_mode`

If set to `true`, will also work during insert mode.

## `min_match_len` and `max_match_len`

Set lower and upper limits on the length of the word being matched.

## `highlight_single_match`

Set to false to stop highlighting words that only appear once.

## `animate`

If you have [snacks.nvim](https://github.com/folke/snacks.nvim) installed and
are using at least `nvim-0.10`, `local-highligh` will use `Snacks.animate` by default. In this case, only the
**background** specified in `hlgroup` will be used.

To disable animation regardless of `snacks`, just set `enabled = false`. All
other arguments are the same as for `Snacks.animate`.

### `char_by_char`

By default, animation is done charachter by character. Set to `false` to animate
the entire word as a whole.

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

## Callbacks

### Match Count

You can request the current count of matches. This can be used, e.g., in a
status line plugin:

```lua
require('local-highlight').match_count(bufnr)
```

where `bufnr` is the buffer number the count is requested for or 0 for the
current buffer.

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
