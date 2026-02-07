---
name: commit
description: Analyze staged and unstaged changes, stage them if needed, and create a conventional commit message
disable-model-invocation: true
---

# Smart Commit Command

Analyze git changes, stage them if necessary, and create a conventional commit message.

## Process

1. **Check git status** with `git status --short`
   - If there are unstaged changes, ask user if they want to stage all or specific files
   - If user confirms, run `git add <files>` or `git add .`
   - If nothing to commit, inform user

2. **Analyze changes** with `git diff --cached` (for staged) and `git diff` (for unstaged if needed)

3. **Determine commit type** based on changes:
   - `feat`: new features or functionality
   - `fix`: bug fixes
   - `chore`: maintenance, dependencies, config
   - `docs`: documentation changes
   - `refactor`: code restructuring
   - `style`: formatting changes
   - `test`: test-related changes
   - `perf`: performance improvements

4. **Generate description** (max 50 chars):
   - Use imperative mood ("add" not "added")
   - Lowercase
   - No period at end
   - Be specific but brief

5. **Present the commit message to user using ask_user_input tool**:
   - Show the generated message in a clear format
   - Provide exactly two options:
     1. "Yes, commit with this message"
     2. "Change commit message"
   - If user selects option 1: Proceed to step 6
   - If user selects option 2: Ask user to provide the new description part (the part after "type: ") and regenerate the full message, then return to this step

6. **After user approval**, execute commit: `git commit -m "type: description"`
   - **IMPORTANT**: Use ONLY the commit message format approved by user
   - **DO NOT** add Co-Authored-By, Signed-off-by, or any other trailers
   - **DO NOT** add multiple lines or body text unless explicitly requested
   - Keep it as a single line: `type: description`

7. **Confirm success** and show the commit hash

## Commit Message Format

**Correct format (single line only):**

```
feat: add ePaper bookmarks feature
```

**INCORRECT formats (do not use):**

```
feat: add ePaper bookmarks feature

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

## User Interaction Flow

```
1. User: /commit
2. Claude: Analyzes changes
3. Claude: Shows generated message: "feat: add ePaper bookmarks feature"
4. Claude: Uses ask_user_input with two options:
   - "Yes, commit with this message"
   - "Change commit message"
5a. If "Yes": Execute git commit
5b. If "Change": Prompt for new description, regenerate, return to step 4
6. Claude: "Committed successfully as abc123f"
```

## Examples

- `feat: add user authentication middleware`
- `fix: resolve memory leak in websocket handler`
- `chore: update dependencies to latest versions`
- `docs: update API documentation`

## Workflow Scenarios

**Scenario A: Nothing staged, but unstaged changes exist**

1. Show what would be staged
2. Ask: "Stage all changes and commit?" or "Select specific files?"
3. Stage and proceed

**Scenario B: Some files already staged**

1. Show staged changes
2. Ask if user wants to include unstaged changes too
3. Proceed with commit

**Scenario C: Everything already staged**

1. Analyze and commit directly

## Error Handling

- If working directory is clean: "Nothing to commit"
- If in detached HEAD state: Warn user before committing
- If merge conflict exists: Inform user to resolve conflicts first
- If user wants to change message: Keep the commit type, only ask for new description part
