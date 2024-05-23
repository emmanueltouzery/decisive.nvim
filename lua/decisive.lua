local function align_csv_clear()
  local ns = vim.api.nvim_create_namespace('__align_csv')
  -- clear existing extmarks
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})) do
    vim.api.nvim_buf_del_extmark(0, ns, mark[1])
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
      col = col .. "," .. item
      if item:match([["$]]) then
        table.insert(cols, col)
        col = nil
      end
    elseif item:match([[^"]]) then
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

  align_csv_clear()
  local ns = vim.api.nvim_create_namespace('__align_csv')
  local col_lengths = {}
  for _, line in ipairs(lines) do
    local cols = split_line(line, vim.b.__align_csv_separator)
    for col_idx, col in ipairs(cols) do
      if not col_lengths[col_idx] or vim.fn.strdisplaywidth(col)+1 > col_lengths[col_idx] then
        col_lengths[col_idx] = vim.fn.strdisplaywidth(col)+1
      end
    end
  end
  for line_idx, line in ipairs(lines) do
    local cols = split_line(line, vim.b.__align_csv_separator)
    local col_from_start = 0
    for col_idx, col in ipairs(cols) do
      if vim.fn.strdisplaywidth(col) < col_lengths[col_idx] then
        vim.api.nvim_buf_set_extmark(0, ns, line_idx-1, col_from_start + vim.fn.strdisplaywidth(col), {
          virt_text = {{string.rep(" ", col_lengths[col_idx] - vim.fn.strdisplaywidth(col)), "CsvFillHl"}},
          virt_text_pos = "inline",
        })
      else
        -- no need for virtual text, the column is full. but add it anyway because of the previous/next column jumps
        vim.api.nvim_buf_set_extmark(0, ns, line_idx-1, col_from_start + vim.fn.strdisplaywidth(col), {
          virt_text = {{"", "CsvFillHl"}},
          virt_text_pos = "inline",
        })
      end
      col_from_start = col_from_start + vim.fn.strdisplaywidth(col) + 1 -- +1 due to ;
    end
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

return {
  align_csv = align_csv,
  align_csv_clear = align_csv_clear,
  align_csv_next_col = align_csv_next_col,
  align_csv_prev_col = align_csv_prev_col,
}
