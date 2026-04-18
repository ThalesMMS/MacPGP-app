//
//  TrustLevelPickerViewModelTests.swift
//  MacPGPTests
//

import Testing
import Foundation
import ObjectivePGP
@testable import MacPGP

@Suite("TrustLevelPickerViewModel Tests")
struct TrustLevelPickerViewModelTests {

    // MARK: - Helpers

    private func generateKey(email: String, trustLevel: TrustLevel = .unknown) -> (KeyringService, PGPKeyModel) {
        let service = KeyringService()
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: email, passphrase: "test-pass")
        try? service.addKey(rawKey)
        guard let model = service.keys.first(where: { $0.email == email }) else {
            fatalError("Test key not added to service")
        }
        if trustLevel != .unknown {
            try? service.updateTrustLevel(model, trustLevel: trustLevel)
            guard let updated = service.keys.first(where: { $0.fingerprint == model.fingerprint }) else {
                fatalError("Test key disappeared after trust update")
            }
            return (service, updated)
        }
        return (service, model)
    }

    private func makeViewModel(key: PGPKeyModel, service: KeyringService) -> TrustLevelPickerViewModel {
        TrustLevelPickerViewModel(key: key, keyringService: service)
    }

    // MARK: - Initialization Tests

    @Test("ViewModel init uses current key from keyring when key exists")
    func testInitUsesKeyFromKeyringWhenPresent() {
        let (service, key) = generateKey(email: "vm-init-keyring@test.local", trustLevel: .full)
        defer {
            if let k = service.keys.first(where: { $0.fingerprint == key.fingerprint }) {
                try? service.deleteKey(k)
            }
        }

        let staleKey = PGPKeyModel(copying: key, trustLevel: .unknown)
        let vm = makeViewModel(key: staleKey, service: service)

        #expect(vm.key.fingerprint == key.fingerprint)
        #expect(vm.selectedTrustLevel == .full)
    }

    @Test("ViewModel init falls back to provided key when key not in keyring")
    func testInitFallsBackToProvidedKeyWhenNotInKeyring() {
        let service = KeyringService()
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        let rawKey = keyGen.generate(for: "vm-init-fallback@test.local", passphrase: "pass")
        let model = PGPKeyModel(from: rawKey, isVerified: false, verificationDate: nil, verificationMethod: nil, trustLevel: .marginal)

        let vm = makeViewModel(key: model, service: service)

        #expect(vm.key.fingerprint == model.fingerprint)
        #expect(vm.selectedTrustLevel == .marginal)
    }

    @Test("ViewModel init sets selectedTrustLevel to match keyring's current trust level")
    func testInitSelectedTrustLevelMatchesKeyringState() {
        let (service, key) = generateKey(email: "vm-init-trust@test.local", trustLevel: .never)
        defer {
            if let k = service.keys.first(where: { $0.fingerprint == key.fingerprint }) {
                try? service.deleteKey(k)
            }
        }

        let vm = makeViewModel(key: key, service: service)

        #expect(vm.selectedTrustLevel == .never)
    }

    @Test("ViewModel init sets isSuccess to false")
    func testInitIsSuccessFalse() {
        let (service, key) = generateKey(email: "vm-init-success@test.local")
        defer { try? service.deleteKey(key) }

        let vm = makeViewModel(key: key, service: service)

        #expect(!vm.isSuccess)
    }

    @Test("ViewModel init sets errorMessage to nil")
    func testInitErrorMessageNil() {
        let (service, key) = generateKey(email: "vm-init-error@test.local")
        defer { try? service.deleteKey(key) }

        let vm = makeViewModel(key: key, service: service)

        #expect(vm.errorMessage == nil)
    }

    // MARK: - hasChanged Tests

    @Test("hasChanged returns false immediately after init")
    func testHasChangedFalseOnInit() {
        let (service, key) = generateKey(email: "vm-haschanged-init@test.local", trustLevel: .marginal)
        defer {
            if let k = service.keys.first(where: { $0.fingerprint == key.fingerprint }) {
                try? service.deleteKey(k)
            }
        }

        let vm = makeViewModel(key: key, service: service)

        #expect(!vm.hasChanged)
    }

    @Test("hasChanged returns true when selectedTrustLevel differs from initial")
    func testHasChangedTrueWhenLevelChanged() {
        let (service, key) = generateKey(email: "vm-haschanged-diff@test.local", trustLevel: .unknown)
        defer {
            if let k = service.keys.first(where: { $0.fingerprint == key.fingerprint }) {
                try? service.deleteKey(k)
            }
        }

        let vm = makeViewModel(key: key, service: service)
        vm.selectedTrustLevel = .full

        #expect(vm.hasChanged)
    }

    @Test("hasChanged returns false when selectedTrustLevel changed back to initial")
    func testHasChangedFalseWhenChangedBackToInitial() {
        let (service, key) = generateKey(email: "vm-haschanged-revert@test.local", trustLevel: .marginal)
        defer {
            if let k = service.keys.first(where: { $0.fingerprint == key.fingerprint }) {
                try? service.deleteKey(k)
            }
        }

        let vm = makeViewModel(key: key, service: service)
        vm.selectedTrustLevel = .full
        vm.selectedTrustLevel = .marginal

        #expect(!vm.hasChanged)
    }

    // MARK: - saveTrustLevel Tests

    @Test("saveTrustLevel sets isSuccess to true on success")
    func testSaveTrustLevelSetsIsSuccess() {
        let (service, key) = generateKey(email: "vm-save-success@test.local", trustLevel: .unknown)
        defer {
            if let k = service.keys.first(where: { $0.fingerprint == key.fingerprint }) {
                try? service.deleteKey(k)
            }
        }

        let vm = makeViewModel(key: key, service: service)
        vm.errorMessage = "previous error"
        vm.selectedTrustLevel = .full
        vm.saveTrustLevel()

        #expect(vm.isSuccess)
        #expect(vm.errorMessage == nil)
    }

    @Test("saveTrustLevel updates key property to reflect new trust level from keyring")
    func testSaveTrustLevelUpdatesKeyProperty() {
        let (service, key) = generateKey(email: "vm-save-key-update@test.local", trustLevel: .unknown)
        defer {
            if let k = service.keys.first(where: { $0.fingerprint == key.fingerprint }) {
                try? service.deleteKey(k)
            }
        }

        let vm = makeViewModel(key: key, service: service)
        vm.selectedTrustLevel = .full
        vm.saveTrustLevel()

        #expect(vm.key.trustLevel == .full)
    }

    @Test("saveTrustLevel calls success handler with updated key")
    func testSaveTrustLevelCallsSuccessHandlerWithUpdatedKey() {
        let (service, key) = generateKey(email: "vm-save-success-handler@test.local", trustLevel: .unknown)
        defer {
            if let k = service.keys.first(where: { $0.fingerprint == key.fingerprint }) {
                try? service.deleteKey(k)
            }
        }

        let vm = makeViewModel(key: key, service: service)
        var callbackKey: PGPKeyModel?
        vm.selectedTrustLevel = .full

        vm.saveTrustLevel { updatedKey in
            callbackKey = updatedKey
        }

        #expect(callbackKey?.fingerprint == key.fingerprint)
        #expect(callbackKey?.trustLevel == .full)
    }

    @Test("saveTrustLevel persists trust level so keyring reflects new level")
    func testSaveTrustLevelPersistsToKeyring() {
        let (service, key) = generateKey(email: "vm-save-persist@test.local", trustLevel: .unknown)
        defer {
            if let k = service.keys.first(where: { $0.fingerprint == key.fingerprint }) {
                try? service.deleteKey(k)
            }
        }

        let vm = makeViewModel(key: key, service: service)
        vm.selectedTrustLevel = .marginal
        vm.saveTrustLevel()

        let keyringKey = service.keys.first(where: { $0.fingerprint == key.fingerprint })
        #expect(keyringKey?.trustLevel == .marginal)
    }

    @Test("saveTrustLevel clears previous errorMessage on new attempt")
    func testSaveTrustLevelClearsPreviousError() {
        let (service, key) = generateKey(email: "vm-save-clear-err@test.local", trustLevel: .unknown)
        defer {
            if let k = service.keys.first(where: { $0.fingerprint == key.fingerprint }) {
                try? service.deleteKey(k)
            }
        }

        let vm = makeViewModel(key: key, service: service)
        vm.selectedTrustLevel = .full
        vm.saveTrustLevel()

        #expect(vm.isSuccess)
        #expect(vm.errorMessage == nil)
    }

    @Test("saveTrustLevel with each trust level succeeds")
    func testSaveTrustLevelAllLevels() {
        let trustLevels: [TrustLevel] = [.never, .marginal, .full, .ultimate]

        for level in trustLevels {
            let email = "vm-save-all-\(level.rawValue.lowercased())@test.local"
            let (service, key) = generateKey(email: email)
            defer {
                if let k = service.keys.first(where: { $0.fingerprint == key.fingerprint }) {
                    try? service.deleteKey(k)
                }
            }

            let vm = makeViewModel(key: key, service: service)
            vm.selectedTrustLevel = level

            vm.saveTrustLevel()
            #expect(vm.isSuccess)
            #expect(vm.key.trustLevel == level)
        }
    }
}
