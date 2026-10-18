# Repository instructions

## Project

- `statusline.sh` is the statusline itself: it reads the Claude Code JSON payload on stdin and prints ANSI text. `install.sh` copies it into the Claude Code config folder, registers it in `settings.json`, and runs the style wizard. `README.md` documents every segment and option.
- Both scripts are pure Bash. Keep them working on macOS's `/bin/bash` 3.2 and on Linux: no associative arrays, `mapfile`, `${var,,}`, or other Bash 4+ features. Avoid GNU-only flags in `sed`, `grep`, `date`, and `awk`.
- `statusline.sh` runs every refresh tick, so keep it fast: no network calls, no new dependencies beyond Bash, git, awk, and standard POSIX tools. `install.sh` may also use curl and jq, or python3 when jq is missing.
- Never execute `statusline.conf`; read only known keys and sanitize their values, as the current parser does.
- Hide a segment when the payload or files it needs are missing instead of printing empty or placeholder pills.
- Code comments are in Spanish, like the existing ones. File, function, and segment names are short and in English.
- When you add or change a segment or option, update in the same change: `all_segments` in `statusline.sh`, `SEGMENTS` and `usage` in `install.sh`, and the tables in `README.md`.

## Validation

- Run `bash tests/run.sh` before committing. It checks syntax, renders mock payloads, and installs into a temporary config folder.
- Add a test to `tests/run.sh` for every new segment, option, or installer behavior.
- Never install into the real `~/.claude` to test. Point `CLAUDE_CONFIG_DIR` at a temporary folder and set `CLAUDE_STATUSLINE_CONFIG=/dev/null` so the user's style does not leak into renders.
- Do not start Claude Code sessions (`claude -p` or similar) to test a change: they spend paid API quota. Use mock JSON payloads and fake files instead.

## Git workflow

- Perform every task that may modify tracked files in an isolated Git worktree. If the current working directory is already a worktree, reuse it; creating a new worktree for each task is not necessary. Check its branch and status before editing, and preserve unrelated user changes. Never edit the primary checkout directly; create an isolated worktree when working from the primary checkout.
- If an isolated worktree cannot be created or used, stop and explain the blocker instead of falling back to the primary checkout.
- Worktrees are sibling working directories attached to the same repository; never create a worktree inside another worktree.
- Create every new branch as `feature/<name>`, where `<name>` is a short, descriptive, lowercase kebab-case slug.
- For an independent change, start the branch from the repository's current default branch unless the user explicitly selects another base.
- Never commit directly to `main` or another protected branch.
- Preserve unrelated user changes and do not rewrite remote history or force-push without explicit authorization.

## Commits and pull requests

- Use Conventional Commits for every commit: `<type>(<optional-scope>): <description>`.
- Plan commits by logical change group before staging files. Give each independently reviewable group its own focused commit; never bundle unrelated groups into one commit.
- When a PR contains multiple logical groups, keep separate commits for those groups, including implementation, configuration or CI changes, tests, and documentation when independently reviewable.
- Stage explicit paths or hunks for each group rather than staging all pending changes indiscriminately.
- Preserve the separate commits on the PR branch; do not squash them before review. The final PR integration still uses squash merge, producing one commit on the default branch.
- Apply this grouping to new commits without rewriting already published history unless explicitly authorized.
- Prefer these types: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `build`, `ci`, `chore`, and `revert`.
- Keep the subject concise and imperative. Mark breaking changes with `!` and a `BREAKING CHANGE:` footer when applicable.
- Use a Conventional Commit title for every pull request so it can become the final squash commit message.
- Always read and complete `.github/PULL_REQUEST_TEMPLATE.md` when creating or updating a pull request. Preserve its structure, fill applicable sections with accurate change and validation details, and remove optional sections only as the template permits. When using GitHub CLI, write the completed description to a file and pass it with `--body-file`; never replace the template with a free-form description.
- Include one relevant Gitmoji from the [official catalog](https://gitmoji.dev/) in every new commit subject and PR title, after the Conventional Commit prefix: `<type>(<optional-scope>): <gitmoji> <description>`. For example, `ci(checks): 👷 add shellcheck and render tests`. Keep the prefix intact so commits remain compatible with Conventional Commits.
- Integrate pull requests exclusively with squash merge. Do not use merge commits or rebase merge.
- Every squash commit on the default branch must end with its pull request reference, ` (#<number>)`, so the branch that produced it stays traceable from `git log`.
- Never pass `--subject` or `--body` to `gh pr merge --squash`. GitHub appends ` (#<number>)` only when it builds the subject from the pull request title; an explicit subject silently drops it.
- Before merging, check that the repository builds squash subjects from the pull request title: `gh api repos/{owner}/{repo} -q .squash_merge_commit_title` must print `PR_TITLE`. With `COMMIT_OR_PR_TITLE`, a pull request with a single commit takes that commit's message as the subject instead of the pull request title, so the ` (#<number>)` suffix is not guaranteed. Changing the setting needs the user's approval: `gh api -X PATCH repos/{owner}/{repo} -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=COMMIT_MESSAGES`.
- If the pull request title is not the message you want on the default branch, correct it with `gh pr edit --title` before merging, then merge without overriding the subject.
- Merge only after required checks and approvals pass and all conflicts and actionable review comments are resolved.
- After merging, verify that the new commit on the default branch carries its ` (#<number>)` suffix. Repairing a missing one means rewriting published history, which needs explicit authorization.

## Stacked pull requests

- Use a stacked pull request only when a change genuinely depends on another unmerged change. Keep independent changes based on the default branch.
- Keep every stack in one repository as a single linear chain. The bottom branch targets the stack trunk, and each higher branch starts from and targets the branch immediately below it.
- Give every stack layer its own focused `feature/<name>` branch, isolated sibling worktree, Conventional Commit history, and reviewable pull request.
- Never describe this as a “worktree on a worktree.” Create the higher worktree from the lower branch ref while keeping both worktree directories separate.
- When stack branches are checked out in separate worktrees, use `gh stack link` or the GitHub website to create or link the stack. Do not run `gh stack checkout`, `gh stack rebase`, or `gh stack sync` across branches held by other worktrees.
- Apply corrections to the lowest layer that owns the change, then update dependent layers in order and verify the resulting ancestry and diffs.
- Merge stacked pull requests from bottom to top using squash merge. After each merge, verify that GitHub correctly rebases or retargets the remaining stack before continuing.
