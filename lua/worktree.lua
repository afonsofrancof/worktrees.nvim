local M = {}

-- Default configuration
local config = {
    -- Path relative to git common dir where worktrees will be created
    -- Examples: ".." (parent dir), "../.worktrees" (special dir), "." (same dir)
    base_path = "..", -- Default to parent directory

    -- Path template for new worktrees, when one isn't manually provided
    -- Use {branch} as placeholder for branch name
    path_template = "{branch}",
}

-- Get the git common directory
local function get_git_common_dir()
    local handle = io.popen("git rev-parse --git-common-dir 2>/dev/null")
    if not handle then return nil end

    local git_dir = handle:read("*a"):gsub("\n$", "")
    handle:close()

    if git_dir and git_dir ~= "" then
        return vim.fn.fnamemodify(git_dir, ":p:h") -- Ensure it's an absolute path without trailing slash
    end

    return nil
end

-- Calculate base path for new worktrees based on config
local function get_worktree_base_path()
    local common_dir = get_git_common_dir()

    if not common_dir then
        vim.notify("Not in a git repository", vim.log.levels.ERROR)
        return nil
    end

    -- Calculate the base path relative to common dir
    if config.base_path == "." then
        return common_dir
    else
        -- Handle relative paths cleanly
        return vim.fn.fnamemodify(vim.fn.resolve(common_dir .. "/" .. config.base_path), ":p:h")
    end
end

-- Get all worktrees using git's native commands
local function get_worktrees()
    local handle = io.popen("git worktree list --porcelain 2>/dev/null")
    if not handle then
        vim.notify("Failed to run git command", vim.log.levels.ERROR)
        return nil
    end

    local output = handle:read("*a")
    handle:close()

    if output == "" then
        vim.notify("No git worktrees found", vim.log.levels.ERROR)
        return nil
    end

    local worktrees = {}
    local current_worktree = {}

    for line in output:gmatch("[^\r\n]+") do
        if line:match("^worktree ") then
            if current_worktree.path then -- Save the previous worktree
                table.insert(worktrees, current_worktree)
            end
            current_worktree = {
                path = line:match("^worktree (.+)")
            }
        elseif line:match("^branch ") then
            current_worktree.branch = line:match("^branch (.+)")
            current_worktree.name = current_worktree.branch:gsub("refs/heads/", "")
        elseif line:match("^HEAD ") then
            current_worktree.head = line:match("^HEAD (.+)")
        elseif line:match("^bare") then
            current_worktree.bare = true
        end
    end

    if current_worktree.path then -- Add the last worktree
        table.insert(worktrees, current_worktree)
    end

    return worktrees
end

-- Get the repository root (top-level directory of current worktree)
local function get_worktree_root()
    local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
    if not handle then return nil end

    local root = handle:read("*a"):gsub("\n$", "")
    handle:close()

    if root and root ~= "" then
        return vim.fn.fnamemodify(root, ":p:h") -- Ensure it's an absolute path without trailing slash
    end

    return nil
end

-- Get the corresponding file path in another worktree
local function get_corresponding_file(worktree_path)
    local current_file = vim.fn.expand("%:p")
    if current_file == "" then
        return nil
    end

    -- Get current worktree
    local current_worktree = get_worktree_root()
    if not current_worktree then
        return nil
    end

    -- Get relative path of current file in the worktree
    local relative_path = string.sub(current_file, string.len(current_worktree) + 2)

    -- Construct the corresponding path in the other worktree
    local corresponding_path = vim.fn.resolve(worktree_path .. "/" .. relative_path)

    -- Check if file exists in the other worktree
    local f = io.open(corresponding_path, "r")
    if f then
        f:close()
        return corresponding_path
    else
        return nil
    end
end


--Util functions
M.utils = {}

-- Create a new worktree
M.utils.create_worktree = function(path, branch)
    if not branch or branch == "" then
        vim.notify("Branch name is required", vim.log.levels.ERROR)
        return false
    end

    local base_path = get_worktree_base_path()
    if not base_path then
        return false
    end

    -- Determine the worktree path
    local worktree_path
    if path and path ~= "" then
        -- User provided a specific path
        if vim.fn.fnamemodify(path, ":p") == path then
            -- Absolute path
            worktree_path = path
        else
            -- Relative path (to base_path)
            worktree_path = vim.fn.resolve(base_path .. "/" .. path)
        end
    else
        -- Use the template to create a path
        local path_from_template = config.path_template:gsub("{branch}", branch)
        worktree_path = vim.fn.resolve(base_path .. "/" .. path_from_template)
    end

    -- Create the worktree
    local cmd = string.format("git worktree add %s %s", vim.fn.shellescape(worktree_path), vim.fn.shellescape(branch))

    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        vim.notify("Failed to execute git command", vim.log.levels.ERROR)
        return false
    end

    local result = handle:read("*a")
    handle:close()

    if result:match("error") or result:match("fatal") then
        vim.notify("Failed to create worktree: " .. result, vim.log.levels.ERROR)
        return false
    else
        vim.notify("Created worktree: " .. branch .. " at " .. worktree_path, vim.log.levels.INFO)
        return true
    end
end

-- Delete a worktree by path
M.utils.delete_worktree = function(path)
    if not path or path == "" then
        vim.notify("Worktree path is required", vim.log.levels.ERROR)
        return false
    end

    local cmd = string.format("git worktree remove %s", vim.fn.shellescape(path))

    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        vim.notify("Failed to execute git command", vim.log.levels.ERROR)
        return false
    end

    local result = handle:read("*a")
    handle:close()

    if result:match("error") or result:match("fatal") then
        vim.notify("Failed to delete worktree: " .. result, vim.log.levels.ERROR)
        return false
    else
        vim.notify("Deleted worktree at: " .. path, vim.log.levels.INFO)
        return true
    end
end

-- Switch to a worktree by path
M.utils.switch_worktree = function(path)
    if not path or path == "" then
        vim.notify("Worktree path is required", vim.log.levels.ERROR)
        return false
    end

    -- Check if the path exists
    local stat = vim.loop.fs_stat(path)
    if not stat or stat.type ~= "directory" then
        vim.notify("Worktree path does not exist: " .. path, vim.log.levels.ERROR)
        return false
    end

    -- Chdir to the new worktree
    vim.cmd("cd " .. vim.fn.fnameescape(path))

    -- Check if the current file exists in the selected worktree
    local corresponding_file = get_corresponding_file(path)

    if corresponding_file then
        -- Switch to the corresponding file in the other worktree
        vim.cmd("edit " .. vim.fn.fnameescape(corresponding_file))
        vim.notify("Switched to worktree: " .. path, vim.log.levels.INFO)
    else
        -- Just change directory to the worktree
        vim.cmd("edit .")
        vim.notify("Switched to worktree: " .. path .. " (file not found)", vim.log.levels.INFO)
    end
    vim.cmd("clearjumps")

    return true
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

            M.utils.create_worktree(path, branch)
        end)
    end)
end

-- Interactive worktree deletion
M.delete = function()
    local worktrees = get_worktrees()
    if not worktrees or #worktrees == 0 then
        vim.notify("No worktrees found", vim.log.levels.ERROR)
        return
    end

    -- Filter out bare repository
    local non_bare_worktrees = {}
    for _, wt in ipairs(worktrees) do
        if not wt.bare then
            table.insert(non_bare_worktrees, wt)
        end
    end

    if #non_bare_worktrees < 1 then
        vim.notify("Need at least one non-bare worktree to delete", vim.log.levels.ERROR)
        return
    end

    -- Format worktrees for selection
    local items = {}
    for _, wt in ipairs(non_bare_worktrees) do
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

        local selected_worktree = non_bare_worktrees[idx]

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
    local worktrees = get_worktrees()
    if not worktrees or #worktrees == 0 then
        vim.notify("No worktrees found", vim.log.levels.ERROR)
        return
    end

    -- Filter out bare repository and current worktree
    local current_dir = vim.fn.getcwd()
    local other_worktrees = {}

    for _, wt in ipairs(worktrees) do
        if not wt.bare and wt.path ~= current_dir then
            table.insert(other_worktrees, wt)
        end
    end

    if #other_worktrees == 0 then
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
