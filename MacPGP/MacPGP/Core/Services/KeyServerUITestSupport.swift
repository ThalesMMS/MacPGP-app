import Foundation

/// UI-test-only seam for `KeyServerService`.
///
/// When MacPGP is launched with `--uitest-keyserver-stub`, the app routes
/// `KeyServerService` through `KeyServerStubURLProtocol`, which serves deterministic
/// fixtures instead of contacting any network. The flag is honored under the same
/// safety gate as `--reset-keyring`: always in DEBUG, and in release only under
/// XCTest. Production launches can never enable the stub.
nonisolated enum KeyServerUITestSupport {
    static let launchArgument = "--uitest-keyserver-stub"
    static let scenarioEnvironmentKey = "MACPGP_UITEST_KEYSERVER_SCENARIO"

    /// Deterministic scenarios the stub can serve, selected by the launch environment.
    enum Scenario: String {
        case successMultiple
        case noResults
        case serverError
        case networkTimeout
        case importSuccess
        case malformedKey
    }

    /// Whether the keyserver stub is enabled for this launch.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument) && isAllowed
    }

    /// The scenario the stub should serve, defaulting to a successful multi-key search.
    static var scenario: Scenario {
        let raw = ProcessInfo.processInfo.environment[scenarioEnvironmentKey] ?? ""
        return Scenario(rawValue: raw) ?? .successMultiple
    }

    /// Builds a `KeyServerService` backed by the deterministic stub protocol.
    @MainActor
    static func makeKeyServerService() -> KeyServerService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KeyServerStubURLProtocol.self]
        return KeyServerService(configuration: configuration)
    }

    /// Mirrors `MacPGPApp.isResetKeyringAllowed`: always allowed in DEBUG, and in
    /// release only under XCTest, so production launches cannot be stubbed.
    private static var isAllowed: Bool {
        #if DEBUG
        return true
        #else
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestSessionIdentifier"] != nil ||
            NSClassFromString("XCTestCase") != nil
        #endif
    }
}
