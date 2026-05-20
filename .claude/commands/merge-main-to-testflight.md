# Merge Main into TestFlight Beta

Merge the current `main` branch into `testflight-beta`, resolving any merge conflicts by preferring changes from `main`.

## Instructions

Perform the following steps to merge `main` into `testflight-beta`:

1. **Ensure a clean working tree**
   - Run `git status` to check for uncommitted changes.
   - If there are uncommitted changes, **stop and inform the user**. Do not stash or discard anything automatically.

2. **Fetch the latest remote state**
   ```
   git fetch origin
   ```

3. **Check out testflight-beta**
   ```
   git checkout testflight-beta
   git pull origin testflight-beta
   ```

4. **Merge main into testflight-beta, preferring main on conflicts**
   ```
   git merge main -X theirs -m "Merge main into testflight-beta"
   ```
   The `-X theirs` strategy option automatically resolves conflicts by taking the `main` (incoming) side.

5. **Verify the merge succeeded**
   - Run `git status` to confirm there are no remaining conflicts.
   - If somehow conflicts remain (e.g., delete/modify conflicts that `-X theirs` doesn't auto-resolve):
     - For each conflicted file, resolve by accepting the `main` version:
       ```
       git checkout --theirs <file>
       git add <file>
       ```
     - After all conflicts are resolved, complete the merge:
       ```
       git commit --no-edit
       ```

6. **Push the updated testflight-beta branch**
   ```
   git push origin testflight-beta
   ```

7. **Return to the previous branch**
   ```
   git checkout main
   ```

8. **Report the result**
   - Summarize what was merged (e.g., number of commits, any conflicts that were resolved).
   - If any conflicts were auto-resolved via `-X theirs`, list the affected files so the user is aware.
