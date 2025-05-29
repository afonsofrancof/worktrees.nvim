--- @class GitModule
local M = {}

-- Get the git common directory
--- This returns the path to the .git directory
--- @return string|nil git_common_dir The normalized path to the git common directory, or nil if not in a git repository
M.get_git_common_dir = function()
    local result = vim.system({ "git", "rev-parse", "--git-common-dir" }, { text = true }):wait()

    if result.code ~= 0 or result.stdout == "" then
        return nil
    end

    local git_dir = vim.trim(result.stdout)
    return vim.fs.normalize(vim.fn.fnamemodify(git_dir, ":p:h"))
end

-- Get the repository root (top-level directory of current worktree)
--- This returns the root directory of the current working tree
--- @return string|nil worktree_root The normalized path to the worktree root, or nil if not in a git repository
M.get_worktree_root = function()
    local result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()

    if result.code ~= 0 or result.stdout == "" then
        return nil
    end

    local root = vim.trim(result.stdout)
    return vim.fs.normalize(vim.fn.fnamemodify(root, ":p:h"))
end

--- Worktree information table
--- @class Worktree
--- @field path string The filesystem path to the worktree
--- @field branch string|nil The full branch reference (e.g., "refs/heads/main")
--- @field name string|nil The branch name without the "refs/heads/" prefix
--- @field head string|nil The commit hash that HEAD points to

--- Get all worktrees (non-bare only)
--- Returns a list of all non-bare worktrees in the repository
--- @return table<string,Worktree>|nil worktrees Array of worktree information tables, or nil if command failed
M.get_worktrees = function()
    local result = vim.system({ "git", "worktree", "list", "--porcelain" }, { text = true }):wait()

    if result.code ~= 0 or result.stdout == "" then
        return nil
    end

    local output = result.stdout or ""

    ---@type table<string,Worktree>
    local worktrees = {}

    -- Split by double newlines to get blocks per worktree
    local blocks = vim.split(output, "\n\n", { trimempty = true })

    for _, block in ipairs(blocks) do
        ---@type Worktree
        local worktree = {}
        local is_bare = false

        -- Process each line in the block
        local lines = vim.split(block, "\n", { trimempty = true })
        for _, line in ipairs(lines) do
            if line:match("^worktree ") then
                worktree.path = vim.fs.normalize(line:match("^worktree (.+)"))
            elseif line:match("^branch ") then
                worktree.branch = line:match("^branch (.+)")
                worktree.name = worktree.branch:gsub("refs/heads/", "")
            elseif line:match("^HEAD ") then
                worktree.head = line:match("^HEAD (.+)")
            elseif line == "bare" then
                is_bare = true
            end
        end

        if worktree.path and not is_bare then
            worktrees[worktree.path] = worktree
        end
    end

    return worktrees
end

return M
