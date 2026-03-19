-- OpenAPI Route Picker for Q.wiki
-- Parses elixir/openapi.json and jumps to controller implementations.

local M = {}

--- Convert an Elixir module name to a file path relative to elixir/lib/
--- e.g. "Qwiki.Notifications.Inbound.Http.Controllers.MessageController" -> "qwiki/notifications/inbound/http/controllers/message_controller.ex"
local function module_to_path(module_name)
  local parts = {}
  for part in module_name:gmatch('[^.]+') do
    -- Convert PascalCase to snake_case
    local snake = part:gsub('(%u)', function(c)
      return '_' .. c:lower()
    end):gsub('^_', '')
    table.insert(parts, snake)
  end
  return table.concat(parts, '/') .. '.ex'
end

--- Find the project root by looking for elixir/openapi.json
local function find_project_root()
  local markers = { 'elixir/openapi.json' }
  local path = vim.fn.getcwd()

  for _ = 1, 20 do
    for _, marker in ipairs(markers) do
      if vim.fn.filereadable(path .. '/' .. marker) == 1 then
        return path
      end
    end
    local parent = vim.fn.fnamemodify(path, ':h')
    if parent == path then
      break
    end
    path = parent
  end
  return nil
end

--- Parse the OpenAPI spec and return route entries
local function parse_openapi(root)
  local spec_path = root .. '/elixir/openapi.json'
  local file = io.open(spec_path, 'r')
  if not file then
    return nil, 'Cannot open ' .. spec_path
  end

  local content = file:read('*a')
  file:close()

  local ok, spec = pcall(vim.json.decode, content)
  if not ok or not spec then
    return nil, 'Failed to parse JSON'
  end

  local routes = {}
  for path, methods in pairs(spec.paths or {}) do
    for method, details in pairs(methods) do
      local operation_id = details.operationId
      if operation_id then
        -- Split "Module.Name.function_name" into module + function
        local last_dot = operation_id:match('.*()%.')
        if last_dot then
          local module_name = operation_id:sub(1, last_dot - 1)
          local func_name = operation_id:sub(last_dot + 1)
          local rel_path = 'elixir/lib/' .. module_to_path(module_name)
          local tags = details.tags or {}
          local tag = tags[1] or ''

          table.insert(routes, {
            method = method:upper(),
            path = path,
            module = module_name,
            func = func_name,
            file = rel_path,
            tag = tag,
            summary = details.summary or '',
          })
        end
      end
    end
  end

  table.sort(routes, function(a, b)
    return a.path < b.path
  end)

  return routes
end

--- Jump to the function definition in the controller file
local function jump_to_route(root, route)
  local abs_path = root .. '/' .. route.file
  if vim.fn.filereadable(abs_path) == 0 then
    vim.notify('File not found: ' .. route.file, vim.log.levels.WARN)
    return
  end

  vim.cmd('edit ' .. vim.fn.fnameescape(abs_path))

  -- Search for the function definition: `def func_name(`
  local pattern = 'def%s+' .. vim.pesc(route.func) .. '%s*[%(]'
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      vim.cmd('normal! zz')
      return
    end
  end

  -- Fallback: just open the file
  vim.notify('Opened file, could not find def ' .. route.func, vim.log.levels.INFO)
end

--- Format a route entry for display
local function format_route(route)
  local method_pad = ('%-6s'):format(route.method)
  return method_pad .. ' ' .. route.path
end

--- Pick routes using Snacks.picker
local function pick_with_snacks(routes, root)
  local items = {}
  for _, route in ipairs(routes) do
    table.insert(items, {
      text = format_route(route),
      route = route,
      file = root .. '/' .. route.file,
      label = route.tag,
    })
  end

  Snacks.picker({
    title = 'OpenAPI Routes',
    items = items,
    format = function(item, _ctx)
      local route = item.route
      local method_hl = ({
        GET = 'DiagnosticOk',
        POST = 'DiagnosticWarn',
        PUT = 'DiagnosticInfo',
        PATCH = 'DiagnosticInfo',
        DELETE = 'DiagnosticError',
      })[route.method] or 'Normal'

      local ret = {}
      table.insert(ret, { ('%-7s'):format(route.method), method_hl })
      table.insert(ret, { route.path .. ' ', 'Normal' })
      if route.tag ~= '' then
        table.insert(ret, { '[' .. route.tag .. ']', 'Comment' })
      end
      return ret
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        jump_to_route(root, item.route)
      end
    end,
    preview = function(ctx)
      local route = ctx.item.route
      local abs_path = root .. '/' .. route.file
      if vim.fn.filereadable(abs_path) == 1 then
        ctx.preview:file(abs_path)

        -- Try to highlight the function
        local lines = vim.fn.readfile(abs_path)
        local pattern = 'def%s+' .. vim.pesc(route.func) .. '%s*[%(]'
        for i, line in ipairs(lines) do
          if line:match(pattern) then
            ctx.preview:highlight({ buf = ctx.buf, line = i })
            ctx.preview:loc({ buf = ctx.buf, line = i })
            break
          end
        end
      else
        ctx.preview:set_lines({ 'File not found: ' .. route.file })
      end
    end,
  })
end

--- Pick routes using vim.ui.select (fallback)
local function pick_with_ui_select(routes, root)
  local labels = {}
  for _, route in ipairs(routes) do
    table.insert(labels, format_route(route))
  end

  vim.ui.select(labels, { prompt = 'OpenAPI Routes:' }, function(_, idx)
    if idx then
      jump_to_route(root, routes[idx])
    end
  end)
end

--- Main entry point
function M.pick()
  local root = find_project_root()
  if not root then
    vim.notify('Could not find elixir/openapi.json in parent directories', vim.log.levels.ERROR)
    return
  end

  local routes, err = parse_openapi(root)
  if not routes then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  if #routes == 0 then
    vim.notify('No routes with operationId found', vim.log.levels.WARN)
    return
  end

  local has_snacks, _ = pcall(function()
    return Snacks.picker
  end)
  if has_snacks and Snacks.picker then
    pick_with_snacks(routes, root)
  else
    pick_with_ui_select(routes, root)
  end
end

--- Setup keymaps and user command
function M.setup(opts)
  opts = opts or {}
  local key = opts.key or '<leader>so'

  vim.keymap.set('n', key, M.pick, { desc = 'OpenAPI Routes' })
  vim.api.nvim_create_user_command('OpenAPIRoutes', M.pick, { desc = 'Search OpenAPI routes' })
end

return M
