import Foundation
import AVFoundation

@Observable
final class FingerprintAudioService: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isPlaying = false
    private(set) var lastError: Error?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // NATO Phonetic Alphabet
    private let phoneticAlphabet: [Character: String] = [
        "A": "Alpha", "B": "Bravo", "C": "Charlie", "D": "Delta",
        "E": "Echo", "F": "Foxtrot", "G": "Golf", "H": "Hotel",
        "I": "India", "J": "Juliett", "K": "Kilo", "L": "Lima",
        "M": "Mike", "N": "November", "O": "Oscar", "P": "Papa",
        "Q": "Quebec", "R": "Romeo", "S": "Sierra", "T": "Tango",
        "U": "Uniform", "V": "Victor", "W": "Whiskey", "X": "X-ray",
        "Y": "Yankee", "Z": "Zulu"
    ]

    private let phoneticNumbers: [Character: String] = [
        "0": "Zero", "1": "One", "2": "Two", "3": "Three",
        "4": "Four", "5": "Five", "6": "Six", "7": "Seven",
        "8": "Eight", "9": "Nine"
    ]

    /// Convert a fingerprint to phonetic words
    /// - Parameter fingerprint: The PGP key fingerprint (hex string)
    /// - Returns: Phonetic representation as a string
    func formatPhonetic(_ fingerprint: String) -> String {
        let cleaned = fingerprint
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .uppercased()

        var phonetic: [String] = []

        for char in cleaned {
            if let word = phoneticAlphabet[char] {
                phonetic.append(word)
            } else if let word = phoneticNumbers[char] {
                phonetic.append(word)
            }
        }

        return phonetic.joined(separator: " ")
    }

    /// Speak a fingerprint using text-to-speech
    /// - Parameter fingerprint: The PGP key fingerprint to read aloud
    func speak(_ fingerprint: String) {
        guard !isPlaying else { return }

        lastError = nil

        let phoneticText = formatPhonetic(fingerprint)

        guard !phoneticText.isEmpty else {
            lastError = NSError(
                domain: "FingerprintAudioService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid fingerprint format"]
            )
            return
        }

        let utterance = AVSpeechUtterance(string: phoneticText)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        isPlaying = true
        synthesizer.speak(utterance)
    }

    /// Stop current speech playback
    func stop() {
        guard isPlaying else { return }

        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isPlaying = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isPlaying = false
    }
}
