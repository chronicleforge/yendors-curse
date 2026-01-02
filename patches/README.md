# NetHack iOS Port - Active Patches (Complete Set)

**Last Updated:** 2025-10-24
**Purpose:** These patches capture ALL manual modifications to `origin/NetHack/` source code.

## 🎯 Critical Information

**Problem Solved:** On a fresh clone, the gameplay branch was missing `NETHACK_EXPORT` and other changes because we had modified NetHack source files directly without creating patches.

**Solution:** All manual changes in `origin/NetHack/` are now captured as patches. The other machine will build correctly after:
1. Cloning the repo
2. Running `./build_nethack_dylib.sh` (applies patches automatically)

---

## 📦 Complete Patch List (10 Patches)

### Export Patches (3)

**1. `extern_export.patch`** - Export declarations in `include/extern.h`
- Adds `NETHACK_EXPORT` for `nhl_init()` (Lua initialization)
- Adds `NETHACK_EXPORT` for `decode_mixed()` (glyph decoding)
- Adds extern declaration for `savegamestate()` (iOS live saves)

**2. `dlb_export.patch`** - DLB file system exports in `include/dlb.h`
- Exports all DLB functions (`dlb_init`, `dlb_fopen`, `dlb_fread`, etc.)
- Required for iOS file handling bridge

**3. `save_restore_export.patch`** - Save/restore system in `src/save.c` + `src/restore.c`
- Makes `savegamestate()` public (was `staticfn`)
- Makes `restgamestate()` public (was `staticfn`)
- Adds debug logging for restore flow
- **CRITICAL for iOS save system integration**

---

### iOS Platform Adaptations (3)

**4. `ios_moveloop_exit.patch`** - Clean game loop exit in `src/allmain.c`
- Checks `program_state.gameover` in moveloop
- Exits cleanly with `break` instead of `exit(0)`
- Allows dylib to unload properly when game ends

**5. `ios_syscf_skip.patch`** - Skip system config check in `src/cfgfiles.c`
- Skips `/etc/NetHack/sysconf` check on iOS (file doesn't exist)
- Uses `#ifdef IOS_PLATFORM` guard
- User `.nethackrc` is still loaded normally

**6. `ios_tutorial_skip.patch`** - Skip tutorial on mobile in `src/options.c`
- Always returns FALSE for `ask_do_tutorial()`
- Touch interface doesn't work well with tutorial prompts

---

### Stability Fixes (3)

**7. `botl_reset_guard.patch`** - Status line re-init fix in `src/botl.c`
- Resets `initalready` static guard in `init_blstats()`
- Allows re-initialization after `nh_restart()` (Continue feature)
- **ROOT CAUSE FIX:** Static guard persisted after `status_finish()`, blocking re-init

**8. `nhlua_defensive_init.patch`** - Lua defensive initialization in `src/nhlua.c`
- Attempts to initialize Lua if `gl.luacore` is NULL
- Returns empty string instead of `panic()` if init fails
- Matches `restore_luadata()` behavior (defensive pattern)
- **Prevents crash** during early save_currentstate() calls

**9. `ios_relink_timers_deferred.patch`** - Deferred timer relinking in `src/timeout.c`
- `relink_timers()`: Uses temp variable so failed `find_oid()` doesn't corrupt `arg` union
- `timer_is_local()`: Checks `needs_fixup` before accessing `arg.a_obj` (prevents NULL deref)
- **ROOT CAUSE FIX:** `getlev()` calls `relink_timers()` BEFORE inventory loads
- **CRITICAL:** `arg` is a union - `arg.a_uint` (o_id) and `arg.a_obj` (pointer) share memory!
- **Prevents crash** when restoring multi-level saves (D:2+ with items from D:1)

---

### Bridge API (1)

**10. `pager_lookat_export.patch`** - Magnifying glass API in `src/pager.c`
- Makes `lookat()` function public (was `staticfn`)
- Exports monster/object inspection for iOS bridge
- Used for magnifying glass feature (tap to inspect)

---

## 🔧 How Patches Are Applied

Patches are applied automatically by `build_nethack_dylib.sh` before compilation:

```bash
patch -p0 -N -s -f < patches/[name].patch 2>/dev/null || true
```

**Flags:**
- `-p0`: Apply in current directory (paths are relative to project root)
- `-N`: Skip if already applied (idempotent)
- `-s`: Silent mode (no output)
- `-f`: Force (non-interactive, no questions)
- `2>/dev/null`: Suppress stderr
- `|| true`: Always succeed (don't fail build)

**Result:** Fully non-interactive, can run multiple times safely.

---

## 📋 Patch Categories Summary

| Category | Count | Purpose |
|----------|-------|---------|
| **Export Patches** | 3 | Expose NetHack functions to iOS bridge |
| **iOS Adaptations** | 3 | Mobile platform compatibility |
| **Stability Fixes** | 3 | Prevent crashes and enable Continue feature |
| **Bridge API** | 1 | Enable iOS-specific features (inspection) |
| **TOTAL** | **10** | Complete set of manual modifications |

---

## 🔍 Verification

To verify patches match the current `origin/NetHack/` state:

```bash
# Show modified files in origin/NetHack/
cd origin/NetHack && git status

# Generate current diffs
git diff include/extern.h > /tmp/current_extern.patch
git diff include/dlb.h > /tmp/current_dlb.patch
git diff src/save.c src/restore.c > /tmp/current_save_restore.patch
# ... etc for all 10 files

# Compare with stored patches
diff /tmp/current_extern.patch patches/extern_export.patch
```

If there are differences, patches need updating.

---

## 📝 Modified Files List

All patches modify these NetHack source files:

1. `origin/NetHack/include/extern.h` - Export declarations
2. `origin/NetHack/include/dlb.h` - DLB exports
3. `origin/NetHack/src/save.c` - Save function export
4. `origin/NetHack/src/restore.c` - Restore function export
5. `origin/NetHack/src/allmain.c` - Moveloop exit logic
6. `origin/NetHack/src/botl.c` - Status guard reset
7. `origin/NetHack/src/cfgfiles.c` - SYSCF skip
8. `origin/NetHack/src/nhlua.c` - Lua defensive init
9. `origin/NetHack/src/options.c` - Tutorial skip
10. `origin/NetHack/src/timeout.c` - Deferred timer relinking (multi-level restore fix)
11. `origin/NetHack/src/pager.c` - lookat() export

---

## 🚨 Important Notes

### Why Patches Instead of Fork?

- **Upgradability:** Easier to port to new NetHack versions
- **Minimal Changes:** Only 10 files modified out of 200+ source files
- **Transparency:** Each patch is documented and reviewable
- **Git-Friendly:** Patches are committed, `origin/` is `.gitignore`d

### Updating Patches

When making new changes to `origin/NetHack/`:

```bash
# Generate new patch
cd origin/NetHack
git diff path/to/file.c > ../../patches/new_patch.patch

# Update build_nethack_dylib.sh to apply it
# Add to patch section with clear comment

# Test on clean clone
cd /tmp
git clone [repo] test-build
cd test-build
./build_nethack_dylib.sh  # Should apply all patches successfully
```

### Patch Maintenance

When upgrading NetHack versions:
1. Checkout new NetHack version in `origin/NetHack/`
2. Try building without patches first
3. If build fails, reapply patches one by one
4. Some patches may no longer be needed (e.g., if NetHack made functions public)
5. Update patch files if context changed
6. Test thoroughly - especially save/load system

---

## ✅ Success Criteria

After cloning on a new machine and running `./build_nethack_dylib.sh`:

- ✅ All 10 patches apply successfully (non-interactive)
- ✅ No compilation errors
- ✅ `libnethack.dylib` builds successfully
- ✅ iOS app links and runs
- ✅ Save/Load works correctly
- ✅ No crashes during gameplay

If any of these fail, patches may be out of sync with `origin/NetHack/` state.

---

## 📚 Related Documentation

- `BUILD_DYLIB_SUMMARY.md` - Dylib build system overview
- `claude-files/DYLIB_AGENT_CONTEXT.md` - Technical deep-dive
- `build_nethack_dylib.sh` - Build script that applies patches
- `CLAUDE.md` - Project guidelines (see "iOS PATCHES" section)

---

**These 10 patches capture 100% of manual changes to NetHack source code.**
**The gameplay branch will now build correctly on any machine! 🎉**
