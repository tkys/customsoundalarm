import SwiftUI
import MessageUI
import UIKit

/// 設定画面（#204）。
/// ナイトモード・問い合わせ・レビュー・使い方・プライバシー・バージョンをこの順に置く。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showingBedside = false
    @State private var showingMail = false
    @State private var mailBody = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingBedside = true
                    } label: {
                        row(title: "night_mode", systemImage: "moon.zzz")
                    }
                    .accessibilityIdentifier("settings.bedside")
                }

                Section {
                    Button {
                        openContact()
                    } label: {
                        row(title: "settings_contact", systemImage: "envelope")
                    }
                    .accessibilityIdentifier("settings.contact")

                    Button {
                        AnalyticsService.shared.capture(.reviewLinkOpened)
                        openURL(SettingsLogic.reviewURL)
                    } label: {
                        externalRow(title: "settings_review", systemImage: "star")
                    }
                    .accessibilityIdentifier("settings.review")

                    Button {
                        openURL(SettingsLogic.howToURL(locale: .current))
                    } label: {
                        externalRow(title: "settings_howto", systemImage: "book")
                    }
                    .accessibilityIdentifier("settings.howto")
                }

                Section {
                    Button {
                        openURL(SettingsLogic.privacyURL)
                    } label: {
                        externalRow(title: "settings_privacy", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("settings.privacy")

                    versionRow
                }
            }
            .warmListBackground()
            .accessibilityIdentifier("settings.root")
            .navigationTitle(String(localized: "settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close") { dismiss() }
                        .accessibilityIdentifier("settings.close")
                }
            }
            .onAppear {
                AnalyticsService.shared.capture(.settingsOpened)
            }
            .fullScreenCover(isPresented: $showingBedside) {
                BedsideClockView()
            }
            .sheet(isPresented: $showingMail) {
                MailComposeView(
                    recipients: [SettingsLogic.supportEmail],
                    subject: String(localized: "settings_mail_subject"),
                    body: mailBody
                ) {
                    showingMail = false
                }
            }
        }
    }

    /// アプリの外に出る行。右端に小さな矢印を置く（読み上げ不要）。
    private func externalRow(title: LocalizedStringKey, systemImage: String) -> some View {
        HStack {
            row(title: title, systemImage: systemImage)
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
        }
    }

    /// 最大の文字サイズでは「バージョン」がハイフンで切れないよう縦に積む。
    @ViewBuilder
    private var versionRow: some View {
        let version = Text(SettingsLogic.appVersionString())
            .foregroundStyle(Color.textSecondary)
            .accessibilityIdentifier("settings.version")
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text("settings_version")
                version
            }
        } else {
            HStack {
                Text("settings_version")
                Spacer(minLength: 12)
                version
            }
        }
    }

    private func row(title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.actionText)
        }
    }

    /// メールが使えればメール作成、使えなければサポートページを開く。
    private func openContact() {
        if MFMailComposeViewController.canSendMail() {
            AnalyticsService.shared.capture(.supportContactOpened(method: .mail))
            mailBody = SettingsLogic.mailBody(
                appVersion: SettingsLogic.appVersionString(),
                osVersion: UIDevice.current.systemVersion,
                deviceModel: SettingsLogic.deviceModelName()
            )
            showingMail = true
        } else {
            AnalyticsService.shared.capture(.supportContactOpened(method: .web))
            openURL(SettingsLogic.supportURL)
        }
    }
}

// MARK: - Mail

/// メール作成画面。本文は送る前に本人が編集・削除できる。
struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish()
        }
    }
}
