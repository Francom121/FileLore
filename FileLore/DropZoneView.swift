import SwiftUI
import UniformTypeIdentifiers

/// Main window: a prominent drop zone. Dropping a file (or opening one via the
/// Dock icon / `filelore://` URL) opens a note editor window for that file.
///
/// URL routing deliberately does NOT live here: an `onOpenURL` on this scene
/// makes SwiftUI treat the "main" WindowGroup as the URL-handling scene and
/// materialize a NEW drop-zone window for every incoming URL (right-click →
/// Add/Edit FileLore Note spawned one drop zone per click). All URL handling
/// lives in `AppDelegate.application(_:open:)` → `WindowRouter` instead.
struct DropZoneView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("Drop a file to attach a note")
                .font(.title2.weight(.semibold))
            Text("You can also drop files onto the FileLore Dock icon,\nright-click a file in Finder → Add/Edit FileLore Note,\nor select a file in Finder and press \(GlobalShortcutStore.load().displayString).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .padding(16)
        }
        .background(WindowCaptureView { window in
            WindowRouter.shared.registerMainWindow(window)
        })
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            // Collect every dropped URL first, then route: several files at
            // once open the batch editor instead of N single editors.
            // `loadObject(ofClass: URL.self)` reliably vends URLs for Finder
            // drags; `loadItem` can hand back Data or a private type instead.
            let group = DispatchGroup()
            let lock = NSLock()
            var urls: [URL] = []
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                    if let url = object {
                        lock.lock()
                        urls.append(url)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                guard !urls.isEmpty else { return }
                if urls.count > 1 {
                    WindowRouter.shared.openBatchEditor(for: urls)
                } else {
                    openWindow(id: "note-editor", value: urls[0])
                }
            }
            return true
        }
        .onAppear {
            WindowRouter.shared.register(openWindow)
        }
    }
}

/// Reports the `NSWindow` hosting this view as soon as it joins one, so
/// `WindowRouter` can raise the existing drop-zone window instead of
/// opening duplicates (`openWindow(id:)` on a WindowGroup always creates
/// a new window).
private struct WindowCaptureView: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowCaptureNSView {
        let view = WindowCaptureNSView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: WindowCaptureNSView, context: Context) {
        nsView.onResolve = onResolve
    }
}

private final class WindowCaptureNSView: NSView {
    var onResolve: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onResolve?(window)
        }
    }
}
