#if DEBUG
    import AppKit

    extension AppKitUIRegression {
        static func checkMenuExtras() async {
            let display = CGRect(x: -1440, y: -900, width: 1440, height: 900)
            let icon = CGRect(x: -80, y: -900, width: 22, height: 28)
            precondition(MenuExtraGeometry.visibleItem(icon, on: display))
            precondition(!MenuExtraGeometry.visibleItem(icon.offsetBy(dx: 100, dy: 0), on: display))
            precondition(!MenuExtraGeometry.visibleItem(icon.offsetBy(dx: 0, dy: 80), on: display))
            precondition(!MenuExtraGeometry.visibleItem(CGRect(x: -80, y: -900, width: 22, height: 0), on: display))
            let region = CGRect(x: -100, y: -900, width: 100, height: 28)
            let crop = MenuExtraGeometry.crop(frame: icon, region: region, pixels: CGSize(width: 200, height: 56))
            precondition(crop == CGRect(x: 40, y: 0, width: 44, height: 56))
            precondition(MenuExtraGeometry.crop(frame: icon.offsetBy(dx: 100, dy: 0), region: region,
                                               pixels: CGSize(width: 200, height: 56)) == nil)
            let visible = CGRect(x: -1440, y: -872, width: 1440, height: 824)
            let size = CGSize(width: 300, height: 240)
            let anchor = CGRect(x: -45, y: -40, width: 32, height: 32)
            let origin = MenuExtraGeometry.popupOrigin(size: size, anchor: anchor, visible: visible)
            precondition(visible.contains(CGRect(origin: origin, size: size)))
            precondition(origin.y + size.height == anchor.minY - 8)
            precondition(origin.x + size.width == visible.maxX)
            let backdrop = CGRect(x: -600, y: -872, width: 656, height: 962)
            let controls = CGRect(x: -425, y: -838, width: 290, height: 525)
            let movedOrigin = MenuExtraGeometry.windowOrigin(container: backdrop, content: controls,
                                                            anchor: anchor, visible: visible)
            let movedControls = controls.offsetBy(dx: movedOrigin.x - backdrop.minX,
                                                 dy: movedOrigin.y - backdrop.minY)
            precondition(visible.contains(movedControls), "Transparent backdrops must not determine popup placement")
            precondition(movedControls.maxY == anchor.minY - 8)
            checkMenuExtraImage()
            await checkMenuCaptureCompletion()
            print("Menu-extra geometry and capture completion regressions passed")
        }

        private static func checkMenuCaptureCompletion() async {
            let canceled = MenuExtrasCapture.CaptureRequest()
            canceled.finish(.failure(CancellationError()))
            do {
                let _: CGImage = try await withCheckedThrowingContinuation { canceled.start($0) }
                preconditionFailure("Cancellation before registration must resume the waiter")
            } catch { precondition(error is CancellationError) }

            let completed = MenuExtrasCapture.CaptureRequest()
            do {
                let _: CGImage = try await withCheckedThrowingContinuation { continuation in
                    completed.start(continuation)
                    completed.finish(.failure(CancellationError()))
                    // A late callback or timeout must not resume a completed waiter twice.
                    completed.finish(.failure(CocoaError(.userCancelled)))
                }
                preconditionFailure("Canceled capture must throw")
            } catch { precondition(error is CancellationError) }
        }

        private static func checkMenuExtraImage() {
            guard let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                                          bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                preconditionFailure("Bitmap context required")
            }
            context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 3, y: 3, width: 2, height: 2))
            guard let source = context.makeImage() else { preconditionFailure("Fixture image required") }
            let image = MenuExtraImage.make(source, size: CGSize(width: 8, height: 8))
            precondition(image.isTemplate, "Monochrome native icons must adapt to taskbar appearance")
            guard let result = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let data = result.dataProvider?.data else { preconditionFailure("Image data required") }
            let bytes = CFDataGetBytePtr(data)
            precondition(bytes?[3] == 0, "Flat menu-bar background must become transparent")
            precondition(bytes?[(3 * 8 + 3) * 4 + 3] == 255, "The actual icon pixels must remain opaque")
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 5, y: 3, width: 1, height: 2))
            guard let mixedSource = context.makeImage() else { preconditionFailure("Mixed fixture required") }
            let mixed = MenuExtraImage.make(mixedSource, size: CGSize(width: 8, height: 8))
            precondition(!mixed.isTemplate, "Colored indicators must retain their color")
            let adapted = MenuExtraImage.adaptingMonochrome(mixed, to: .black)
            guard let adaptedCG = adapted.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let adaptedData = adaptedCG.dataProvider?.data else { preconditionFailure("Adapted image required") }
            let adaptedBytes = CFDataGetBytePtr(adaptedData)
            precondition(adaptedBytes?[(3 * 8 + 3) * 4] == 0, "White glyph pixels must be readable on a light taskbar")
            precondition(adaptedBytes?[(3 * 8 + 5) * 4] == 255, "A red status indicator must stay red")
        }
    }
#endif
