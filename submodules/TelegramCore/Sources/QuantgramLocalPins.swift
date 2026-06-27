import Foundation
import Postbox

// Quantgram "local pinned chats".
//
// When enabled, server pinned chats are loaded ONCE (seed) on account entry,
// after which pinning becomes local-only: local pin changes are not pushed to
// the server (see TogglePeerChatPinned) and incoming server pin state no longer
// overwrites the local pinned list. Flags live in UserDefaults so the UI
// (SettingsUI) and the core sync can share them within the app process.
//
// Keys:
//   quantgram.localPins   Bool — feature enabled
//   quantgram.pinsSeeded  Bool — server pins have been applied once since enabling
public final class QuantgramLocalPins {
    public static var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "quantgram.localPins")
    }

    public static var seeded: Bool {
        get { return UserDefaults.standard.bool(forKey: "quantgram.pinsSeeded") }
        set { UserDefaults.standard.set(newValue, forKey: "quantgram.pinsSeeded") }
    }

    public static func resetSeed() {
        UserDefaults.standard.set(false, forKey: "quantgram.pinsSeeded")
    }
}

// Applies a server-provided pinned item list to the postbox, honouring local
// pins: for the root chat list with local pins enabled, the server list is
// applied only once (seed) and then ignored so the local list is preserved.
func quantgramApplyServerPinnedItemIds(transaction: Transaction, groupId: PeerGroupId, itemIds: [PinnedItemId]) {
    var isRoot = false
    if case .root = groupId {
        isRoot = true
    }
    if isRoot && QuantgramLocalPins.isEnabled {
        if QuantgramLocalPins.seeded {
            return
        }
        QuantgramLocalPins.seeded = true
    }
    transaction.setPinnedItemIds(groupId: groupId, itemIds: itemIds)
}
