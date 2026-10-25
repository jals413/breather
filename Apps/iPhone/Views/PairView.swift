import BreatherKit
import SwiftUI

struct PairView: View {
    let model: PhoneModel
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ZStack {
                    Circle().fill(Brand.gradient).frame(width: 120, height: 120)
                        .shadow(color: Brand.teal.opacity(0.4), radius: 20, y: 10)
                    BreatherMark(color: .white).frame(width: 64, height: 64)
                }
                .padding(.top, 40)

                VStack(spacing: 8) {
                    Text("Breather for iPhone").font(.largeTitle.bold())
                    Text("See your Mac's breaks on your Lock Screen and Dynamic Island, and feel them on your Apple Watch.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Step(number: 1, text: "On your Mac, open Breather Settings → iPhone & Apple Watch.")
                    Step(number: 2, text: "Turn on “Connect to iPhone & Apple Watch”, then click “Pair a New iPhone…”.")
                    Step(number: 3, text: "Type the 6-digit code here.")
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))

                CodeField(code: $code, focused: $focused)
                    .onChange(of: code) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(LinkConstants.pairingCodeLength))
                        if digits != new { code = digits }
                        if digits.count == LinkConstants.pairingCodeLength { model.pair(code: digits) }
                    }

                if let status = model.pairingStatus {
                    HStack(spacing: 8) {
                        if model.isPairing { ProgressView() }
                        Text(status).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }

                Label(model.isConnected ? "Your Mac is nearby" : "Looking for your Mac…",
                      systemImage: model.isConnected ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                    .font(.footnote)
                    .foregroundStyle(model.isConnected ? Brand.teal : .secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear { focused = true }
    }
}

private struct Step: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Brand.teal))
            Text(text).font(.callout)
        }
    }
}

/// Six boxes over a hidden text field, like Apple's verification code entry.
private struct CodeField: View {
    @Binding var code: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(focused)
                .opacity(0.01)
            HStack(spacing: 10) {
                ForEach(0..<LinkConstants.pairingCodeLength, id: \.self) { i in
                    let chars = Array(code)
                    Text(i < chars.count ? String(chars[i]) : "")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .frame(width: 46, height: 58)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(i == chars.count ? Brand.teal : .clear, lineWidth: 2))
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
    }
}
