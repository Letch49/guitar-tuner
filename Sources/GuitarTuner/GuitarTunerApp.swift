import SwiftUI

@main
struct GuitarTunerApp: App {
    @StateObject private var viewModel = TunerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 660)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    viewModel.start()
                }
        }
        .defaultSize(width: 1100, height: 720)
    }
}
