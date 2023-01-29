-- This module highlights reference usages and the corresponding
-- definition on cursor hold.

local parsers = require "nvim-treesitter.parsers"
local ts_utils = require "nvim-treesitter.ts_utils"
local api = vim.api

local M = {}

local usage_namespace = api.nvim_create_namespace("highlight_usages_in_window")
local last_nodes = {}

-- row is 0-based
local function get_node_at_position(row, col, ignore_injected_langs)
  local buf = api.nvim_win_get_buf(0)
  local root_lang_tree = parsers.get_parser(buf)
  if not root_lang_tree then
    return
  end

  local root
  if ignore_injected_langs then
    for _, tree in ipairs(root_lang_tree:trees()) do
      local tree_root = tree:root()
      if tree_root and ts_utils.is_in_node_range(tree_root, row, col) then
        root = tree_root
        break
      end
    end
  else
    root = ts_utils.get_root_for_position(row, col, root_lang_tree)
  end

  if not root then
    return
  end

  return root:named_descendant_for_range(row, col, row, col)
end

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

function M.highlight_usages(bufnr)
  local node_at_point = ts_utils.get_node_at_cursor()
  if node_at_point and node_at_point:child_count() > 0 then
    M.clear_usage_highlights(bufnr)
    return
  end
  -- Don't calculate usages again if we are on the same node.
  if node_at_point and node_at_point == last_nodes[bufnr] and M.has_highlights(bufnr) then
    return
  else
    last_nodes[bufnr] = node_at_point
  end

  M.clear_usage_highlights(bufnr)
  if not node_at_point then
    return
  end

  -- dumb find all matches of the node
  -- matching whole word ('\<' and '\>')
  local curpattern = string.format([[\V\<%s\>]], vim.treesitter.query.get_node_text(node_at_point, bufnr))
  local status, regex = pcall(vim.regex, curpattern)
  if not status then
    return
  end

  for row=vim.fn.line('w0') - 1, vim.fn.line('w$') do
    local lines = api.nvim_buf_get_lines(bufnr, row, row + 1, false)
    if #lines > 0 then
      local matches = all_matches(regex, lines[1])
      if matches and #matches > 0 then
        for _, col in ipairs(matches) do
          local node = get_node_at_position(row, col, false)
          if node and node ~= node_at_point and node:type() ~= 'comment' then
            ts_utils.highlight_node(node, bufnr, usage_namespace, "TSDefinitionUsage")
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
    -- {'CursorMoved', 'InsertEnter'}, {
      group = au,
      buffer = bufnr,
      callback = function()
        M.clear_usage_highlights(bufnr)
      end
    }
  )
end

function M.detach(bufnr)
  M.clear_usage_highlights(bufnr)
  api.nvim_del_augroup_by_name(string.format("Highlight_usages_in_window_%d", bufnr))
  last_nodes[bufnr] = nil
end

return M
