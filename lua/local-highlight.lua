-- This module highlights reference usages and the corresponding
-- definition on cursor hold.

local api = vim.api

local M = {
  regexes = {},
}

local usage_namespace = api.nvim_create_namespace("highlight_usages_in_window")
local last_nodes = {}

local function all_matches(regex, line)
  local ans = {}
  local offset = 0
  while #line > 0 do
    local s, e = regex:match_str(line)
    if not s then
      return ans
    end
    table.insert(ans, s + offset)
    offset = offset + e
    line = line:sub(e + 1)
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
  local curword = vim.fn.expand('<cword>')
  if not curword or #curword == 0 then
    M.clear_usage_highlights(bufnr)
    return
  end
  local topline, botline = vim.fn.line('w0') - 1, vim.fn.line('w$')
  -- Don't calculate usages again if we are on the same node.
  if (last_nodes[bufnr]
      and curword == last_nodes[bufnr].curword
      and topline == last_nodes[bufnr].topline
      and botline == last_nodes[bufnr].botline
      and M.has_highlights(bufnr)) then
    return
  else
      last_nodes[bufnr] = {
        curword = curword,
        topline = topline,
        botline = botline,
      }
  end

  M.clear_usage_highlights(bufnr)

  -- dumb find all matches of the node
  -- matching whole word ('\<' and '\>')
  local cursor_range = { cursor[1] - 1, cursor[2] }
  local curpattern = string.format([[\V\<%s\>]], curword)
  local curpattern_len = #curword
  local status, regex = pcall(M.regex, curpattern)
  if not status then
    return
  end

  for row=topline, botline do
    local lines = api.nvim_buf_get_lines(bufnr, row, row + 1, false)
    if #lines > 0 then
      local matches = all_matches(regex, lines[1])
      if matches and #matches > 0 then
        for _, col in ipairs(matches) do
          if row ~= cursor_range[1] or cursor_range[2] < col or cursor_range[2] > col + curpattern_len then
            vim.highlight.range(
              bufnr,
              usage_namespace,
              'TSDefinitionUsage',
              { row, col },
              { row, col + curpattern_len }
            )
          end
        end
      end
    end
  end
end

function M.has_highlights(bufnr)
  return #api.nvim_buf_get_extmarks(bufnr, usage_namespace, 0, -1, {}) > 0
end

function M.clear_usage_highlights(bufnr)
  api.nvim_buf_clear_namespace(bufnr, usage_namespace, 0, -1)
end

function M.attach(bufnr)
  local au = api.nvim_create_augroup(string.format("Highlight_usages_in_window_%d", bufnr), {clear = true})
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
  api.nvim_del_augroup_by_name(string.format("Highlight_usages_in_window_%d", bufnr))
  last_nodes[bufnr] = nil
end


function M.setup(config)
  local au = api.nvim_create_augroup("Highlight_usages_in_window", {clear = true})
  if config.file_types and #(config.file_types)> 0 then
    vim.api.nvim_create_autocmd('FileType', {
      group = au,
      pattern = config.file_types or {},
      callback = function(data)
        M.attach(data.buf)
      end
    })
  end
end

return M
