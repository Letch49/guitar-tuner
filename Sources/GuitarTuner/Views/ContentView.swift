import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: TunerViewModel

    @State private var showSettings = false
    @State private var gearRotation: Double = 0

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            mainPane
        }
        .background(Theme.background)
        .overlay {
            if viewModel.permissionDenied {
                permissionOverlay
            }
        }
    }

    // MARK: - Main pane

    private var mainPane: some View {
        ZStack {
            GridBackground()
            VStack(spacing: 0) {
                topBar
                GaugeView()
                    .padding(.top, 4)
                HeadstockView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                statusPill
                    .padding(.bottom, 18)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Guitar Tuner")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Spacer()

            LevelMeter(level: viewModel.inputLevel)
                .help("Input level")

            Circle()
                .fill(viewModel.isRunning ? Theme.accent : Color.red)
                .frame(width: 8, height: 8)

            Picker("", selection: $viewModel.selectedDeviceUID) {
                ForEach(viewModel.devices) { device in
                    Text(device.name).tag(Optional(device.uid))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                    gearRotation += 120
                }
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .rotationEffect(.degrees(gearRotation))
            }
            .buttonStyle(.borderless)
            .foregroundColor(Theme.textSecondary)
            .help("Settings")
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            if let message = viewModel.captureErrorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
            } else if viewModel.frequency == nil {
                Image(systemName: "waveform")
                Text("Play a string")
            } else if viewModel.isInTune {
                Image(systemName: "checkmark.circle.fill")
                Text("In tune")
            } else if viewModel.cents < 0 {
                Image(systemName: "arrow.up")
                Text("Tune up")
            } else {
                Image(systemName: "arrow.down")
                Text("Tune down")
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(pillForeground)
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Capsule().fill(pillBackground))
        .animation(.easeOut(duration: 0.15), value: viewModel.isInTune)
    }

    private var pillBackground: Color {
        if viewModel.captureErrorMessage != nil { return Color.red.opacity(0.25) }
        if viewModel.frequency == nil { return Theme.panelLight }
        return viewModel.isInTune ? Theme.accent : Theme.warn.opacity(0.2)
    }

    private var pillForeground: Color {
        if viewModel.captureErrorMessage != nil { return .red }
        if viewModel.frequency == nil { return Theme.textSecondary }
        return viewModel.isInTune ? Color.black.opacity(0.85) : Theme.warn
    }

    // MARK: - Permission overlay

    private struct LevelMeter: View {
        let level: Float

        private var normalized: CGFloat {
            guard level > 0 else { return 0 }
            let db = 20 * log10(Double(level))
            return CGFloat(max(0, min(1, (db + 60) / 60)))
        }

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(normalized > 0.9 ? Color.red : Theme.accent)
                        .frame(width: max(0, geo.size.width * normalized))
                        .animation(.linear(duration: 0.1), value: normalized)
                }
            }
            .frame(width: 70, height: 6)
        }
    }


    private var permissionOverlay: some View {
        ZStack {
            Color.black.opacity(0.75)
            VStack(spacing: 14) {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                Text("Microphone access is required")
                    .font(.title3.bold())
                Text("Open System Settings → Privacy & Security → Microphone\nand enable access for Guitar Tuner, then relaunch the app.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.textSecondary)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(40)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
        }
        .ignoresSafeArea()
    }
}
