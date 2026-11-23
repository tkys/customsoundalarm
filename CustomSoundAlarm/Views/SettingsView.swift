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
    @State private var mailAttachment: MailAttachment?
    @State private var sharePayload: SharePayload?
    @State private var isPreparingContact = false

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
                        HStack {
                            row(title: "settings_contact", systemImage: "envelope")
                            if isPreparingContact {
                                Spacer(minLength: 8)
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isPreparingContact)
                    .accessibilityIdentifier("settings.contact")

                    Button {
                        AnalyticsService.shared.capture(.supportContactOpened(
                            method: .web,
                            diagnosticsAttached: false
                        ))
                        openURL(SettingsLogic.supportURL)
                    } label: {
                        externalRow(title: "settings_support_page", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("settings.support")

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
                    body: mailBody,
                    attachment: mailAttachment
                ) {
                    showingMail = false
                }
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheetView(activityItems: payload.activityItems)
                    .accessibilityIdentifier("settings.shareSheet")
                    .presentationDetents([.medium, .large])
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

    /// メールが使えればメール作成、使えなければ共有シートを開く（#255）。
    /// どちらも診断 JSON を添付し、送るかどうかは本人に委ねる。
    private func openContact() {
        guard !isPreparingContact else { return }
        isPreparingContact = true

        let body = SettingsLogic.mailBody(
            appVersion: SettingsLogic.appVersionString(),
            osVersion: UIDevice.current.systemVersion,
            deviceModel: SettingsLogic.deviceModelName()
        )

        Task {
            let reportURL = await DiagnosticsService.writeReport()
            let attachment = reportURL.flatMap { url -> MailAttachment? in
                guard let data = DiagnosticsService.reportData(at: url) else { return nil }
                return MailAttachment(data: data, fileName: DiagnosticsService.fileName)
            }
            let attached = attachment != nil
            let canMail = !AppGroup.isUITestContactNoMail
                && MFMailComposeViewController.canSendMail()

            await MainActor.run {
                isPreparingContact = false
                if canMail {
                    AnalyticsService.shared.capture(.supportContactOpened(
                        method: .mail,
                        diagnosticsAttached: attached
                    ))
                    mailBody = body
                    mailAttachment = attachment
                    showingMail = true
                } else {
                    AnalyticsService.shared.capture(.supportContactOpened(
                        method: .share,
                        diagnosticsAttached: attached
                    ))
                    sharePayload = SharePayload(
                        text: SettingsLogic.shareText(body: body),
                        fileURL: reportURL
                    )
                }
            }
        }
    }
}

// MARK: - Share

/// 共有シートに渡す文面と診断ファイル。
struct SharePayload: Identifiable {
    let id = UUID()
    let text: String
    let fileURL: URL?

    var activityItems: [Any] {
        var items: [Any] = [text]
        if let fileURL {
            items.append(fileURL)
        }
        return items
    }
}

/// メールが使えない端末向けの共有シート（#255）。
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.view.accessibilityIdentifier = "settings.shareSheet"
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Mail

/// メール作成画面。本文は送る前に本人が編集・削除できる。
struct MailAttachment {
    let data: Data
    let fileName: String
}

struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let attachment: MailAttachment?
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        if let attachment {
            controller.addAttachmentData(
                attachment.data,
                mimeType: "application/json",
                fileName: attachment.fileName
            )
        }
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
