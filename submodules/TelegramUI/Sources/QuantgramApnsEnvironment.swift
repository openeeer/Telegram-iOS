import Foundation

// Quantgram: detect the actual APNs environment from the embedded provisioning
// profile (aps-environment entitlement) instead of relying on the build
// configuration (#if DEBUG). This is required for sideloaded / re-signed builds
// (e.g. via eSign with a development/ad-hoc certificate): such builds are signed
// with aps-environment = "development", so their APNs token is a SANDBOX token.
// Registering it as production makes Apple drop the pushes — the classic
// "notifications only arrive when opening the app" symptom.
//
// Returns true when the app is signed for the sandbox (development) APNs gateway.
func quantgramApnsEnvironmentIsSandbox() -> Bool {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
          let data = try? Data(contentsOf: url),
          let raw = String(data: data, encoding: .isoLatin1) else {
        // No embedded provisioning profile (App Store build) — production.
        return false
    }
    guard let plistStart = raw.range(of: "<plist"),
          let plistEnd = raw.range(of: "</plist>") else {
        return false
    }
    let plistString = String(raw[plistStart.lowerBound ..< plistEnd.upperBound])
    guard let plistData = plistString.data(using: .isoLatin1),
          let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
          let entitlements = plist["Entitlements"] as? [String: Any],
          let apsEnvironment = entitlements["aps-environment"] as? String else {
        return false
    }
    return apsEnvironment.lowercased() == "development"
}
