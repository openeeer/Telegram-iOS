import UIKit
import Phantom

@objc(Application) class Application: UIApplication {
    override init() {
        super.init()
        // Stage 2c-1 smoke test: verify the Phantom static library links and its
        // C-exported symbols are callable. Replaced by real wiring in 2c-2.
        if let v = PhantomBindingVersion() {
            NSLog("[Phantom] binding version: \(String(cString: v))")
            PhantomFreeString(v)
        }
    }

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
    }
}
