import AppKit
import CoreImage
import ScreenCaptureKit

/// One continuing stream per display keeps the recording indicator and menu-bar layout stable.
@MainActor
final class MenuExtrasLiveCapture {
    private struct Session {
        let stream: SCStream
        let output: MenuExtrasFrameOutput
        let display: SCDisplay
        var region: CGRect
    }
    private var sessions: [CGDirectDisplayID: Session] = [:]
    private var generation = UUID()

    func image(in region: CGRect, displayID: CGDirectDisplayID) async throws -> CGImage {
        let request = MenuExtrasCapture.CaptureRequest()
        let identity = generation
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.start(continuation)
                if let session = sessions[displayID] {
                    use(session, region: region, displayID: displayID, request: request)
                } else {
                    SCShareableContent.getExcludingDesktopWindows(
                        false, onScreenWindowsOnly: true) { [weak self] content, error in
                        let transfer = MenuExtrasContentTransfer(content: content)
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == identity, request.isPending else { return }
                            guard let display = transfer.content?.displays.first(where: { $0.displayID == displayID })
                            else {
                                request.finish(.failure(error ?? CocoaError(.featureUnsupported)))
                                return
                            }
                            self.start(display: display, region: region, request: request)
                        }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    request.finish(.failure(CocoaError(.coderReadCorrupt)))
                }
            }
        } onCancel: {
            request.finish(.failure(CancellationError()))
        }
    }

    private func start(display: SCDisplay, region: CGRect, request: MenuExtrasCapture.CaptureRequest) {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        filter.includeMenuBar = true
        let output = MenuExtrasFrameOutput()
        let stream = SCStream(filter: filter, configuration: configuration(region, display: display), delegate: output)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        } catch {
            request.finish(.failure(error))
            return
        }
        sessions[display.displayID] = Session(stream: stream, output: output, display: display, region: region)
        output.request(request, clear: true)
        stream.startCapture { error in
            if let error { output.fail(error) }
        }
    }

    private func use(_ session: Session, region: CGRect, displayID: CGDirectDisplayID,
                     request: MenuExtrasCapture.CaptureRequest) {
        if session.region == region {
            session.output.request(request, clear: false)
            return
        }
        sessions[displayID]?.region = region
        let output = session.output
        output.invalidate()
        session.stream.updateConfiguration(configuration(region, display: session.display)) { error in
            if let error {
                request.finish(.failure(error))
            } else {
                output.request(request, clear: true)
            }
        }
    }

    private func configuration(_ region: CGRect, display: SCDisplay) -> SCStreamConfiguration {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.width = max(1, Int(ceil(region.width * CGFloat(filter.pointPixelScale))))
        config.height = max(1, Int(ceil(region.height * CGFloat(filter.pointPixelScale))))
        config.showsCursor = false
        config.capturesAudio = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3
        return config
    }

    func stop() {
        generation = UUID()
        for session in sessions.values {
            session.output.fail(CancellationError())
            session.stream.stopCapture { _ in }
        }
        sessions.removeAll()
    }
}

private struct MenuExtrasContentTransfer: @unchecked Sendable {
    // Immutable SDK metadata is handed to the main actor and never mutated.
    let content: SCShareableContent?
}

private final class MenuExtrasFrameOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "gt.quintero.Docky.menu-extras-frames", qos: .utility)
    private let lock = NSLock()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var latest: CGImage?
    private var waiting: [MenuExtrasCapture.CaptureRequest] = []
    private var failure: Error?

    func request(_ request: MenuExtrasCapture.CaptureRequest, clear: Bool) {
        let ready: Result<CGImage, Error>? = lock.withLock {
            if clear { latest = nil }
            if let failure { return .failure(failure) }
            if let latest { return .success(latest) }
            waiting.removeAll { !$0.isPending }
            waiting.append(request)
            return nil
        }
        if let ready { request.finish(ready) }
    }
    func invalidate() { lock.withLock { latest = nil } }
    func fail(_ error: Error) {
        let pending = lock.withLock {
            failure = error
            defer { waiting.removeAll(); latest = nil }
            return waiting
        }
        pending.forEach { $0.finish(.failure(error)) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { fail(error) }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue else { return }
        let input = CIImage(cvPixelBuffer: buffer)
        guard let image = context.createCGImage(input, from: input.extent) else { return }
        let pending = lock.withLock {
            latest = image
            defer { waiting.removeAll() }
            return waiting
        }
        pending.forEach { $0.finish(.success(image)) }
    }
}
