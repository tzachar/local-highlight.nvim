-- This module highlights reference usages and the corresponding
-- definition on cursor hold.

local api = vim.api

local M = {
  regexes = {},
  config = {
    file_types = {},
    hlgroup = 'LocalHighlight',
    cw_hlgroup = nil,
  },
}

local usage_namespace = api.nvim_create_namespace("highlight_usages_in_window")
local last_cache = {}

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

function M.regex(pattern)
  local ret = M.regexes[pattern]
  if ret ~= nil then
    return ret
  end
  ret = vim.regex(pattern)
  if #(M.regexes) > 1000 then
    table.remove(M.regexes, 1)
    table.insert(M.regexes, ret)
  end

  return ret
end

function M.highlight_usages(bufnr)
  local cursor = api.nvim_win_get_cursor(0)
  local line = vim.fn.getline('.')
  if string.sub(line, cursor[2] + 1, cursor[2] + 1) == ' ' then
    M.clear_usage_highlights(bufnr)
    return
  end
  local curword, curword_start, curword_end = unpack(
    vim.fn.matchstrpos(
      line,
      [[\k*\%]] .. cursor[2] + 1 .. [[c\k*]]
    )
  )
  if not curword or #curword == 0 then
    M.clear_usage_highlights(bufnr)
    return
  end
  local topline, botline = vim.fn.line('w0') - 1, vim.fn.line('w$')
  -- Don't calculate usages again if we are on the same word.
  if (last_cache[bufnr]
      and curword == last_cache[bufnr].curword
      and topline == last_cache[bufnr].topline
      and botline == last_cache[bufnr].botline
      and cursor[1] == last_cache[bufnr].row
      and cursor[2] >= last_cache[bufnr].col_start
      and cursor[2] <= last_cache[bufnr].col_end
      and M.has_highlights(bufnr)) then
    return
  else
      last_cache[bufnr] = {
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

  -- local start = vim.fn.reltime()
  for row=topline, botline - 1 do
    local matches = all_matches(bufnr, regex, row)
    if matches and #matches > 0 then
      for _, col in ipairs(matches) do
        if row ~= cursor_range[1] or cursor_range[2] < col or cursor_range[2] > col + curpattern_len then
          vim.highlight.range(
            bufnr,
            usage_namespace,
            M.config.hlgroup,
            { row, col },
            { row, col + curpattern_len }
          )
        elseif (
          row == cursor_range[1]
          and cursor_range[2] >= col
          and cursor_range[2] <= col + curpattern_len
          and M.config.cw_hlgroup
        ) then
          vim.highlight.range(
            bufnr,
            usage_namespace,
            M.config.cw_hlgroup,
            { row, col },
            { row, col + curpattern_len }
          )
        end
      end
    end
  end
  -- dump(vim.fn.reltimefloat(vim.fn.reltime(start)) * 1000)
end

function M.has_highlights(bufnr)
  return #api.nvim_buf_get_extmarks(bufnr, usage_namespace, 0, -1, {}) > 0
end

function M.clear_usage_highlights(bufnr)
  api.nvim_buf_clear_namespace(bufnr, usage_namespace, 0, -1)
end

function M.buf_au_group_name(bufnr)
  return string.format("Highlight_usages_in_window_%d", bufnr)
end

function M.is_attached(bufnr)
  local au_group_name = M.buf_au_group_name(bufnr)
  local status, aus = pcall(api.nvim_get_autocmds, {group = au_group_name})
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
  local au = api.nvim_create_augroup(
    M.buf_au_group_name(bufnr),
    {clear = true}
  )
  api.nvim_create_autocmd(
    {'CursorHold'}, {
      group = au,
      buffer = bufnr,
      callback = function()
        M.highlight_usages(bufnr)
      end
    }
  )
  api.nvim_create_autocmd(
    {'InsertEnter'}, {
      group = au,
      buffer = bufnr,
      callback = function()
        M.clear_usage_highlights(bufnr)
      end
    }
  )
  api.nvim_create_autocmd(
    {'BufDelete'}, {
      group = au,
      buffer = bufnr,
      callback = function()
        M.clear_usage_highlights(bufnr)
        M.detach(bufnr)
      end
    }
  )
end

function M.detach(bufnr)
  M.clear_usage_highlights(bufnr)
  api.nvim_del_augroup_by_name(M.buf_au_group_name(bufnr))
  last_cache[bufnr] = nil
end


function M.setup(config)
  vim.api.nvim_set_hl(0, "LocalHighlight", {
    fg="#dcd7ba",
    bg="#2d4f67",
  })

  M.config = vim.tbl_deep_extend(
    "keep",
    config or {},
    M.config
  )
  local au = api.nvim_create_augroup("Highlight_usages_in_window", {clear = true})
  if config.file_types and #(config.file_types)> 0 then
    vim.api.nvim_create_autocmd('FileType', {
      group = au,
      pattern = config.file_types,
      callback = function(data)
        M.attach(data.buf)
      end
    })
  elseif config.file_types == nil then
    vim.api.nvim_create_autocmd('BufRead', {
      group = au,
      pattern = '*.*',
      callback = function(data)
        M.attach(data.buf)
      end
    })
  end

  --- add togglecommands
  vim.api.nvim_create_user_command(
    'LocalHighlightOff',
    function()
      M.detach(vim.fn.bufnr('%'))
    end,
    {desc='Turn local-highligh.nvim off'}
  )
  vim.api.nvim_create_user_command(
    'LocalHighlightOn',
    function()
      M.attach(vim.fn.bufnr('%'))
    end,
    {desc='Turn local-highligh.nvim on'}
  )
  vim.api.nvim_create_user_command(
    'LocalHighlightToggle',
    function()
      local bufnr = vim.fn.bufnr('%')
      if M.is_attached(bufnr) then
        M.detach(bufnr)
      else
        M.attach(bufnr)
      end
    end,
    {desc='Toggle local-highligh.nvim'}
  )

end

return M
