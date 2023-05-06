# cmp-better-path

A fork of cmp-path, nvim-cmp source for filesystem paths. It is just better!


## Configuration

The below source configuration options are available. To set any of these options, do:

```lua
require'cmp'.setup({
  sources = {
    {
      name = 'better-path',
      option = {
        -- Options go into this table
      },
    },
  },
})
```


### trailing_slash (type: boolean)

_Default:_ `false`

Specify if completed directory names should include a trailing slash. Enabling this option makes this source behave like Vim's built-in path completion.

### label_trailing_slash (type: boolean)

_Default:_ `true`

Specify if directory names in the completion menu should include a trailing slash.

### get_cwd (type: function)

_Default:_ returns the current working directory of the current buffer

Specifies the base directory for relative paths.

### show_hidden_files_by_default (type: boolean)

_Default:_ `false`

Specify if hidden files should appear in the completion menu without the need of typing `.` first.
