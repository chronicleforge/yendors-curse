# Yendor's Curse - NetHack iOS Port

A modern iOS port of the classic roguelike NetHack.

## Building

```bash
# Clone with submodules
git clone --recursive https://github.com/chronicleforge/yendors-curse.git
cd yendors-curse

# Build the NetHack dynamic library
./build_nethack_dylib.sh

# Open in Xcode and build
open nethack.xcodeproj
```

## Structure

- `NetHack/` - NetHack source (submodule)
- `lua/` - Lua 5.4.6 (submodule)
- `src/` - C bridge code
- `swift/` - SwiftUI app
- `patches/` - iOS compatibility patches
- `zone_allocator/` - Memory management

## License

NetHack is licensed under the [NetHack General Public License](https://nethack.org/common/license.html).
