# WitchLeash → KeepYourHead rename — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the `WitchLeash` mod to `KeepYourHead` across filesystem layout, file contents, and the repo README. Display name shown in-game becomes "Keep Your Head".

**Architecture:** Mechanical rename in three commits. Commit 1 moves the files (`git mv` preserves history); the mod is internally broken at this point because the file contents still reference the old name. Commit 2 substitutes every identifier inside the moved files, restoring the mod. Commit 3 updates the README. A final manual verification step covers the game-dir symlink and in-game smoke test.

**Tech Stack:** Lua (DMF — Darktide Mod Framework), Windows filesystem, git.

**Scope notes:**
- The design spec references `docs/superpowers/plans/2026-05-07-ghostrunner-v0.md` (line 130 mentions `WitchLeash` parenthetically). That file is NOT in this worktree's HEAD — it's a staged change on the parent branch. Out of scope for this plan; will be reconciled by the user when the rename merges back.
- All paths in this plan are relative to the worktree root.
- Windows filesystem is case-insensitive but git tracks PascalCase here; the source-of-truth path inside the worktree is `WitchLeash/` (capital `L`).

---

## Task 1: Filesystem renames via `git mv`

**Files (renames only — contents change in Task 2):**
- Rename: `WitchLeash/` → `KeepYourHead/`
- Rename: `KeepYourHead/WitchLeash.mod` → `KeepYourHead/KeepYourHead.mod`
- Rename: `KeepYourHead/scripts/mods/WitchLeash/` → `KeepYourHead/scripts/mods/KeepYourHead/`
- Rename: `KeepYourHead/scripts/mods/KeepYourHead/WitchLeash.lua` → `…/KeepYourHead.lua`
- Rename: `…/WitchLeash_data.lua` → `…/KeepYourHead_data.lua`
- Rename: `…/WitchLeash_localization.lua` → `…/KeepYourHead_localization.lua`
- Rename: `…/HudElementWitchLeashWarning.lua` → `…/HudElementKeepYourHeadWarning.lua`

- [ ] **Step 1: Confirm starting state**

Run:
```bash
git status
git ls-files WitchLeash/
```

Expected: working tree clean (only the spec commit is ahead of main); `git ls-files` shows 5 files under `WitchLeash/`.

- [ ] **Step 2: Rename the top-level folder**

Run:
```bash
git mv WitchLeash KeepYourHead
```

- [ ] **Step 3: Rename the inner `scripts/mods/` folder**

Run:
```bash
git mv KeepYourHead/scripts/mods/WitchLeash KeepYourHead/scripts/mods/KeepYourHead
```

- [ ] **Step 4: Rename the `.mod` file**

Run:
```bash
git mv KeepYourHead/WitchLeash.mod KeepYourHead/KeepYourHead.mod
```

- [ ] **Step 5: Rename the four Lua files inside `scripts/mods/KeepYourHead/`**

Run:
```bash
git mv KeepYourHead/scripts/mods/KeepYourHead/WitchLeash.lua              KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead.lua
git mv KeepYourHead/scripts/mods/KeepYourHead/WitchLeash_data.lua         KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_data.lua
git mv KeepYourHead/scripts/mods/KeepYourHead/WitchLeash_localization.lua KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_localization.lua
git mv KeepYourHead/scripts/mods/KeepYourHead/HudElementWitchLeashWarning.lua KeepYourHead/scripts/mods/KeepYourHead/HudElementKeepYourHeadWarning.lua
```

- [ ] **Step 6: Verify the rename**

Run:
```bash
git status --short
```

Expected output (six `R` lines, one per rename — order may vary):
```
R  WitchLeash/WitchLeash.mod -> KeepYourHead/KeepYourHead.mod
R  WitchLeash/scripts/mods/WitchLeash/HudElementWitchLeashWarning.lua -> KeepYourHead/scripts/mods/KeepYourHead/HudElementKeepYourHeadWarning.lua
R  WitchLeash/scripts/mods/WitchLeash/WitchLeash.lua -> KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead.lua
R  WitchLeash/scripts/mods/WitchLeash/WitchLeash_data.lua -> KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_data.lua
R  WitchLeash/scripts/mods/WitchLeash/WitchLeash_localization.lua -> KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_localization.lua
```

Also verify no untracked stragglers:
```bash
ls WitchLeash/ 2>/dev/null
```
Expected: directory does not exist (no output, exit code 2).

- [ ] **Step 7: Commit the rename**

Run:
```bash
git commit -m "$(cat <<'EOF'
refactor: rename WitchLeash directory tree to KeepYourHead

Pure path rename — file contents still reference the old identifier and
will be substituted in the next commit. The mod is non-functional between
these two commits and that is intentional.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Substitute identifiers inside renamed files

**Files:**
- Modify: `KeepYourHead/KeepYourHead.mod`
- Modify: `KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead.lua`
- Modify: `KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_data.lua`
- Modify: `KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_localization.lua`
- Modify: `KeepYourHead/scripts/mods/KeepYourHead/HudElementKeepYourHeadWarning.lua`

- [ ] **Step 1: Edit `KeepYourHead.mod`**

File path: `KeepYourHead/KeepYourHead.mod`

Final contents (replace the file entirely):
```lua
return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`KeepYourHead` encountered an error loading the Darktide Mod Framework.")

		new_mod("KeepYourHead", {
			mod_script       = "KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead",
			mod_data         = "KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_data",
			mod_localization = "KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_localization",
		})
	end,
	packages = {},
}
```

- [ ] **Step 2: Edit `KeepYourHead_data.lua` — top of file only**

In file `KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_data.lua`:

Replace:
```lua
local mod = get_mod("WitchLeash")
```
With:
```lua
local mod = get_mod("KeepYourHead")
```

Leave the rest of the file unchanged.

- [ ] **Step 3: Edit `KeepYourHead_localization.lua` — display name only**

In file `KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_localization.lua`:

Replace:
```lua
	mod_name = {
		en = "Witch Leash",
	},
```
With:
```lua
	mod_name = {
		en = "Keep Your Head",
	},
```

Leave every other localization entry unchanged (the per-setting keys like `peril_threshold`, `group_blocking`, etc. are internal and don't change).

- [ ] **Step 4: Edit `KeepYourHead.lua` — six discrete replacements**

In file `KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead.lua`:

**4a.** Replace:
```lua
local mod = get_mod("WitchLeash")
```
With:
```lua
local mod = get_mod("KeepYourHead")
```

**4b.** In the comment block above `debug_log`, replace the substring `search for "WitchLeash"` with `search for "KeepYourHead"`. Full surrounding context for uniqueness — replace:
```
-- newest file and search for "WitchLeash". pcall guards in case `print` is
```
With:
```
-- newest file and search for "KeepYourHead". pcall guards in case `print` is
```

**4c.** Replace inside `debug_log`:
```lua
	pcall(print, "[WitchLeash] " .. line)
```
With:
```lua
	pcall(print, "[KeepYourHead] " .. line)
```

**4d.** Replace inside the force-staff-fire diagnostic `debug_log` call:
```lua
					"[WitchLeash] force-staff-fire weapon=%s allow=%s inferno=%s vent_match=%s combat=%s cooldown=%s duration=%s peril=%.3f",
```
With:
```lua
					"[KeepYourHead] force-staff-fire weapon=%s allow=%s inferno=%s vent_match=%s combat=%s cooldown=%s duration=%s peril=%.3f",
```

**4e.** Replace inside the action-dump `debug_log` call:
```lua
		"[WitchLeash] action=%s peril=%.3f weapon=%s combat=%s grenade=%s",
```
With:
```lua
		"[KeepYourHead] action=%s peril=%.3f weapon=%s combat=%s grenade=%s",
```

**4f.** Replace the HUD element registration block:
```lua
mod:register_hud_element({
	class_name = "HudElementWitchLeashWarning",
	filename = "WitchLeash/scripts/mods/WitchLeash/HudElementWitchLeashWarning",
```
With:
```lua
mod:register_hud_element({
	class_name = "HudElementKeepYourHeadWarning",
	filename = "KeepYourHead/scripts/mods/KeepYourHead/HudElementKeepYourHeadWarning",
```

**4g.** Replace the HUD element lookup in `mod.update`:
```lua
	local element = hud:element("HudElementWitchLeashWarning")
```
With:
```lua
	local element = hud:element("HudElementKeepYourHeadWarning")
```

- [ ] **Step 5: Edit `HudElementKeepYourHeadWarning.lua` — rename class and scenegraph id**

In file `KeepYourHead/scripts/mods/KeepYourHead/HudElementKeepYourHeadWarning.lua`:

This file is small and every occurrence of `WitchLeash`/`witch_leash` should be replaced. The mechanical substitution rules:
- `witch_leash_warning_area` → `keep_your_head_warning_area` (appears twice — scenegraph definition key on line 9, scenegraph id string on line 37)
- `HudElementWitchLeashWarning` → `HudElementKeepYourHeadWarning` (appears eight times across class declaration, method declarations, super call, and the `return` line)

After the replacements, the file should contain zero hits for `WitchLeash` or `witch_leash` (case-insensitive).

- [ ] **Step 6: Verify zero remaining old identifiers in `KeepYourHead/`**

Run from the worktree root:
```bash
git grep -in -E 'witchleash|witch_leash|witch leash' -- KeepYourHead/
```

Expected: empty output (exit code 1 from `git grep` is normal when no matches found).

- [ ] **Step 7: Commit the substitutions**

Run:
```bash
git add KeepYourHead/
git commit -m "$(cat <<'EOF'
refactor: substitute WitchLeash → KeepYourHead inside renamed files

Replaces the mod id (PascalCase), the HudElement class name, the
scenegraph id (snake_case), the log prefixes, and the in-game display
name. Mod is now internally consistent and should load under the new
identifier.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Update the repo README

**Files:**
- Modify: `README.md` (line 9 only)

- [ ] **Step 1: Edit the mods table entry**

In `README.md`, replace:
```
| [WitchLeash](WitchLeash/) | Blocks peril-generating inputs at high peril to prevent sudden and violent head explosion. | _coming soon_ |
```
With:
```
| [KeepYourHead](KeepYourHead/) | Blocks peril-generating inputs at high peril to prevent sudden and violent head explosion. | _coming soon_ |
```

(The description and Nexus column stay the same — only the link text and folder reference change.)

- [ ] **Step 2: Verify the README has no remaining stale references**

Run:
```bash
git grep -in -E 'witchleash|witch leash' -- README.md
```

Expected: empty.

- [ ] **Step 3: Commit**

Run:
```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs: update README mod table for KeepYourHead rename

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Repository-wide verification

- [ ] **Step 1: Full-repo identifier sweep**

Run:
```bash
git grep -in -E 'witchleash|witch_leash|witch leash' -- ':!docs/superpowers/specs/' ':!docs/superpowers/plans/'
```

(Specs/plans are documentation of the rename and legitimately mention both names. The exclude pathspecs filter those out.)

Expected: empty output.

- [ ] **Step 2: File-tree sanity check**

Run:
```bash
git ls-files | grep -i witch
```

Expected: empty.

Then:
```bash
git ls-files KeepYourHead/
```

Expected:
```
KeepYourHead/KeepYourHead.mod
KeepYourHead/scripts/mods/KeepYourHead/HudElementKeepYourHeadWarning.lua
KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead.lua
KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_data.lua
KeepYourHead/scripts/mods/KeepYourHead/KeepYourHead_localization.lua
```

- [ ] **Step 3: Confirm git considers each rename a rename (not delete+add)**

Run:
```bash
git log --diff-filter=R --summary --name-status -3 -- KeepYourHead/
```

Expected: each Task 1 / Task 2 rename appears as `rename WitchLeash/... => KeepYourHead/...` rather than separate `delete` and `add` lines. (Substitutions inside Task 2 may also show modifications — that's fine.)

If git classified any rename as delete+add, history is partially lost. This is rarely fixable retroactively without redoing the rename — flag it to the user before continuing.

---

## Task 5: Game-directory cleanup and in-game smoke test (manual)

This task can't run in the worktree — it requires the symlinked install in Steam, plus a Darktide launch. Present the steps to the user and wait for their confirmation.

- [ ] **Step 1: Tell the user the code work is complete and three things still need to happen in their game dir**

Print:
```
Code-side rename done in worktree. Three manual steps remain (outside the
worktree, against the live Darktide install):

1. Delete the broken symlink:
     C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\WitchLeash

2. Re-run symlink_mods.bat as Administrator from the merged branch (so the
   KeepYourHead folder is present at the repo root). The script will create
   the new mods/KeepYourHead symlink.

3. If the game's mods/mod_load_order.txt contains a WitchLeash entry,
   rename that entry to KeepYourHead. (Some users edit this manually; if
   it's empty or only references mods the launcher manages, skip.)

Then launch Darktide and confirm:
  - Mod appears as "Keep Your Head" in the mod options menu.
  - No DMF errors mentioning KeepYourHead in the newest console-*.log
    under %USERPROFILE%\AppData\Roaming\Fatshark\Darktide\console_logs\.
  - In a Psykhanium run with peril near threshold, the HUD warning text
    ("DANGER") shows up.

Reply when verified, or tell me if anything broke.
```

- [ ] **Step 2: If the user reports a problem**

Read the newest `console-*.log` and search for `KeepYourHead`, `HudElementKeepYourHeadWarning`, and `keep_your_head_warning_area`. Common failure modes:
- `script not found` → path inside `KeepYourHead.mod` is wrong; reread Task 2 Step 1.
- HUD never appears → either `HudElementKeepYourHeadWarning` class registration mismatch (Task 2 Step 4f vs Task 2 Step 5), or the scenegraph id rename (Task 2 Step 5) was applied inconsistently between the definition and the `UIWidget.create_definition` second argument.
- `get_mod returned nil` → `new_mod` id in `KeepYourHead.mod` doesn't match a `get_mod(...)` call inside the Lua files.

---

## Notes for follow-up (not part of this branch)

When merging this branch back, the user has a staged but uncommitted file in the parent working tree at `docs/superpowers/plans/2026-05-07-ghostrunner-v0.md` that contains a parenthetical `WitchLeash` reference (line 130). They should update `(quick_chat, WitchLeash)` to `(quick_chat, KeepYourHead)` in that file before they commit it. This plan does not modify it because the file isn't in this worktree's HEAD.
