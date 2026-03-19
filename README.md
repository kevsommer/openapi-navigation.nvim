# openapi-navigation.nvim

A Neovim plugin that parses your OpenAPI spec and lets you jump directly to controller implementations.

Built for Elixir projects using `elixir/openapi.json`.

## Features

- **Route Picker** — Browse all OpenAPI routes and jump to the corresponding controller function
- **Go to Service** — From a controller action, jump to the first `*Service.method()` call's definition
- **Snacks.picker integration** — Rich route display with method highlighting and file preview, falls back to `vim.ui.select`

## Requirements

- Neovim >= 0.9
- An `elixir/openapi.json` file with `operationId` fields (e.g. `Module.Name.function_name`)
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim) for the enhanced picker

## Installation

### lazy.nvim

```lua
{
  "your-user/openapi-navigation.nvim",
  opts = {},
}
```

With custom keymaps:

```lua
{
  "your-user/openapi-navigation.nvim",
  opts = {
    key = "<leader>so",        -- default: <leader>so
    service_key = "gs",        -- default: gs (buffer-local in .ex files)
  },
}
```

## Usage

| Keymap         | Description                                      |
| -------------- | ------------------------------------------------ |
| `<leader>so`   | Open the OpenAPI route picker                    |
| `gs`           | Jump to Service method definition (in .ex files) |
| `:OpenAPIRoutes` | Open the route picker via command               |

## How It Works

1. Searches upward from `cwd` for `elixir/openapi.json`
2. Parses `operationId` fields (format: `Module.Name.function_name`) to resolve controller files and functions
3. Converts Elixir module names to snake_case file paths under `elixir/lib/`
4. Jumps to the matching `def function_name(` in the resolved file
