# claude-statusline

A Powerlevel10k-style statusline for [Claude Code](https://code.claude.com): rounded pills, usage bars, and session stats in three lines. Pure Bash.

<img src="assets/statusline.png" alt="claude-statusline: project, branch and PR, model and effort; context, 5-hour and weekly usage bars; session time, lines changed, cost and cache" width="900">

## What it shows

| Line | Segment | Meaning |
|---|---|---|
| 1 | Project | Folder of the session. It follows the worktree when you switch. |
| 1 | Branch | Branch and git counts, with p10k symbols: `⇡ahead ⇣behind +staged !modified ?untracked ~conflicts`. Green when clean, yellow with changes. Shown inside git worktrees. |
| 1 | PR | Open pull request of the branch: `✔` approved, `●` pending, `✘` changes requested, `✎` draft. |
| 1 | `/rename` | Reminder to name the session. It disappears once you run `/rename`. |
| 1 | Model · Effort | Model of the session, colored by family, and the reasoning effort. `󱐋` marks fast mode. |
| 2 | Context | Context window used. |
| 2 | Today | 5-hour usage limit and time until it resets. |
| 2 | Week | 7-day usage limit and time until it resets. |
| 3 | Time | Session duration. |
| 3 | Lines | Lines added and removed in the session, as a proportional bar, plus files changed in the repo. |
| 3 | Cost · Cache | Estimated session cost in USD and prompt-cache hit ratio. Grey with `󰜗` when the cache has gone cold. |

Usage bars turn green, yellow, and red at 60% and 80%. Pills wrap to new lines and spread across the full terminal width, like p10k.

## Requirements

- A [Nerd Font](https://www.nerdfonts.com/) in your terminal (for example, MesloLGS NF, the font Powerlevel10k recommends).
- Bash, git, and awk (preinstalled on macOS and Linux).
- A recent version of Claude Code. Segments whose data the payload does not include are hidden.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/sergiomorapardo/claude-statusline/main/install.sh | bash
```

The installer copies the script to `~/.claude/statusline.sh` and adds the `statusLine` block to `~/.claude/settings.json`. The rest of your settings stay as they are. It backs up any file it changes, and you can run it again to update. If you already have another statusline, it stops without changing anything. Add `--force` to replace it:

```bash
curl -fsSL https://raw.githubusercontent.com/sergiomorapardo/claude-statusline/main/install.sh | bash -s -- --force
```

It respects `CLAUDE_CONFIG_DIR` and needs `jq` or `python3` to edit the settings.

### Install with Claude Code

Paste this into Claude Code:

```text
Install the statusline from https://github.com/sergiomorapardo/claude-statusline following its README.
```

### Instructions for agents

If you are an AI agent installing this statusline for a user:

1. Run `curl -fsSL https://raw.githubusercontent.com/sergiomorapardo/claude-statusline/main/install.sh | bash`.
2. Check the exit code:
   - `0`: installed. Tell the user to send a message or restart Claude Code to see it.
   - `2`: the user already has another statusline. Nothing was changed. Show the user the command the installer printed and ask whether to replace it. Run again with `bash -s -- --force` only after the user says yes.
   - `1`: show the error to the user. Do not edit `settings.json` by hand to work around it.
3. Tell the user that the icons need a [Nerd Font](https://www.nerdfonts.com/) in their terminal. If they look like boxes or question marks, the terminal font is the cause.

### Manual install

Download the script:

```bash
curl -fsSL https://raw.githubusercontent.com/sergiomorapardo/claude-statusline/main/statusline.sh -o ~/.claude/statusline.sh
```

Add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh",
    "padding": 0,
    "refreshInterval": 2
  }
}
```

`refreshInterval` keeps the session time and the reset countdowns up to date between messages.

## How it works

Claude Code sends a JSON payload to the script on stdin. The script reads it with `grep` and `sed` (no `jq` needed) and calls `git status` on the session folder. It makes no network calls and reads the transcript only to detect whether the session has a custom name.

Comments in the script are in Spanish.

## License

[MIT](LICENSE) © Sergio A. Mora Pardo · [GitHub](https://github.com/sergiomorapardo) · [LinkedIn](https://www.linkedin.com/in/sergiomorapardo/)
