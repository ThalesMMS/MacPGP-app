import SwiftUI
import Testing
@testable import MacPGP

@Suite("TrustLevel Presentation Tests")
struct TrustLevelPresentationTests {
    @Test("TrustLevel color maps every level to its badge color")
    func testColorMapping() {
        #expect(TrustLevel.unknown.color == Color.gray)
        #expect(TrustLevel.never.color == Color.red)
        #expect(TrustLevel.marginal.color == Color.orange)
        #expect(TrustLevel.full.color == Color.green)
        #expect(TrustLevel.ultimate.color == Color.purple)
    }
}
