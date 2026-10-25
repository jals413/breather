import BreatherKit
import SwiftUI

struct PairView: View {
    let model: PhoneModel
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            NightBackground()
            ScrollView {
                VStack(spacing: 26) {
                    ZStack {
                        BreathingHalo(color: Brand.mint).frame(width: 220, height: 220)
                        Circle().fill(Brand.gradient).frame(width: 112, height: 112)
                            .shadow(color: Brand.teal.opacity(0.5), radius: 24, y: 10)
                        BreatherMark(color: .white).frame(width: 60, height: 60)
                    }
                    .frame(height: 200)
                    .padding(.top, 20)

                    VStack(spacing: 8) {
                        Text("Breather").font(.system(size: 34, weight: .bold))
                        Text(Brand.tagline).font(.title3).foregroundStyle(BrandStyle.secondaryText)
                        Text("Your Mac's breaks on your Lock Screen and Dynamic Island, and a tap on your Apple Watch.")
                            .font(.callout)
                            .foregroundStyle(BrandStyle.tertiaryText)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Step(number: 1, text: "On your Mac, open Breather Settings → iPhone & Apple Watch.")
                        Step(number: 2, text: "Click “Pair a New iPhone…” and scan the QR code with your camera.")
                        Step(number: 3, text: "Or type the 6-digit code below.")
                    }
                    .brandCard(padding: 18)

                    CodeField(code: $code, focused: $focused)
                        .onChange(of: code) { _, new in
                            let digits = String(new.filter(\.isNumber).prefix(LinkConstants.pairingCodeLength))
                            if digits != new { code = digits }
                            if digits.count == LinkConstants.pairingCodeLength { model.pair(code: digits) }
                        }

                    if let status = model.pairingStatus {
                        HStack(spacing: 8) {
                            if model.isPairing { ProgressView().tint(.white) }
                            Text(status).font(.callout).foregroundStyle(BrandStyle.secondaryText).multilineTextAlignment(.center)
                        }
                    }

                    HStack(spacing: 6) {
                        Circle().fill(model.isConnected ? Brand.mint : BrandStyle.tertiaryText).frame(width: 7, height: 7)
                        Text(model.isConnected ? "Your Mac is nearby" : "Looking for your Mac…")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(BrandStyle.secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(BrandStyle.cardFill))
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
    }
}

private struct Step: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.bold())
                .foregroundStyle(Brand.night)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Brand.mint))
            Text(text).font(.callout).foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// Six glass boxes over a hidden text field, like Apple's verification code entry.
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
                        .font(BrandStyle.numeral(28))
                        .frame(width: 46, height: 58)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BrandStyle.cardFill))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(focused.wrappedValue && i == chars.count ? Brand.mint : BrandStyle.cardStroke,
                                          lineWidth: focused.wrappedValue && i == chars.count ? 2 : 1))
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
    }
}
