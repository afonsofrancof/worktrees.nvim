local M = {}
local git = require("worktrees.git")
-- Default configuration
local config = {
    -- Path relative to git common dir where worktrees will be created
    -- Examples: ".." (parent dir), "../.worktrees" (special dir), "." (same dir)
    base_path = "..", -- Default to parent directory

    -- Path template for new worktrees, when one isn't manually provided
    -- Use {branch} as placeholder for branch name
    path_template = "{branch}",
}

-- Calculate base path for new worktrees based on config
local function get_base_path()
    local common_dir = git.get_git_common_dir()

    if not common_dir then
        vim.notify("Not in a git repository", vim.log.levels.ERROR)
        return nil
    end

    -- Calculate the base path relative to common dir
    -- Use joinpath and normalize for clean path handling
    return vim.fs.normalize(vim.fs.joinpath(common_dir, config.base_path))
end

-- Get the corresponding file path in another worktree
local function get_current_file_in_other_worktree(target_worktree_path)
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
    local stat = vim.loop.fs_stat(target_file)
    if stat then
        return target_file
    else
        return nil
    end
end

--Util functions
M.utils = {}

-- Switch to a worktree by path
M.utils.switch_worktree = function(path)
    if not path or path == "" then
        vim.notify("Worktree path is required", vim.log.levels.ERROR)
        return false
    end

    -- Normalize the path for consistency
    local normalized_path = vim.fs.normalize(path)

    -- Check if the path exists
    local stat = vim.loop.fs_stat(normalized_path)
    if not stat or stat.type ~= "directory" then
        vim.notify("Worktree path does not exist: " .. path, vim.log.levels.ERROR)
        return false
    end

    -- Try to find branch name for the worktree
    local branch_name = nil
    local worktrees = git.get_worktrees()
    if worktrees then
        for _, wt in ipairs(worktrees) do
            if vim.fs.normalize(wt.path) == normalized_path then
                branch_name = wt.name
                break
            end
        end
    end

    -- Prepare display name for notifications (branch name or path)
    local display_name = branch_name or vim.fs.basename(normalized_path)

    -- Check if the current file exists in the selected worktree
    local corresponding_file = get_current_file_in_other_worktree(path)

    -- Chdir to the new worktree
    vim.cmd("cd " .. vim.fn.fnameescape(path))

    if corresponding_file then
        -- Switch to the corresponding file in the other worktree
        vim.cmd("edit " .. vim.fn.fnameescape(corresponding_file))
        vim.notify("Switched to worktree: " .. display_name, vim.log.levels.INFO)
    else
        -- Just change directory to the worktree
        vim.cmd("edit .")
        vim.notify("Switched to worktree: " .. display_name .. " (file not found)", vim.log.levels.INFO)
    end
    vim.cmd("clearjumps")

    return true
end

-- Create a new worktree
---@param path string path to the new worktree
---@param branch string name of the branch to use in the new worktree
---@param switch? boolean should the plugin switch to the newly created worktree
---@return string|nil # path of the new worktree if it was created successfully
M.utils.create_worktree = function(path, branch, switch)
    if not branch or branch == "" then
        vim.notify("Branch name is required", vim.log.levels.ERROR)
        return nil
    end

    local base_path = get_base_path()
    if not base_path then
        return nil
    end

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
            worktree_path = vim.fs.normalize(vim.fn.resolve(
                vim.fs.joinpath(base_path, path)
            ))
        end
    else
        -- Use the template to create a path
        local path_from_template = config.path_template:gsub("{branch}", branch)
        worktree_path = vim.fs.normalize(vim.fn.resolve(
            vim.fs.joinpath(base_path, path_from_template)
        ))
    end

    -- Make sure the branch exists
    -- No need to check the exit code; it creates the branch if it doesn't exists and harmlessly barfs if it does
    vim.system({ "git", "branch", branch }):wait()

    -- Create the worktree
    local result = vim.system({
        "git", "worktree", "add",
        worktree_path, branch
    }, { text = true }):wait()

    if result.code ~= 0 then
        vim.notify("Failed to create worktree: " .. (result.stderr or ""), vim.log.levels.ERROR)
        return nil
    else
        vim.notify("Created worktree: " .. branch .. " at " .. worktree_path, vim.log.levels.INFO)

        -- Check if this is the first worktree, if so switch to it
        local _, count = git.get_worktrees()
        if count == 1 or switch == true then
            vim.schedule(function()
                M.utils.switch_worktree(worktree_path)
            end)
        end

        return worktree_path
    end
end

-- Delete a worktree by path
M.utils.delete_worktree = function(path)
    if not path or path == "" then
        vim.notify("Worktree path is required", vim.log.levels.ERROR)
        return false
    end

    local result = vim.system({
        "git", "worktree", "remove", path, "--force"
    }, { text = true }):wait()

    if result.code ~= 0 then
        vim.notify("Failed to delete worktree: " .. (result.stderr or ""), vim.log.levels.ERROR)
        return false
    else
        vim.notify("Deleted worktree at: " .. path, vim.log.levels.INFO)
        return true
    end
end

-- Interactive UI functions

-- Interactive worktree creation
M.create = function()
    vim.ui.input({
        prompt = "Enter branch name for new worktree: ",
    }, function(branch)
        if not branch or branch == "" then
            vim.notify("Worktree creation cancelled", vim.log.levels.INFO)
            return
        end

        vim.ui.input({
            prompt = "Enter path for new worktree (empty for template): ",
        }, function(path)
            if path == nil then -- User cancelled
                vim.notify("Worktree creation cancelled", vim.log.levels.INFO)
                return
            end

            path = M.utils.create_worktree(path, branch)
            -- Check if creation succeeded
            if not path then
                return
            end
            -- Use a select prompt for confirmation instead of text input
            vim.ui.select({ "No", "Yes" }, {
                prompt = "Switch to the new worktree?",
            }, function(confirm)
                if confirm == "Yes" then
                    M.utils.switch_worktree(path)
                end
            end)
        end)
    end)
end

-- Interactive worktree deletion
M.delete = function()
    local worktrees, number_of_worktrees = git.get_worktrees()
    if not worktrees or number_of_worktrees == 0 then
        return
    end

    -- Format worktrees for selection
    local items = {}
    for _, wt in ipairs(worktrees) do
        local branch_info = wt.name or vim.fn.fnamemodify(wt.path, ":t")
        local label = branch_info .. " (" .. wt.path .. ")"
        table.insert(items, label)
    end

    vim.ui.select(items, {
        prompt = "Select worktree to delete:",
    }, function(choice, idx)
        if not choice then
            vim.notify("Worktree deletion cancelled", vim.log.levels.INFO)
            return
        end

        local selected_worktree = worktrees[idx]

        -- Use a select prompt for confirmation instead of text input
        vim.ui.select({ "No", "Yes" }, {
            prompt = "Confirm deletion of worktree at '" .. selected_worktree.path .. "':",
        }, function(confirm)
            if confirm == "Yes" then
                M.utils.delete_worktree(selected_worktree.path)
            else
                vim.notify("Worktree deletion cancelled", vim.log.levels.INFO)
            end
        end)
    end)
end

-- Interactive worktree switching
M.switch = function()
    local worktrees, number_of_worktrees = git.get_worktrees()
    if not worktrees or number_of_worktrees == 0 then
        return
    end

    -- Get current worktree path if it exists
    local current_worktree_path = git.get_worktree_root() or ""

    -- Filter out current worktree
    local other_worktrees = {}
    local other_worktrees_count = 0
    for _, wt in ipairs(worktrees) do
        -- Normalize paths before comparison to handle different path formats
        if vim.fs.normalize(wt.path) ~= vim.fs.normalize(current_worktree_path) then
            table.insert(other_worktrees, wt)
            other_worktrees_count = other_worktrees_count + 1
        end
    end

    if other_worktrees_count == 0 then
        vim.notify("No other worktrees available to switch to", vim.log.levels.ERROR)
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
            vim.notify("Worktree switch cancelled", vim.log.levels.INFO)
            return
        end

        local selected_worktree = other_worktrees[idx]
        M.utils.switch_worktree(selected_worktree.path)
    end)
end

-- Setup function for user commands
M.setup = function(opts)
    opts = opts or {}

    -- Apply user configuration
    if opts.base_path ~= nil then
        config.base_path = opts.base_path
    end

    if opts.path_template ~= nil then
        config.path_template = opts.path_template
    end

    -- Default command names
    local commands = {
        create = opts.commands and opts.commands.create or "WorktreeCreate",
        delete = opts.commands and opts.commands.delete or "WorktreeDelete",
        switch = opts.commands and opts.commands.switch or "WorktreeSwitch",
    }

    -- Create user commands for interactive UI functions
    vim.api.nvim_create_user_command(commands.create, function()
        M.create()
    end, {
        desc = "Create a git worktree (interactive)",
    })

    vim.api.nvim_create_user_command(commands.delete, function()
        M.delete()
    end, {
        desc = "Delete a git worktree (interactive)",
    })

    vim.api.nvim_create_user_command(commands.switch, function()
        M.switch()
    end, {
        desc = "Switch to a git worktree (interactive)",
    })

    -- Set up optional key mappings
    if opts.mappings then
        if opts.mappings.create then
            vim.keymap.set('n', opts.mappings.create, M.create,
                { noremap = true, silent = true, desc = "Create git worktree" })
        end

        if opts.mappings.delete then
            vim.keymap.set('n', opts.mappings.delete, M.delete,
                { noremap = true, silent = true, desc = "Delete git worktree" })
        end

        if opts.mappings.switch then
            vim.keymap.set('n', opts.mappings.switch, M.switch,
                { noremap = true, silent = true, desc = "Switch git worktree" })
        end
    end
end

return M
