import Foundation
import Phantom
import TelegramCore
import SwiftSignalKit

// Phantom proxy integration.
//
// "Phantom" is not a plain ProxyServerSettings the OS dials directly — it is an
// embedded Go engine (statically linked, see third-party/Phantom) that runs a
// local SOCKS5 listener on 127.0.0.1:1080. Selecting a Phantom proxy:
//   1. persists the reality config (UserDefaults.standard — same process reads
//      it; no app group needed, robust to sideload re-signing),
//   2. starts the engine (PhantomStart),
//   3. activates a SOCKS5 ProxyServerSettings pointing at the local listener, so
//      Telegram's MTProto transport routes through the tunnel.

public let phantomLocalSocksHost = "127.0.0.1"
public let phantomLocalSocksPort: Int32 = 1080

/// User-entered Phantom (reality) configuration.
public struct PhantomProxyConfig: Codable, Equatable {
    public var remote: String // "host:port"
    public var secret: String // hex, >= 16 bytes
    public var sni: String
    public var realityPublicKey: String // base64 raw-url
    public var realityShortId: String   // hex, 8 bytes
    public var vision: Bool
    public var postQuantum: Bool
    public var tlsFragment: Bool

    public init(remote: String, secret: String, sni: String, realityPublicKey: String, realityShortId: String, vision: Bool, postQuantum: Bool, tlsFragment: Bool) {
        self.remote = remote
        self.secret = secret
        self.sni = sni
        self.realityPublicKey = realityPublicKey
        self.realityShortId = realityShortId
        self.vision = vision
        self.postQuantum = postQuantum
        self.tlsFragment = tlsFragment
    }
}

private let phantomEnabledKey = "phantom.enabled"
private let phantomConfigKey = "phantom.config.v1"

/// Serializes the config into the JSON schema expected by the engine
/// (phantom/mobile Config). The local SOCKS5 address is injected here.
func phantomConfigJSON(_ c: PhantomProxyConfig) -> String {
    let dict: [String: Any] = [
        "remote": c.remote,
        "transport": "reality",
        "sni": c.sni,
        "secret": c.secret,
        "reality_public_key": c.realityPublicKey,
        "reality_short_id": c.realityShortId,
        "socks": "\(phantomLocalSocksHost):\(phantomLocalSocksPort)",
        "vision": c.vision,
        "post_quantum": c.postQuantum,
        "tls_fragment": c.tlsFragment,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
          let json = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return json
}

/// Starts the engine with the given JSON config. Returns nil on success or the
/// error message on failure. Idempotent (the engine refuses a double start).
@discardableResult
func phantomEngineStart(_ json: String) -> String? {
    return json.withCString { cs -> String? in
        guard let res = PhantomStart(UnsafeMutablePointer(mutating: cs)) else {
            return nil
        }
        defer { PhantomFreeString(res) }
        let msg = String(cString: res)
        return msg.isEmpty ? nil : msg
    }
}

/// Stops the engine (idempotent).
func phantomEngineStop() {
    PhantomStop()
}

func phantomEngineIsRunning() -> Bool {
    return PhantomIsRunning() != 0
}

// MARK: - Persistence

func phantomSavePersisted(config: PhantomProxyConfig, enabled: Bool) {
    let defaults = UserDefaults.standard
    if let data = try? JSONEncoder().encode(config), let s = String(data: data, encoding: .utf8) {
        defaults.set(s, forKey: phantomConfigKey)
    }
    defaults.set(enabled, forKey: phantomEnabledKey)
}

func phantomLoadPersisted() -> (config: PhantomProxyConfig, enabled: Bool)? {
    let defaults = UserDefaults.standard
    guard let s = defaults.string(forKey: phantomConfigKey),
          let data = s.data(using: .utf8),
          let config = try? JSONDecoder().decode(PhantomProxyConfig.self, from: data) else {
        return nil
    }
    return (config, defaults.bool(forKey: phantomEnabledKey))
}

func phantomSetEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: phantomEnabledKey)
}

/// Called once early in app launch (from Application.init). If a Phantom proxy
/// was enabled, (re)starts the engine so the local SOCKS5 listener is up before
/// Telegram's network restores and dials the active (local) proxy.
public func phantomApplyPersistedConfigAtLaunch() {
    guard let (config, enabled) = phantomLoadPersisted(), enabled else {
        return
    }
    _ = phantomEngineStart(phantomConfigJSON(config))
}

// MARK: - Proxy activation

/// The local SOCKS5 server that represents the running Phantom tunnel.
func phantomLocalProxyServer() -> ProxyServerSettings {
    return ProxyServerSettings(host: phantomLocalSocksHost, port: phantomLocalSocksPort, connection: .socks5(username: nil, password: nil))
}

/// Adds (if missing) and activates the local SOCKS5 proxy in the account
/// manager's proxy settings, enabling proxying.
func phantomActivateLocalProxy(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
    let server = phantomLocalProxyServer()
    return updateProxySettingsInteractively(accountManager: accountManager, { settings in
        var settings = settings
        if !settings.servers.contains(server) {
            settings.servers.append(server)
        }
        settings.activeServer = server
        settings.enabled = true
        return settings
    })
}
