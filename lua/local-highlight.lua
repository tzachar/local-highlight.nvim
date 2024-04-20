-- This module highlights reference usages and the corresponding
-- definition on cursor hold.

local api = vim.api

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
          bufnr,
          usage_namespace,
          M.config.hlgroup,
          { row, col },
          { row, col + curpattern_len },
        })
      elseif row == cursor_range[1] and cursor_range[2] >= col and cursor_range[2] <= col + curpattern_len and M.config.cw_hlgroup then
        table.insert(args, {
          bufnr,
          usage_namespace,
          M.config.cw_hlgroup,
          { row, col },
          { row, col + curpattern_len },
        })
      end
    end
  end

  if M.config.highlight_single_match or #args > 1 then
    for _, arg in ipairs(args) do
      vim.highlight.range(unpack(arg))
    end
    M.last_count[bufnr] = #args
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

function M.setup(config)
  vim.api.nvim_set_hl(0, 'LocalHighlight', {
    fg = '#dcd7ba',
    bg = '#2d4f67',
    default = true,
  })

  M.config = vim.tbl_deep_extend('keep', config or {}, M.config)
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
