#!/usr/bin/env bash

# Vibe - Git worktree automation with Claude Code integration
# Usage: 
#   vibe "implement user authentication"  # Create worktree + launch Claude Code
#   vibe merge                            # Interactive merge between worktrees

set -euo pipefail

# Configuration - create worktrees as siblings to the current repo
readonly WORKTREE_BASE="../"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Show usage
usage() {
    cat << EOF
Usage: vibe [COMMAND] [OPTIONS]

Commands:
  vibe "task description"    Create worktree with Claude Code
  vibe merge                 Merge current worktree into another
  vibe list                  List all worktrees
  vibe clean                 Remove merged worktree folders

Options:
  -h, --help                Show this help
  --from BRANCH             Start worktree from specific branch (default: main)

Examples:
  vibe "add user authentication"
  vibe "fix login bug" --from develop
  vibe merge
EOF
}

# Error handling
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

# Check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        error "Not in a git repository"
    fi
}

# Generate branch name using Claude Code
generate_branch_name() {
    local task="$1"
    
    # Try to use Claude Code to generate a branch name
    if command -v claude >/dev/null 2>&1; then
        local branch_name
        branch_name=$(echo "Convert this task to a git branch name (kebab-case, 2-4 words, under 20 chars): $task" | \
            claude --output-format text 2>/dev/null | \
            tr -d '\n' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
        
        # Validate the generated name
        if [[ -n "$branch_name" && ${#branch_name} -le 20 && "$branch_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
            echo "$branch_name"
            return 0
        fi
    fi
    
    # Fallback to simple conversion
    echo "$task" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/--*/-/g' | cut -c1-20 | sed 's/-$//'
}

# Determine the best base branch to branch from
get_base_branch() {
    local specified_branch="$1"
    
    # If explicitly specified, use that
    if [[ -n "$specified_branch" ]]; then
        echo "$specified_branch"
        return 0
    fi
    
    # Try current branch first
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null)
    if [[ -n "$current_branch" ]]; then
        echo "$current_branch"
        return 0
    fi
    
    # Fallback to master, then main
    if git show-ref --verify --quiet refs/heads/master; then
        echo "master"
    elif git show-ref --verify --quiet refs/heads/main; then
        echo "main"
    else
        error "Could not determine base branch (no current branch, master, or main found)"
    fi
}

# Create worktree and launch Claude Code
create_worktree() {
    local task="$1"
    local specified_from_branch="$2"
    
    info "create_worktree called with task: '$task'"
    
    # Determine base branch
    local from_branch
    from_branch=$(get_base_branch "$specified_from_branch")
    info "Base branch determined: $from_branch"
    
    # Generate branch name
    local branch_name
    branch_name=$(generate_branch_name "$task")
    info "Generated branch name: $branch_name"
    
    info "Creating worktree: $branch_name (from $from_branch)"
    
    # Ensure worktree base directory exists
    mkdir -p "$WORKTREE_BASE"
    info "Created worktree base directory: $WORKTREE_BASE"
    
    local worktree_path="$WORKTREE_BASE/$branch_name"
    info "Worktree path will be: $worktree_path"
    
    # Check if branch already exists
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        info "Branch $branch_name already exists, adding worktree for it"
        # Branch exists, add worktree for it
        if ! git worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
            error "Could not create worktree for existing branch $branch_name"
        fi
    else
        info "Creating new branch $branch_name and worktree"
        # Create new branch and worktree
        if ! git worktree add -b "$branch_name" "$worktree_path" "$from_branch" 2>/dev/null; then
            error "Could not create new worktree and branch $branch_name"
        fi
    fi
    info "Worktree creation completed"
    
    # Change to worktree directory
    info "Changing to worktree directory: $worktree_path"
    cd "$worktree_path" || error "Could not change to worktree directory"
    info "Successfully changed to worktree directory"
    
    info "✅ Created worktree at: $worktree_path"
    info "📝 Task: $task"
    info "🌿 Current branch: $(git branch --show-current)"
    
    # Launch Claude Code with the task, then start shell in worktree
    if command -v claude >/dev/null 2>&1; then
        info "🤖 Starting Claude Code..."
        info "Executing: claude --dangerously-skip-permissions \"$task\""
        claude --dangerously-skip-permissions "$task"
        info "Claude Code session ended. Starting shell in worktree directory..."
    else
        warn "Claude Code not found. Install it to get AI assistance."
    fi
    
    # Start a new shell in the worktree directory
    exec $SHELL
}

# List all worktrees
list_worktrees() {
    check_git_repo
    
    echo "Git worktrees:"
    git worktree list --porcelain | awk '
        /^worktree/ { path = $2 }
        /^branch refs\/heads\// { 
            gsub(/^branch refs\/heads\//, "")
            printf "  %-20s %s\n", $0, path
        }
        /^detached/ { 
            printf "  %-20s %s (detached)\n", "HEAD", path
        }
    '
}

# Clean up merged worktree folders
clean_worktrees() {
    check_git_repo
    
    # Get list of worktrees that no longer exist as directories
    local stale_worktrees
    stale_worktrees=$(git worktree list --porcelain | awk '
        /^worktree/ { path = $2; getline; if (/^branch/) print path }
    ' | while read -r path; do
        if [[ ! -d "$path" ]]; then
            echo "$path"
        fi
    done)
    
    if [[ -n "$stale_worktrees" ]]; then
        info "Pruning stale worktree references..."
        git worktree prune
    fi
    
    # List worktrees that could be removed
    echo "Worktrees that might be safe to remove:"
    git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads/ | \
        grep '\[gone\]' | awk '{print $1}' | while read -r branch; do
        local worktree_path
        worktree_path=$(git worktree list --porcelain | awk -v branch="$branch" '
            /^worktree/ {path=$2} 
            /^branch refs\/heads\// {gsub(/^branch refs\/heads\//, ""); if($0==branch) print path}
        ')
        if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
            echo "  $branch -> $worktree_path"
        fi
    done
}

# Interactive merge between worktrees
merge_worktree() {
    check_git_repo
    
    local current_branch
    current_branch=$(git branch --show-current)
    
    if [[ -z "$current_branch" ]]; then
        error "You are in detached HEAD state. Cannot merge."
    fi
    
    info "Current branch: $current_branch"
    
    # List available target branches (excluding current)
    local available_branches
    available_branches=$(git worktree list --porcelain | awk '
        /^worktree/ {path=$2} 
        /^branch refs\/heads\// {
            gsub(/^branch refs\/heads\//, "")
            if ($0 != "'"$current_branch"'") print $0 ":" path
        }
    ')
    
    if [[ -z "$available_branches" ]]; then
        error "No other worktrees found to merge into"
    fi
    
    echo "Available branches to merge into:"
    echo "$available_branches" | nl -w2 -s') '
    
    # Get user selection
    echo -n "Select target branch number: "
    read -r selection
    
    local target_info
    target_info=$(echo "$available_branches" | sed -n "${selection}p")
    
    if [[ -z "$target_info" ]]; then
        error "Invalid selection"
    fi
    
    local target_branch="${target_info%%:*}"
    local target_path="${target_info##*:}"
    
    info "Merging $current_branch into $target_branch..."
    
    # Switch to target worktree
    info "Switching to target worktree: $target_path"
    cd "$target_path" || error "Could not change to target worktree"
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        git stash push -m "Auto-stash before merge $(date +%s)"
        local stashed=true
    fi
    
    # Attempt rebase
    if git rebase "$current_branch"; then
        info "✅ Merge successful!"
        
        # Restore stash if we created one
        if [[ "${stashed:-}" == "true" ]]; then
            if git stash list | grep -q "Auto-stash before merge"; then
                git stash pop
            fi
        fi
        
        # Offer to remove source worktree
        echo -n "Remove source worktree folder? (y/N): "
        read -r -n 1 remove_worktree
        echo
        
        if [[ "$remove_worktree" =~ ^[Yy]$ ]]; then
            local source_path
            source_path=$(git worktree list --porcelain | awk -v branch="$current_branch" '
                /^worktree/ {path=$2} 
                /^branch refs\/heads\// {gsub(/^branch refs\/heads\//, ""); if($0==branch) print path}
            ')
            
            if [[ -n "$source_path" && -d "$source_path" ]]; then
                git worktree remove "$source_path" 2>/dev/null || rm -rf "$source_path"
                info "Removed worktree: $source_path"
            fi
        fi
        
    else
        warn "❌ Conflicts detected!"
        info "Try running: claude 'resolve these git conflicts and continue the rebase'"
        info "After resolving, run: git rebase --continue"
        return 1
    fi
}

# Prompt user for task description using editor
prompt_for_task() {
    local editor="${EDITOR:-nvim}"
    info "Opening editor: $editor"
    local temp_file
    temp_file=$(mktemp)
    
    # Add helpful prompt to the temp file
    cat > "$temp_file" << 'EOF'
# Enter your task description below (lines starting with # are ignored)
# Examples:
#   add user authentication
#   fix the login bug
#   implement dark mode toggle

EOF
    
    # Open editor
    if ! "$editor" "$temp_file"; then
        rm -f "$temp_file"
        error "Editor exited with error"
    fi
    
    # Extract task from file (ignore comment lines and empty lines)
    local task
    task=$(grep -v '^#' "$temp_file" | grep -v '^[[:space:]]*$' | head -1)
    rm -f "$temp_file"
    
    if [[ -z "$task" ]]; then
        error "No task description provided"
    fi
    
    TASK_RESULT="$task"
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        info "Starting vibe with no arguments..."
        # Check git repo first, then prompt for task description
        check_git_repo
        info "Git repo check passed"
        info "About to call prompt_for_task..."
        prompt_for_task
        info "prompt_for_task completed, task result: '$TASK_RESULT'"
        create_worktree "$TASK_RESULT" ""
        return 0
    fi
    
    local from_branch=""
    local task=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                return 0
                ;;
            --from)
                from_branch="$2"
                shift 2
                ;;
            merge)
                merge_worktree
                return $?
                ;;
            list)
                list_worktrees
                return 0
                ;;
            clean)
                clean_worktrees
                return 0
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                if [[ -z "$task" ]]; then
                    task="$1"
                else
                    error "Multiple task descriptions provided"
                fi
                shift
                ;;
        esac
    done
    
    # If we have a task, create worktree
    if [[ -n "$task" ]]; then
        check_git_repo
        create_worktree "$task" "$from_branch"
    else
        usage
    fi
}

# Run main function
main "$@"
