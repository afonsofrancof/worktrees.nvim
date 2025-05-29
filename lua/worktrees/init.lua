--- *worktrees* Git worktree management
--- *Worktrees*
---
--- MIT License
---
--- ==============================================================================
---
--- Features:
--- - Interactive creation, deletion, and switching of git worktrees
--- - Configurable base path and path templates for new worktrees
--- - Automatic file correspondence when switching between worktrees

--- @class GitModule
local git = require("worktrees.git")

-- Module definition ==========================================================
local Worktrees = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table.
---
---@usage >lua
---   require('worktrees').setup() -- use default config
---   -- OR
---   require('worktrees').setup({}) -- replace {} with your config table
--- <
Worktrees.setup = function(config)
    -- Setup config
    config = H.setup_config(config)

    -- Apply config
    H.apply_config(config)
end

--- Module config
Worktrees.config = {
    -- Path relative to git common dir where worktrees will be created
    -- Examples: ".." (parent dir), "../.worktrees" (special dir), "." (same dir)
    base_path = "..",

    -- Path template for new worktrees, when one isn't manually provided
    -- Use {branch} as placeholder for branch name
    path_template = "{branch}",

    -- Command names for interactive functions
    commands = {
        create = "WorktreeCreate",
        delete = "WorktreeDelete",
        switch = "WorktreeSwitch",
    },

    -- Optional key mappings
    mappings = {
        create = nil, -- e.g., "<leader>wc"
        delete = nil, -- e.g., "<leader>wd"
        switch = nil, -- e.g., "<leader>ws"
    },
}

-- Module functionality =======================================================

--- Utility functions for programmatic worktree management
Worktrees.utils = {}

--- Switch to a worktree by path
---@param path string path to the worktree
---@return boolean success Indicates if the switch was successful
Worktrees.utils.switch_worktree = function(path)
    local worktrees = git.get_worktrees()
    if not worktrees or vim.tbl_count(worktrees) == 0 then
        H.notify("No git worktrees found in this repo", vim.log.levels.ERROR)
        return false
    end

    if not path or path == "" then
        H.notify("Worktree path is required", vim.log.levels.ERROR)
        return false
    end

    -- Normalize the path for consistency
    local normalized_path = vim.fs.normalize(path)

    -- Check if the path exists
    local stat = vim.uv.fs_stat(normalized_path)
    if not stat or stat.type ~= "directory" then
        H.notify("Worktree path does not exist: " .. path, vim.log.levels.ERROR)
        return false
    end

    -- Try to find branch name for the worktree
    local target_worktree = worktrees[normalized_path]
    if not target_worktree then
        H.notify("Path is not a worktree in the current repository: " .. path, vim.log.levels.ERROR)
        return false
    end

    local branch_name = target_worktree.name

    if not branch_name then
        H.notify("Path is not a worktree in the current repository: " .. path, vim.log.levels.ERROR)
        return false
    end

    -- Check if the current file exists in the selected worktree
    local corresponding_file = H.get_current_file_in_other_worktree(path)

    -- Change directory to the new worktree
    vim.cmd.cd(vim.fn.fnameescape(path))

    if corresponding_file then
        -- Switch to the corresponding file in the other worktree
        vim.cmd.edit(vim.fn.fnameescape(corresponding_file))
        H.notify("Switched to worktree: " .. branch_name, vim.log.levels.INFO)
    else
        -- Just change directory to the worktree
        vim.cmd.edit(".")
        H.notify(
            "Switched to worktree: " .. branch_name .. " (file not found)",
            vim.log.levels.INFO
        )
    end
    vim.cmd.clearjumps()

    return true
end

--- Create a new worktree
---@param path string|nil path to the new worktree (optional)
---@param branch string name of the branch to use in the new worktree
---@param switch? boolean should the plugin switch to the newly created worktree
---@return string|nil path of the new worktree if it was created successfully
Worktrees.utils.create_worktree = function(path, branch, switch)
    if not branch or branch == "" then
        H.notify("Branch name is required", vim.log.levels.ERROR)
        return nil
    end

    local base_path = H.get_base_path()
    if not base_path then return nil end

    -- Trim whitespace from path if it exists
    path = path and vim.trim(path)

    -- Determine the worktree path
    local worktree_path
    if path and path ~= "" then
        -- User provided a specific path
        if vim.fn.fnamemodify(path, ":p") == path then
            -- Absolute path
            worktree_path = vim.fs.normalize(path)
        else
            -- Relative path (to base_path)
            worktree_path = vim.fs.normalize(
                vim.fn.resolve(vim.fs.joinpath(base_path, path))
            )
        end
    else
        -- Use the template to create a path
        local path_from_template = Worktrees.config.path_template:gsub(
            "{branch}",
            branch
        )
        worktree_path = vim.fs.normalize(
            vim.fn.resolve(vim.fs.joinpath(base_path, path_from_template))
        )
    end

    -- Make sure the branch exists
    -- No need to check the exit code; it creates the branch if it doesn't exist
    -- and harmlessly fails if it does
    vim.system({ "git", "branch", branch }):wait()

    -- Create the worktree
    local result = vim.system({
        "git",
        "worktree",
        "add",
        worktree_path,
        branch,
    }, { text = true }):wait()

    if result.code ~= 0 then
        H.notify(
            "Failed to create worktree: " .. (result.stderr or ""),
            vim.log.levels.ERROR
        )
        return nil
    else
        H.notify(
            "Created worktree: " .. branch .. " at " .. worktree_path,
            vim.log.levels.INFO
        )

        -- Check if this is the first worktree, if so switch to it
        local worktrees = git.get_worktrees()
        if (worktrees and vim.tbl_count(worktrees) == 1) or switch == true then
            vim.schedule(function()
                Worktrees.utils.switch_worktree(worktree_path)
            end)
        end

        return worktree_path
    end
end

--- Delete a worktree by path
---@param path string path to the worktree
---@return boolean success Indicates if the deletion was successful
Worktrees.utils.delete_worktree = function(path)
    if not path or path == "" then
        H.notify("Worktree path is required", vim.log.levels.ERROR)
        return false
    end

    local result = vim.system({
        "git",
        "worktree",
        "remove",
        path,
        "--force",
    }, { text = true }):wait()

    if result.code ~= 0 then
        H.notify(
            "Failed to delete worktree: " .. (result.stderr or ""),
            vim.log.levels.ERROR
        )
        return false
    else
        H.notify("Deleted worktree at: " .. path, vim.log.levels.INFO)
        return true
    end
end

-- Interactive UI functions ===================================================

--- Interactive worktree creation
Worktrees.create = function()
    vim.ui.input({
        prompt = "Enter branch name for new worktree: ",
    }, function(branch)
        if not branch or branch == "" then
            H.notify("Worktree creation cancelled", vim.log.levels.INFO)
            return
        end

        vim.ui.input({
            prompt = "Enter path for new worktree (empty for template): ",
        }, function(path)
            if path == nil then -- User cancelled
                H.notify("Worktree creation cancelled", vim.log.levels.INFO)
                return
            end

            local created_path = Worktrees.utils.create_worktree(path, branch)
            -- Check if creation succeeded
            if not created_path then return end

            -- Use a select prompt for confirmation instead of text input
            vim.ui.select({ "No", "Yes" }, {
                prompt = "Switch to the new worktree?",
            }, function(confirm)
                if confirm == "Yes" then
                    Worktrees.utils.switch_worktree(created_path)
                end
            end)
        end)
    end)
end

--- Interactive worktree deletion
Worktrees.delete = function()
    local worktrees = git.get_worktrees()
    if not worktrees or vim.tbl_count(worktrees) == 0 then
        H.notify("No worktrees found", vim.log.levels.WARN)
        return
    end

    ---@type Worktree[]
    local worktree_list = vim.tbl_values(worktrees)

    -- Format worktrees for selection
    local items = {}
    for _, wt in ipairs(worktree_list) do
        local branch_info = wt.name or vim.fn.fnamemodify(wt.path, ":t")
        local label = branch_info .. " (" .. wt.path .. ")"
        table.insert(items, label)
    end

    vim.ui.select(items, {
        prompt = "Select worktree to delete:",
    }, function(choice, idx)
        if not choice then
            H.notify("Worktree deletion cancelled", vim.log.levels.INFO)
            return
        end

        local selected_worktree = worktree_list[idx]

        -- Use a select prompt for confirmation
        vim.ui.select({ "No", "Yes" }, {
            prompt = "Confirm deletion of worktree at '" .. selected_worktree.path .. "':",
        }, function(confirm)
            if confirm == "Yes" then
                Worktrees.utils.delete_worktree(selected_worktree.path)
            else
                H.notify("Worktree deletion cancelled", vim.log.levels.INFO)
            end
        end)
    end)
end

--- Interactive worktree switching
Worktrees.switch = function()
    local worktrees = git.get_worktrees()
    if not worktrees or vim.tbl_count(worktrees) == 0 then
        H.notify("No worktrees found", vim.log.levels.WARN)
        return
    end

    -- Get current worktree path if it exists
    local current_worktree_path = vim.fs.normalize(git.get_worktree_root() or "")

    local other_worktrees = vim.tbl_filter(function(wt)
        return wt.path ~= current_worktree_path
    end, worktrees)

    if #other_worktrees == 0 then
        H.notify(
            "No other worktrees available to switch to",
            vim.log.levels.WARN
        )
        return
    end

    -- Format worktrees for selection
    local items = {}
    for _, wt in ipairs(other_worktrees) do
        local branch_info = wt.name or vim.fn.fnamemodify(wt.path, ":t")
        local label = branch_info .. " (" .. wt.path .. ")"
        table.insert(items, label)
    end

    vim.ui.select(items, {
        prompt = "Select worktree to switch to:",
    }, function(choice, idx)
        if not choice then
            H.notify("Worktree switch cancelled", vim.log.levels.INFO)
            return
        end

        local selected_worktree = other_worktrees[idx]
        Worktrees.utils.switch_worktree(selected_worktree.path)
    end)
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(Worktrees.config)

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
    H.check_type("config", config, "table", true)
    config = vim.tbl_deep_extend("force", vim.deepcopy(H.default_config), config or {})

    H.check_type("base_path", config.base_path, "string")
    H.check_type("path_template", config.path_template, "string")
    H.check_type("commands", config.commands, "table")
    H.check_type("mappings", config.mappings, "table")

    -- Validate commands
    H.check_type("commands.create", config.commands.create, "string")
    H.check_type("commands.delete", config.commands.delete, "string")
    H.check_type("commands.switch", config.commands.switch, "string")

    -- Validate mappings (can be nil)
    H.check_type("mappings.create", config.mappings.create, "string", true)
    H.check_type("mappings.delete", config.mappings.delete, "string", true)
    H.check_type("mappings.switch", config.mappings.switch, "string", true)

    return config
end

H.apply_config = function(config)
    Worktrees.config = config

    -- Create user commands
    H.create_commands(config.commands)

    -- Set up optional key mappings
    H.create_mappings(config.mappings)
end

H.create_commands = function(commands)
    local command_defs = {
        {
            commands.create,
            Worktrees.create,
            "Create a git worktree (interactive)",
        },
        {
            commands.delete,
            Worktrees.delete,
            "Delete a git worktree (interactive)",
        },
        {
            commands.switch,
            Worktrees.switch,
            "Switch to a git worktree (interactive)",
        },
    }

    for _, cmd in ipairs(command_defs) do
        vim.api.nvim_create_user_command(cmd[1], cmd[2], { desc = cmd[3] })
    end
end

H.create_mappings = function(mappings)
    local mapping_defs = {
        {
            mappings.create,
            Worktrees.create,
            "Create git worktree",
        },
        {
            mappings.delete,
            Worktrees.delete,
            "Delete git worktree",
        },
        {
            mappings.switch,
            Worktrees.switch,
            "Switch git worktree",
        },
    }

    for _, mapping in ipairs(mapping_defs) do
        if mapping[1] then
            vim.keymap.set("n", mapping[1], mapping[2], {
                noremap = true,
                silent = true,
                desc = mapping[3],
            })
        end
    end
end

-- Utilities ------------------------------------------------------------------
H.error = function(msg)
    error("(worktrees) " .. msg, 0)
end

H.check_type = function(name, val, ref, allow_nil)
    if
        type(val) == ref
        or (ref == "callable" and vim.is_callable(val))
        or (allow_nil and val == nil)
    then
        return
    end
    H.error(
        string.format("`%s` should be %s, not %s", name, ref, type(val))
    )
end

H.notify = function(msg, level)
    vim.notify(msg, level or vim.log.levels.INFO)
end

-- Calculate base path for new worktrees based on config
H.get_base_path = function()
    local common_dir = git.get_git_common_dir()

    if not common_dir then
        vim.notify("Not in a git repository", vim.log.levels.ERROR)
        return nil
    end

    return vim.fs.normalize(vim.fs.joinpath(common_dir, Worktrees.config.base_path))
end

-- Get the corresponding file path in another worktree
H.get_current_file_in_other_worktree = function(target_worktree_path)
    local current_file = vim.fn.expand("%:p")
    if current_file == "" then
        return nil
    end

    local current_worktree = git.get_worktree_root()
    if not current_worktree then
        return nil
    end

    -- Normalize paths to avoid format differences
    current_worktree = vim.fs.normalize(current_worktree)
    current_file = vim.fs.normalize(current_file)
    target_worktree_path = vim.fs.normalize(target_worktree_path)

    -- Check if the current file is within the current worktree
    local is_descendant = vim.startswith(current_file, current_worktree)
    if not is_descendant then
        return nil
    end

    -- Get relative path from worktree to current file
    local relative_path = vim.fs.relpath(current_worktree, current_file)

    -- Create corresponding path in target worktree
    local target_file = vim.fs.joinpath(target_worktree_path, relative_path)

    -- Check if the file exists in the target worktree
    local stat = vim.uv.fs_stat(target_file)
    if stat then
        return target_file
    else
        return nil
    end
end

return Worktrees
