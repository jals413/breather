import AppKit
import BreatherKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct DevicesPane: View {
    let app: AppModel

    var body: some View {
        @Bindable var store = app.store
        let phone = app.phone
        Form {
            PaneHeader(pane: .devices)

            Section {
                Toggle("Connect to iPhone & Apple Watch", isOn: $store.settings.phoneLinkEnabled)
                if store.settings.phoneLinkEnabled {
                    LabeledContent("Bluetooth", value: phone.bluetoothStatus)
                    LabeledContent("Connected right now", value: phone.connectedCount == 0 ? "None" : "\(phone.connectedCount)")
                }
            } footer: {
                Text("Your iPhone shows each break as a Live Activity on the Lock Screen and in the Dynamic Island, and your Apple Watch taps you. Breather uses Bluetooth while your phone is near your Mac, and your local network while the phone app is open.")
            }

            if store.settings.phoneLinkEnabled {
                Section("Paired devices") {
                    if phone.devices.isEmpty {
                        Text("No devices yet.").foregroundStyle(.secondary)
                    }
                    ForEach(phone.devices) { device in
                        HStack(spacing: 10) {
                            SettingsBadge(symbol: "iphone", tint: Brand.teal)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name)
                                Text(device.lastSeen.map { "Last seen \($0.formatted(.relative(presentation: .named)))" } ?? "Paired")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Forget", role: .destructive) { phone.forget(device) }
                        }
                    }
                    PairingRow(phone: phone)
                }

                Section {
                    Toggle("Block distracting apps on iPhone during breaks", isOn: $store.settings.phoneBlockDuringBreaks)
                } header: {
                    Text("During breaks")
                } footer: {
                    Text(FeatureFlags.paidAccount
                         ? "Choose which apps to block in Breather on your iPhone. Uses Screen Time."
                         : "Uses Screen Time on the iPhone. \(FeatureFlags.paidExplanation)")
                }

                Section {
                    if FeatureFlags.paidAccount {
                        TextField("Team ID", text: $store.settings.apnsTeamID)
                        TextField("Key ID", text: $store.settings.apnsKeyID)
                        HStack {
                            Text(store.settings.apnsKeyPath.isEmpty ? "No key chosen" : (store.settings.apnsKeyPath as NSString).lastPathComponent)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Choose .p8 Key…") {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.init(filenameExtension: "p8") ?? .data]
                                if panel.runModal() == .OK, let url = panel.url { store.settings.apnsKeyPath = url.path }
                            }
                        }
                        if let result = phone.apns.lastResult {
                            LabeledContent("Last push", value: result).font(.caption)
                        }
                    } else {
                        Label {
                            Text("Reach your iPhone anywhere, even asleep or in Low Power Mode, with Apple push. \(FeatureFlags.paidExplanation)")
                        } icon: {
                            Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple push")
                }
            }
        }
    }
}

private struct PairingRow: View {
    let phone: PhoneLink

    var body: some View {
        if let code = phone.pairingCode, let expires = phone.pairingExpires {
            VStack(spacing: 10) {
                Text("Scan with your iPhone camera, or type the code in Breather on your iPhone")
                    .font(.callout).foregroundStyle(.secondary)
                if let url = phone.pairingURL, let qr = QRCode.image(for: url.absoluteString) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 150, height: 150)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                }
                Text(code.map(String.init).joined(separator: " "))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .tracking(4)
                    .textSelection(.enabled)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, expires.timeIntervalSince(context.date))
                    Text(left > 0 ? "Expires in \(Int(left))s" : "Expired").font(.caption).foregroundStyle(.secondary)
                }
                Button("Cancel") { phone.cancelPairing() }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else {
            HStack {
                Spacer()
                Button("Pair a New iPhone…") { phone.startPairing() }
                    .disabled(phone.devices.count >= LinkConstants.maxPairedDevices)
            }
        }
    }
}

enum QRCode {
    static func image(for string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
