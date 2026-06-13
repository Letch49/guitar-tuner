import SwiftUI

@main
struct GuitarTunerApp: App {
    @StateObject private var viewModel = TunerViewModel()
    private let settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 660)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    viewModel.start()
                }
        }
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(viewModel)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        } label: {
            MenuBarLabel()
                .environmentObject(viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
