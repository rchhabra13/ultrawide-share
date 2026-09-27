import AppKit
import CoreMedia
import ScreenCaptureKit

// Captures the selected displays and draws them in one window, laid out the way
// they are arranged in System Settings. Share that window in any meeting app.

final class DisplayStream: NSObject, SCStreamOutput, SCStreamDelegate {
    let layer = CALayer()
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "UltrawideShare.frames")

    init(display: SCDisplay, excluding app: SCRunningApplication?) throws {
        super.init()
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor

        // Our own window is excluded so the composite never captures itself.
        let filter = SCContentFilter(display: display,
                                     excludingApplications: app.map { [$0] } ?? [],
                                     exceptingWindows: [])
        let config = SCStreamConfiguration()
        let mode = CGDisplayCopyDisplayMode(display.displayID)
        config.width = mode?.pixelWidth ?? display.width
        config.height = mode?.pixelHeight ?? display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
    }

    func start() async throws { try await stream?.startCapture() }

    func stop() async { try? await stream?.stopCapture() }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Idle frames (screen unchanged) carry no image, so keep showing the last one.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async { [layer] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = surface
            CATransaction.commit()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("UltrawideShare: stream stopped: \(error.localizedDescription)")
    }
}

final class CompositeView: NSView {
    // Each display's rectangle in global coordinates, normalized later to the view.
    var tiles: [(CGRect, CALayer)] = [] { didSet { rebuild() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var bounding: CGRect { tiles.map(\.0).reduce(CGRect.null) { $0.union($1) } }

    private func rebuild() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        tiles.forEach { layer?.addSublayer($0.1) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let box = bounding
        guard !box.isNull, box.width > 0 else { return }
        let scale = min(bounds.width / box.width, bounds.height / box.height)
        let offsetX = (bounds.width - box.width * scale) / 2
        let offsetY = (bounds.height - box.height * scale) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (rect, tile) in tiles {
            // CGDisplayBounds uses a top-left origin, NSView uses bottom-left.
            tile.frame = CGRect(x: offsetX + (rect.minX - box.minX) * scale,
                                y: offsetY + (box.maxY - rect.maxY) * scale,
                                width: rect.width * scale,
                                height: rect.height * scale)
        }
        CATransaction.commit()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var window: NSWindow?
    private var streams: [DisplayStream] = []
    private var selected: Set<CGDirectDisplayID> = []
    private var isOn: Bool { window != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        selected = Set(NSScreen.screens.filter { !$0.localizedName.contains("Sidecar") }.compactMap(Self.displayID))
        rebuildMenu()
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func rebuildMenu() {
        statusItem.button?.image = NSImage(systemSymbolName: isOn ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                                           accessibilityDescription: "Ultrawide Share")
        let menu = NSMenu()
        menu.addItem(withTitle: isOn ? "Turn Off Ultrawide Share" : "Turn On Ultrawide Share",
                     action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Displays to combine:", action: nil, keyEquivalent: "")
        for screen in NSScreen.screens {
            guard let id = Self.displayID(screen) else { continue }
            let item = NSMenuItem(title: screen.localizedName, action: #selector(toggleDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(id)
            item.state = selected.contains(id) ? .on : .off
            item.isEnabled = !isOn
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func toggleDisplay(_ sender: NSMenuItem) {
        let id = CGDirectDisplayID(sender.tag)
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        rebuildMenu()
    }

    @objc private func toggle() {
        Task { @MainActor in
            if isOn { await turnOff() } else { await turnOn() }
        }
    }

    @MainActor private func turnOn() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let me = content.applications.first { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let displays = content.displays.filter { selected.contains($0.displayID) }
            guard !displays.isEmpty else { throw NSError(domain: "UltrawideShare", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Pick at least one display to combine."]) }

            let newStreams = try displays.map { try DisplayStream(display: $0, excluding: me) }
            let view = CompositeView(frame: .zero)
            view.tiles = zip(displays, newStreams).map { (CGDisplayBounds($0.displayID), $1.layer) }
            for s in newStreams { try await s.start() }
            streams = newStreams
            showWindow(with: view)
        } catch {
            await stopStreams()
            let alert = NSAlert()
            alert.messageText = "Could not start Ultrawide Share"
            alert.informativeText = "\(error.localizedDescription)\n\nIf this is the first run, allow UltrawideShare in System Settings > Privacy & Security > Screen & System Audio Recording, then quit and reopen it."
            alert.runModal()
        }
        rebuildMenu()
    }

    @MainActor private func showWindow(with view: CompositeView) {
        let box = view.bounding
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(screen.width * 0.9, box.width)
        let size = NSSize(width: width, height: width * box.height / box.width)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Ultrawide Share"
        window.contentView = view
        window.contentAspectRatio = box.size
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    @MainActor private func turnOff() async {
        let closing = window
        window = nil
        closing?.close()
        await stopStreams()
        rebuildMenu()
    }

    @MainActor private func stopStreams() async {
        for s in streams { await s.stop() }
        streams = []
    }

    func windowWillClose(_ notification: Notification) {
        guard window != nil else { return }
        Task { @MainActor in await turnOff() }
    }
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
