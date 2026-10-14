import AppKit
import ScreenCaptureKit

enum MenuExtrasCapture {
    /// Capture only the menu-extra band, never the desktop or app content below it.
    static func image(in region: CGRect) async throws -> CGImage {
        let request = CaptureRequest()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.start(continuation)
                DispatchQueue.global(qos: .utility).async {
                    capture(region, request: request)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    request.finish(.failure(CaptureError.timedOut))
                }
            }
        } onCancel: {
            request.finish(.failure(CancellationError()))
        }
    }

    private enum CaptureError: Error { case unavailable, timedOut }

    private static func capture(_ region: CGRect, request: CaptureRequest) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            guard request.isPending else { return }
            guard let display = content?.displays.first(where: { $0.frame.contains(region) }) else {
                request.finish(.failure(error ?? CaptureError.unavailable))
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            filter.includeMenuBar = true
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            configuration.width = max(1, Int(ceil(region.width * CGFloat(filter.pointPixelScale))))
            configuration.height = max(1, Int(ceil(region.height * CGFloat(filter.pointPixelScale))))
            configuration.showsCursor = false
            configuration.capturesAudio = false
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let image {
                    request.finish(.success(image))
                    return
                }
                request.finish(.failure(error ?? CaptureError.unavailable))
            }
        }
    }

    /// ScreenCaptureKit may call back after cancellation or the deadline; resume exactly once.
    final class CaptureRequest: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<CGImage, Error>?
        private var result: Result<CGImage, Error>?
        var isPending: Bool { lock.withLock { result == nil } }
        func start(_ continuation: CheckedContinuation<CGImage, Error>) {
            let previous = lock.withLock {
                if result == nil { self.continuation = continuation }
                return result
            }
            if let previous { continuation.resume(with: previous) }
        }
        func finish(_ result: Result<CGImage, Error>) {
            let pending = lock.withLock { () -> CheckedContinuation<CGImage, Error>? in
                guard self.result == nil else { return nil }
                self.result = result
                defer { continuation = nil }
                return continuation
            }
            pending?.resume(with: result)
        }
    }
}
