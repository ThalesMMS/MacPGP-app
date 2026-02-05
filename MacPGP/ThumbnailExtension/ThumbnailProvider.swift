import QuickLookThumbnailing
import Cocoa

class ThumbnailProvider: QLThumbnailProvider {

    private let fileAnalyzer = PGPFileAnalyzer()
    private let renderer = ThumbnailRenderer()

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {

        // Check if this is a PGP file
        guard PGPFileAnalyzer.isPGPFile(url: request.fileURL) else {
            handler(nil, nil)
            return
        }

        // Analyze the file to determine encryption status
        guard let result = try? fileAnalyzer.analyze(fileAt: request.fileURL),
              result.isEncrypted else {
            handler(nil, nil)
            return
        }

        // Generate thumbnail with visual indicators for encryption type
        let reply = QLThumbnailReply(contextSize: request.maximumSize, currentContextDrawing: { () -> Bool in
            return self.renderer.renderThumbnail(for: result, in: request.maximumSize)
        })

        handler(reply, nil)
    }
}
