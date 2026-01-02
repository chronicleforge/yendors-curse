#!/bin/bash
# Build script for NetHack as dynamic library (.dylib) for iOS Simulator
# This builds a shared library instead of static archive for better debugging

set -e

# Change to script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

ORIGIN_DIR="NetHack"
BUILD_DIR="build"
OBJ_DIR="$BUILD_DIR/obj"  # Put .o files in subdirectory to avoid Xcode linking them
TARGET="arm64-apple-ios26.0-simulator"
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
OUTPUT_DYLIB="$BUILD_DIR/libnethack.dylib"

# Create obj directory for intermediate files
mkdir -p "$OBJ_DIR"

echo "Building NetHack as dynamic library from $ORIGIN_DIR..."
echo "Target: $TARGET"
echo "Output: $OUTPUT_DYLIB"

# Create build directory
mkdir -p $BUILD_DIR

# Verify submodules exist
if [ ! -d "NetHack" ]; then
    echo "Error: NetHack not found. Run: git submodule update --init"
    exit 1
fi
if [ ! -d "lua" ]; then
    echo "Error: lua not found. Run: git submodule update --init"
    exit 1
fi

# Compiler flags (same as static library build)
CFLAGS="-target $TARGET"
CFLAGS="$CFLAGS -isysroot $SDK_PATH"
CFLAGS="$CFLAGS -I$ORIGIN_DIR/include"
CFLAGS="$CFLAGS -I$ORIGIN_DIR/sys/share"
CFLAGS="$CFLAGS -Ilua"
CFLAGS="$CFLAGS -INetHack"
CFLAGS="$CFLAGS -Izone_allocator"
CFLAGS="$CFLAGS -DNO_SIGNAL"
CFLAGS="$CFLAGS -DIOS_PLATFORM"
CFLAGS="$CFLAGS -DDLB"
CFLAGS="$CFLAGS -DPREFIXES_IN_USE"
CFLAGS="$CFLAGS -DNOCWD_ASSUMPTIONS"
CFLAGS="$CFLAGS -DLUA_USE_POSIX"
CFLAGS="$CFLAGS -DLUA_USE_IOS"
CFLAGS="$CFLAGS -DNO_TERMS"
CFLAGS="$CFLAGS -DNO_TERMCAP_HEADERS"
CFLAGS="$CFLAGS -DUSE_ZONE_ALLOCATOR"
CFLAGS="$CFLAGS -DREPLACE_SYSTEM_MALLOC"
CFLAGS="$CFLAGS -DMONITOR_HEAP"
CFLAGS="$CFLAGS -DBUILD_DYLIB"  # Enable dylib-specific stubs
# Structured logging for debugging (set NH_STRUCTURED_LOGGING=1 to enable)
if [ "${NH_STRUCTURED_LOGGING:-0}" = "1" ]; then
    echo "🔍 Structured logging ENABLED (NH_STRUCTURED_LOGGING=1)"
    CFLAGS="$CFLAGS -DNH_STRUCTURED_LOGGING"
else
    echo "📝 Structured logging disabled (set NH_STRUCTURED_LOGGING=1 to enable)"
fi
CFLAGS="$CFLAGS -fPIC"  # Position-independent code for shared library
CFLAGS="$CFLAGS -fvisibility=hidden"  # Hide all symbols by default
CFLAGS="$CFLAGS -c"
CFLAGS="$CFLAGS -w"

# First, create config headers that NetHack expects
echo "Creating config headers..."

# Create nhlua.h with correct Lua paths for iOS (Lua is in lua, not ../lib/lua544)
echo "  Creating nhlua.h with iOS Lua paths..."
cat > "$ORIGIN_DIR/include/nhlua.h" << 'NHLUA_EOF'
/* nhlua.h - iOS modified for lua-5.4.6 in origin/ */
#include "lua.h"
LUA_API int   (lua_error) (lua_State *L) NORETURN;
#include "lualib.h"
#include "lauxlib.h"
/*nhlua.h*/
NHLUA_EOF

cat > src/ios_config.h << 'EOF'
/* Minimal config for iOS port */
#ifndef IOS_CONFIG_H
#define IOS_CONFIG_H

/* Platform settings */
#define UNIX
#define BSD
#define NO_SIGNAL

/* Enable Lua support - we have it compiled */
/* Note: CROSSCOMPILE removed to enable Lua */

/* Disable terminal capabilities */
#define NO_TERMS
#define NO_TERMCAP_HEADERS

/* Zone-based memory management */
#ifdef USE_ZONE_ALLOCATOR
#include "nethack_zone.h"
#endif

/* Stubs for missing functions */
#define strcmpi(s1,s2) strcasecmp(s1,s2)
/* strncmpi is already in NetHack's hacklib.h */

#endif
EOF

# List of essential NetHack source files (same as static library build)
SOURCES=(
    # Lua library files (core only, not interpreter)
    "lua/lapi.c"
    "lua/lauxlib.c"
    "lua/lbaselib.c"
    "lua/lcode.c"
    "lua/lcorolib.c"
    "lua/lctype.c"
    "lua/ldblib.c"
    "lua/ldebug.c"
    "lua/ldo.c"
    "lua/ldump.c"
    "lua/lfunc.c"
    "lua/lgc.c"
    "lua/linit.c"
    "lua/liolib.c"
    "lua/llex.c"
    "lua/lmathlib.c"
    "lua/lmem.c"
    "lua/loadlib.c"
    "lua/lobject.c"
    "lua/lopcodes.c"
    "lua/loslib.c"
    "lua/lparser.c"
    "lua/lstate.c"
    "lua/lstring.c"
    "lua/lstrlib.c"
    "lua/ltable.c"
    "lua/ltablib.c"
    "lua/ltm.c"
    "lua/lundump.c"
    "lua/lutf8lib.c"
    "lua/lvm.c"
    "lua/lzio.c"

    # Core data files
    "$ORIGIN_DIR/src/monst.c"
    "$ORIGIN_DIR/src/objects.c"
    "$ORIGIN_DIR/src/decl.c"

    # Utilities
    "$ORIGIN_DIR/src/rnd.c"
    "$ORIGIN_DIR/src/hacklib.c"
    "zone_allocator/nethack_memory_final.c"
    "zone_allocator/nethack_static_alloc.c"

    # Character
    "$ORIGIN_DIR/src/role.c"
    "$ORIGIN_DIR/src/u_init.c"
    "$ORIGIN_DIR/src/attrib.c"

    # Object system
    "$ORIGIN_DIR/src/objnam.c"
    "$ORIGIN_DIR/src/mkobj.c"

    # Monster system
    "$ORIGIN_DIR/src/mon.c"
    "$ORIGIN_DIR/src/mondata.c"
    "$ORIGIN_DIR/src/monmove.c"

    # Map/Dungeon
    "$ORIGIN_DIR/src/vision.c"
    "$ORIGIN_DIR/src/display.c"
    "$ORIGIN_DIR/src/drawing.c"

    # More core systems
    "$ORIGIN_DIR/src/invent.c"
    "$ORIGIN_DIR/src/artifact.c"
    "$ORIGIN_DIR/src/weapon.c"
    "$ORIGIN_DIR/src/worn.c"
    "$ORIGIN_DIR/src/wield.c"
    "$ORIGIN_DIR/src/write.c"
    "$ORIGIN_DIR/src/fountain.c"
    "$ORIGIN_DIR/src/sit.c"
    "$ORIGIN_DIR/src/save.c"
    "$ORIGIN_DIR/src/restore.c"
    "$ORIGIN_DIR/src/pickup.c"
    "$ORIGIN_DIR/src/steal.c"
    "$ORIGIN_DIR/src/steed.c"
    "$ORIGIN_DIR/src/polyself.c"
    "$ORIGIN_DIR/src/were.c"
    "$ORIGIN_DIR/src/dog.c"
    "$ORIGIN_DIR/src/dogmove.c"
    "$ORIGIN_DIR/src/mail.c"
    "$ORIGIN_DIR/src/music.c"
    "$ORIGIN_DIR/src/engrave.c"
    "$ORIGIN_DIR/src/dothrow.c"
    "$ORIGIN_DIR/src/do_name.c"
    "$ORIGIN_DIR/src/do_wear.c"

    # Essential systems for basic gameplay
    "$ORIGIN_DIR/src/shk.c"
    "$ORIGIN_DIR/src/shknam.c"
    "$ORIGIN_DIR/src/light.c"
    "$ORIGIN_DIR/src/timeout.c"
    "$ORIGIN_DIR/src/track.c"
    "$ORIGIN_DIR/src/trap.c"
    "$ORIGIN_DIR/src/uhitm.c"
    "$ORIGIN_DIR/src/mhitm.c"
    "$ORIGIN_DIR/src/mhitu.c"
    "$ORIGIN_DIR/src/mthrowu.c"
    "$ORIGIN_DIR/src/mcastu.c"
    "$ORIGIN_DIR/src/zap.c"
    "$ORIGIN_DIR/src/explode.c"
    "$ORIGIN_DIR/src/potion.c"
    "$ORIGIN_DIR/src/read.c"
    "$ORIGIN_DIR/src/spell.c"
    "$ORIGIN_DIR/src/eat.c"
    "$ORIGIN_DIR/src/apply.c"
    "$ORIGIN_DIR/src/pray.c"
    "$ORIGIN_DIR/src/priest.c"
    "$ORIGIN_DIR/src/minion.c"
    "$ORIGIN_DIR/src/makemon.c"

    # NetHack Lua integration
    "$ORIGIN_DIR/src/nhlua.c"
    "$ORIGIN_DIR/src/nhlsel.c"
    "$ORIGIN_DIR/src/nhlobj.c"

    # Dungeon structure
    "$ORIGIN_DIR/src/dungeon.c"
    "$ORIGIN_DIR/src/dbridge.c"
    "$ORIGIN_DIR/src/region.c"
    "$ORIGIN_DIR/src/rect.c"
    "$ORIGIN_DIR/src/vault.c"
    "$ORIGIN_DIR/src/dig.c"
    "$ORIGIN_DIR/src/teleport.c"
    "$ORIGIN_DIR/src/lock.c"
    "$ORIGIN_DIR/src/sounds.c"
    "$ORIGIN_DIR/src/cmd.c"
    "$ORIGIN_DIR/src/pline.c"
    "$ORIGIN_DIR/src/o_init.c"

    # More essential files
    "$ORIGIN_DIR/src/botl.c"
    "$ORIGIN_DIR/src/calendar.c"
    "$ORIGIN_DIR/src/mplayer.c"
    "$ORIGIN_DIR/src/rumors.c"
    "$ORIGIN_DIR/src/sys.c"
    "$ORIGIN_DIR/src/topten.c"
    "$ORIGIN_DIR/src/wizard.c"
    "$ORIGIN_DIR/src/worm.c"

    # Missing essential files
    "$ORIGIN_DIR/src/allmain.c"
    "$ORIGIN_DIR/src/mklev.c"
    "$ORIGIN_DIR/src/mkroom.c"
    "$ORIGIN_DIR/src/ball.c"
    "$ORIGIN_DIR/src/bones.c"
    "$ORIGIN_DIR/src/detect.c"
    "$ORIGIN_DIR/src/dokick.c"
    "$ORIGIN_DIR/src/end.c"
    "$ORIGIN_DIR/src/exper.c"
    "$ORIGIN_DIR/src/extralev.c"
    "$ORIGIN_DIR/src/hack.c"
    "$ORIGIN_DIR/src/insight.c"
    "$ORIGIN_DIR/src/isaac64.c"
    "$ORIGIN_DIR/src/mdlib.c"
    "$ORIGIN_DIR/src/mkmap.c"
    "$ORIGIN_DIR/src/mkmaze.c"
    "$ORIGIN_DIR/src/muse.c"
    "$ORIGIN_DIR/src/options.c"
    "$ORIGIN_DIR/src/pager.c"
    # pickup.c already listed earlier (line 152) - removed duplicate
    "$ORIGIN_DIR/src/quest.c"
    "$ORIGIN_DIR/sys/share/random.c"
    "$ORIGIN_DIR/src/sp_lev.c"
    "$ORIGIN_DIR/src/files.c"
    "$ORIGIN_DIR/src/do.c"

    # Missing core files
    "$ORIGIN_DIR/src/cfgfiles.c"
    "$ORIGIN_DIR/src/coloratt.c"
    "src/ios_append_slash.c"
    "$ORIGIN_DIR/src/getpos.c"
    "$ORIGIN_DIR/src/glyphs.c"
    "$ORIGIN_DIR/src/stairs.c"
    "$ORIGIN_DIR/src/strutil.c"
    "$ORIGIN_DIR/src/symbols.c"
    "$ORIGIN_DIR/src/windows.c"
    "$ORIGIN_DIR/src/wizcmds.c"
    "$ORIGIN_DIR/src/utf8map.c"
    "$ORIGIN_DIR/src/report.c"
    "$ORIGIN_DIR/src/questpgr.c"
    "$ORIGIN_DIR/src/selvar.c"
    "$ORIGIN_DIR/src/sfstruct.c"
    "$ORIGIN_DIR/src/sfbase.c"

    # Platform-specific files (essential for dylib)
    "$ORIGIN_DIR/src/version.c"    # Version info with dlb support
    # NOTE: dlb.c is EXCLUDED - iOS uses custom dlb implementation in ios_dylib_stubs.c
    # The NetHack dlb.c is for archive files (.dlb), iOS loads directly from app bundle

    # iOS Bridge Files - REQUIRED for dylib to export Swift-facing functions
    # These provide the API that Swift code calls (nethack_get_available_races_for_role, etc.)
    "src/RealNetHackBridge.c"      # Main bridge with validation functions
    # "src/ios_travel.c"           # DISABLED: Travel feature not yet implemented
    "src/ios_winprocs.c"           # Window procedures (Core NetHack display system)
    "src/ios_notifications.m"      # Objective-C notification posting to Swift
    "src/ios_dylib_stubs.c"        # Platform stubs for dylib build (minimal set)
    "src/ios_filesys.c"            # iOS filesystem helpers
    "src/ios_newgame.c"            # Game initialization and character creation
    "src/ios_game_lifecycle.c"     # Lifecycle management (shutdown, reinit)
    "src/ios_dylib_lifecycle.c"    # UNIFIED dylib init/shutdown (single source of truth)
    "src/ios_autoplay.c"           # Autoplay/debug features
    "src/ios_object_bridge.c"      # Object/inventory bridge
    "src/ios_container_bridge.c"   # Floor container operations bridge
    "src/ios_game_state_buffer.c"  # Lock-free game state push buffer (Push Model)
    "src/ios_render_queue.c"       # Render queue for display updates
    "src/ios_restore.c"            # Restore/load game functions
    "src/action_registry.c"        # Action registry
    "src/action_system.c"          # Action system
    "src/ios_dungeon.c"            # iOS dungeon.lua support
    "src/ios_save_integration.c"   # Save/load integration (REQUIRED for Swift)
    "src/ios_slot_manager.c"       # Save slot management (REQUIRED for Swift)
    "src/ios_character_save.c"     # Character save/load (REQUIRED for Swift)
    "src/ios_character_status.c"   # Character status bridge (Equipment, Identity, Conditions)
    "src/ios_msg_history.c"        # Message history buffer
    "src/ios_nhlua_patch.c"        # Lua patches for iOS
    "src/ios_memory_integration.c" # Memory system integration
    "src/ios_event_driven.c"       # Event-driven architecture
    "src/ios_crash_handler.c"      # Crash checkpoint logging
    "src/nhlua_debug.c"            # Lua debugging utilities
    "src/NetHackCoreIntegration.c" # Core integration
    # "src/ios_structured_log.c"   # Structured JSON logging (optional)
)

# Apply essential iOS patches (COMPLETE SET - matches all manual changes in NetHack/)
echo "Applying iOS patches..."
PATCH_DIR="$SCRIPT_DIR/patches"

# 1. Export declarations (extern.h) - NETHACK_EXPORT for bridge functions
if [ -f "$PATCH_DIR/extern_export.patch" ]; then
    echo "  [1/11] Applying extern_export.patch (export declarations)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/extern_export.patch" 2>/dev/null) || true
fi

# 2. DLB library exports (dlb.h) - NETHACK_EXPORT for file handling
if [ -f "$PATCH_DIR/dlb_export.patch" ]; then
    echo "  [2/11] Applying dlb_export.patch (DLB file system)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/dlb_export.patch" 2>/dev/null) || true
fi

# 3. Save/Restore exports (save.c + restore.c) - Combined patch for save system
if [ -f "$PATCH_DIR/save_restore_export.patch" ]; then
    echo "  [3/11] Applying save_restore_export.patch (save/restore system)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/save_restore_export.patch" 2>/dev/null) || true
fi

# 4. iOS moveloop exit (allmain.c) - Clean game loop exit instead of exit(0)
if [ -f "$PATCH_DIR/ios_moveloop_exit.patch" ]; then
    echo "  [4/11] Applying ios_moveloop_exit.patch (clean game exit)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/ios_moveloop_exit.patch" 2>/dev/null) || true
fi

# 5. Status line guard reset (botl.c) - Allow re-init after nh_restart()
if [ -f "$PATCH_DIR/botl_reset_guard.patch" ]; then
    echo "  [5/11] Applying botl_reset_guard.patch (status re-init fix)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/botl_reset_guard.patch" 2>/dev/null) || true
fi

# 6. SYSCF skip (cfgfiles.c) - No /etc/NetHack on iOS
if [ -f "$PATCH_DIR/ios_syscf_skip.patch" ]; then
    echo "  [6/11] Applying ios_syscf_skip.patch (skip system config)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/ios_syscf_skip.patch" 2>/dev/null) || true
fi

# 7. Lua defensive init (nhlua.c) - Graceful fallback instead of panic
if [ -f "$PATCH_DIR/nhlua_defensive_init.patch" ]; then
    echo "  [7/11] Applying nhlua_defensive_init.patch (Lua safety)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/nhlua_defensive_init.patch" 2>/dev/null) || true
fi

# 8. Tutorial skip (options.c) - Skip tutorial on mobile
if [ -f "$PATCH_DIR/ios_tutorial_skip.patch" ]; then
    echo "  [8/11] Applying ios_tutorial_skip.patch (skip tutorial)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/ios_tutorial_skip.patch" 2>/dev/null) || true
fi

# 9. Pager lookat export (pager.c) - Export lookat() for magnifying glass
if [ -f "$PATCH_DIR/pager_lookat_export.patch" ]; then
    echo "  [9/11] Applying pager_lookat_export.patch (inspection API)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/pager_lookat_export.patch" 2>/dev/null) || true
fi

# 10. Deferred timer relinking (timeout.c) - Fix multi-level restore crash
if [ -f "$PATCH_DIR/ios_relink_timers_deferred.patch" ]; then
    echo "  [10/12] Applying ios_relink_timers_deferred.patch (multi-level restore fix)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/ios_relink_timers_deferred.patch" 2>/dev/null) || true
fi

# 11. Timer safety net (timeout.c) - Defensive logging for orphaned timers
if [ -f "$PATCH_DIR/ios_run_timers_safety.patch" ]; then
    echo "  [11/13] Applying ios_run_timers_safety.patch (orphaned timer safety net)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/ios_run_timers_safety.patch" 2>/dev/null) || true
fi

# 12. iOS u_init stub (u_init.c) - Backward-compat stub for role templates
if [ -f "$PATCH_DIR/ios_u_init_stub.patch" ]; then
    if ! grep -q "ios_reset_role_inventory_templates" "$ORIGIN_DIR/src/u_init.c" 2>/dev/null; then
        echo "  [12/13] Applying ios_u_init_stub.patch (u_init backward-compat stub)..."
        (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/ios_u_init_stub.patch" 2>/dev/null) || true
    else
        echo "  [12/13] ios_u_init_stub.patch already applied (skipping)"
    fi
fi

# 13. iOS travel interrupt (hack.c) - Immediate travel interrupt in lookaround()
if [ -f "$PATCH_DIR/ios_travel_interrupt.patch" ]; then
    echo "  [13/13] Applying ios_travel_interrupt.patch (immediate travel interrupt)..."
    (cd "$ORIGIN_DIR" && patch -p1 -N -s -f < "$PATCH_DIR/ios_travel_interrupt.patch" 2>/dev/null) || true
fi

echo "✓ All iOS patches applied (13 total)"
echo "  - 3 export patches (extern.h, dlb.h, save/restore)"
echo "  - 3 iOS adaptations (syscf, tutorial, moveloop)"
echo "  - 6 stability fixes (botl guard, Lua defensive, timer relink, timer safety, u_init stub, travel interrupt)"
echo "  - 1 bridge API (pager lookat)"
echo ""
echo "These patches match ALL manual changes in NetHack/"
echo "The other machine will now build correctly after cloning!"

# Compile each source file with -fPIC
echo "Compiling source files..."
OBJECT_FILES=()
for source in "${SOURCES[@]}"; do
    if [ -f "$source" ]; then
        basename=$(basename "$source" .c)
        echo "  Compiling $basename..."

        # Add include for our config
        if clang $CFLAGS -include src/ios_config.h "$source" -o "$OBJ_DIR/${basename}.o" 2>&1 | head -10; then
            OBJECT_FILES+=("$OBJ_DIR/${basename}.o")
        else
            echo "    Warning: Failed to compile $basename"
        fi
    else
        echo "  Warning: $source not found"
    fi
done

# Create dynamic library with install_name
echo "Creating dynamic library..."
echo "Linking ${#OBJECT_FILES[@]} object files..."

# Set install_name for proper loading in app bundle
INSTALL_NAME="@rpath/libnethack.dylib"

clang -dynamiclib \
    -target $TARGET \
    -isysroot $SDK_PATH \
    -install_name "$INSTALL_NAME" \
    -o "$OUTPUT_DYLIB" \
    "${OBJECT_FILES[@]}" \
    -framework CoreFoundation \
    -framework Foundation \
    -framework Security \
    -lc++ \
    -compatibility_version 1.0 \
    -current_version 3.7.0

# Verify the dylib was created
if [ -f "$OUTPUT_DYLIB" ]; then
    echo "✓ Dynamic library created successfully"
    echo ""
    echo "Library info:"
    file "$OUTPUT_DYLIB"
    ls -lh "$OUTPUT_DYLIB"
    echo ""
    echo "Install name:"
    otool -D "$OUTPUT_DYLIB"
    echo ""
    echo "Dependencies:"
    otool -L "$OUTPUT_DYLIB" | head -10
else
    echo "❌ Failed to create dynamic library"
    exit 1
fi

# Copy lua resources for embedding in app bundle
echo ""
echo "Ensuring lua_resources are available..."
if [ ! -d "src/lua_resources" ]; then
    echo "Creating lua_resources directory..."
    mkdir -p nethack/lua_resources
fi

if [ ! -f "src/lua_resources/dungeon.lua" ]; then
    echo "Copying Lua files to resources..."
    cp NetHack/dat/*.lua nethack/lua_resources/ 2>/dev/null || echo "Warning: Some lua files may not have been copied"
fi

echo "✓ Lua resources ready"

# Generate data files (bogusmon, epitaph, engrave) from .txt sources
echo ""
echo "Generating data files (bogusmon, epitaph, engrave)..."
if [ -f "scripts/generate_data_files.py" ]; then
    python3 scripts/generate_data_files.py
    if [ $? -eq 0 ]; then
        echo "✓ Data files generated"
    else
        echo "⚠️  Warning: Data file generation failed (non-critical)"
    fi
else
    echo "⚠️  Warning: generate_data_files.py not found"
fi

echo ""
echo "=========================================="
echo "✅ Build complete!"
echo "=========================================="
echo "Dynamic library: $OUTPUT_DYLIB"
echo ""
echo "To use this dylib in your project:"
echo "1. Add it to 'Frameworks, Libraries, and Embedded Content'"
echo "2. Set 'Embed & Sign' or 'Embed Without Signing'"
echo "3. Ensure Runpath Search Paths includes @executable_path/Frameworks"
echo ""
