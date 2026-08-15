# Merge TestFlight Beta into Store Build

Merge the current `testflight-beta` branch into `store-build`, resolving any merge conflicts by preferring changes from `testflight-beta`. After a successful merge, switch back to `main` and bump the patch version to prepare for the next development cycle.

## Instructions

Perform the following steps:

---

### Part 1: Merge testflight-beta → store-build

1. **Ensure a clean working tree**
   - Run `git status` to check for uncommitted changes.
   - If there are uncommitted changes, **stop and inform the user**. Do not stash or discard anything automatically.

2. **Fetch the latest remote state**
   ```
   git fetch origin
   ```

3. **Check out store-build**
   ```
   git checkout store-build
   git pull origin store-build
   ```

4. **Merge testflight-beta into store-build, preferring testflight-beta on conflicts**
   ```
   git merge testflight-beta -X theirs -m "Merge testflight-beta into store-build"
   ```
   The `-X theirs` strategy option automatically resolves conflicts by taking the `testflight-beta` (incoming) side.

5. **Verify the merge succeeded**
   - Run `git status` to confirm there are no remaining conflicts.
   - If somehow conflicts remain (e.g., delete/modify conflicts that `-X theirs` doesn't auto-resolve):
     - For each conflicted file, resolve by accepting the `testflight-beta` version:
       ```
       git checkout --theirs <file>
       git add <file>
       ```
     - After all conflicts are resolved, complete the merge:
       ```
       git commit --no-edit
       ```

6. **Push the updated store-build branch**
   ```
   git push origin store-build
   ```

---

### Part 2: Bump version on main for next release cycle

7. **Check out main**
   ```
   git checkout main
   git pull origin main
   ```

8. **Read the current version** from `GymStreak.xcodeproj/project.pbxproj`
   - Find the current `MARKETING_VERSION` value (e.g., `1.2.3`).
   - Compute the new version by incrementing the **patch** component by 1 (e.g., `1.2.3` → `1.2.4`).

9. **Update MARKETING_VERSION in project.pbxproj**
   - Replace **all** occurrences of `MARKETING_VERSION = <old>;` with `MARKETING_VERSION = <new>;` across all production targets and configurations. There are typically 6 occurrences (3 targets × 2 configurations: GymStreak, GymStreakWidgetsExtension, GymStreakWatch Watch App — each for Debug and Release).
   - **Do not** change the version in test targets (e.g., `GymStreakUITests`).

9b. **Update CURRENT_PROJECT_VERSION (the build number) in the same file**
   - Read the current `CURRENT_PROJECT_VERSION` of the production targets (e.g. `1000`) and increment it by 1 → `<new-build>`.
   - Replace it at the **same 6** production sites only. The test targets (`GymStreakTests`, `GymStreakUITests`, `GymStreakWatchTests`) stay at `CURRENT_PROJECT_VERSION = 1`.
   - **Never skip this and never let the production build number fall below `1000`.** The Founder grant (`docs/pro-subscription.md`) permanently grants Pro, free, to every install reporting an original build below `FounderStatusService.cutoffBuild` (`1000`). Shipping a build below the cutoff silently grants Founder to every new paying user, and the only visible symptom is missing revenue. If the value read is below `1000`, stop and tell the user.

10. **Archive release notes into CHANGELOG.md**
    - Read the contents of `TestFlight/WhatToTest.en-US.txt`.
    - If `CHANGELOG.md` does not exist, create it with a header: `# Changelog`
    - Prepend a new version section at the top of the changelog (below the `# Changelog` header) using Keep a Changelog format:
      ```
      ## [<old-version>] - <YYYY-MM-DD>

      ### Added / Improved / Fixed
      <contents from WhatToTest.en-US.txt>
      ```
    - Categorize each bullet under the appropriate subsection (`Added`, `Improved`, or `Fixed`) based on its content.

11. **Clear the WhatToTest files** for the next release cycle
    - Overwrite `TestFlight/WhatToTest.en-US.txt` with an empty file.
    - Overwrite `TestFlight/WhatToTest.de-DE.txt` with an empty file.

12. **Commit the version bump**
    ```
    git add GymStreak.xcodeproj/project.pbxproj CHANGELOG.md TestFlight/WhatToTest.en-US.txt TestFlight/WhatToTest.de-DE.txt
    git commit -m "Bump version to <new-version> for next release cycle"
    ```

13. **Push main**
    ```
    git push origin main
    ```

---

### Part 3: Report

14. **Report the result**
    - Summarize the merge (number of commits, any conflicts resolved).
    - State the version bump: `<old-version>` → `<new-version>`, and the build bump: `<old-build>` → `<new-build>`.
    - Confirm the WhatToTest files were archived and cleared.
    - If any conflicts were auto-resolved via `-X theirs`, list the affected files.
