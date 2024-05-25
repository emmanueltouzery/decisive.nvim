# Decisive.nvim

Decisive.nvim is a neovim plugin to assist work with CSV files. It uses neovim 0.10+ 'inline extmarks' feature to insert virtual text to make the CSV columns line up.

This means that you see the columns lined up, but you can edit the file, save it to disk, and the padding text is never written to disk. If you enter extra text, you may have to re-trigger decisive to align the columns again (see the `auto_realign` setting).

Besides the function to line up columns, the plugin also provides:
- functions to jump to the next and previous columns, which you could map to `[c` and `]c` for instance
- a "inner cell" text object, so you can yank, change, delete, select a single cell of the csv (with `yic` for instance)

You can see a quick demo here:
[![asciicast](https://asciinema.org/a/UUILNVHx1BORR9Ujvb3kLRAh5.svg)](https://asciinema.org/a/UUILNVHx1BORR9Ujvb3kLRAh5)

Besides adding extra spaces to line up columns, it could maybe be technically possible to hide the separators, but I'd like to keep the plugin simple and easy to reason about.

Possible setup:
```lua
vim.keymap.set('n', '<leader>cca', ":lua require('decisive').align_csv({})<cr>", {desc="align CSV", silent=true})
vim.keymap.set('n', '<leader>ccA', ":lua require('decisive').align_csv_clear({})<cr>", {desc="align CSV clear", silent=true})
vim.keymap.set('n', '[c', ":lua require('decisive').align_csv_prev_col()<cr>", {desc="align CSV prev col", silent=true})
vim.keymap.set('n', ']c', ":lua require('decisive').align_csv_next_col()<cr>", {desc="align CSV next col", silent=true})

-- setup text objects (optional)
require('decisive').setup{}
```

The `align_csv` function takes a map parameter; here are the keys for the `align_csv` function map parameter:
- `csv_separator`: string, character to use for this alignment. If not specified, `decisive` will attempt to guess it;
- `auto_realign`: string list or false, whether to automatically re-align the columns after some events. Default: `{'InsertLeave', 'TextChanged'}`. Set to `false` to disable, or set other events; this is a buffer-local autocommand, not global;
- `auto_realign_limit_ms`: `auto_realign` will not trigger if alignment takes more than 50ms or the duration you specify

The `setup` function is totally optional, it enables the cell text object if you want it. You can change the text object leader (the default is `c`) through the `cell_text_object_leader` option.

The highlight group that is used for the virtual inserted spaces is `CsvFillHl`. You could use it if you wanted the virtual spaces to have a specific color, for instance with `hi CsvFillHl ctermbg=red guibg=red`.

Note that decisive is currently written very naively and will take a lot of CPU and memory to process larger CSV files.
