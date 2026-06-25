import UIKit
import Phantom

@objc(Application) class Application: UIApplication {
    override init() {
        super.init()
        // Stage 2c-1 smoke test: verify the Phantom gomobile framework links and
        // its exported symbols are callable. Replaced by real wiring in 2c-2.
        NSLog("[Phantom] binding version: \(PhantommobileBindingVersion())")
    }

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
    }
}
