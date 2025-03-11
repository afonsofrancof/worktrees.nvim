# worktrees.nvim

A simple and configurable Neovim plugin for working with Git worktrees.

`worktrees.nvim` makes it easy to create, delete, and switch between Git worktrees directly from Neovim. 
When switching between worktrees, it will try to open the same file in the target worktree if it exists.

## Demo

https://github.com/user-attachments/assets/9873ec7e-4660-4301-9618-82054af3eb1f

## Features

- Create new Git worktrees with branch creation
- Delete worktrees with confirmation
- Switch between worktrees while preserving your place in files
- Customizable commands and keymaps
- Works with any Git worktree structure

## Requirements

- Neovim 0.7.0 or higher
- Git installed and accessible in path
- A Git repository

## Installation

## Setup with [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
   'afonsofrancof/worktrees.nvim',
   opts = {
          -- Specify where to create worktrees relative to git common dir
          -- The common dir is the .git dir in a normal repo or the root dir of a bare repo
          base_path = "..",  -- Parent directory of common dir
          
          -- Template for worktree folder names
          -- This is only used if you don't specify the folder name when creating the worktree
          path_template = "{branch}",  -- Default: use branch name
          
          -- Command names
          commands = {
            create = "WorktreeCreate",
            delete = "WorktreeDelete",
            switch = "WorktreeSwitch",
          },
          
          -- Key mappings
          mappings = {
            create = "<leader>wtc",
            delete = "<leader>wtd",
            switch = "<leader>wts",
          }
    }
}
```

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `base_path` | Path relative to git common directory where worktrees will be created | `".."` (parent directory) |
| `path_template` | Template for worktree folder names, `{branch}` is replaced with branch name | `"{branch}"` |
| `commands.create` | Command name for creating worktrees | `"WorktreeCreate"` |
| `commands.delete` | Command name for deleting worktrees | `"WorktreeDelete"` |
| `commands.switch` | Command name for switching worktrees | `"WorktreeSwitch"` |
| `mappings.create` | Key mapping for creating worktrees | `nil` (not set) |
| `mappings.delete` | Key mapping for deleting worktrees | `nil` (not set) |
| `mappings.switch` | Key mapping for switching worktrees | `nil` (not set) |

### Common Worktree Configurations

#### Worktrees in parent directory (standard)

```lua
require('worktrees').setup({
  base_path = ".."  -- worktrees at the parent directory of the .git directory
})
```

#### Worktrees inside the repository

```lua
require('worktrees').setup({
  base_path = "."  -- worktrees inside same directory as .git
})
```

#### Worktrees outside the repository

```lua
require('worktrees').setup({
  base_path = "../.."  -- worktrees outside the repo 
})
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:WorktreeCreate` | Interactively create a new worktree |
| `:WorktreeDelete` | Delete a worktree with an interactive selector |
| `:WorktreeSwitch` | Switch to another worktree with an interactive selector |

### Functions (for scripting)

```lua
-- Creating a worktree programmatically
require('worktrees').create_worktree("path/to/worktree", "feature-branch")

-- Deleting a worktree programmatically
require('worktrees').delete_worktree("path/to/worktree")

-- Switching to a worktree programmatically
require('worktrees').switch_worktree("path/to/worktree")
```

## How It Works

1. **Create:** When creating a worktree, you'll be prompted for a branch name and an optional path. The path is relative to the `base_path` specified in your config.

2. **Delete:** Shows a selection menu of available worktrees. After selecting one, you'll be asked to confirm deletion.

3. **Switch:** Shows a selection menu of other worktrees. After selecting one, the plugin will:
   - If the current file exists in the target worktree: Switch to that file
   - Otherwise: Change to the worktree directory and open the startup buffer

## License

MIT
