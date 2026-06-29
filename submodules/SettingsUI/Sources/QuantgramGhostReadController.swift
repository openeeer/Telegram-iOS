import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private struct QuantgramGhostReadState: Equatable {
    var light: Bool
    var full: Bool
    var ghostLocked: Bool
}

private func currentGhostReadState() -> QuantgramGhostReadState {
    let ghostLocked = UserDefaults.standard.bool(forKey: "quantgram.ghostMode")
    let stored = QuantgramGhostRead.storedMode
    return QuantgramGhostReadState(
        light: !ghostLocked && stored == .light,
        full: ghostLocked || stored == .full,
        ghostLocked: ghostLocked
    )
}

private final class QuantgramGhostReadArguments {
    let toggleLight: (Bool) -> Void
    let toggleFull: (Bool) -> Void
    init(toggleLight: @escaping (Bool) -> Void, toggleFull: @escaping (Bool) -> Void) {
        self.toggleLight = toggleLight
        self.toggleFull = toggleFull
    }
}

private enum QuantgramGhostReadSection: Int32 {
    case light
    case full
}

private enum QuantgramGhostReadEntry: ItemListNodeEntry {
    case light(PresentationTheme, String, Bool, Bool)
    case lightInfo(PresentationTheme, String)
    case full(PresentationTheme, String, Bool, Bool)
    case fullInfo(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
            case .light, .lightInfo:
                return QuantgramGhostReadSection.light.rawValue
            case .full, .fullInfo:
                return QuantgramGhostReadSection.full.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
            case .light:
                return 0
            case .lightInfo:
                return 1
            case .full:
                return 2
            case .fullInfo:
                return 3
        }
    }

    static func <(lhs: QuantgramGhostReadEntry, rhs: QuantgramGhostReadEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! QuantgramGhostReadArguments
        switch self {
            case let .light(_, text, value, enabled):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, enableInteractiveChanges: enabled, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.toggleLight(value)
                })
            case let .lightInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .full(_, text, value, enabled):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, enableInteractiveChanges: enabled, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.toggleFull(value)
                })
            case let .fullInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func quantgramGhostReadEntries(presentationData: PresentationData, state: QuantgramGhostReadState) -> [QuantgramGhostReadEntry] {
    var entries: [QuantgramGhostReadEntry] = []
    let enabled = !state.ghostLocked
    entries.append(.light(presentationData.theme, "Light", state.light, enabled))
    entries.append(.lightInfo(presentationData.theme, "Сообщения остаются непрочитанными, пока вы не отправите ответ в этом чате."))
    entries.append(.full(presentationData.theme, "Full", state.full, enabled))
    if state.ghostLocked {
        entries.append(.fullInfo(presentationData.theme, "Сообщения никогда не помечаются прочитанными автоматически. Включено принудительно режимом «Призрак»."))
    } else {
        entries.append(.fullInfo(presentationData.theme, "Сообщения никогда не помечаются прочитанными автоматически, даже после отправки ответа."))
    }
    return entries
}

public func quantgramGhostReadController(context: AccountContext) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }

    let statePromise = ValuePromise<QuantgramGhostReadState>(currentGhostReadState(), ignoreRepeated: true)

    let arguments = QuantgramGhostReadArguments(toggleLight: { value in
        if UserDefaults.standard.bool(forKey: "quantgram.ghostMode") {
            return
        }
        if value {
            QuantgramGhostRead.setStoredMode(.light)
        } else if QuantgramGhostRead.storedMode == .light {
            QuantgramGhostRead.setStoredMode(.off)
        }
        statePromise.set(currentGhostReadState())
    }, toggleFull: { value in
        if UserDefaults.standard.bool(forKey: "quantgram.ghostMode") {
            return
        }
        if value {
            QuantgramGhostRead.setStoredMode(.full)
        } else if QuantgramGhostRead.storedMode == .full {
            QuantgramGhostRead.setStoredMode(.off)
        }
        statePromise.set(currentGhostReadState())
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Нечиталка"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: quantgramGhostReadEntries(presentationData: presentationData, state: state), style: .blocks, emptyStateItem: nil, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(presentationData: ItemListPresentationData(presentationData), updatedPresentationData: context.sharedContext.presentationData |> map(ItemListPresentationData.init(_:)), state: signal, tabBarItem: nil)
    return controller
}
