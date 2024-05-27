local function align_csv_clear(opts)
  local ns = vim.api.nvim_create_namespace('__align_csv')
  -- clear existing extmarks
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})) do
    vim.api.nvim_buf_del_extmark(0, ns, mark[1])
  end

  if (opts == nil or opts.keep_autocmd ~= true) and vim.b.__align_csv_autocmd ~= nil then
    vim.api.nvim_del_autocmd(vim.b.__align_csv_autocmd)
    vim.b.__align_csv_autocmd = nil
  end
end

local function split_line(line, sep)
  local separator_indices = {}
  local next_sep_idx = vim.fn.stridx(line, sep)
  while next_sep_idx ~= -1 do
    table.insert(separator_indices, {next_sep_idx, 0})
    if #line > next_sep_idx and line:sub(next_sep_idx+2, next_sep_idx+2) == '"' then
      -- quoted field!
      local end_quote_idx = vim.fn.stridx(line, '"', next_sep_idx+2)
      if line:sub(end_quote_idx+1, end_quote_idx+1) == '"' then
        -- finished the quoted field
        table.insert(separator_indices, {end_quote_idx+1, 0})
        next_sep_idx = end_quote_idx+1
      else
        -- i don't like this quoted field. just act as if it wasn't quoted
        next_sep_idx = vim.fn.stridx(line, sep, next_sep_idx+1)
      end
    else
      next_sep_idx = vim.fn.stridx(line, sep, next_sep_idx+1)
    end
  end
  -- i have the byte indices, now i want the display widths
  local width = vim.fn.strdisplaywidth(line)
  local cur_end = #line
  for i=#separator_indices, 1, -1 do
    local item = separator_indices[i]
    width = width - vim.fn.strdisplaywidth(line:sub(item[1]+1, cur_end))
    cur_end = item[1]
    item[2] = width
  end

  return separator_indices
end

local function align_csv(opts)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  if #lines == 0 then
    return
  end

  known_separators = {',', ';', '\t'}
  if vim.b.__align_csv_separator == nil then
    if opts.csv_separator ~= nil then
      vim.b.__align_csv_separator = opts.csv_separator
    else
      for _, sep in ipairs(known_separators) do
        if #vim.split(lines[1], sep) >= 2 then
          vim.b.__align_csv_separator = sep
        end
      end
    end
  end

  local start_align = vim.loop.hrtime()

  align_csv_clear({keep_autocmd = true})
  local ns = vim.api.nvim_create_namespace('__align_csv')
  local col_max_lengths = {}
  local col_lengths = {}
  for line_idx, line in ipairs(lines) do
    local cols_info = split_line(line, vim.b.__align_csv_separator)
    for col_idx, col_info in ipairs(cols_info) do
      local display_width = col_info[2]
      if not col_max_lengths[col_idx] or display_width+1 > col_max_lengths[col_idx] then
        col_max_lengths[col_idx] = display_width+1
      end
    end
    col_lengths[line_idx] = cols_info
  end
  for line_idx, line_cols_info in ipairs(col_lengths) do
    for col_idx, col_info in ipairs(line_cols_info) do
      local col_display_width = col_info[2]
      local col_length = col_info[1]
      if col_idx < #line_cols_info then
        local extmark_col = col_length+1
        if col_display_width < col_max_lengths[col_idx] then
          vim.api.nvim_buf_set_extmark(0, ns, line_idx-1, extmark_col, {
            virt_text = {{string.rep(" ", col_max_lengths[col_idx] - col_display_width), "CsvFillHl"}},
            virt_text_pos = "inline",
          })
        else
          -- no need for virtual text, the column is full. but add it anyway because of the previous/next column jumps
          vim.api.nvim_buf_set_extmark(0, ns, line_idx-1, extmark_col, {
            virt_text = {{"", "CsvFillHl"}},
            virt_text_pos = "inline",
          })
        end
      end
    end
  end

  local elapsed = (vim.loop.hrtime() - start_align) / 1e6
  if opts.print_speed and elapsed > 50 then
    print("Formatted in " .. elapsed .. "ms.")
  end
  if vim.b.__align_csv_autocmd == nil and elapsed < (opts.auto_realign_limit_ms or 50) and opts.auto_realign ~= false then
    vim.b.__align_csv_autocmd = vim.api.nvim_create_autocmd(opts.auto_realign or {"InsertLeave", "TextChanged"}, {
      buffer = 0,
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
