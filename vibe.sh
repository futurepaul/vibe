#!/usr/bin/env bash

set -euo pipefail

readonly WORKTREE_BASE="../"

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

usage() {
    cat << EOF
Usage: vibe [COMMAND] [OPTIONS]

Commands:
  vibe "task description"    Create worktree with Claude Code
  vibe merge                 Merge current worktree into another
  vibe list                  List all worktrees
  vibe clean                 Remove merged worktree folders
  vibe check [red|yellow|green] Show line counts for source files

Options:
  -h, --help                Show this help
  --from BRANCH             Start worktree from specific branch (default: main)

Examples:
  vibe "add user authentication"
  vibe "fix login bug" --from develop
  vibe merge
EOF
}

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

check_git_repo() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        error "Not in a git repository"
    fi
}

# Generate branch name using Claude Code, fallback to simple conversion
generate_branch_name() {
    local task="$1"
    
    # Try to use Claude Code for intelligent branch naming
    if command -v claude >/dev/null 2>&1; then
        local branch_name
        branch_name=$(echo "Convert this task to a git branch name (kebab-case, 2-4 words, under 20 chars): $task" | \
            claude --output-format text 2>/dev/null | \
            tr -d '\n' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
        
        # Validate generated name meets git branch requirements
        if [[ -n "$branch_name" && ${#branch_name} -le 20 && "$branch_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
            echo "$branch_name"
            return 0
        fi
    fi
    
    # Fallback: simple task-to-branch conversion
    echo "$task" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/--*/-/g' | cut -c1-20 | sed 's/-$//'
}


get_base_branch() {
    local specified_branch="$1"
    
    if [[ -n "$specified_branch" ]]; then
        echo "$specified_branch"
        return 0
    fi
    
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null)
    if [[ -n "$current_branch" ]]; then
        echo "$current_branch"
        return 0
    fi
    
    if git show-ref --verify --quiet refs/heads/master; then
        echo "master"
    elif git show-ref --verify --quiet refs/heads/main; then
        echo "main"
    else
        error "Could not determine base branch (no current branch, master, or main found)"
    fi
}

create_worktree() {
    local task="$1"
    local specified_from_branch="$2"
    
    info "create_worktree called with task: '$task'"
    
    local from_branch
    from_branch=$(get_base_branch "$specified_from_branch")
    info "Base branch determined: $from_branch"
    local branch_name
    branch_name=$(generate_branch_name "$task")
    info "Generated branch name: $branch_name"
    
    info "Creating worktree: $branch_name (from $from_branch)"
    
    mkdir -p "$WORKTREE_BASE"
    info "Created worktree base directory: $WORKTREE_BASE"
    
    local worktree_path="$WORKTREE_BASE/$branch_name"
    info "Worktree path will be: $worktree_path"
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        info "Branch $branch_name already exists, adding worktree for it"
        
        if ! git worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
            error "Could not create worktree for existing branch $branch_name"
        fi
    else
        info "Creating new branch $branch_name and worktree"
        
        if ! git worktree add -b "$branch_name" "$worktree_path" "$from_branch" 2>/dev/null; then
            error "Could not create new worktree and branch $branch_name"
        fi
    fi
    
    info "Worktree creation completed"
    
    info "Changing to worktree directory: $worktree_path"
    cd "$worktree_path" || error "Could not change to worktree directory"
    info "Successfully changed to worktree directory"
    
    info "✅ Created worktree at: $worktree_path"
    info "📝 Task: $task"
    info "🌿 Current branch: $(git branch --show-current)"
    if command -v claude >/dev/null 2>&1; then
        info "🤖 Starting Claude Code..."
        info "Executing: claude --dangerously-skip-permissions \"$task\""
        claude --dangerously-skip-permissions "$task"
        info "Claude Code session ended. Starting shell in worktree directory..."
    else
        warn "Claude Code not found. Install it to get AI assistance."
    fi
    
    exec $SHELL
}

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

clean_worktrees() {
    check_git_repo
    
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

check_files() {
    check_git_repo
    local filter="$1"
    
    if [[ -n "$filter" ]]; then
        info "🔍 Checking $filter files..."
    else
        info "🔍 Checking line counts for all tracked files..."
    fi
    # Process all git-tracked files for line counting, excluding binary assets
    # Use git pathspec excludes (case-insensitive) for robustness
    git ls-files -- ':(exclude,icase)*.png' ':(exclude,icase)*.jpg' ':(exclude,icase)*.jpeg' ':(exclude,icase)*.gif' ':(exclude,icase)*.pdf' | while read -r file; do
        if [[ -f "$file" ]]; then
            local lines
            lines=$(wc -l < "$file" 2>/dev/null || echo "0")
            # Categorize file by line count with color coding
            local category=""
            local output=""
            
            if (( lines > 500 )); then
                category="red"    # Critical: needs refactoring
                output="${RED}%4d${NC} %s ⚠️\n"
            elif (( lines > 400 )); then
                category="yellow" # Warning: consider refactoring
                output="${YELLOW}%4d${NC} %s ⚡\n"
            else
                category="green"  # Good: manageable size
                output="${GREEN}%4d${NC} %s\n"
            fi
            if [[ -z "$filter" || "$filter" == "$category" ]]; then
                printf "$output" "$lines" "$file"
            fi
        fi
    done | sort -rn
}

merge_worktree() {
    check_git_repo
    
    local current_branch
    current_branch=$(git branch --show-current)
    
    if [[ -z "$current_branch" ]]; then
        error "You are in detached HEAD state. Cannot merge."
    fi
    
    info "Current branch: $current_branch"
    local available_branches
    # Find all worktrees except current one for merge targets
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
    info "Switching to target worktree: $target_path"
    cd "$target_path" || error "Could not change to target worktree"
    # Stash uncommitted changes before merge
    if ! git diff-index --quiet HEAD --; then
        git stash push -m "Auto-stash before merge $(date +%s)"
        local stashed=true
    fi
    if git merge "$current_branch"; then
        info "✅ Merge successful!"
        # Restore stashed changes after successful merge
        if [[ "${stashed:-}" == "true" ]]; then
            if git stash list | grep -q "Auto-stash before merge"; then
                git stash pop
            fi
        fi
        echo -n "Remove source worktree folder? (y/N): "
        read -r -n 1 remove_worktree
        echo
        
        if [[ "$remove_worktree" =~ ^[Yy]$ ]]; then
            local source_path
            # Find the filesystem path of the source worktree to remove
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
        info "Try running: claude 'resolve these git conflicts and complete the merge'"
        info "After resolving, run: git commit"
        return 1
    fi
}

prompt_for_task() {
    local editor="${EDITOR:-nvim}"
    info "Opening editor: $editor"
    
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
# Enter your task description below (lines starting with # are ignored)
# Examples:
#   add user authentication
#   fix the login bug
#   implement dark mode toggle

EOF
    if ! "$editor" "$temp_file"; then
        rm -f "$temp_file"
        error "Editor exited with error"
    fi
    
    local task
    # Extract non-comment, non-empty lines as task description
    task=$(grep -v '^#' "$temp_file" | grep -v '^[[:space:]]*$' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
    rm -f "$temp_file"
    
    if [[ -z "$task" ]]; then
        error "No task description provided"
    fi
    
    TASK_RESULT="$task"
}

main() {
    if [[ $# -eq 0 ]]; then
        info "Starting vibe with no arguments..."
        
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
    
    # Parse command line arguments
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
            check)
                shift
                check_files "${1:-}"
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
    
    if [[ -n "$task" ]]; then
        check_git_repo
        create_worktree "$task" "$from_branch"
    else
        usage
    fi
}


main "$@"


