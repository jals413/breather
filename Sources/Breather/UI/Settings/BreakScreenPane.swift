import AppKit
import SwiftUI

struct BreakScreenPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        let look = $store.settings.appearance
        Form {
            PaneHeader(pane: .breakScreen)

            Section {
                LivePreview(appearance: store.settings.appearance)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                HStack {
                    Spacer()
                    Button("Preview full screen") { app.engine.startBreak(kind: .custom, duration: 10) }
                }
            }

            Section("Themes") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(BreakTheme.all) { theme in
                            ThemeCard(theme: theme, selected: store.settings.appearance == theme.appearance) {
                                withAnimation(.snappy) { store.settings.appearance = theme.appearance }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Background") {
                Picker("Style", selection: look.background) {
                    ForEach(BreakBackground.allCases) { Text($0.title).tag($0) }
                }
                switch store.settings.appearance.background {
                case .aurora:
                    Picker("Palette", selection: look.auroraPalette) {
                        ForEach(AuroraPalette.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Animate", isOn: look.animateBackground)
                case .gradient:
                    ColorPicker("Top", selection: color(look.gradientTop), supportsOpacity: false)
                    ColorPicker("Bottom", selection: color(look.gradientBottom), supportsOpacity: false)
                case .solid:
                    ColorPicker("Colour", selection: color(look.solidColor), supportsOpacity: false)
                case .image:
                    ImageSourceRow(path: look.imagePath)
                    LabeledSlider(title: "Blur", value: look.imageBlur, range: 0...60, step: 2) { $0 == 0 ? "None" : "\(Int($0))" }
                    LabeledSlider(title: "Dim", value: look.dimming, range: 0...0.8, step: 0.05) { "\(Int($0 * 100))%" }
                case .wallpaper, .frosted:
                    LabeledSlider(title: "Dim", value: look.dimming, range: 0...0.8, step: 0.05) { "\(Int($0 * 100))%" }
                }
            }

            Section("Timer") {
                Picker("Style", selection: look.timerStyle) {
                    ForEach(TimerStyle.allCases) { Text($0.title).tag($0) }
                }
                if store.settings.appearance.timerStyle != .hidden {
                    Picker("Font", selection: look.timerDesign) {
                        ForEach(TextDesign.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Weight", selection: look.timerWeight) {
                        ForEach(TextWeight.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledSlider(title: "Size", value: look.timerScale, range: 0.6...1.8, step: 0.05) { "\(Int($0 * 100))%" }
                    ColorPicker("Accent", selection: color(look.accent), supportsOpacity: false)
                }
            }

            Section("Text") {
                ColorPicker("Colour", selection: color(look.textColor), supportsOpacity: false)
                Picker("Message font", selection: look.messageDesign) {
                    ForEach(TextDesign.allCases) { Text($0.title).tag($0) }
                }
                Picker("Message weight", selection: look.messageWeight) {
                    ForEach(TextWeight.allCases) { Text($0.title).tag($0) }
                }
                LabeledSlider(title: "Message size", value: look.messageScale, range: 0.6...1.6, step: 0.05) { "\(Int($0 * 100))%" }
            }

            Section("Show") {
                Toggle("Break name", isOn: look.showKindLabel)
                Toggle("Message", isOn: look.showMessage)
                Toggle("Breathing glow", isOn: look.showBreathingHalo)
                Toggle("“Breathe in / Breathe out” guide", isOn: look.showBreathingCue)
                Toggle("Current time", isOn: look.showClock)
                Toggle("Keyboard hint", isOn: look.showHint)
            }
        }
    }

    private func color(_ binding: Binding<RGBA>) -> Binding<Color> {
        Binding { binding.wrappedValue.color } set: { binding.wrappedValue = RGBA($0) }
    }
}

let sampleSession = BreakSession(kind: .short, start: .now, duration: 20, message: "Look at something 20 feet away.")

/// The real break screen, scaled down and ticking.
struct LivePreview: View {
    var appearance: BreakAppearance
    @State private var start = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            // Loop a 20s break forever.
            let elapsed = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: 20)
            var session = sampleSession
            let _ = { session.start = context.date.addingTimeInterval(-elapsed) }()
            BreakScreen(appearance: appearance, session: session, now: context.date, skip: .skip, canSnooze: true,
                        screen: NSScreen.main, isPreview: true)
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.separator))
    }
}

struct ThemeCard: View {
    var theme: BreakTheme
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                BreakScreen(appearance: { var a = theme.appearance; a.animateBackground = false; return a }(),
                            session: sampleSession, now: sampleSession.start.addingTimeInterval(7), skip: .hidden,
                            canSnooze: false, screen: NSScreen.main, isPreview: true)
                    .frame(width: 150, height: 94)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 3 : 1)
                    )
                Text(theme.id).font(.caption).foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ImageSourceRow: View {
    @Binding var path: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo")
                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Choose…") { choose() }
        }
    }

    private var description: String {
        guard let path else { return "Pick an image, or a folder to rotate through" }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return (isDir.boolValue ? "Folder: " : "") + (path as NSString).abbreviatingWithTildeInPath
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "Use"
        panel.message = "Choose a photo, or a folder of photos to rotate through."
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}
