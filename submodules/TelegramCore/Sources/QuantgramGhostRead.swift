import Foundation
import Postbox

// Quantgram "read without read receipt" (ghost read).
//
// Modes (stored in UserDefaults under "quantgram.ghostReadMode"):
//   off   — normal read behaviour.
//   light — incoming messages stay unread until the user sends a message
//           (reply) in that chat; after that, reads flow normally.
//   full  — incoming messages are never marked read automatically (not even
//           after replying).
//
// When the "Ghost" mode is enabled ("quantgram.ghostMode"), the effective mode
// is forced to .full regardless of the stored value.
public enum QuantgramGhostReadMode: Int32 {
    case off = 0
    case light = 1
    case full = 2
}

public final class QuantgramGhostRead {
    private static let lock = NSLock()
    private static var repliedPeers = Set<PeerId>()

    private static let modeKey = "quantgram.ghostReadMode"
    private static let legacyKey = "quantgram.ghostRead"
    private static let ghostModeKey = "quantgram.ghostMode"

    /// The user-selected mode (ignores the Ghost override), migrating the legacy
    /// boolean flag on first read.
    public static var storedMode: QuantgramGhostReadMode {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: modeKey) == nil {
            // Migrate the old on/off flag to light/off.
            return defaults.bool(forKey: legacyKey) ? .light : .off
        }
        return QuantgramGhostReadMode(rawValue: Int32(defaults.integer(forKey: modeKey))) ?? .off
    }

    public static func setStoredMode(_ mode: QuantgramGhostReadMode) {
        UserDefaults.standard.set(Int(mode.rawValue), forKey: modeKey)
    }

    /// The effective mode actually used for read suppression: Ghost mode forces
    /// .full, otherwise the user-selected mode applies.
    public static var effectiveMode: QuantgramGhostReadMode {
        if UserDefaults.standard.bool(forKey: ghostModeKey) {
            return .full
        }
        return storedMode
    }

    /// Marks that the user has sent a message in the given peer, so reads are
    /// allowed to flow in light mode from now on this session.
    public static func markReplied(_ peerId: PeerId) {
        lock.lock()
        repliedPeers.insert(peerId)
        lock.unlock()
    }

    /// Whether applying the incoming read index should be suppressed for this peer.
    public static func shouldSuppressRead(_ peerId: PeerId) -> Bool {
        switch effectiveMode {
        case .off:
            return false
        case .full:
            return true
        case .light:
            lock.lock()
            let replied = repliedPeers.contains(peerId)
            lock.unlock()
            return !replied
        }
    }
}
