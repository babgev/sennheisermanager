import SwiftUI
import MomentumKit

/// Using an AppDelegate so the first Bluetooth call happens from
/// `applicationDidFinishLaunching` (a run-loop callout). Touching IOBluetooth
/// from a `DispatchQueue.main.async` block instead deadlocks the coordinator.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = M4Controller()
    private var started = false

    override init() {
        super.init()
        Diag.write("AppDelegate.init")
        // Fallback: if the launch callback doesn't fire, kick off shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startOnce("init+0.5s")
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Diag.write("applicationWillFinishLaunching")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Diag.write("applicationWillTerminate — closing channel")
        controller.shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startOnce("applicationDidFinishLaunching")
    }

    private func startOnce(_ via: String) {
        guard !started else { return }
        started = true
        Diag.write("startOnce via \(via)")
        controller.start()
    }
}

@main
struct MomentumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(controller: appDelegate.controller)
        } label: {
            MenuBarLabel(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Small wrapper so the menu bar icon observes controller state changes.
/// The glyph stays constant (custom headphones+waveform mark); only its
/// prominence reflects whether we're connected — never swapped per listening mode.
private struct MenuBarLabel: View {
    @ObservedObject var controller: M4Controller
    var body: some View {
        Image(nsImage: MenuBarIcon.image)
            .renderingMode(.template)
            .opacity(controller.isConnected ? 1.0 : 0.5)
    }
}
