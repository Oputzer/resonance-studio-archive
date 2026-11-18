import SwiftUI

struct RootView: View {
    @EnvironmentObject private var account: Account
    @State private var showTerms = false

    var body: some View {
        Group {
            if account.hasAcceptedTerms && account.isSignedIn {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .animation(.smooth(duration: 0.35), value: account.isSignedIn)
        .onReceive(NotificationCenter.default.publisher(for: .showTerms)) { _ in showTerms = true }
        .sheet(isPresented: $showTerms) { TermsSheet() }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var account: Account
    @State private var step: Step = .welcome

    enum Step { case welcome, terms, signIn }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            RadialGradient(colors: [Brand.accent.opacity(0.18), .clear], center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()

            Group {
                switch step {
                case .welcome: WelcomeStep { step = .terms }
                case .terms: TermsStep(onBack: { step = .welcome }) { account.acceptTerms(); step = .signIn }
                case .signIn: SignInStep(onBack: { step = .terms })
                }
            }
            .frame(maxWidth: 560)
            .padding(40)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
        }
        .animation(.smooth(duration: 0.35), value: step)
        .onAppear { if account.hasAcceptedTerms { step = .signIn } }
    }
}

private struct WelcomeStep: View {
    var next: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            LogoMark(size: 120)
                .shadow(color: Brand.accent.opacity(0.35), radius: 24, y: 10)
            VStack(spacing: 8) {
                Text("Welcome to Resonance Studio")
                    .font(.system(size: 34, weight: .bold))
                Text("Music that stays with you.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                Feature(symbol: "arrow.down.circle.fill", title: "Any format",
                        text: "Save public SoundCloud playlists as Original, MP3, AAC, WAV or FLAC.")
                Feature(symbol: "photo.fill", title: "Artwork and details",
                        text: "Cover art, release dates, genres, play counts and more, built in.")
                Feature(symbol: "folder.fill", title: "Your library, on your Mac",
                        text: "In a Resonance Studio folder on your Desktop, one dated folder per playlist.")
            }
            .padding(.vertical, 8)
            Button(action: next) {
                Text("Get Started").frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct Feature: View {
    let symbol: String, title: String, text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Brand.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TermsStep: View {
    var onBack: () -> Void
    var onAgree: () -> Void
    @State private var agreed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Terms of Use").font(.system(size: 28, weight: .bold))
                Text("Please read these carefully. You need to accept them to use Resonance Studio.")
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LegalText().padding(22)
            }
            .frame(height: 360)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))

            Toggle(isOn: $agreed) {
                Text("I have read and agree to the Terms of Use and Privacy Policy. I understand that I am responsible for what I download and I accept all legal risk of using Resonance Studio.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)

            HStack {
                Button("Back", action: onBack).controlSize(.large)
                Spacer()
                Button(action: onAgree) { Text("Agree and Continue").frame(minWidth: 160) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!agreed)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct SignInStep: View {
    @EnvironmentObject private var account: Account
    var onBack: () -> Void

    @State private var email = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var emailValid: Bool {
        email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) != nil
    }

    var body: some View {
        VStack(spacing: 22) {
            LogoMark(size: 72)
                .shadow(color: Brand.accent.opacity(0.3), radius: 16, y: 6)
            VStack(spacing: 8) {
                Text(sentTo == nil ? "Create your account" : "Check your email")
                    .font(.system(size: 28, weight: .bold))
                Group {
                    if let sentTo {
                        Text("Enter the code we sent to **\(sentTo)**.")
                    } else {
                        Text("Sign in or sign up with your email. We'll send you a one-time code. No password needed.")
                    }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            }

            Group {
                if sentTo == nil {
                    TextField("name@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .font(.title3)
                } else {
                    TextField("Code", text: $code)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .onChange(of: code) { _, new in
                            let digits = String(new.filter(\.isNumber).prefix(10))
                            if digits != new { code = digits }
                        }
                }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .frame(maxWidth: 340)
            .focused($focused)
            .onSubmit(primary)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Button(action: primary) {
                ZStack {
                    Text(sentTo == nil ? "Continue" : "Verify").opacity(busy ? 0 : 1)
                    if busy { ProgressView().controlSize(.small) }
                }
                .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(busy || (sentTo == nil ? !emailValid : code.count < 6))
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 18) {
                if sentTo != nil {
                    Button("Use a different email") { sentTo = nil; code = ""; error = nil }
                    Button("Resend code") { Task { await send(resend: true) } }
                } else {
                    Button("Back to Terms", action: onBack)
                }
            }
            .buttonStyle(.link)
            .font(.callout)

            if !Backend.isConfigured {
                Text("Test build: the sign-in server isn't connected yet, so your email is only saved on this Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear { focused = true }
    }

    private func primary() {
        if sentTo == nil { Task { await send(resend: false) } } else { Task { await verify() } }
    }

    private func send(resend: Bool) async {
        guard emailValid, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        do {
            if !Backend.isConfigured {
                try await account.verify(email: address, code: "")
                return
            }
            try await account.sendCode(to: address)
            sentTo = address
            focused = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verify() async {
        guard let sentTo, code.count >= 6, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { try await account.verify(email: sentTo, code: code) }
        catch { self.error = error.localizedDescription }
    }
}

struct TermsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            ScrollView { LegalText().padding(28) }
            Divider()
            HStack {
                Text("You accepted version \(Legal.version).").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640, height: 600)
    }
}
