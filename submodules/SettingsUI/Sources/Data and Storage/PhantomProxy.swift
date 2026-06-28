import Foundation
import UIKit
import Network
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
public let phantomLocalSocksPort: Int32 = 1081

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
public func phantomConfigJSON(_ c: PhantomProxyConfig) -> String {
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
public func phantomEngineStart(_ json: String) -> String? {
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

/// Returns recent engine log output (on-device diagnostics).
func phantomLogTail() -> String {
    guard let res = PhantomLogTail() else { return "" }
    defer { PhantomFreeString(res) }
    return String(cString: res)
}

/// Measures the TCP connect time (ms) to host:port, e.g. to show the latency of
/// a Phantom server before connecting. Calls completion on the main queue with
/// the round-trip in milliseconds, or nil if unreachable within the timeout.
public func phantomMeasurePing(host: String, port: UInt16, completion: @escaping (Int?) -> Void) {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
        DispatchQueue.main.async { completion(nil) }
        return
    }
    let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
    let start = Date()
    var finished = false
    let finish: (Int?) -> Void = { ms in
        if finished {
            return
        }
        finished = true
        connection.cancel()
        DispatchQueue.main.async { completion(ms) }
    }
    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            finish(Int(Date().timeIntervalSince(start) * 1000.0))
        case .failed, .cancelled:
            finish(nil)
        default:
            break
        }
    }
    connection.start(queue: DispatchQueue.global(qos: .userInitiated))
    DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
        finish(nil)
    }
}

// MARK: - Share link (phantom://) — interoperable with the desktop/server format
// (internal/panel/share.go): "phantom://" + base64url(JSON{v,name,transport,
// server,sni,reality_public,short_id,secret}).

private struct phantomShareJSON: Codable {
    var v: Int
    var name: String?
    var transport: String
    var server: String
    var sni: String
    var reality_public: String?
    var short_id: String?
    var secret: String
}

private func phantomBase64urlEncode(_ data: Data) -> String {
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func phantomBase64urlDecode(_ s: String) -> Data? {
    var str = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let rem = str.count % 4
    if rem > 0 {
        str += String(repeating: "=", count: 4 - rem)
    }
    return Data(base64Encoded: str)
}

/// Builds a shareable phantom:// link from a config.
func phantomShareLink(_ c: PhantomProxyConfig) -> String {
    let sc = phantomShareJSON(v: 1, name: "Phantom", transport: "reality", server: c.remote, sni: c.sni, reality_public: c.realityPublicKey, short_id: c.realityShortId, secret: c.secret)
    guard let data = try? JSONEncoder().encode(sc) else { return "" }
    return "phantom://" + phantomBase64urlEncode(data)
}

/// Parses a phantom:// link into a config, or nil if not a valid link.
public func phantomParseShareLink(_ s: String) -> PhantomProxyConfig? {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("phantom://") else { return nil }
    let b64 = String(trimmed.dropFirst("phantom://".count))
    guard let data = phantomBase64urlDecode(b64),
          let sc = try? JSONDecoder().decode(phantomShareJSON.self, from: data),
          !sc.server.isEmpty else {
        return nil
    }
    return PhantomProxyConfig(remote: sc.server, secret: sc.secret, sni: sc.sni, realityPublicKey: sc.reality_public ?? "", realityShortId: sc.short_id ?? "", vision: true, postQuantum: true, tlsFragment: true)
}

// MARK: - Persistence

public func phantomSavePersisted(config: PhantomProxyConfig, enabled: Bool) {
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

// MARK: - App lifecycle (background → foreground recovery) + reconnect

// Weak reference to the shared account manager, set from the app delegate at
// launch. Needed to nudge Telegram to re-dial the proxy after recovery.
private weak var phantomStoredAccountManager: AccountManager<TelegramAccountManagerTypes>?

/// Provides the shared account manager so background→foreground recovery can
/// force Telegram to re-dial the proxy. Call once at launch.
public func phantomSetAccountManager(_ accountManager: AccountManager<TelegramAccountManagerTypes>) {
    phantomStoredAccountManager = accountManager
    PhantomLifecycleObserver.shared.register()
}

/// Recovers the Phantom connection: restarts the engine (fresh local SOCKS5
/// listener + upstream) and then forces Telegram to drop and re-dial the proxy
/// — exactly what manually toggling the proxy off/on does. This is the reliable
/// fix for a dead connection after the app was suspended in background.
public func phantomReconnect(accountManager: AccountManager<TelegramAccountManagerTypes>) {
    phantomStoredAccountManager = accountManager
    guard let config = phantomLoadConfig() else {
        return
    }
    let json = phantomConfigJSON(config)
    let server = phantomLocalProxyServer()
    // Stopping the engine waits for the port to be released; do it off the main
    // thread so app activation isn't blocked.
    DispatchQueue.global(qos: .userInitiated).async {
        _ = phantomEngineStart(json)
        Queue.mainQueue().async {
            let _ = updateProxySettingsInteractively(accountManager: accountManager, { settings in
                var settings = settings
                settings.enabled = false
                return settings
            }).start(completed: {
                // Give Telegram a moment to tear down the old proxy connection,
                // then re-activate so it re-dials through the fresh listener.
                Queue.mainQueue().after(0.4, {
                    let _ = updateProxySettingsInteractively(accountManager: accountManager, { settings in
                        var settings = settings
                        if !settings.servers.contains(server) {
                            settings.servers.append(server)
                        }
                        settings.activeServer = server
                        settings.enabled = true
                        return settings
                    }).start()
                })
            })
        }
    }
}

// When the app is suspended in background (or the screen is locked), iOS freezes
// the in-process Phantom engine and tears down its sockets. On resume the engine
// may still report "running" but is dead, so Telegram keeps dialing the local
// port with no working tunnel — previously only an app restart (or toggling the
// proxy off/on a few times) fixed it. We recover automatically on resume.
private final class PhantomLifecycleObserver {
    static let shared = PhantomLifecycleObserver()
    private var registered = false
    private var leftActiveAt: Date?

    func register() {
        if self.registered {
            return
        }
        self.registered = true
        NotificationCenter.default.addObserver(self, selector: #selector(self.willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func willResignActive() {
        if self.leftActiveAt == nil {
            self.leftActiveAt = Date()
        }
    }

    @objc private func didBecomeActive() {
        let elapsed = self.leftActiveAt.map { Date().timeIntervalSince($0) } ?? 0.0
        self.leftActiveAt = nil

        guard let (config, enabled) = phantomLoadPersisted(), enabled else {
            return
        }
        // Skip recovery for brief interruptions where the engine is still alive.
        if elapsed < 3.0 && phantomEngineIsRunning() {
            return
        }
        if let accountManager = phantomStoredAccountManager {
            phantomReconnect(accountManager: accountManager)
        } else {
            // No account manager available yet — at least refresh the engine.
            let json = phantomConfigJSON(config)
            DispatchQueue.global(qos: .userInitiated).async {
                _ = phantomEngineStart(json)
            }
        }
    }
}

/// Called once early in app launch (from Application.init). Registers the
/// recovery observer, and if a Phantom proxy was enabled, (re)starts the engine
/// so the local SOCKS5 listener is up before Telegram's network restores and
/// dials the active (local) proxy.
public func phantomApplyPersistedConfigAtLaunch() {
    PhantomLifecycleObserver.shared.register()
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

/// Reports whether the given proxy server is our local Phantom entry
/// (127.0.0.1:<phantomLocalSocksPort> SOCKS5).
func phantomIsLocalProxy(_ server: ProxyServerSettings) -> Bool {
    guard server.host == phantomLocalSocksHost, server.port == phantomLocalSocksPort else {
        return false
    }
    if case .socks5 = server.connection {
        return true
    }
    return false
}

/// Returns the persisted Phantom config (reality params), if any.
func phantomLoadConfig() -> PhantomProxyConfig? {
    return phantomLoadPersisted()?.config
}

/// Adds (if missing) and activates the local SOCKS5 proxy in the account
/// manager's proxy settings, enabling proxying.
public func phantomActivateLocalProxy(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
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
