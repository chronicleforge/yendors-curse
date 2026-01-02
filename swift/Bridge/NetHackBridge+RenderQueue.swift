import Foundation

// =============================================================================
// NetHackBridge+RenderQueue - Render Queue Consumer Extension
// =============================================================================
//
// This extension handles the render queue consumer pattern (Phase 2):
// - Enum for update types (glyph, message, status, commands)
// - Data structs for each update type
// - Queue consumption method for batch processing
//
// The render queue is a lock-free double buffer that allows the game thread
// to push updates while the UI thread consumes them without blocking.
// =============================================================================

extension NetHackBridge {

    // MARK: - Lazy Wrappers (C Function Calls)

    internal func ios_get_render_queue_wrap() throws -> UnsafeMutablePointer<RenderQueue>? {
        try ensureDylibLoaded()
        if _ios_get_render_queue == nil {
            _ios_get_render_queue = try dylib.resolveFunction("ios_get_render_queue")
        }
        return _ios_get_render_queue?()
    }

    internal func render_queue_dequeue_wrap(_ queue: UnsafeMutablePointer<RenderQueue>, _ elem: UnsafeMutablePointer<RenderQueueElement>) throws -> Bool {
        try ensureDylibLoaded()
        if _render_queue_dequeue == nil {
            _render_queue_dequeue = try dylib.resolveFunction("render_queue_dequeue")
        }
        guard let fn = _render_queue_dequeue else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "render_queue_dequeue")
        }
        return fn(queue, elem)
    }

    internal func render_queue_is_empty_wrap(_ queue: UnsafePointer<RenderQueue>) throws -> Bool {
        try ensureDylibLoaded()
        if _render_queue_is_empty == nil {
            _render_queue_is_empty = try dylib.resolveFunction("render_queue_is_empty")
        }
        guard let fn = _render_queue_is_empty else {
            throw DylibLoader.LoadError.symbolNotFound(symbol: "render_queue_is_empty")
        }
        return fn(queue)
    }

    // MARK: - Render Update Types

    enum RenderUpdateType: UInt32 {
        case updateGlyph = 0
        case updateMessage = 1
        case updateStatus = 2
        case cmdFlushMap = 3
        case cmdClearMap = 4
        case cmdTurnComplete = 5
    }

    // MARK: - Update Data Structures

    struct MapUpdateData {
        let x: Int16
        let y: Int16
        let glyph: Int32
        let ch: Int8
        let color: UInt8
        let glyphflags: UInt32  // MG_PET, MG_RIDDEN, MG_DETECT etc.
    }

    // Glyph flag constants from NetHack display.h
    static let MG_PET: UInt32     = 0x00010  // Represents a pet
    static let MG_RIDDEN: UInt32  = 0x00020  // Represents a ridden monster
    static let MG_DETECT: UInt32  = 0x00008  // Detected via telepathy
    static let MG_INVIS: UInt32   = 0x00004  // Invisible monster

    struct MessageUpdateData {
        let text: UnsafeMutablePointer<CChar>
        let category: UnsafeMutablePointer<CChar>
        let attr: Int32
    }

    struct StatusUpdateData {
        let hp: Int32
        let hpmax: Int32
        let pw: Int32
        let pwmax: Int32
        let level: Int32
        let exp: Int
        let ac: Int32
        let str: Int32
        let dex: Int32
        let con: Int32
        let intel: Int32
        let wis: Int32
        let cha: Int32
        let gold: Int
        let moves: Int
        let align: (Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8)  // char align[16] from C
        let hunger: Int32
        let conditions: UInt  // BL_CONDITION bitmask (30 flags)
    }

    // MARK: - Queue Consumer

    /// Consume all pending updates from the render queue
    /// - Returns: Array of (type, data) tuples for processing
    /// - Performance: Lock-free, batch processing
    func consumeRenderQueue() -> [(type: RenderUpdateType, data: Any)] {
        guard let queue = try? ios_get_render_queue_wrap() else {
            return []
        }

        var updates: [(type: RenderUpdateType, data: Any)] = []
        var elem = RenderQueueElement()

        while (try? render_queue_dequeue_wrap(queue, &elem)) == true {
            guard let updateType = RenderUpdateType(rawValue: elem.type.rawValue) else {
                continue
            }

            switch updateType {
            case .updateGlyph:
                let mapUpdate = elem.data.map
                let update = MapUpdateData(
                    x: mapUpdate.x,
                    y: mapUpdate.y,
                    glyph: mapUpdate.glyph,
                    ch: mapUpdate.ch,
                    color: mapUpdate.color,
                    glyphflags: mapUpdate.glyphflags
                )
                updates.append((type: .updateGlyph, data: update))

            case .updateMessage:
                let msgUpdate = elem.data.message
                let message = MessageUpdateData(
                    text: msgUpdate.text,
                    category: msgUpdate.category,
                    attr: msgUpdate.attr
                )
                updates.append((type: .updateMessage, data: message))

            case .updateStatus:
                let statUpdate = elem.data.status
                let status = StatusUpdateData(
                    hp: statUpdate.hp,
                    hpmax: statUpdate.hpmax,
                    pw: statUpdate.pw,
                    pwmax: statUpdate.pwmax,
                    level: statUpdate.level,
                    exp: Int(statUpdate.exp),
                    ac: statUpdate.ac,
                    str: statUpdate.str,
                    dex: statUpdate.dex,
                    con: statUpdate.con,
                    intel: statUpdate.intel,
                    wis: statUpdate.wis,
                    cha: statUpdate.cha,
                    gold: Int(statUpdate.gold),
                    moves: Int(statUpdate.moves),
                    align: statUpdate.align,
                    hunger: statUpdate.hunger,
                    conditions: UInt(statUpdate.conditions)
                )
                updates.append((type: .updateStatus, data: status))

            case .cmdFlushMap:
                updates.append((type: .cmdFlushMap, data: ()))

            case .cmdClearMap:
                updates.append((type: .cmdClearMap, data: ()))

            case .cmdTurnComplete:
                let cmd = elem.data.command
                updates.append((type: .cmdTurnComplete, data: Int(cmd.turn_number)))
            }
        }

        return updates
    }
}
