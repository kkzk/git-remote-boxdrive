# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`git-remote-boxdrive` is a single-file bash git remote helper (`boxdrive::<path>` URLs) that treats a Box Drive (or any synced) folder as a **plain file tree** remote. The remote folder holds only ordinary files — no `.git`, no bundles, no metadata. History lives only in local repos. Target environment is Git for Windows (git + bundled bash/find); no other dependencies may be introduced.

User-facing docs and code comments/messages are in Japanese; keep that convention.

## Commands

```bash
bash test.sh     # full test suite (uses a temp local folder in place of Box)
```

There is no build or lint step. Tests are a single sequential scenario script (sections `== 1.` … `== 12.`) with shared state between sections, so individual tests cannot be run in isolation — to debug one, comment out later sections or add `exit` after the relevant section. `test.sh` prepends the repo dir to `PATH` and sets an isolated `GIT_CONFIG_GLOBAL`, so it tests the working copy of `git-remote-boxdrive` directly.

`git-remote-boxdrive` must keep LF line endings and its executable bit. `install.cmd` / `uninstall.cmd` (double-click installers for non-technical users: copy to `%LOCALAPPDATA%\Programs\git-remote-boxdrive` and add it to the user `Path` via HKCU registry, preserving the value's type) are UTF-8 with `chcp 65001` and **must keep CRLF** — with LF, cmd misparses the Japanese lines. Editing them with `sed -i` in Git Bash can strip the CR; re-check with `file`. Line endings are pinned in `.gitattributes`.

## Architecture

The helper speaks the git remote-helper protocol on stdin/stdout (`capabilities` → `fetch`, `push`). Key design points that span several functions:

- **Snapshot model**: `snapshot_tree` hashes every file in the Box folder (`git hash-object -w --no-filters`, raw bytes, all mode `100644`) into a temporary index and `write-tree`s it. Comparison is by content hash, never mtime.
- **State ref**: the last known Box state is stored at `refs/box-state/<sha of BOX_DIR path>` (keyed by folder, not remote name).
- **list**: if the current Box tree differs from the state ref's tree, a synthetic commit ("Box snapshot", author `box`, parent = previous state) is created and advertised as `refs/heads/$BRANCH`. Objects are written during `list`, so the `fetch` command is a no-op.
- **push** (`push_one`), in order:
  1. Reject with `fetch first` if the Box tree ≠ state ref tree (Box changed since last pull/push) — the core requirement.
  2. Reject non-fast-forward unless `+` (force).
  3. Apply only the `diff-tree` between Box tree and source tree; writes go to `*.boxgit-tmp.$$` then `mv`. Paths are validated with `safe_path` before any write.
  4. Re-snapshot and verify it equals the pushed tree; only then update the state ref.
- Only one branch exists on the remote (`main`, overridable via `BOX_BRANCH`). Pushes to other refs and ref deletions are rejected.
- `is_ignored` lists OS/Box junk files excluded from snapshots (`.DS_Store`, `desktop.ini`, `Thumbs.db`, `~$*`, `*.boxgit-tmp.*`, `.~lock.*#`, `.git/`). Exec bits, symlinks, empty dirs, and filenames with newlines are not preserved.
- `GIT_DIR` is made absolute at startup because the helper `cd`s into the Box folder.

## Known limitations (by design)

No locking/CAS on Box, so near-simultaneous pushes can race (post-push verification attempts to detect it). Every `list` rescans the whole folder, so very large trees are slow. Line endings are stored byte-for-byte; README recommends `.gitattributes` with `* text=auto eol=lf`.
