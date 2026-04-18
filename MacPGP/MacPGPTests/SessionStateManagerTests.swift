import Foundation
import Testing
@testable import MacPGP

@Suite("SessionStateManager Tests")
struct SessionStateManagerTests {

    // MARK: - Initial state

    @Test("encryptOutputFiles starts empty")
    func testEncryptOutputFilesInitiallyEmpty() {
        let state = SessionStateManager()
        #expect(state.encryptOutputFiles.isEmpty)
    }

    @Test("decryptOutputFiles starts empty")
    func testDecryptOutputFilesInitiallyEmpty() {
        let state = SessionStateManager()
        #expect(state.decryptOutputFiles.isEmpty)
    }

    @Test("signOutputFiles starts empty")
    func testSignOutputFilesInitiallyEmpty() {
        let state = SessionStateManager()
        #expect(state.signOutputFiles.isEmpty)
    }

    // MARK: - clearAll resets output file arrays

    @Test("clearAll resets encryptOutputFiles to empty")
    func testClearAllResetsEncryptOutputFiles() {
        let state = SessionStateManager()
        state.encryptOutputFiles = [
            URL(fileURLWithPath: "/tmp/file1.asc"),
            URL(fileURLWithPath: "/tmp/file2.asc")
        ]
        #expect(state.encryptOutputFiles.count == 2)

        state.clearAll()

        #expect(state.encryptOutputFiles.isEmpty)
    }

    @Test("clearAll resets decryptOutputFiles to empty")
    func testClearAllResetsDecryptOutputFiles() {
        let state = SessionStateManager()
        state.decryptOutputFiles = [
            URL(fileURLWithPath: "/tmp/decrypted.txt")
        ]
        #expect(state.decryptOutputFiles.count == 1)

        state.clearAll()

        #expect(state.decryptOutputFiles.isEmpty)
    }

    @Test("clearAll resets signOutputFiles to empty")
    func testClearAllResetsSignOutputFiles() {
        let state = SessionStateManager()
        state.signOutputFiles = [
            URL(fileURLWithPath: "/tmp/file.txt.sig")
        ]
        #expect(state.signOutputFiles.count == 1)

        state.clearAll()

        #expect(state.signOutputFiles.isEmpty)
    }

    @Test("clearAll resets all three output file arrays simultaneously")
    func testClearAllResetsAllOutputFileArrays() {
        let state = SessionStateManager()
        state.encryptOutputFiles = [URL(fileURLWithPath: "/tmp/a.asc")]
        state.decryptOutputFiles = [URL(fileURLWithPath: "/tmp/b.txt")]
        state.signOutputFiles = [URL(fileURLWithPath: "/tmp/c.sig")]

        state.clearAll()

        #expect(state.encryptOutputFiles.isEmpty)
        #expect(state.decryptOutputFiles.isEmpty)
        #expect(state.signOutputFiles.isEmpty)
    }

    // MARK: - clearAll preserves correct reset of other fields alongside new ones

    @Test("clearAll also resets unrelated encrypt fields")
    func testClearAllResetsEncryptRelatedFields() {
        let state = SessionStateManager()
        state.encryptOutputFiles = [URL(fileURLWithPath: "/tmp/a.asc")]
        state.encryptOutputText = "some encrypted text"
        state.encryptInputText = "hello"
        state.encryptionProgress = 0.75

        state.clearAll()

        #expect(state.encryptOutputFiles.isEmpty)
        #expect(state.encryptOutputText == "")
        #expect(state.encryptInputText == "")
        #expect(state.encryptionProgress == 0.0)
    }

    @Test("clearAll also resets unrelated decrypt fields")
    func testClearAllResetsDecryptRelatedFields() {
        let state = SessionStateManager()
        state.decryptOutputFiles = [URL(fileURLWithPath: "/tmp/b.txt")]
        state.decryptOutputText = "some decrypted text"
        state.decryptionProgress = 0.5

        state.clearAll()

        #expect(state.decryptOutputFiles.isEmpty)
        #expect(state.decryptOutputText == "")
        #expect(state.decryptionProgress == 0.0)
    }

    @Test("clearAll also resets unrelated sign fields")
    func testClearAllResetsSignRelatedFields() {
        let state = SessionStateManager()
        state.signOutputFiles = [URL(fileURLWithPath: "/tmp/c.sig")]
        state.signOutputText = "signed message"
        state.signInputText = "hello"

        state.clearAll()

        #expect(state.signOutputFiles.isEmpty)
        #expect(state.signOutputText == "")
        #expect(state.signInputText == "")
    }

    // MARK: - Mutability

    @Test("encryptOutputFiles can hold multiple URLs")
    func testEncryptOutputFilesAcceptsMultipleURLs() {
        let state = SessionStateManager()
        let urls = (1...5).map { URL(fileURLWithPath: "/tmp/file\($0).asc") }
        state.encryptOutputFiles = urls
        #expect(state.encryptOutputFiles.count == 5)
        #expect(state.encryptOutputFiles == urls)
    }

    @Test("decryptOutputFiles can be replaced independently of signOutputFiles")
    func testOutputFileArraysAreIndependent() {
        let state = SessionStateManager()
        let decryptURL = URL(fileURLWithPath: "/tmp/decrypted.txt")
        let signURL = URL(fileURLWithPath: "/tmp/signed.asc")

        state.decryptOutputFiles = [decryptURL]
        state.signOutputFiles = [signURL]

        #expect(state.decryptOutputFiles == [decryptURL])
        #expect(state.signOutputFiles == [signURL])

        // Clearing one does not affect the other
        state.decryptOutputFiles = []
        #expect(state.decryptOutputFiles.isEmpty)
        #expect(state.signOutputFiles == [signURL])
    }
}