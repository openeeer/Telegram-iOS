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
private let phantomConfigKey = "phantom.config.v1"     // legacy single config (migrated)
private let phantomConfigsKey = "phantom.configs.v2"   // list of saved configs
private let phantomActivePortKey = "phantom.activePort"

/// A saved Phantom connection: the reality config plus a stable id, a display
/// name and the dedicated local SOCKS5 port that represents it in the proxy list.
public struct PhantomSavedConfig: Codable, Equatable {
    public var id: String
    public var name: String
    public var port: Int32
    public var config: PhantomProxyConfig
}

private func phantomDecodeConfigs() -> [PhantomSavedConfig] {
    guard let s = UserDefaults.standard.string(forKey: phantomConfigsKey),
          let data = s.data(using: .utf8),
          let list = try? JSONDecoder().decode([PhantomSavedConfig].self, from: data) else {
        return []
    }
    return list
}

private func phantomEncodeConfigs(_ list: [PhantomSavedConfig]) {
    if let data = try? JSONEncoder().encode(list), let s = String(data: data, encoding: .utf8) {
        UserDefaults.standard.set(s, forKey: phantomConfigsKey)
    }
}

private func phantomDefaultName(for config: PhantomProxyConfig) -> String {
    if let idx = config.remote.firstIndex(of: ":") {
        return String(config.remote[..<idx])
    }
    if !config.sni.isEmpty {
        return config.sni
    }
    return config.remote.isEmpty ? "Phantom" : config.remote
}

/// Returns all saved Phantom configs, migrating a legacy single config on first run.
public func phantomLoadConfigs() -> [PhantomSavedConfig] {
    var list = phantomDecodeConfigs()
    if list.isEmpty {
        let defaults = UserDefaults.standard
        if let s = defaults.string(forKey: phantomConfigKey), let data = s.data(using: .utf8),
           let legacy = try? JSONDecoder().decode(PhantomProxyConfig.self, from: data) {
            let entry = PhantomSavedConfig(id: UUID().uuidString, name: phantomDefaultName(for: legacy), port: phantomLocalSocksPort, config: legacy)
            list = [entry]
            phantomEncodeConfigs(list)
            if defaults.object(forKey: phantomActivePortKey) == nil {
                defaults.set(Int(phantomLocalSocksPort), forKey: phantomActivePortKey)
            }
        }
    }
    return list
}

public func phantomSaveConfigs(_ list: [PhantomSavedConfig]) {
    phantomEncodeConfigs(list)
}

public func phantomActivePort() -> Int32? {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: phantomActivePortKey) == nil {
        return nil
    }
    return Int32(defaults.integer(forKey: phantomActivePortKey))
}

public func phantomSetActivePort(_ port: Int32?) {
    let defaults = UserDefaults.standard
    if let port = port {
        defaults.set(Int(port), forKey: phantomActivePortKey)
    } else {
        defaults.removeObject(forKey: phantomActivePortKey)
    }
}

/// The currently active saved config (the one whose local port is selected).
public func phantomActiveEntry() -> PhantomSavedConfig? {
    let list = phantomLoadConfigs()
    if let port = phantomActivePort(), let entry = list.first(where: { $0.port == port }) {
        return entry
    }
    return list.first
}

public func phantomAllPorts() -> Set<Int32> {
    return Set(phantomLoadConfigs().map { $0.port })
}

public func phantomConfigForPort(_ port: Int32) -> PhantomSavedConfig? {
    return phantomLoadConfigs().first(where: { $0.port == port })
}

private func phantomNextFreePort() -> Int32 {
    let used = phantomAllPorts()
    var port: Int32 = phantomLocalSocksPort
    while used.contains(port) || port == 1080 {
        port += 1
    }
    return port
}

/// Adds a new saved config (or updates an existing one with the same server +
/// secret), returning the stored entry.
public func phantomAddOrUpdateConfig(config: PhantomProxyConfig, name: String?) -> PhantomSavedConfig {
    var list = phantomLoadConfigs()
    if let index = list.firstIndex(where: { $0.config.remote == config.remote && $0.config.secret == config.secret }) {
        list[index].config = config
        if let name = name, !name.isEmpty {
            list[index].name = name
        }
        phantomEncodeConfigs(list)
        return list[index]
    }
    let resolvedName = (name?.isEmpty == false) ? name! : phantomDefaultName(for: config)
    let entry = PhantomSavedConfig(id: UUID().uuidString, name: resolvedName, port: phantomNextFreePort(), config: config)
    list.append(entry)
    phantomEncodeConfigs(list)
    return entry
}

public func phantomRemoveConfigForPort(_ port: Int32) {
    var list = phantomLoadConfigs()
    list.removeAll(where: { $0.port == port })
    phantomEncodeConfigs(list)
    if phantomActivePort() == port {
        phantomSetActivePort(nil)
    }
}

/// Serializes the config into the JSON schema expected by the engine
/// (phantom/mobile Config). The local SOCKS5 address is injected here.
public func phantomConfigJSON(_ c: PhantomProxyConfig, port: Int32 = phantomLocalSocksPort) -> String {
    let dict: [String: Any] = [
        "remote": c.remote,
        "transport": "reality",
        "sni": c.sni,
        "secret": c.secret,
        "reality_public_key": c.realityPublicKey,
        "reality_short_id": c.realityShortId,
        "socks": "\(phantomLocalSocksHost):\(port)",
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
    let entry = phantomAddOrUpdateConfig(config: config, name: nil)
    phantomSetActivePort(entry.port)
    UserDefaults.standard.set(enabled, forKey: phantomEnabledKey)
}

func phantomLoadPersisted() -> (config: PhantomProxyConfig, enabled: Bool)? {
    guard let entry = phantomActiveEntry() else {
        return nil
    }
    return (entry.config, UserDefaults.standard.bool(forKey: phantomEnabledKey))
}

func phantomSetEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: phantomEnabledKey)
}

// MARK: - App lifecycle (background → foreground recovery) + reconnect

// Weak reference to the shared account manager, set from the app delegate at
// launch. Needed to nudge Telegram to re-dial the proxy after recovery.
private weak var phantomStoredAccountManager: AccountManager<TelegramAccountManagerTypes>?
// Provider of the active account's connection status, so recovery can verify
// the connection actually came back and retry otherwise.
private var phantomConnectionStatusProvider: (() -> Signal<ConnectionStatus, NoError>?)?
private var phantomRecoveryDisposable: Disposable?
private let phantomMaxRecoveryAttempts = 6

/// Provides the shared account manager so background→foreground recovery can
/// force Telegram to re-dial the proxy. Call once at launch.
public func phantomSetAccountManager(_ accountManager: AccountManager<TelegramAccountManagerTypes>) {
    phantomStoredAccountManager = accountManager
    PhantomLifecycleObserver.shared.register()
}

/// Provides the active account's connection status signal (call once at launch).
public func phantomSetConnectionStatusProvider(_ provider: @escaping () -> Signal<ConnectionStatus, NoError>?) {
    phantomConnectionStatusProvider = provider
}

// Forces Telegram to drop and re-dial the proxy (equivalent to toggling the
// proxy off/on) so it reconnects through the freshly restarted local listener.
private func phantomNudgeProxy(accountManager: AccountManager<TelegramAccountManagerTypes>, port: Int32) {
    let server = phantomLocalProxyServer(port: port)
    let _ = updateProxySettingsInteractively(accountManager: accountManager, { settings in
        var settings = settings
        settings.enabled = false
        return settings
    }).start(completed: {
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

/// Recovers the Phantom connection after the app was suspended: restarts the
/// engine and nudges Telegram, then checks the connection status and retries
/// (a short suspension recovers in one pass; a long one — where the port is
/// still held or Telegram is in a long backoff — needs several).
public func phantomReconnect(accountManager: AccountManager<TelegramAccountManagerTypes>) {
    phantomStoredAccountManager = accountManager
    guard phantomLoadConfig() != nil else {
        return
    }
    phantomRecoveryDisposable?.dispose()
    phantomRecoveryDisposable = nil
    phantomRunRecoveryAttempt(accountManager: accountManager, attempt: 0)
}

private func phantomRunRecoveryAttempt(accountManager: AccountManager<TelegramAccountManagerTypes>, attempt: Int) {
    guard let entry = phantomActiveEntry() else {
        return
    }
    let json = phantomConfigJSON(entry.config, port: entry.port)
    // Restart the engine on a background queue (stop waits for the port to be
    // released, which can block after a long suspension). Fire-and-forget so a
    // wedged restart can't stall the recovery loop.
    DispatchQueue.global(qos: .userInitiated).async {
        _ = phantomEngineStart(json)
    }
    // Give the fresh listener a moment to come up, then nudge Telegram to
    // re-dial and schedule a status check that retries if still offline.
    Queue.mainQueue().after(1.0, {
        phantomNudgeProxy(accountManager: accountManager, port: entry.port)
        phantomScheduleRecoveryCheck(accountManager: accountManager, attempt: attempt)
    })
}

private func phantomScheduleRecoveryCheck(accountManager: AccountManager<TelegramAccountManagerTypes>, attempt: Int) {
    Queue.mainQueue().after(5.0, {
        // Stop retrying if the app went to background, Phantom was disabled, or
        // we've exhausted the attempts.
        if UIApplication.shared.applicationState != .active {
            return
        }
        guard let (_, enabled) = phantomLoadPersisted(), enabled else {
            return
        }
        if attempt + 1 >= phantomMaxRecoveryAttempts {
            return
        }
        guard let statusSignal = phantomConnectionStatusProvider?() else {
            // No status available — do a couple of blind retries only.
            if attempt < 2 {
                phantomRunRecoveryAttempt(accountManager: accountManager, attempt: attempt + 1)
            }
            return
        }
        phantomRecoveryDisposable?.dispose()
        phantomRecoveryDisposable = (statusSignal
        |> take(1)
        |> deliverOnMainQueue).start(next: { status in
            let connected: Bool
            switch status {
            case .online, .updating:
                connected = true
            default:
                connected = false
            }
            if !connected {
                phantomRunRecoveryAttempt(accountManager: accountManager, attempt: attempt + 1)
            }
        })
    })
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

        guard UserDefaults.standard.bool(forKey: phantomEnabledKey), let entry = phantomActiveEntry() else {
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
            let json = phantomConfigJSON(entry.config, port: entry.port)
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
    guard UserDefaults.standard.bool(forKey: phantomEnabledKey), let entry = phantomActiveEntry() else {
        return
    }
    _ = phantomEngineStart(phantomConfigJSON(entry.config, port: entry.port))
}

// MARK: - Proxy activation

/// The local SOCKS5 server that represents a running Phantom tunnel on a port.
func phantomLocalProxyServer(port: Int32 = phantomLocalSocksPort) -> ProxyServerSettings {
    return ProxyServerSettings(host: phantomLocalSocksHost, port: port, connection: .socks5(username: nil, password: nil))
}

/// Reports whether the given proxy server is one of our local Phantom entries
/// (127.0.0.1:<a saved phantom port> SOCKS5).
func phantomIsLocalProxy(_ server: ProxyServerSettings) -> Bool {
    guard server.host == phantomLocalSocksHost else {
        return false
    }
    guard case .socks5 = server.connection else {
        return false
    }
    return server.port == phantomLocalSocksPort || phantomAllPorts().contains(server.port)
}

/// Returns the config (reality params) of the active Phantom connection, if any.
func phantomLoadConfig() -> PhantomProxyConfig? {
    return phantomActiveEntry()?.config
}

/// Marks the given saved config active (selected port + enabled) and points
/// Telegram's proxy at its local port. Does NOT (re)start the engine — callers do.
public func phantomActivateConfig(_ entry: PhantomSavedConfig, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
    phantomSetActivePort(entry.port)
    UserDefaults.standard.set(true, forKey: phantomEnabledKey)
    let server = phantomLocalProxyServer(port: entry.port)
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

/// Starts the engine for the saved config that owns the given local port (used
/// when the user switches to a Phantom entry in the proxy list).
public func phantomStartEngineForPort(_ port: Int32) {
    guard let entry = phantomConfigForPort(port) else {
        return
    }
    phantomSetActivePort(entry.port)
    UserDefaults.standard.set(true, forKey: phantomEnabledKey)
    let json = phantomConfigJSON(entry.config, port: entry.port)
    DispatchQueue.global(qos: .userInitiated).async {
        _ = phantomEngineStart(json)
    }
}

/// Activates the currently active Phantom connection (back-compat helper).
public func phantomActivateLocalProxy(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
    if let entry = phantomActiveEntry() {
        return phantomActivateConfig(entry, accountManager: accountManager)
    }
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
