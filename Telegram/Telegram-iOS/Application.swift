import UIKit
import SettingsUI

@objc(Application) class Application: UIApplication {
    override init() {
        super.init()
        // If a Phantom proxy was configured & enabled, (re)start the embedded
        // engine early so its local SOCKS5 listener is up before Telegram's
        // network restores and dials the active (local) proxy.
        phantomApplyPersistedConfigAtLaunch()
    }

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
    }
}
