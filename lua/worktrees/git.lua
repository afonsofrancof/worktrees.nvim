local M = {}

-- Get the git common directory
M.get_git_common_dir = function()
    local result = vim.system({ "git", "rev-parse", "--git-common-dir" }, { text = true }):wait()

    if result.code ~= 0 or result.stdout == "" then
        return nil
    end

    local git_dir = vim.trim(result.stdout)
    return vim.fs.normalize(vim.fn.fnamemodify(git_dir, ":p:h"))
end

-- Get the repository root (top-level directory of current worktree)
M.get_worktree_root = function()
    local result = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()

    if result.code ~= 0 or result.stdout == "" then
        return nil
    end

    local root = vim.trim(result.stdout)
    return vim.fs.normalize(vim.fn.fnamemodify(root, ":p:h"))
end

-- Get all worktrees (non-bare only)
M.get_worktrees = function()
    local result = vim.system({ "git", "worktree", "list", "--porcelain" }, { text = true }):wait()

    if result.code ~= 0 or result.stdout == "" then
        vim.notify("No git worktrees found", vim.log.levels.ERROR)
        return nil, 0
    end

    local output = result.stdout or ""
    local worktrees = {}
    local count = 0

    -- Split by double newlines to get blocks per worktree
    local blocks = vim.split(output, "\n\n", { trimempty = true })

    for _, block in ipairs(blocks) do
        local worktree = {}
        local is_bare = false

        -- Process each line in the block
        local lines = vim.split(block, "\n", { trimempty = true })
        for _, line in ipairs(lines) do
            if line:match("^worktree ") then
                worktree.path = line:match("^worktree (.+)")
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
            table.insert(worktrees, worktree)
            count = count + 1
        end
    end

    return worktrees, count
end

return M
