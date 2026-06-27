import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// Quantgram fork settings (non-standard features). Stored in standard
// UserDefaults so both the UI here and the core read-receipt logic can read the
// same flags within the app process.
public struct QuantgramSettings {
    private static let ghostReadKey = "quantgram.ghostRead"

    /// "Read without read receipt": incoming messages are marked read only after
    /// the user sends a reply in the chat.
    public static var ghostRead: Bool {
        get { return UserDefaults.standard.bool(forKey: ghostReadKey) }
        set { UserDefaults.standard.set(newValue, forKey: ghostReadKey) }
    }
}

private final class QuantgramAdvancedArguments {
    let toggleGhostRead: (Bool) -> Void
    init(toggleGhostRead: @escaping (Bool) -> Void) {
        self.toggleGhostRead = toggleGhostRead
    }
}

private enum QuantgramSection: Int32 {
    case reading
}

private enum QuantgramEntry: ItemListNodeEntry {
    case ghostRead(PresentationTheme, String, Bool)
    case ghostReadInfo(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
            case .ghostRead, .ghostReadInfo:
                return QuantgramSection.reading.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
            case .ghostRead:
                return 0
            case .ghostReadInfo:
                return 1
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
        }
    }
}

private func quantgramAdvancedEntries(presentationData: PresentationData, ghostRead: Bool) -> [QuantgramEntry] {
    var entries: [QuantgramEntry] = []
    entries.append(.ghostRead(presentationData.theme, "Read without read receipt", ghostRead))
    entries.append(.ghostReadInfo(presentationData.theme, "When enabled, incoming messages are marked as read only after you send a reply in the chat."))
    return entries
}

public func quantgramAdvancedController(context: AccountContext) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }

    let statePromise = ValuePromise<Bool>(QuantgramSettings.ghostRead, ignoreRepeated: true)

    let arguments = QuantgramAdvancedArguments(toggleGhostRead: { value in
        QuantgramSettings.ghostRead = value
        statePromise.set(value)
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, ghostRead -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Advanced"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: quantgramAdvancedEntries(presentationData: presentationData, ghostRead: ghostRead), style: .blocks, emptyStateItem: nil, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(presentationData: ItemListPresentationData(presentationData), updatedPresentationData: context.sharedContext.presentationData |> map(ItemListPresentationData.init(_:)), state: signal, tabBarItem: nil)
    return controller
}
