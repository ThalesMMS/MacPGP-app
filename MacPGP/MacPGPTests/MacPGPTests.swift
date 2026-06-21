//
//  MacPGPTests.swift
//  MacPGPTests
//
//  Created by Thales Matheus Mendonça Santos on 04/02/26.
//

import Testing
import Foundation
@testable import MacPGP

struct MacPGPTests {

    @Test func appBundleRegistersPGPDocumentTypes() throws {
        let appBundle = Bundle(identifier: "thalesmms.MacPGP") ?? Bundle.main
        let documentTypes = try #require(appBundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let registeredExtensions = Set(
            documentTypes
                .compactMap { $0["CFBundleTypeExtensions"] as? [String] }
                .flatMap { $0 }
        )

        #expect(registeredExtensions.isSuperset(of: ["asc", "gpg", "pgp"]))
    }

}
