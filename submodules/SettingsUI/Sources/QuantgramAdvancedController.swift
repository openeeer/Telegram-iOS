import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// Quantgram fork settings (non-standard features). Stored in standard
// UserDefaults so both the UI here and the core logic can read the same flags
// within the app process.
public struct QuantgramSettings {
    private static let ghostReadKey = "quantgram.ghostRead"
    private static let localPinsKey = "quantgram.localPins"
    private static let pinsSeededKey = "quantgram.pinsSeeded"

    /// "Read without read receipt": incoming messages are marked read only after
    /// the user sends a reply in the chat.
    public static var ghostRead: Bool {
        get { return UserDefaults.standard.bool(forKey: ghostReadKey) }
        set { UserDefaults.standard.set(newValue, forKey: ghostReadKey) }
    }

    /// "Local pinned chats": server pins seed once on entry, then pinning is
    /// local-only (not synced, not overwritten by the server).
    public static var localPins: Bool {
        get { return UserDefaults.standard.bool(forKey: localPinsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: localPinsKey)
            if newValue {
                // Re-seed from the server once after (re)enabling.
                UserDefaults.standard.set(false, forKey: pinsSeededKey)
            }
        }
    }
}

private struct QuantgramState: Equatable {
    var ghostRead: Bool
    var localPins: Bool
}

private final class QuantgramAdvancedArguments {
    let toggleGhostRead: (Bool) -> Void
    let toggleLocalPins: (Bool) -> Void
    init(toggleGhostRead: @escaping (Bool) -> Void, toggleLocalPins: @escaping (Bool) -> Void) {
        self.toggleGhostRead = toggleGhostRead
        self.toggleLocalPins = toggleLocalPins
    }
}

private enum QuantgramSection: Int32 {
    case reading
    case pins
}

private enum QuantgramEntry: ItemListNodeEntry {
    case ghostRead(PresentationTheme, String, Bool)
    case ghostReadInfo(PresentationTheme, String)
    case localPins(PresentationTheme, String, Bool)
    case localPinsInfo(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
            case .ghostRead, .ghostReadInfo:
                return QuantgramSection.reading.rawValue
            case .localPins, .localPinsInfo:
                return QuantgramSection.pins.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
            case .ghostRead:
                return 0
            case .ghostReadInfo:
                return 1
            case .localPins:
                return 2
            case .localPinsInfo:
                return 3
        }
    }

    static func <(lhs: QuantgramEntry, rhs: QuantgramEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! QuantgramAdvancedArguments
        switch self {
            case let .ghostRead(_, text, value):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.toggleGhostRead(value)
                })
            case let .ghostReadInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .localPins(_, text, value):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.toggleLocalPins(value)
                })
            case let .localPinsInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func quantgramAdvancedEntries(presentationData: PresentationData, state: QuantgramState) -> [QuantgramEntry] {
    var entries: [QuantgramEntry] = []
    entries.append(.ghostRead(presentationData.theme, "Read without read receipt", state.ghostRead))
    entries.append(.ghostReadInfo(presentationData.theme, "When enabled, incoming messages are marked as read only after you send a reply in the chat."))
    entries.append(.localPins(presentationData.theme, "Local pinned chats", state.localPins))
    entries.append(.localPinsInfo(presentationData.theme, "Server pinned chats load once on sign-in, then pinning is local-only (not synced, not limited by the server). Pins won't appear on your other devices."))
    return entries
}

public func quantgramAdvancedController(context: AccountContext) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }

    let statePromise = ValuePromise<QuantgramState>(QuantgramState(ghostRead: QuantgramSettings.ghostRead, localPins: QuantgramSettings.localPins), ignoreRepeated: true)

    let arguments = QuantgramAdvancedArguments(toggleGhostRead: { value in
        QuantgramSettings.ghostRead = value
        statePromise.set(QuantgramState(ghostRead: QuantgramSettings.ghostRead, localPins: QuantgramSettings.localPins))
    }, toggleLocalPins: { value in
        QuantgramSettings.localPins = value
        statePromise.set(QuantgramState(ghostRead: QuantgramSettings.ghostRead, localPins: QuantgramSettings.localPins))
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Advanced"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: quantgramAdvancedEntries(presentationData: presentationData, state: state), style: .blocks, emptyStateItem: nil, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(presentationData: ItemListPresentationData(presentationData), updatedPresentationData: context.sharedContext.presentationData |> map(ItemListPresentationData.init(_:)), state: signal, tabBarItem: nil)
    return controller
}
