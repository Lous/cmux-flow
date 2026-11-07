# cmux-flow

**cmux-flow is an unofficial fork of [cmux](https://github.com/manaflow-ai/cmux)**, the
macOS terminal by Manaflow, Inc. It is not affiliated with or endorsed by Manaflow.
"cmux" is Manaflow's name; this fork uses "cmux-flow" only to say where it comes from,
and ships its own icon.

Maintained by [Lous](https://github.com/Lous). Modified from cmux
[`be5e243`](https://github.com/manaflow-ai/cmux/commit/be5e24339c6eabb8e929a7029c4e6f834e257c97)
on 2026-11-07.

## Why

Agent-driven work often spans several repositories in one workspace. cmux-flow lets you
review every project's branch, changed files and diffs without leaving the terminal for
an editor.

## What this fork adds

- **Git tab in the right sidebar** (open the sidebar with ⌘⌥B, then the Git tab):
  - every Git repository the workspace touches, from the workspace folder and from each
    terminal's directory, remembered per workspace across restarts;
  - branch, ahead/behind, and staged / changes / merge-conflict entries with
    VS Code-style status letters and line counts;
  - live refresh as files change;
  - stage, unstage and discard files from hover buttons or the context menu, or a
    whole section at once; discarding asks first and moves new files to the Trash;
  - click a file to see its diff in a reusable preview tab, or open the whole working
    tree, staged changes, or the branch against its base.
- **Diff viewer**:
  - "Show in Files" on each file opens the Files tab with that file selected;
  - diffs opened from the Git tab reopen with the new colors after a theme change, and
    every diff keeps an opaque background so its colors stay readable;
  - the line numbers stay solid while long lines scroll sideways.
- **Git-aware Files explorer**:
  - git status for workspaces rooted at a folder of repositories;
  - status letters (M/A/D/R/U), a dot on changed folders, untracked files in green;
  - live refresh without reloading the tree, so it no longer flickers while terminals
    create or delete files, and a fix for decorations that never reached top-level
    rows or collapsed folders when git status arrived after the tree was shown.

## How it differs from cmux

| | cmux | cmux-flow |
|---|---|---|
| App name / bundle id | cmux / `com.cmuxterm.app` | cmux-flow / `io.github.lous.cmux-flow` |
| URL scheme | `cmux://` | `cmux-flow://` |
| Control socket | `~/.local/state/cmux/cmux.sock` | `/tmp/cmux-fork-<bundle-id>.sock` |
| Crash reports and analytics | Sentry and PostHog (opt-out in Settings) | **none** — never sent to Manaflow |
| Remote feature flags | fetched from Manaflow | none; every flag uses its local default |
| Auto-update | Sparkle, from cmux releases | **off**; install new releases of this fork |
| Cloud network extension | included | removed (needs Manaflow's signing identity) |
| Computer Use helper | included | removed (would share cmux's helper identity) |

Both apps can be installed and open at the same time. Things they still share:

- your settings file, `~/.config/cmux/cmux.json`, and your Ghostty config;
- account and Cloud features, which talk to Manaflow's services under
  [their terms](https://cmux.com) and may not work in this fork.

Some interface text still says "cmux".

## Install

1. Download the `.dmg` from this repository's Releases and drag cmux-flow to Applications.
2. The app is ad-hoc signed, not notarized. The first time, right-click cmux-flow in
   Applications and choose **Open**, then confirm.

## Build from source

Prerequisites: Xcode 26 or later (plus `xcodebuild -downloadComponent MetalToolchain`),
Zig 0.16 (`brew install zig@0.16`), Rust via [rustup](https://rustup.rs), and bun.

```bash
git clone --recursive https://github.com/Lous/cmux.git cmux-flow
cd cmux-flow
./scripts/setup.sh
./scripts/fork/build-release.sh              # Apple silicon; add --universal for Intel too
```

The app and DMG land in `dist/`. The first build takes 30–60 minutes.

For development, tagged Debug builds run beside any installed app:

```bash
CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag my-change
open ~/Library/Developer/Xcode/DerivedData/cmux-my-change/Build/Products/Debug/"cmux DEV my-change.app"
```

## Keeping up with cmux

```bash
git remote add upstream https://github.com/manaflow-ai/cmux.git
git fetch upstream
git merge upstream/main
python3 scripts/wire-app-sources.py   # re-wire this fork's new files if project.pbxproj conflicted
```

The fork's own pieces live in `Sources/SourceControl*.swift`,
`Sources/FileExplorerGitStatusWatcher.swift`, `scripts/fork/` and this file, so merges
rarely conflict.

## License

Same as cmux: the macOS app, CLI and the rest of this repository are licensed under the
GNU General Public License v3.0 or later (see [LICENSE](LICENSE)), except the server
directories that LICENSE lists, which remain under the Business Source License 1.1 and
are unchanged here. Copyright in cmux remains with Manaflow, Inc. and its contributors;
this fork's changes are offered under the same GPL terms.
