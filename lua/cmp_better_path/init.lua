local cmp = require 'cmp'

local NAME_REGEX = [[\%([^/\\:\*?<>'"`\|]\)]]
local PATH_REGEX = vim.regex(([[\%([!'"`]\)\zs\%([^/\\:\*?<>'"`\| ]*\)\=\%(/PAT*\)\+$]]):gsub('PAT', NAME_REGEX))

local source = {}

local constants = {
  max_lines = 20,
}

---@class cmp_better_path.Option
---@field public trailing_slash boolean
---@field public label_trailing_slash boolean
---@field public get_cwd fun(): string | table
---@field public show_hidden_files_by_default boolean

---@type cmp_better_path.Option
local defaults = {
  trailing_slash = false,
  label_trailing_slash = true,
  get_cwd = function(params)
    return {
      vim.fn.getcwd(),
      vim.fn.expand(("#%d:p:h"):format(params.context.bufnr)),
    }
  end,
  show_hidden_files_by_default = false,
}

local uniquify_table = function(a_table)
  local newArray = {}
  local guard = {}
  for _, element in ipairs(a_table) do
    if not guard[element] then
      guard[element] = true
      table.insert(newArray, element)
    end
  end
  return newArray
end

source.new = function()
  return setmetatable({}, { __index = source })
end

source.get_trigger_characters = function()
  return { '/', '.' }
end

source.get_keyword_pattern = function(_, _)
  return NAME_REGEX .. '*'
end

source.complete = function(self, params, callback)
  local option = self:_validate_option(params)

  local dirnames = self:_dirname(params, option)
  if not dirnames then
    return callback()
  end

  local include_hidden = option.show_hidden_files_by_default or string.sub(params.context.cursor_before_line, params.offset, params.offset) == '.'
  local all_candidates = {}
  for _, dirname in ipairs(dirnames) do
    self:_candidates(dirname, include_hidden, option, function(err, candidates)
      if not err then
        for _, v in ipairs(candidates) do
          table.insert(all_candidates, v)
        end
      end
    end)
  end

  callback(all_candidates)
end

source.resolve = function(self, completion_item, callback)
  local data = completion_item.data
  if data.stat and data.stat.type == 'file' then
    local ok, documentation = pcall(function()
      return self:_get_documentation(data.path, constants.max_lines)
    end)
    if ok then
      completion_item.documentation = documentation
    end
  end
  callback(completion_item)
end

source._dirname = function(self, params, option)
  local s = PATH_REGEX:match_str(params.context.cursor_before_line)
  if not s then
    return nil
  end

  local path = string.sub(params.context.cursor_before_line, s + 1)
  local dirname = path:sub(1, path:find("[/\\][^/\\]*$") - 1)

  local dir_match_fn = function(basedir)
    if string.sub(path, 1, 1) == "~" then
      return vim.fn.resolve(vim.fn.expand('~') .. dirname:sub(2))
    end
    if path == "/" then
      return vim.fn.resolve("/")
    end
    if string.sub(path, 1, 1) == "/" then
      return vim.fn.resolve("/" .. dirname)
    end
    return vim.fn.resolve(basedir .. '/' .. dirname)
  end

  if vim.api.nvim_get_mode().mode == 'c' then
    return { dir_match_fn(vim.fn.getcwd()) }
  end

  -- or a simple string (for backward compatibility)
  local search_directories = option.get_cwd(params)

  if type(search_directories) == "string" then
    return { dir_match_fn(search_directories) }
  end

  local matched_dirs = {}
  for _, a_dirname in ipairs(uniquify_table(search_directories)) do
    local matched = dir_match_fn(a_dirname)
    if matched then
      table.insert(matched_dirs, matched)
    end
  end
  return matched_dirs
end

source._candidates = function(_, dirname, include_hidden, option, callback)
  local fs, err = vim.loop.fs_scandir(dirname)
  if err then
    return callback(err, nil)
  end

  local items = {}

  local function create_item(name, fs_type)
    if not (include_hidden or string.sub(name, 1, 1) ~= '.') then
      return
    end

    local path = dirname .. '/' .. name
    local stat = vim.loop.fs_stat(path)
    local lstat = nil
    if stat then
      fs_type = stat.type
    elseif fs_type == 'link' then
      -- Broken symlink
      lstat = vim.loop.fs_lstat(dirname)
      if not lstat then
        return
      end
    else
      return
    end

    local item = {
      label = name,
      filterText = name,
      insertText = name,
      kind = cmp.lsp.CompletionItemKind.File,
      data = {
        path = path,
        type = fs_type,
        stat = stat,
        lstat = lstat,
      },
    }
    if fs_type == 'directory' then
      item.kind = cmp.lsp.CompletionItemKind.Folder
      if option.label_trailing_slash then
        item.label = name .. '/'
      else
        item.label = name
      end
      item.insertText = name .. '/'
      if not option.trailing_slash then
        item.word = name
      end
    end
    table.insert(items, item)
  end

  while true do
    local name, fs_type, e = vim.loop.fs_scandir_next(fs)
    if e then
      return callback(fs_type, nil)
    end
    if not name then
      break
    end
    create_item(name, fs_type)
  end

  callback(nil, items)
end

source._is_slash_comment = function(_)
  local commentstring = vim.bo.commentstring or ''
  local no_filetype = vim.bo.filetype == ''
  local is_slash_comment = false
  is_slash_comment = is_slash_comment or commentstring:match('/%*')
  is_slash_comment = is_slash_comment or commentstring:match('//')
  return is_slash_comment and not no_filetype
end

---@return cmp_better_path.Option
source._validate_option = function(_, params)
  local option = vim.tbl_deep_extend('keep', params.option, defaults)
  vim.validate({
    trailing_slash = { option.trailing_slash, 'boolean' },
    label_trailing_slash = { option.label_trailing_slash, 'boolean' },
    get_cwd = { option.get_cwd, 'function' },
    show_hidden_files_by_default = { option.show_hidden_files_by_default, 'boolean' },
  })
  return option
end

source._get_documentation = function(_, filename, count)
  local binary = assert(io.open(filename, 'rb'))
  local first_kb = binary:read(1024)
  if first_kb:find('\0') then
    return { kind = cmp.lsp.MarkupKind.PlainText, value = 'binary file' }
  end

  local contents = {}
  for content in first_kb:gmatch("[^\r\n]+") do
    table.insert(contents, content)
    if count ~= nil and #contents >= count then
      break
    end
  end

  local filetype = vim.filetype.match({ filename = filename })
  if not filetype then
    return { kind = cmp.lsp.MarkupKind.PlainText, value = table.concat(contents, '\n') }
  end

  table.insert(contents, 1, '```' .. filetype)
  table.insert(contents, '```')
  return { kind = cmp.lsp.MarkupKind.Markdown, value = table.concat(contents, '\n') }
end

return source
