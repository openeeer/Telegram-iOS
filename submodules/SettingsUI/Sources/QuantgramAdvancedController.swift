import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// Quantgram fork settings (non-standard features). Stored in standard
// UserDefaults so both the UI here and the core logic can read the same flags
// within the app process.
public struct QuantgramSettings {
    private static let localPinsKey = "quantgram.localPins"
    private static let pinsSeededKey = "quantgram.pinsSeeded"
    private static let disableLinkPreviewsKey = "quantgram.disableLinkPreviews"
    private static let disableSwipeCameraKey = "quantgram.disableSwipeCamera"
    private static let showMessageCountKey = "quantgram.showMessageCount"
    private static let ghostModeKey = "quantgram.ghostMode"
    private static let hideStoriesKey = "quantgram.hideStories"
    private static let hideSearchButtonKey = "quantgram.hideSearchButton"

    /// "Local pinned chats": server pins seed once on entry, then pinning is
    /// local-only (not synced, not overwritten by the server).
    public static var localPins: Bool {
        get { return UserDefaults.standard.bool(forKey: localPinsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: localPinsKey)
            if newValue {
                UserDefaults.standard.set(false, forKey: pinsSeededKey)
            }
        }
    }

    /// "Disable link preview generation": don't request a web page preview while
    /// composing, and strip previews from outgoing messages.
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

    /// "Show message count": display the total number of messages in a chat on
    /// the profile screen.
    public static var showMessageCount: Bool {
        get { return UserDefaults.standard.bool(forKey: showMessageCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: showMessageCountKey) }
    }

    /// "Ghost mode": never report online presence, and force full ghost read.
    public static var ghostMode: Bool {
        get { return UserDefaults.standard.bool(forKey: ghostModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: ghostModeKey) }
    }

    /// "Hide stories": fully hide the stories block on the Chats screen.
    public static var hideStories: Bool {
        get { return UserDefaults.standard.bool(forKey: hideStoriesKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideStoriesKey) }
    }

    /// "Hide search button": hide the tab-bar search button on the Chats screen
    /// (the pull-down search bar stays).
    public static var hideSearchButton: Bool {
        get { return UserDefaults.standard.bool(forKey: hideSearchButtonKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideSearchButtonKey) }
    }
}

private struct QuantgramState: Equatable {
    var localPins: Bool
    var disableLinkPreviews: Bool
    var disableSwipeCamera: Bool
    var showMessageCount: Bool
    var ghostMode: Bool
    var hideStories: Bool
    var hideSearchButton: Bool
}

private func currentQuantgramState() -> QuantgramState {
    return QuantgramState(localPins: QuantgramSettings.localPins, disableLinkPreviews: QuantgramSettings.disableLinkPreviews, disableSwipeCamera: QuantgramSettings.disableSwipeCamera, showMessageCount: QuantgramSettings.showMessageCount, ghostMode: QuantgramSettings.ghostMode, hideStories: QuantgramSettings.hideStories, hideSearchButton: QuantgramSettings.hideSearchButton)
}

private final class QuantgramAdvancedArguments {
    let openGhostRead: () -> Void
    let toggleLocalPins: (Bool) -> Void
    let toggleDisableLinkPreviews: (Bool) -> Void
    let toggleDisableSwipeCamera: (Bool) -> Void
    let toggleShowMessageCount: (Bool) -> Void
    let toggleGhostMode: (Bool) -> Void
    let toggleHideStories: (Bool) -> Void
    let toggleHideSearchButton: (Bool) -> Void
    init(openGhostRead: @escaping () -> Void, toggleLocalPins: @escaping (Bool) -> Void, toggleDisableLinkPreviews: @escaping (Bool) -> Void, toggleDisableSwipeCamera: @escaping (Bool) -> Void, toggleShowMessageCount: @escaping (Bool) -> Void, toggleGhostMode: @escaping (Bool) -> Void, toggleHideStories: @escaping (Bool) -> Void, toggleHideSearchButton: @escaping (Bool) -> Void) {
        self.openGhostRead = openGhostRead
        self.toggleLocalPins = toggleLocalPins
        self.toggleDisableLinkPreviews = toggleDisableLinkPreviews
        self.toggleDisableSwipeCamera = toggleDisableSwipeCamera
        self.toggleShowMessageCount = toggleShowMessageCount
        self.toggleGhostMode = toggleGhostMode
        self.toggleHideStories = toggleHideStories
        self.toggleHideSearchButton = toggleHideSearchButton
    }
}

private enum QuantgramSection: Int32 {
    case ghost
    case reading
    case pins
    case links
    case camera
    case chats
    case messages
}

private enum QuantgramEntry: ItemListNodeEntry {
    case ghostMode(PresentationTheme, String, Bool)
    case ghostModeInfo(PresentationTheme, String)
    case ghostRead(PresentationTheme, String)
    case ghostReadInfo(PresentationTheme, String)
    case localPins(PresentationTheme, String, Bool)
    case localPinsInfo(PresentationTheme, String)
    case disableLinkPreviews(PresentationTheme, String, Bool)
    case disableLinkPreviewsInfo(PresentationTheme, String)
    case disableSwipeCamera(PresentationTheme, String, Bool)
    case disableSwipeCameraInfo(PresentationTheme, String)
    case hideStories(PresentationTheme, String, Bool)
    case hideStoriesInfo(PresentationTheme, String)
    case hideSearchButton(PresentationTheme, String, Bool)
    case hideSearchButtonInfo(PresentationTheme, String)
    case showMessageCount(PresentationTheme, String, Bool)
    case showMessageCountInfo(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
            case .ghostMode, .ghostModeInfo:
                return QuantgramSection.ghost.rawValue
            case .ghostRead, .ghostReadInfo:
                return QuantgramSection.reading.rawValue
            case .localPins, .localPinsInfo:
                return QuantgramSection.pins.rawValue
            case .disableLinkPreviews, .disableLinkPreviewsInfo:
                return QuantgramSection.links.rawValue
            case .disableSwipeCamera, .disableSwipeCameraInfo:
                return QuantgramSection.camera.rawValue
            case .hideStories, .hideStoriesInfo, .hideSearchButton, .hideSearchButtonInfo:
                return QuantgramSection.chats.rawValue
            case .showMessageCount, .showMessageCountInfo:
                return QuantgramSection.messages.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
            case .ghostMode:
                return 0
            case .ghostModeInfo:
                return 1
            case .ghostRead:
                return 2
            case .ghostReadInfo:
                return 3
            case .localPins:
                return 4
            case .localPinsInfo:
                return 5
            case .disableLinkPreviews:
                return 6
            case .disableLinkPreviewsInfo:
                return 7
            case .disableSwipeCamera:
                return 8
            case .disableSwipeCameraInfo:
                return 9
            case .hideStories:
                return 10
            case .hideStoriesInfo:
                return 11
            case .hideSearchButton:
                return 12
            case .hideSearchButtonInfo:
                return 13
            case .showMessageCount:
                return 14
            case .showMessageCountInfo:
                return 15
        }
    }

    static func <(lhs: QuantgramEntry, rhs: QuantgramEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! QuantgramAdvancedArguments
        switch self {
            case let .ghostMode(_, text, value):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.toggleGhostMode(value)
                })
            case let .ghostModeInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .ghostRead(_, text):
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: text, label: "", labelStyle: .text, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: {
                    arguments.openGhostRead()
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
            case let .hideStories(_, text, value):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.toggleHideStories(value)
                })
            case let .hideStoriesInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .hideSearchButton(_, text, value):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.toggleHideSearchButton(value)
                })
            case let .hideSearchButtonInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
            case let .showMessageCount(_, text, value):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, enableInteractiveChanges: true, enabled: true, sectionId: self.section, style: .blocks, updated: { value in
                    arguments.toggleShowMessageCount(value)
                })
            case let .showMessageCountInfo(_, text):
                return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func quantgramAdvancedEntries(presentationData: PresentationData, state: QuantgramState) -> [QuantgramEntry] {
    var entries: [QuantgramEntry] = []
    entries.append(.ghostMode(presentationData.theme, "Режим «Призрак»", state.ghostMode))
    entries.append(.ghostModeInfo(presentationData.theme, "Вы не отображаетесь «в сети» даже при активном использовании. Автоматически включается Full-нечиталка (её нельзя отключить, пока активен «Призрак»). Примечание: «последнее посещение» сервер обновляет при действиях — его скрывают настройки приватности Telegram."))
    entries.append(.ghostRead(presentationData.theme, "Нечиталка"))
    entries.append(.ghostReadInfo(presentationData.theme, "Управление чтением сообщений без отправки галочек о прочтении: режимы Light и Full."))
    entries.append(.localPins(presentationData.theme, "Локальные закреплённые чаты", state.localPins))
    entries.append(.localPinsInfo(presentationData.theme, "Закреплённые чаты загружаются с сервера один раз при входе, дальше закрепление работает только локально (не синхронизируется и не ограничивается лимитом сервера). На других устройствах эти закрепления не появятся."))
    entries.append(.disableLinkPreviews(presentationData.theme, "Не генерировать превью ссылок", state.disableLinkPreviews))
    entries.append(.disableLinkPreviewsInfo(presentationData.theme, "Превью ссылок не запрашивается с сервера при наборе и не прикрепляется к вашим отправленным сообщениям — меньше трафика и следов."))
    entries.append(.disableSwipeCamera(presentationData.theme, "Не открывать камеру свайпом", state.disableSwipeCamera))
    entries.append(.disableSwipeCameraInfo(presentationData.theme, "Свайп по списку чатов больше не открывает камеру историй. Переключение папок свайпом продолжает работать."))
    entries.append(.hideStories(presentationData.theme, "Скрыть истории", state.hideStories))
    entries.append(.hideStoriesInfo(presentationData.theme, "Блок историй на экране «Чаты» полностью скрывается — нет ни блока, ни свёрнутого состояния, ни анимации разворота."))
    entries.append(.hideSearchButton(presentationData.theme, "Скрыть кнопку поиска", state.hideSearchButton))
    entries.append(.hideSearchButtonInfo(presentationData.theme, "Круглая кнопка поиска в нижней панели скрывается на всех вкладках (Чаты, Контакты, Звонки, Настройки). Строка поиска (свайп списка вниз) остаётся."))
    entries.append(.showMessageCount(presentationData.theme, "Показывать количество сообщений", state.showMessageCount))
    entries.append(.showMessageCountInfo(presentationData.theme, "В профиле чата (ЛС и группы) показывается общее число сообщений в переписке."))
    return entries
}

public func quantgramAdvancedController(context: AccountContext) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }

    var pushControllerImpl: ((ViewController) -> Void)?

    let statePromise = ValuePromise<QuantgramState>(currentQuantgramState(), ignoreRepeated: true)

    let arguments = QuantgramAdvancedArguments(openGhostRead: {
        pushControllerImpl?(quantgramGhostReadController(context: context))
    }, toggleLocalPins: { value in
        QuantgramSettings.localPins = value
        statePromise.set(currentQuantgramState())
    }, toggleDisableLinkPreviews: { value in
        QuantgramSettings.disableLinkPreviews = value
        statePromise.set(currentQuantgramState())
    }, toggleDisableSwipeCamera: { value in
        QuantgramSettings.disableSwipeCamera = value
        statePromise.set(currentQuantgramState())
    }, toggleShowMessageCount: { value in
        QuantgramSettings.showMessageCount = value
        statePromise.set(currentQuantgramState())
    }, toggleGhostMode: { value in
        QuantgramSettings.ghostMode = value
        context.account.shouldKeepOnlinePresence.set(.single(!value))
        statePromise.set(currentQuantgramState())
    }, toggleHideStories: { value in
        QuantgramSettings.hideStories = value
        statePromise.set(currentQuantgramState())
    }, toggleHideSearchButton: { value in
        QuantgramSettings.hideSearchButton = value
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
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}
