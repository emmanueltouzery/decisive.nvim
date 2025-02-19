local function check_version()
  if vim.version().major == 0 and vim.version().minor < 10 then
    local emsg = string.format("decisive.nvim requires nvim-0.10 to work, current version is %d.%d.%d", vim.version().major, vim.version().minor, vim.version().patch)
    vim.notify(emsg, vim.log.levels.ERROR)
    return false
  end
  return true
end

local function align_csv_clear(opts)
  local ns = vim.api.nvim_create_namespace('__align_csv')
  local bufnr = opts.bufnr or 0
  -- clear existing extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  if (opts == nil or opts.keep_autocmd ~= true) and vim.b[bufnr].__align_csv_autocmd ~= nil then
    vim.api.nvim_del_autocmd(vim.b[bufnr].__align_csv_autocmd)
    vim.b[bufnr].__align_csv_autocmd = nil
  end
end

-- messy due to supporting " fields containing the separator
-- presumably not the most performant, if it's even correct
local function split_line(line, sep)
  local list = vim.split(line, sep)
  -- now we merge back some cols that were quoted
  local cols = {}
  local col = nil
  for _, item in ipairs(list) do
    if col ~= nil then
      col = col .. sep .. item
      if #item >= 1 and item:sub(#item) == '"' then
        table.insert(cols, col)
        col = nil
      end
    elseif #item >= 1 and item:sub(1, 1) == '"' and item:sub(#item) ~= '"' then
      -- incomplete quoted column, store its beginning in variable
      col = item
    else
      table.insert(cols, item)
    end
  end
  if col ~= nil then
    table.insert(cols, col)
  end
  return cols
end

local function align_csv(opts)
  if not check_version() then
    return
  end
  local bufnr = opts.bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines == 0 then
    return
  end

  local known_separators = {',', ';', '\t'}
  local line = 1
  local test_line = lines[line]
  -- tolerate a few blank lines at the top of the file (for instance
  -- when pasting a CSV in a new buffer)
  while #test_line == 0 and line <= #lines do
    line = line + 1
    test_line = lines[line]
  end
  if vim.b[bufnr].__align_csv_separator == nil then
    if opts.csv_separator ~= nil then
      vim.b[bufnr].__align_csv_separator = opts.csv_separator
    else
      for _, sep in ipairs(known_separators) do
        if #vim.split(test_line, sep) >= 2 then
          vim.b[bufnr].__align_csv_separator = sep
        end
      end
    end
  end

  local start_align = vim.loop.hrtime()

  align_csv_clear({keep_autocmd = true, bufnr = bufnr})
  local ns = vim.api.nvim_create_namespace('__align_csv')
  local col_max_lengths = {}
  local col_lengths = {}
  for line_idx, line in ipairs(lines) do
    local cols = split_line(line, vim.b[bufnr].__align_csv_separator)
    local col_lengths_line = {}
    for col_idx, col in ipairs(cols) do
      -- include the separator for display width, very important for tabs which have variable width
      local display_width = vim.fn.strdisplaywidth(col .. vim.b[bufnr].__align_csv_separator)
      table.insert(col_lengths_line, {display_width, #col})
      if not col_max_lengths[col_idx] or display_width+1 > col_max_lengths[col_idx] then
        col_max_lengths[col_idx] = display_width+1
      end
    end
    col_lengths[line_idx] = col_lengths_line
  end
  for line_idx, line_cols_info in ipairs(col_lengths) do
    local col_from_start = 0
    local row_hl_name = "CsvFillHlOdd"
    if line_idx % 2 == 0 then
      row_hl_name = "CsvFillHlEven"
    end
    for col_idx, col_info in ipairs(line_cols_info) do
      local col_display_width = col_info[1]
      local col_length = col_info[2]
      if col_idx < #line_cols_info then
        local extmark_col = col_from_start + col_length+1
        if col_display_width < col_max_lengths[col_idx] then
          vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx-1, extmark_col, {
            virt_text = {{string.rep(" ", col_max_lengths[col_idx] - col_display_width), row_hl_name}},
            virt_text_pos = 'inline',
          })
        else
          -- no need for virtual text, the column is full. but add it anyway because of the previous/next column jumps
          vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx-1, extmark_col, {
            virt_text = {{"", row_hl_name}},
            virt_text_pos = 'inline',
          })
        end
        col_from_start = extmark_col
      end
    end
  end

  local elapsed = (vim.loop.hrtime() - start_align) / 1e6
  if opts.print_speed and elapsed > 50 then
    print("Formatted in " .. elapsed .. "ms.")
  end
  if vim.b[bufnr].__align_csv_autocmd == nil and elapsed < (opts.auto_realign_limit_ms or 50) and opts.auto_realign ~= false then
    vim.b[bufnr].__align_csv_autocmd = vim.api.nvim_create_autocmd(opts.auto_realign or {"InsertLeave", "TextChanged"}, {
      buffer = bufnr,
      callback = function()
        require("decisive").align_csv(opts)
      end
    })
  end
end

local function align_csv_next_col()
  local ns = vim.api.nvim_create_namespace('__align_csv')
  local next_mark = vim.api.nvim_buf_get_extmarks(0, ns, {vim.fn.line('.')-1, vim.fn.col('.')+1}, -1, {limit = 1})
  if #next_mark == 1 then
    if next_mark[1][2]+1 > vim.fn.line('.') then
      -- moving to next line. the first column is the start of the line
      vim.fn.setpos('.', {0, next_mark[1][2]+1, 1, 0})
    else
      vim.fn.setpos('.', {0, next_mark[1][2]+1, next_mark[1][3]+1, 0})
    end
  end
end

local function align_csv_prev_col()
  local ns = vim.api.nvim_create_namespace('__align_csv')
  local next_mark = vim.api.nvim_buf_get_extmarks(0, ns, {vim.fn.line('.')-1, vim.fn.col('.')-2}, 0, {limit = 1})
  if vim.fn.col('.') == 1 then
    next_mark = vim.api.nvim_buf_get_extmarks(0, ns, {vim.fn.line('.')-1, vim.fn.col('.')-1}, 0, {limit = 1})
  end
  if #next_mark == 1 then
    if next_mark[1][2]+1 < vim.fn.line('.') and vim.fn.col('.') > 1 then
      -- the previous mark is on the previous line, but let's not forget
      -- about the first column of the line!
      vim.fn.setpos('.', {0, vim.fn.line('.'), 1, 0})
    else
      vim.fn.setpos('.', {0, next_mark[1][2]+1, next_mark[1][3]+1, 0})
    end
  else
    -- go to the beginning of the line
    vim.fn.setpos('.', {0, vim.fn.line('.'), 1, 0})
  end
end

local function inner_cell_to()
  local ns = vim.api.nvim_create_namespace('__align_csv')
  local prev_mark = vim.api.nvim_buf_get_extmarks(0, ns, {vim.fn.line('.')-1, vim.fn.col('.')-1}, 0, {limit = 1})
  local next_mark = vim.api.nvim_buf_get_extmarks(0, ns, {vim.fn.line('.')-1, vim.fn.col('.')+1}, -1, {limit = 1})
  vim.fn.setpos('.', {0, prev_mark[1][2]+1, prev_mark[1][3]+1, 0})
  vim.cmd("norm! v" .. (next_mark[1][3] - prev_mark[1][3] - 2) .. "lo")
end

local function setup(opts)
  if not check_version() then
    return
  end
  if opts.enable_text_objects ~= false then
    local cell_key = opts.cell_text_object_leader or 'c'
    vim.cmd([[onoremap <silent> i]] .. cell_key .. [[ :<c-u>lua require('decisive').inner_cell_to()<cr>]])
    vim.cmd([[xnoremap <silent> i]] .. cell_key .. [[ :<c-u>lua require('decisive').inner_cell_to()<cr>]])
  end
end

return {
  align_csv = align_csv,
  align_csv_clear = align_csv_clear,
  align_csv_next_col = align_csv_next_col,
  align_csv_prev_col = align_csv_prev_col,
  inner_cell_to = inner_cell_to,
  setup = setup,
}
