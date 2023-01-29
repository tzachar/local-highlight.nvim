local queries = require "nvim-treesitter.query"

local M = {}

function M.init()
  require "nvim-treesitter".define_modules {
    local_highlight = {
      module_path = "local-highlight.internal",
      is_supported = function(lang)
        return true
      end
    }
  }
end

return M
