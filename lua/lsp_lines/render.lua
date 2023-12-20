local M = {}

local HIGHLIGHTS = {
  native = {
    [vim.diagnostic.severity.ERROR] = "DiagnosticVirtualTextError",
    [vim.diagnostic.severity.WARN] = "DiagnosticVirtualTextWarn",
    [vim.diagnostic.severity.INFO] = "DiagnosticVirtualTextInfo",
    [vim.diagnostic.severity.HINT] = "DiagnosticVirtualTextHint",
  },
  coc = {
    [vim.diagnostic.severity.ERROR] = "CocErrorVirtualText",
    [vim.diagnostic.severity.WARN] = "CocWarningVirtualText",
    [vim.diagnostic.severity.INFO] = "CocInfoVirtualText",
    [vim.diagnostic.severity.HINT] = "CocHintVirtualText",
  },
}

-- These don't get copied, do they? We only pass around and compare pointers, right?
local SPACE = "space"
local DIAGNOSTIC = "diagnostic"
local OVERLAP = "overlap"
local BLANK = "blank"

---Returns the distance between two columns in cells.
---
---Some characters (like tabs) take up more than one cell. A diagnostic aligned
---under such characters needs to account for that and add that many spaces to
---its left.
---
---@return integer
local function distance_between_cols(bufnr, lnum, start_col, end_col)
  local lines = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)
  if vim.tbl_isempty(lines) then
    -- This can only happen is the line is somehow gone or out-of-bounds.
    return 1
  end

  local sub = string.sub(lines[1], start_col, end_col)
  return vim.fn.strdisplaywidth(sub, 0) -- these are indexed starting at 0
end

local function splitStringIntoLines(str, maxLineLength)
    local lines = {}
    local line = ""

    for word in str:gmatch("%S+") do
        if #line + #word <= maxLineLength then
            line = line .. word .. " "
        else
            if #line > 0 then
                table.insert(lines, line)
            end
            line = word .. " "
        end
    end

    if #line > 0 then
        table.insert(lines, line)
    end

    return table.concat(lines, "\n")
end

local function gmatch_to_table(input_string, pattern)
    local results = {}
    for match in input_string:gmatch(pattern) do
        table.insert(results, match)
    end
    return results
end

---@param namespace number
---@param bufnr number
---@param diagnostics table
---@param opts boolean|Opts
---@param source 'native'|'coc'|nil If nil, defaults to 'native'.
function M.show(namespace, bufnr, diagnostics, opts, source)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  vim.validate({
    namespace = { namespace, "n" },
    bufnr = { bufnr, "n" },
    diagnostics = {
      diagnostics,
      vim.tbl_islist,
      "a list of diagnostics",
    },
    opts = { opts, "t", true },
  })

  table.sort(diagnostics, function(a, b)
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    else
      return a.col < b.col
    end
  end)

  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  if #diagnostics == 0 then
    return
  end
  local highlight_groups = HIGHLIGHTS[source or "native"]

  if opts.virtual_lines.single_line then
    local error_count = {}

    for _, diagnostic in ipairs(diagnostics) do
        local severity_level = diagnostic.severity
        if error_count[diagnostic.lnum] == nil then
            error_count[diagnostic.lnum] = {}
        end

        if error_count[diagnostic.lnum][severity_level] == nil then
            error_count[diagnostic.lnum][severity_level] = 1
        else
            error_count[diagnostic.lnum][severity_level] = error_count[diagnostic.lnum][severity_level] + 1
        end
    end

    for lnum, severity_levels in pairs(error_count) do
        local line_length = #(vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1])
        local diagnostic_col = 0 -- Adjust this to your preferred column
        local virt_text = {}

        for severity_level, count in pairs(severity_levels) do
            local severity_label = ""
            if severity_level == vim.diagnostic.severity.ERROR then
                severity_label = "Error"
            elseif severity_level == vim.diagnostic.severity.WARN then
                severity_label = "Warn"
            elseif severity_level == vim.diagnostic.severity.INFO then
                severity_label = "Info"
            elseif severity_level == vim.diagnostic.severity.HINT then
                severity_label = "Hint"
            end

            local severity_sign = vim.fn.sign_getdefined("DiagnosticSign" .. severity_label)[1]
        vim.print(severity_sign)
            local severity_text =  severity_sign.text .. count
            table.insert(virt_text, { " " .. severity_text, highlight_groups[severity_level] })
        end

        vim.api.nvim_buf_set_extmark(
            bufnr,
            namespace,
            lnum,
            diagnostic_col,
            { virt_text = virt_text }
        )
    end

    return
end
 





  -- This loop reads line by line, and puts them into stacks with some
  -- extra data, since rendering each line will require understanding what
  -- is beneath it.
  local line_stacks = {}
  local prev_lnum = -1
  local prev_col = 0

  for _, diagnostic in ipairs(diagnostics) do

    -- -- for single line diagnostics, we can just render them as a single line
    -- local line_length = #(vim.api.nvim_buf_get_lines(bufnr, diagnostic.lnum, diagnostic.lnum + 1, false)[1])
    -- if line_length + #diagnostic.message < 118 or opts.virtual_lines.single_line then
    --   local msg;
    --   if diagnostic.code then
    --     msg = string.format("%s [%s]", diagnostic.message, diagnostic.code)
    --   else
    --     msg = diagnostic.message
    --   end
    --
    --   local col = math.min(diagnostic.col, line_length)
    --
    --   vim.api.nvim_buf_set_extmark(
    --     bufnr,
    --     namespace,
    --     diagnostic.lnum,
    --     col,
    --     { virt_text = { { "     " .. msg, highlight_groups[diagnostic.severity] } } }
    --   )
    --   goto skip
    -- end

    if line_stacks[diagnostic.lnum] == nil then
      line_stacks[diagnostic.lnum] = {}
    end

    local stack = line_stacks[diagnostic.lnum]

    if diagnostic.lnum ~= prev_lnum then
      table.insert(stack, { SPACE, string.rep(" ", distance_between_cols(bufnr, diagnostic.lnum, 0, diagnostic.col)) })
    elseif diagnostic.col ~= prev_col then
      -- Clarification on the magic numbers below:
      -- +1: indexing starting at 0 in one API but at 1 on the other.
      -- -1: for non-first lines, the previous col is already drawn.
      table.insert(
        stack,
        { SPACE, string.rep(" ", distance_between_cols(bufnr, diagnostic.lnum, prev_col + 1, diagnostic.col) - 1) }
      )
    else
      table.insert(stack, { OVERLAP, diagnostic.severity })
    end

    if diagnostic.message:find("^%s*$") then
      table.insert(stack, { BLANK, diagnostic })
    else
      table.insert(stack, { DIAGNOSTIC, diagnostic })
    end

    prev_lnum = diagnostic.lnum
    prev_col = diagnostic.col
    ::skip::
  end

  for lnum, lelements in pairs(line_stacks) do
    local virt_lines = {}
    local virt_text = {}

    -- We read in the order opposite to insertion because the last
    -- diagnostic for a real line, is rendered upstairs from the
    -- second-to-last, and so forth from the rest.
    for i = #lelements, 1, -1 do -- last element goes on top
      if lelements[i][1] == DIAGNOSTIC then
        local diagnostic = lelements[i][2]
        local empty_space_hi
        if opts.virtual_lines and opts.virtual_lines.highlight_whole_line == false then
          empty_space_hi = ""
        else
          empty_space_hi = highlight_groups[diagnostic.severity]
        end

        local left = {}
        local overlap = false
        local multi = 0

        -- Iterate the stack for this line to find elements on the left.
        for j = 1, i - 1 do
          local type = lelements[j][1]
          local data = lelements[j][2]
          if type == SPACE then
            if multi == 0 then
              table.insert(left, { data, empty_space_hi })
            else
              table.insert(left, { string.rep("─", data:len()), highlight_groups[diagnostic.severity] })
            end
          elseif type == DIAGNOSTIC then
            -- If an overlap follows this, don't add an extra column.
            if lelements[j + 1][1] ~= OVERLAP then
              table.insert(left, { "│", highlight_groups[data.severity] })
            end
            overlap = false
          elseif type == BLANK then
            if multi == 0 then
              table.insert(left, { "└", highlight_groups[data.severity] })
            else
              table.insert(left, { "┴", highlight_groups[data.severity] })
            end
            multi = multi + 1
          elseif type == OVERLAP then
            overlap = true
          end
        end

        local center_symbol
        if overlap and multi > 0 then
          center_symbol = "┼"
        elseif overlap then
          center_symbol = "├"
        elseif multi > 0 then
          center_symbol = "┴"
        else
          center_symbol = "└"
        end
        -- local center_text =
        local center = {
          { string.format("%s%s", center_symbol, "──── "), highlight_groups[diagnostic.severity] },
        }

        -- TODO: We can draw on the left side if and only if:
        -- a. Is the last one stacked this line.
        -- b. Has enough space on the left.
        -- c. Is just one line.
        -- d. Is not an overlap.

        local msg
        if diagnostic.code then
          msg = string.format("%s [%s]", diagnostic.message, diagnostic.code)
        else
          msg = diagnostic.message
        end

        local msg_lines = gmatch_to_table(msg, "([^\n]+)")

        for _, msg_line in ipairs(msg_lines) do
          local create_line = function(message)
            local line = {}
            vim.list_extend(line, left)
            vim.list_extend(line, center)
            table.insert(line, { message, highlight_groups[diagnostic.severity] })
            if overlap then
              center = { { "│", highlight_groups[diagnostic.severity] }, { "     ", empty_space_hi } }
            else
              center = { { "      ", empty_space_hi } }
            end
            return line
          end
          -- trim message to not have indentation
          msg_line = msg_line:match("^%s*(.-)%s*$")
          -- vim.list_extend(vline, { { msg_line, highlight_groups[diagnostic.severity] } })
          -- table.insert(virt_lines, vline)
          if #msg_line < 118 then
            table.insert(virt_lines, create_line(msg_line))
          else
            local has_matches = false
            -- split message by single quotes to make it readable
            for msg_part in msg_line:gmatch("(.-)'") do
              has_matches = true
              table.insert(virt_lines, create_line(msg_part:match("^%s*(.-)%s*$")))
            end

            -- no matches found for code, print the whole line
            if not has_matches then
              table.insert(virt_lines, create_line(msg_line))
            end

            if #msg_lines > 1 and opts.virtual_lines.short_diagnostic then
              table.insert(virt_lines, create_line("..."))
            end
          end

          if opts.virtual_lines.short_diagnostic then
            break
          end
        end
      end
    end

    vim.api.nvim_buf_set_extmark(bufnr, namespace, lnum, 0, { virt_lines = virt_lines })
  end
end

---@param namespace number
---@param bufnr number
function M.hide(namespace, bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
end

return M
