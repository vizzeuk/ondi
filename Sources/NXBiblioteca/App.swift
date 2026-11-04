import SwiftUI


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the window when it appears; the delegate needs it to stop builds when the app quits.
    weak var store: LibraryStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let out = ProcessInfo.processInfo.environment["NXB_SELFTEST"] {
            Task { @MainActor in await SelfTest.run(output: out) }
            return
        }
        // NXB_SNAPSHOT=<file.png>: saves a picture of the main window (for docs and videos).
        if let path = ProcessInfo.processInfo.environment["NXB_SNAPSHOT"] {
            let delay = Double(ProcessInfo.processInfo.environment["NXB_SNAPSHOT_DELAY"] ?? "") ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Self.snapshot(to: path) }
        }
    }

    private static func snapshot(to path: String, attempt: Int = 0) {
        let sheetOnly = ProcessInfo.processInfo.environment["NXB_SNAPSHOT_SHEET"] != nil
        let window = NSApp.windows.filter { $0.isVisible && $0.contentView != nil && (!sheetOnly || $0.sheetParent != nil) }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard let window, let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            if attempt < 10 { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { snapshot(to: path, attempt: attempt + 1) } }
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Closing the window mid-build keeps the app (and the build) running; the Dock icon brings the window back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        (store?.runningJobs ?? 0) == 0
    }

    /// Quitting mid-build used to leave the build's tools running with nobody watching them, and the next build of
    /// that game collided with them. Now the app asks, and stops the build before it exits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.runningJobs > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = store.runningJobs == 1 ? String(localized: "Hay una compilación en curso") : String(localized: "Hay \(store.runningJobs) compilaciones en curso")
        alert.informativeText = String(localized: "Si sales, se detiene. Podrás retomarla después: se conservan las etapas que ya terminaron.")
        alert.addButton(withTitle: "Seguir compilando")
        alert.addButton(withTitle: "Detener y salir")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        store.stopAllJobsForQuit()
        return .terminateNow
    }
}

@main
struct NXBibliotecaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = LibraryStore()

    var body: some Scene {
        WindowGroup(Brand.name) {
            HomeView()
                .environment(store)
                .onAppear { delegate.store = store }
                .preferredColorScheme(.light)
                .tint(Theme.accent)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .defaultSize(width: 1360, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Agregar juegos…") { store.importerRequested = true }
                    .keyboardShortcut("o")
                Button("Recargar biblioteca") { Task { await store.reload() } }
                    .keyboardShortcut("r")
            }
        }

        Settings {
            PreferencesView()
                .environment(store)
                .preferredColorScheme(.light)
                .tint(Theme.accent)
        }
    }
}
