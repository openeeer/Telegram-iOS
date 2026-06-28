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
    private static let disableLinkPreviewsKey = "quantgram.disableLinkPreviews"
    private static let disableSwipeCameraKey = "quantgram.disableSwipeCamera"

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

    /// "Disable link preview generation": don't request a web page preview from
    /// the server while composing, and strip previews from outgoing messages.
    public static var disableLinkPreviews: Bool {
        get { return UserDefaults.standard.bool(forKey: disableLinkPreviewsKey) }
        set { UserDefaults.standard.set(newValue, forKey: disableLinkPreviewsKey) }
    }

    /// "Disable swipe-to-camera": don't open the story camera when swiping the
    /// chat list horizontally.
    public static var disableSwipeCamera: Bool {
        get { return UserDefaults.standard.bool(forKey: disableSwipeCameraKey) }
        set { UserDefaults.standard.set(newValue, forKey: disableSwipeCameraKey) }
    }
}

private struct QuantgramState: Equatable {
    var ghostRead: Bool
    var localPins: Bool
    var disableLinkPreviews: Bool
    var disableSwipeCamera: Bool
}

private func currentQuantgramState() -> QuantgramState {
    return QuantgramState(ghostRead: QuantgramSettings.ghostRead, localPins: QuantgramSettings.localPins, disableLinkPreviews: QuantgramSettings.disableLinkPreviews, disableSwipeCamera: QuantgramSettings.disableSwipeCamera)
}

private final class QuantgramAdvancedArguments {
    let toggleGhostRead: (Bool) -> Void
    let toggleLocalPins: (Bool) -> Void
    let toggleDisableLinkPreviews: (Bool) -> Void
    let toggleDisableSwipeCamera: (Bool) -> Void
    init(toggleGhostRead: @escaping (Bool) -> Void, toggleLocalPins: @escaping (Bool) -> Void, toggleDisableLinkPreviews: @escaping (Bool) -> Void, toggleDisableSwipeCamera: @escaping (Bool) -> Void) {
        self.toggleGhostRead = toggleGhostRead
        self.toggleLocalPins = toggleLocalPins
        self.toggleDisableLinkPreviews = toggleDisableLinkPreviews
        self.toggleDisableSwipeCamera = toggleDisableSwipeCamera
    }
}

private enum QuantgramSection: Int32 {
    case reading
    case pins
    case links
    case camera
}

private enum QuantgramEntry: ItemListNodeEntry {
    case ghostRead(PresentationTheme, String, Bool)
    case ghostReadInfo(PresentationTheme, String)
    case localPins(PresentationTheme, String, Bool)
    case localPinsInfo(PresentationTheme, String)
    case disableLinkPreviews(PresentationTheme, String, Bool)
    case disableLinkPreviewsInfo(PresentationTheme, String)
    case disableSwipeCamera(PresentationTheme, String, Bool)
    case disableSwipeCameraInfo(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
            case .ghostRead, .ghostReadInfo:
                return QuantgramSection.reading.rawValue
            case .localPins, .localPinsInfo:
                return QuantgramSection.pins.rawValue
            case .disableLinkPreviews, .disableLinkPreviewsInfo:
                return QuantgramSection.links.rawValue
            case .disableSwipeCamera, .disableSwipeCameraInfo:
                return QuantgramSection.camera.rawValue
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
            case .disableLinkPreviews:
                return 4
            case .disableLinkPreviewsInfo:
                return 5
            case .disableSwipeCamera:
                return 6
            case .disableSwipeCameraInfo:
                return 7
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
            case let .disableLinkPreviews(_, text, value):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.toggleDisableLinkPreviews(value)
                })
            case let .disableLinkPreviewsInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .disableSwipeCamera(_, text, value):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.toggleDisableSwipeCamera(value)
                })
            case let .disableSwipeCameraInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func quantgramAdvancedEntries(presentationData: PresentationData, state: QuantgramState) -> [QuantgramEntry] {
    var entries: [QuantgramEntry] = []
    entries.append(.ghostRead(presentationData.theme, "Чтение без галочек", state.ghostRead))
    entries.append(.ghostReadInfo(presentationData.theme, "Входящие сообщения помечаются прочитанными только после того, как вы ответите в чате."))
    entries.append(.localPins(presentationData.theme, "Локальные закреплённые чаты", state.localPins))
    entries.append(.localPinsInfo(presentationData.theme, "Закреплённые чаты загружаются с сервера один раз при входе, дальше закрепление работает только локально (не синхронизируется и не ограничивается лимитом сервера). На других устройствах эти закрепления не появятся."))
    entries.append(.disableLinkPreviews(presentationData.theme, "Не генерировать превью ссылок", state.disableLinkPreviews))
    entries.append(.disableLinkPreviewsInfo(presentationData.theme, "Превью ссылок не запрашивается с сервера при наборе и не прикрепляется к вашим отправленным сообщениям — меньше трафика и следов."))
    entries.append(.disableSwipeCamera(presentationData.theme, "Не открывать камеру свайпом", state.disableSwipeCamera))
    entries.append(.disableSwipeCameraInfo(presentationData.theme, "Свайп по списку чатов больше не открывает камеру историй. Переключение папок свайпом продолжает работать."))
    return entries
}

public func quantgramAdvancedController(context: AccountContext) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }

    let statePromise = ValuePromise<QuantgramState>(currentQuantgramState(), ignoreRepeated: true)

    let arguments = QuantgramAdvancedArguments(toggleGhostRead: { value in
        QuantgramSettings.ghostRead = value
        statePromise.set(currentQuantgramState())
    }, toggleLocalPins: { value in
        QuantgramSettings.localPins = value
        statePromise.set(currentQuantgramState())
    }, toggleDisableLinkPreviews: { value in
        QuantgramSettings.disableLinkPreviews = value
        statePromise.set(currentQuantgramState())
    }, toggleDisableSwipeCamera: { value in
        QuantgramSettings.disableSwipeCamera = value
        statePromise.set(currentQuantgramState())
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Дополнительно"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: quantgramAdvancedEntries(presentationData: presentationData, state: state), style: .blocks, emptyStateItem: nil, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(presentationData: ItemListPresentationData(presentationData), updatedPresentationData: context.sharedContext.presentationData |> map(ItemListPresentationData.init(_:)), state: signal, tabBarItem: nil)
    return controller
}
