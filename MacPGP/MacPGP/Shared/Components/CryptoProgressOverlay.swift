import SwiftUI

struct CryptoProgressOverlay: View {
    let actionTitle: String
    var progress: Double?
    var fileCount: Int?

    var body: some View {
        Spacer()

        VStack(spacing: 16) {
            if let progress, progress > 0 {
                ProgressView(value: progress) {
                    Text(progressTitle)
                } currentValueLabel: {
                    Text("\(Int(progress * 100))%")
                }
                .frame(width: 200)
            } else {
                ProgressView("\(actionTitle)...")
            }
        }

        Spacer()
    }

    private var progressTitle: String {
        guard let fileCount else {
            return "\(actionTitle)..."
        }
        return fileCount > 1 ? "\(actionTitle) files..." : "\(actionTitle) file..."
    }
}
