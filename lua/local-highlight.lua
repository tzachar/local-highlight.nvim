-- This module highlights reference usages and the corresponding
-- definition on cursor hold.

local api = vim.api

local M = {
  regexes = {
    cache = {},
    order = {},
  },
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
      enabled = true,
      easing = 'linear',
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
  debounce_timeout = 200,
  debounce_timer = nil,
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
  local ret = M.regexes.cache[pattern]
  if ret ~= nil then
    return ret
  end
  ret = vim.regex(pattern)
  if #M.regexes.order > 1000 then
    local last = table.remove(M.regexes.order, 1)
    M.regexes.cache[last] = nil
  end
  M.regexes.cache[pattern] = ret
  table.insert(M.regexes.order, ret)

  return ret
end

function M.highlight_usages(bufnr)
  local start_time = vim.fn.reltime()
  local cursor = api.nvim_win_get_cursor(0)
  local line = vim.fn.getline('.')
  if string.sub(line, cursor[2] + 1, cursor[2] + 1) == ' ' then
    M.clear_usage_highlights(bufnr)
    M.last_cache[bufnr] = nil
    return
  end
  local curword, curword_start, curword_end = unpack(vim.fn.matchstrpos(line, [[\k*\%]] .. cursor[2] + 1 .. [[c\k*]]))
  if not curword or #curword < M.config.min_match_len or #curword > M.config.max_match_len then
    M.clear_usage_highlights(bufnr)
    M.last_cache[bufnr] = nil
    return
  end
  local topline, botline = vim.fn.line('w0') - 1, vim.fn.line('w$')
  -- Don't calculate usages again if we are on the same word.
  local prev_cache = M.last_cache[bufnr]
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
      matches = {}
    }
    if prev_cache and curword ~= prev_cache.curword then
      prev_cache = nil
    end
  end

  local current_cache =  M.last_cache[bufnr]

  -- dumb find all matches of the word
  -- matching whole word ('\<' and '\>')
  local cursor_range = { cursor[1] - 1, cursor[2] }
  local curpattern = string.format([[\V\<%s\>]], curword)
  local curpattern_len = #curword
  local status, regex = pcall(M.regex, curpattern)
  if not status then
    return
  end

  -- if this is a new word, remove all previous highlights
  if prev_cache == nil then
    M.clear_usage_highlights(bufnr)
  end

  local total_matches = 0
  local to_phase_out = {}
  local to_phase_in = {}
  for row = topline, botline - 1 do
    local matches = all_matches(bufnr, regex, row)
    for _, col in ipairs(matches) do
      total_matches = total_matches + 1
      local hash = row .. '_' .. col
      local is_curword = (row == cursor_range[1] and cursor_range[2] >= col and cursor_range[2] <= col + curpattern_len)
      local hl_group = M.config.hlgroup
      if is_curword then
        hl_group = M.config.cw_hlgroup
      end
      local id = (prev_cache and prev_cache.matches[hash] and prev_cache.matches[hash].id) or api.nvim_buf_set_extmark(
        bufnr,
        usage_namespace,
        row,
        col,
        {
          end_row = row,
          end_col = col + 1,
          hl_group = hl_group,
          priority = 200,
          strict = false,
        }
      )
      current_cache.matches[hash] = {
        id = id,
        len = 0,
        row = row,
        col = col,
        hl_group = hl_group,
        is_curword = is_curword
      }
      if is_curword and prev_cache and M.config.cw_hlgroup == nil then
        to_phase_out[hash] = true
      elseif prev_cache
        and prev_cache.matches[hash]
        and prev_cache.matches[hash].is_curword then
        to_phase_in[hash] = true
      elseif prev_cache and prev_cache.matches[hash] then
        -- skip
      else
      -- and all others which are new
        to_phase_in[hash] = true
      end
    end
  end

  if not M.config.highlight_single_match and total_matches <= 1 then
    return
  end

  if M.config.animate
    and M.config.animate.enabled
    and require('snacks.animate').enabled({ buf = bufnr, name = 'local_highlight' })
    then
      require('snacks.animate')(
        0,
        100,
        function(value, ctx) ---@diagnostic disable-line
          local upto = curpattern_len
          upto = math.floor(value * curpattern_len / 100. + 0.5)
          upto = math.max(1, upto)
          for hash, arg in pairs(current_cache.matches) do
            if to_phase_in[hash] then
              api.nvim_buf_set_extmark(
                bufnr,
                usage_namespace,
                arg.row,
                arg.col,
                {
                  id = arg.id,
                  end_row = arg.row,
                  end_col = arg.col + upto,
                  hl_group = arg.hl_group,
                  strict = false,
                }
              )
            elseif to_phase_out[hash] then
              if curpattern_len - upto <= 1 then
                api.nvim_buf_del_extmark(bufnr, usage_namespace, arg.id)
              else
                api.nvim_buf_set_extmark(
                  bufnr,
                  usage_namespace,
                  arg.row,
                  arg.col,
                  {
                    id = arg.id,
                    end_row = arg.row,
                    end_col = arg.col + curpattern_len - upto,
                    hl_group = arg.hl_group,
                    strict = false,
                  }
                )
              end
            end
          end
        end,
        vim.tbl_extend('keep', {
          int = true,
          id = 'local_highlight_' .. bufnr,
          buf = bufnr,
          duration = {
            step = M.config.animate.duration.step,
            total = math.min(M.config.animate.duration.total, curpattern_len * M.config.animate.duration.step),
          },
        }, M.config.animate)
      )
    else
      for _, arg in pairs(current_cache.matches) do
        api.nvim_buf_set_extmark(
          bufnr,
          usage_namespace,
          arg.row,
          arg.col,
          {
            id = arg.id,
            end_row = arg.row,
            end_col = arg.col + curpattern_len,
            hl_group = arg.hl_group,
            strict = false,
          }
        )
      end
    end
  M.last_count[bufnr] = #current_cache

  local time_since_start = vim.fn.reltimefloat(vim.fn.reltime(start_time)) * 1000
  if M.debug_print_usage_every_time then
    api.nvim_echo({ { string.format('LH: %f', time_since_start) } }, false, {})
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
      if M.debounce_timer then
        M.debounce_timer:stop()
        M.debounce_timer:close()
      end
      M.debounce_timer = (vim.uv or vim.loop).new_timer()
      M.debounce_timer:start(M.debounce_timeout, 0, function()
        vim.schedule(function()
          M.highlight_usages(bufnr)
        end)
      end)
    end,
  }
  api.nvim_create_autocmd({ 'CursorMoved', 'WinScrolled' }, highlighter_args)
  if M.config.insert_mode then
    api.nvim_create_autocmd({ 'CursorMovedI' }, highlighter_args)
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
  api.nvim_set_hl(0, 'LocalHighlight', {
    fg = '#dcd7ba',
    bg = '#2d4f67',
    default = true,
  })
end

function M.setup(config)
  setup_highlight_group()
  api.nvim_create_autocmd('ColorScheme', {
    pattern = '*',
    callback = setup_highlight_group,
  })

  M.config = vim.tbl_deep_extend('keep', config or {}, M.config)
  local background = api.nvim_get_hl(0, {
    create = false,
    name = 'Normal',
  })
  if background ~= nil and not vim.tbl_isempty(background) and background.bg then
    M.config.background = string.format('%06x', background.bg)
  else
    M.config.background = '000000'
  end
  local animate_bg = api.nvim_get_hl(0, {
    create = false,
    name = M.config.hlgroup,
  })
  if animate_bg ~= nil and not vim.tbl_isempty(animate_bg) and animate_bg.bg and M.config.animate then
    M.config.animate.bg = string.format('%06x', animate_bg.bg)
  elseif M.config.animate then
    M.config.animate.bg = '000000'
  end

  -- check if we can use animation
  if M.config.animate and M.config.animate.enabled then
    local err = {}
    if not vim.fn.has('nvim-0.10') == 1 then
      table.insert(err, 'local-highligh.nvim only supports animation on nvim-0.10 onwards')
    end

    if not pcall(require, 'snacks.animate') then
      table.insert(err, 'local-highligh.nvim only supports animation if snacks.nvim is installed')
    end
    if not vim.tbl_isempty(err) then
      M.config.animate = nil
      vim.notify(table.concat(err, '\n'), vim.log.levels.ERROR)
    end
  end

  if not M.config.animate then
    M.config.animate = { enabled = false }
  end
  local au = api.nvim_create_augroup('Highlight_usages_in_window', { clear = true })
  if M.config.file_types and #M.config.file_types > 0 then
    api.nvim_create_autocmd('FileType', {
      group = au,
      pattern = M.config.file_types,
      callback = function(data)
        M.attach(data.buf)
      end,
    })
  elseif M.config.file_types == nil then
    api.nvim_create_autocmd('BufRead', {
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
  api.nvim_create_user_command('LocalHighlightOff', function()
    M.detach(vim.fn.bufnr('%'))
  end, { desc = 'Turn local-highligh.nvim off' })
  api.nvim_create_user_command('LocalHighlightOn', function()
    M.attach(vim.fn.bufnr('%'))
  end, { desc = 'Turn local-highligh.nvim on' })
  api.nvim_create_user_command('LocalHighlightToggle', function()
    local bufnr = vim.fn.bufnr('%')
    if M.is_attached(bufnr) then
      M.detach(bufnr)
    else
      M.attach(bufnr)
    end
  end, { desc = 'Toggle local-highligh.nvim' })

  api.nvim_create_user_command('LocalHighlightStats', function()
    api.nvim_echo({ { M.stats() } }, false, {})
  end, { force = true })
end

return M
