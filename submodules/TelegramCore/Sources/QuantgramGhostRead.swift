import Foundation
import Postbox

// Quantgram "read without read receipt" (ghost read).
//
// When enabled (flag stored by the UI in UserDefaults under "quantgram.ghostRead"),
// incoming messages in a chat are NOT marked as read — and therefore no read
// receipt is sent to the server — until the user sends a message (reply) in that
// chat. The "has replied" state is tracked in memory per session.
public final class QuantgramGhostRead {
    private static let lock = NSLock()
    private static var repliedPeers = Set<PeerId>()

    public static var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "quantgram.ghostRead")
    }

    /// Marks that the user has sent a message in the given peer, so reads (and
    /// read receipts) are allowed to flow normally from now on this session.
    public static func markReplied(_ peerId: PeerId) {
        lock.lock()
        repliedPeers.insert(peerId)
        lock.unlock()
    }

    /// Whether applying the incoming read index should be suppressed for this
    /// peer (ghost read on AND the user has not replied yet).
    public static func shouldSuppressRead(_ peerId: PeerId) -> Bool {
        if !isEnabled {
            return false
        }
        lock.lock()
        let replied = repliedPeers.contains(peerId)
        lock.unlock()
        return !replied
    }
}
