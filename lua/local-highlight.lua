-- This module highlights reference usages and the corresponding
-- definition on cursor hold.

local api = vim.api
local vim_hl = (vim.hl or vim.highlight)


local function interpolate(start_color, end_color, position)
  -- Function to interpolate between two hex colors

  -- Input validation (optional but good practice)
  if type(start_color) ~= "string" or type(end_color) ~= "string" then
    error("start_color and end_color must be strings")
  end
  if type(position) ~= "number" then
    error("position must be a number")
  end
  if position < 0 or position > 1 then
    error("position must be between 0 and 1")
  end
  if start_color:len() ~= 6 or end_color:len() ~= 6 then
    error("start_color and end_color must be in format 'rrggbb'")
  end

  -- Helper function to convert hex color string to RGB components
  local function hex_to_rgb(hex_color)
    local r_hex = hex_color:sub(1, 2)
    local g_hex = hex_color:sub(3, 4)
    local b_hex = hex_color:sub(5, 6)
    return tonumber(r_hex, 16), tonumber(g_hex, 16), tonumber(b_hex, 16)
  end

  -- Helper function to convert RGB components to hex color string
  local function rgb_to_hex(r, g, b)
    return string.format("%02x%02x%02x", r, g, b)
  end

  -- Convert start and end colors to RGB components
  local start_r, start_g, start_b = hex_to_rgb(start_color)
  local end_r, end_g, end_b = hex_to_rgb(end_color)

  -- Interpolate each RGB component
  local interpolated_r = start_r + (end_r - start_r) * position
  local interpolated_g = start_g + (end_g - start_g) * position
  local interpolated_b = start_b + (end_b - start_b) * position

  -- Ensure RGB values are within the valid range (0-255)
  interpolated_r = math.floor(interpolated_r + 0.5) -- Round to nearest integer
  interpolated_g = math.floor(interpolated_g + 0.5)
  interpolated_b = math.floor(interpolated_b + 0.5)

  interpolated_r = math.max(0, math.min(255, interpolated_r))
  interpolated_g = math.max(0, math.min(255, interpolated_g))
  interpolated_b = math.max(0, math.min(255, interpolated_b))


  -- Convert interpolated RGB back to hex color string
  local interpolated_color = rgb_to_hex(interpolated_r, interpolated_g, interpolated_b)

  return interpolated_color
end

local function get_highlight(bufnr, row, col)
  local hl_groups = {}
  local function append(data, priority)
    table.insert(
      hl_groups,
      {
        data.hl_group_link or data.hl_group,
        priority
      }
    )

  end
  local items = vim.inspect_pos(
    bufnr,
    row,
    col,
    {
      extmarks = true,
      semantic_tokens = true,
      syntax = true,
      treesitter = true,
    }
  )
  if #items.treesitter > 0 then
    for _, capture in ipairs(items.treesitter) do
      append(capture, capture.metadata.priority or vim_hl.priorities.treesitter)
    end
  end
  if #items.semantic_tokens > 0 then
     for _, extmark in ipairs(items.semantic_tokens) do
       append(extmark.opts, extmark.opts.priority)
     end
  end
  if #items.syntax > 0 then
    for _, syn in ipairs(items.syntax) do
       append(syn, 0)
    end
  end

  if #items.extmarks > 0 then
    for _, extmark in ipairs(items.extmarks) do
      if extmark.opts.hl_group then
        append(extmark.opts, 0)
      end
    end
  end
  if #hl_groups > 0 then
    table.sort(hl_groups, function (a, b) return a[2] > b[2] end)
    for _, g in ipairs(hl_groups) do
      local x = vim.api.nvim_get_hl(
        0,
        {
          name = g[1],
          link = false,
          create = false,
        }
      )
      if x ~= nil and not vim.tbl_isempty(x) then
        if x.fg then
          x.fg = string.format("%06x", x.fg)  ---@diagnostic disable-line
        end
        if x.bg then
          x.bg = string.format("%06x", x.bg)  ---@diagnostic disable-line
        end
        return x
      end
    end
  end
  return nil -- No highlight group found at the cursor position
end

local M = {
  regexes = {},
  config = {
    file_types = nil,
    disable_file_types = nil,
    hlgroup = 'LocalHighlight',
    cw_hlgroup = nil,
    insert_mode = false,
    min_match_len = 1,
    max_match_len = math.huge,
    highlight_single_match = true,
    animate = {
      enabled = vim.fn.has("nvim-0.10") == 1 and require('snacks.animate'),
      char_by_char = true,
      easing = "linear",
      duration = {
        step = 10, -- ms per step
        total = 100, -- maximum duration
      },
    },
  },
  timing_info = {},
  usage_count = 0,
  debug_print_usage_every_time = false,
  last_cache = {},
  last_count = {},
}

local usage_namespace = api.nvim_create_namespace('highlight_usages_in_window')

local function all_matches(bufnr, regex, line)
  local ans = {}
  local offset = 0
  while true do
    local s, e = regex:match_line(bufnr, line, offset)
    if not s then
      return ans
    end
    table.insert(ans, s + offset)
    offset = offset + e
  end
end

function M.stats()
  local avg_time = 0
  for _, t in ipairs(M.timing_info) do
    avg_time = avg_time + t
  end
  return string.format(
    [[
Total Usage Count    : %d
Average Running Time : %f msec
  ]],
    M.usage_count,
    avg_time / #M.timing_info
  )
end

function M.regex(pattern)
  local ret = M.regexes[pattern]
  if ret ~= nil then
    return ret
  end
  ret = vim.regex(pattern)
  if #M.regexes > 1000 then
    table.remove(M.regexes, 1)
    table.insert(M.regexes, ret)
  end

  return ret
end

function M.highlight_usages(bufnr)
  local start_time = vim.fn.reltime()
  local cursor = api.nvim_win_get_cursor(0)
  local line = vim.fn.getline('.')
  if string.sub(line, cursor[2] + 1, cursor[2] + 1) == ' ' then
    M.clear_usage_highlights(bufnr)
    return
  end
  local curword, curword_start, curword_end = unpack(vim.fn.matchstrpos(line, [[\k*\%]] .. cursor[2] + 1 .. [[c\k*]]))
  if not curword or #curword < M.config.min_match_len or #curword > M.config.max_match_len then
    M.clear_usage_highlights(bufnr)
    return
  end
  local topline, botline = vim.fn.line('w0') - 1, vim.fn.line('w$')
  -- Don't calculate usages again if we are on the same word.
  if M.last_cache[bufnr] and curword == M.last_cache[bufnr].curword and topline == M.last_cache[bufnr].topline and botline == M.last_cache[bufnr].botline and cursor[1] == M.last_cache[bufnr].row and cursor[2] >= M.last_cache[bufnr].col_start and cursor[2] <= M.last_cache[bufnr].col_end and M.has_highlights(bufnr) then
    return
  else
    M.last_cache[bufnr] = {
      curword = curword,
      topline = topline,
      botline = botline,
      row = cursor[1],
      col_start = curword_start,
      col_end = curword_end,
    }
  end

  M.clear_usage_highlights(bufnr)

  -- dumb find all matches of the word
  -- matching whole word ('\<' and '\>')
  local cursor_range = { cursor[1] - 1, cursor[2] }
  local curpattern = string.format([[\V\<%s\>]], curword)
  local curpattern_len = #curword
  local status, regex = pcall(M.regex, curpattern)
  if not status then
    return
  end

  local args = {}
  for row = topline, botline - 1 do
    local matches = all_matches(bufnr, regex, row)
    for _, col in ipairs(matches) do
      if row ~= cursor_range[1] or cursor_range[2] < col or cursor_range[2] > col + curpattern_len then
        table.insert(args, {
          org_hl = get_highlight(bufnr, row, col),
          hl_args = {
            bufnr,
            usage_namespace,
            M.config.hlgroup,
            { row, col },
            { row, col + curpattern_len },
          }
        })
      elseif row == cursor_range[1] and cursor_range[2] >= col and cursor_range[2] <= col + curpattern_len and M.config.cw_hlgroup then
        table.insert(args, {
          org_hl = get_highlight(bufnr, row, col),
          hl_args = {
            bufnr,
            usage_namespace,
            M.config.cw_hlgroup,
            { row, col },
            { row, col + curpattern_len },
          }
        })
      end
    end
  end

  if M.config.highlight_single_match or #args > 1 then
    for i, arg in ipairs(args) do
      if M.config.animate and M.config.animate.enabled and require('snacks.animate').enabled({ buf = bufnr, name = "local_highlight" }) then
        require('snacks.animate')(
          0,
          100,
          function(value, ctx)  ---@diagnostic disable-line
            local bg = interpolate(
              (arg.org_hl and arg.org_hl.bg) or M.config.background,
              M.config.animate.bg,
              value / 100.
            )
            vim.api.nvim_set_hl(0, arg.hl_args[3], {
              bg = '#' .. bg,
              default = false,
            })
            local upto = curpattern_len
            if M.config.animate.char_by_char then
              upto = math.floor(value * curpattern_len / 100. + 0.5)
              dump(upto)
            end
            if M.config.animate.char_by_char or ctx.anim.opts.first_time then
              vim_hl.range(
                arg.hl_args[1],
                arg.hl_args[2],
                arg.hl_args[3],
                arg.hl_args[4],
                {arg.hl_args[4][1], arg.hl_args[4][2] + upto}
              )
              ctx.anim.opts.first_time = false  ---@diagnostic disable-line
            end
          end,
          vim.tbl_extend("keep", {
            int = true,
            id = "local_highlight_" .. bufnr .. "_" .. i,
            buf = bufnr,
            first_time = true,
          }, M.config.animate)
        )
      else
        vim_hl.range(unpack(arg.hl_args))
      end
      M.last_count[bufnr] = #args
    end
  end

  local time_since_start = vim.fn.reltimefloat(vim.fn.reltime(start_time)) * 1000
  if M.debug_print_usage_every_time then
    vim.api.nvim_echo({ { string.format('LH: %f', time_since_start) } }, false, {})
  end
  table.insert(M.timing_info, time_since_start)
  M.usage_count = M.usage_count + 1
end

function M.match_count(bufnr)
  if (bufnr or 0) == 0 then
    bufnr = vim.fn.bufnr()
  end
  return M.last_count[bufnr] or 0
end

function M.has_highlights(bufnr)
  return #api.nvim_buf_get_extmarks(bufnr, usage_namespace, 0, -1, {}) > 0
end

function M.clear_usage_highlights(bufnr)
  M.last_count[bufnr] = 0
  api.nvim_buf_clear_namespace(bufnr, usage_namespace, 0, -1)
end

function M.buf_au_group_name(bufnr)
  return string.format('Highlight_usages_in_window_%d', bufnr)
end

function M.is_attached(bufnr)
  local au_group_name = M.buf_au_group_name(bufnr)
  local status, aus = pcall(api.nvim_get_autocmds, { group = au_group_name })
  if status and #(aus or {}) > 0 then
    return true
  else
    return false
  end
end

function M.attach(bufnr)
  if M.is_attached(bufnr) then
    return
  end
  local au = api.nvim_create_augroup(M.buf_au_group_name(bufnr), { clear = true })
  local highlighter_args = {
    group = au,
    buffer = bufnr,
    callback = function()
      M.highlight_usages(bufnr)
    end,
  }
  api.nvim_create_autocmd({ 'CursorHold' }, highlighter_args)
  if M.config.insert_mode then
    api.nvim_create_autocmd({ 'CursorHoldI' }, highlighter_args)
  else
    api.nvim_create_autocmd({ 'InsertEnter' }, {
      group = au,
      buffer = bufnr,
      callback = function()
        M.clear_usage_highlights(bufnr)
      end,
    })
  end
  api.nvim_create_autocmd({ 'BufDelete' }, {
    group = au,
    buffer = bufnr,
    callback = function()
      M.clear_usage_highlights(bufnr)
      M.detach(bufnr)
    end,
  })
end

function M.detach(bufnr)
  M.clear_usage_highlights(bufnr)
  api.nvim_del_augroup_by_name(M.buf_au_group_name(bufnr))
  M.last_cache[bufnr] = nil
end

local function setup_highlight_group()
  vim.api.nvim_set_hl(0, 'LocalHighlight', {
    fg = '#dcd7ba',
    bg = '#2d4f67',
    default = true,
  })
end

function M.setup(config)
  setup_highlight_group()
  vim.api.nvim_create_autocmd('ColorScheme', {
    pattern = '*',
    callback = setup_highlight_group,
  })

  M.config = vim.tbl_deep_extend('keep', config or {}, M.config)
  local background = vim.api.nvim_get_hl(
    0,
    {
      create = false,
      name = 'Normal',
    }
  )
  if background ~= nil and not vim.tbl_isempty(background) and background.bg then
    M.config.background = string.format("%06x", background.bg)
  else
    M.config.background = '000000'
  end
  local animate_bg = vim.api.nvim_get_hl(
    0,
    {
      create = false,
      name = M.config.hlgroup,
    }
  )
  if animate_bg ~= nil and not vim.tbl_isempty(animate_bg) and animate_bg.bg and M.config.animate then
    M.config.animate.bg = string.format("%06x", animate_bg.bg)
  elseif M.config.animate then
    M.config.animate.bg = '000000'
  end
  if not M.config.animate then
    M.config.animate = { enabled = false }
  end
  local au = api.nvim_create_augroup('Highlight_usages_in_window', { clear = true })
  if M.config.file_types and #M.config.file_types > 0 then
    vim.api.nvim_create_autocmd('FileType', {
      group = au,
      pattern = M.config.file_types,
      callback = function(data)
        M.attach(data.buf)
      end,
    })
  elseif M.config.file_types == nil then
    vim.api.nvim_create_autocmd('BufRead', {
      group = au,
      pattern = '*.*',
      callback = function(data)
        if M.config.disable_file_types then
          if vim.tbl_contains(M.config.disable_file_types, vim.bo.filetype) then
            return
          end
        end
        M.attach(data.buf)
      end,
    })
  end

  --- add togglecommands
  vim.api.nvim_create_user_command('LocalHighlightOff', function()
    M.detach(vim.fn.bufnr('%'))
  end, { desc = 'Turn local-highligh.nvim off' })
  vim.api.nvim_create_user_command('LocalHighlightOn', function()
    M.attach(vim.fn.bufnr('%'))
  end, { desc = 'Turn local-highligh.nvim on' })
  vim.api.nvim_create_user_command('LocalHighlightToggle', function()
    local bufnr = vim.fn.bufnr('%')
    if M.is_attached(bufnr) then
      M.detach(bufnr)
    else
      M.attach(bufnr)
    end
  end, { desc = 'Toggle local-highligh.nvim' })

  vim.api.nvim_create_user_command('LocalHighlightStats', function()
    vim.api.nvim_echo({ { M.stats() } }, false, {})
  end, { force = true })
end

return M
