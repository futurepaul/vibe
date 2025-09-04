# Vibe

Inspired by [@justinmoon](https://github.com/justinmoon)'s setup but with less tmux.

**Git worktree automation with Claude Code integration**

Vibe streamlines your development workflow by automatically creating git worktrees for new features and launching Claude Code with your task description. No more manual branch management or remembering where you left off!

## Features

- 🚀 **Instant worktrees**: Create a new git worktree and branch with one command
- 🤖 **Claude Code integration**: Automatically launch Claude Code with your task
- 📝 **Interactive prompts**: Use your preferred editor to write task descriptions
- 🔀 **Smart merging**: Interactive worktree merging with conflict resolution
- 🌿 **Intelligent branching**: Branches from your current branch by default
- 🧹 **Cleanup tools**: List and clean up old worktrees

## Installation

### Prerequisites

- Git (with worktree support)
- [Claude Code](https://claude.ai/code) (optional but recommended)
- A Unix-like system (macOS, Linux, WSL)

### Install Script

1. **Clone or download** the vibe.sh script:
   ```bash
   # Option 1: Clone this repo
   git clone https://github.com/futurepaul/vibe.git
   cd vibe
   
   # Option 2: Download directly
   curl -O https://raw.githubusercontent.com/futurepaul/vibe/main/vibe.sh
   ```

2. **Make it executable**:
   ```bash
   chmod +x vibe.sh
   ```

3. **Link to your PATH** (so you can run `vibe` from anywhere):
   ```bash
   # Create symlink (adjust paths as needed)
   sudo ln -sf ~/path/to/vibe.sh /usr/local/bin/vibe
   
   # Or add to your shell PATH in ~/.bashrc or ~/.zshrc:
   export PATH="$PATH:~/path/to/vibe"
   ```

4. **Verify installation**:
   ```bash
   vibe --help
   ```

## Usage

### Quick Start

```bash
# In any git repository:
cd your-git-repo

# Create worktree with task description
vibe "add user authentication"

# Or use interactive mode (opens your $EDITOR)
vibe
```

### Commands

#### Create Worktree
```bash
# Create worktree from current branch
vibe "implement dark mode"

# Create worktree from specific branch
vibe "fix login bug" --from main

# Interactive mode - opens editor for task description
vibe
```

#### Manage Worktrees
```bash
# List all worktrees
vibe list

# Interactive merge between worktrees
vibe merge

# Clean up old worktrees
vibe clean

# Help
vibe --help
```

### How it Works

1. **Branch Detection**: Vibe automatically branches from your current branch (falls back to `master` → `main`)
2. **Worktree Creation**: Creates sibling directories (e.g., `../feature-branch/`)
3. **Claude Code Launch**: Opens Claude Code with your task description
4. **Shell Session**: After Claude Code exits, starts a shell in the worktree directory

### Example Workflow

```bash
# Start in your main project
cd ~/projects/my-app

# Create worktree for new feature
vibe "add shopping cart functionality"
# → Creates ../add-shopping-cart/ 
# → Launches Claude Code
# → After Claude Code exits, you're in the worktree directory

# Work on your feature...
git add .
git commit -m "implement shopping cart"

# Merge back to main branch
vibe merge
# → Interactive prompt to select target branch
# → Automatically handles rebasing and cleanup
```

## Configuration

### Environment Variables

- **`EDITOR`**: Your preferred editor (default: `nvim`)
- **`SHELL`**: Your shell (automatically detected)

### Customization

You can modify the script's behavior by editing these variables in `vibe.sh`:

- `WORKTREE_BASE`: Where worktrees are created (default: `../` - as siblings)
- Branch naming logic in the `generate_branch_name()` function

## Worktree Structure

Vibe creates worktrees as **siblings** to your main repository:

```
projects/
├── my-app/              # Your main repo
├── add-auth/            # Worktree for authentication feature
├── fix-bug-123/         # Worktree for bug fix  
└── refactor-api/        # Worktree for API refactor
```

This keeps your main repository clean while providing easy access to all feature branches.

## Claude Code Integration

If [Claude Code](https://claude.ai/code) is installed:
- Automatically launches with your task description
- Uses `--dangerously-skip-permissions` flag for seamless integration
- After Claude Code exits, drops you into a shell in the worktree

Without Claude Code:
- Simply creates the worktree and starts a shell session
- You can install Claude Code later and it will work automatically

## Troubleshooting

### Common Issues

**"Not in a git repository"**
- Make sure you're running vibe from inside a git repository

**"Could not create worktree"**
- Check that the parent directory is writable
- Ensure the branch you're trying to branch from exists

**Editor doesn't open in interactive mode**
- Check your `$EDITOR` environment variable: `echo $EDITOR`
- Set it if needed: `export EDITOR=vim` (or your preferred editor)

### Debug Mode

The script includes helpful logging that shows:
- Which branch it's branching from
- Where the worktree is being created
- Each step of the process

## Contributing

Contributions welcome! Please feel free to submit issues and pull requests.

## License

MIT License - feel free to modify and distribute.

---

**Happy coding with Vibe! 🎵**
