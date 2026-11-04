import Testing
import Foundation
@testable import CustomSoundAlarm

/// `PrivacyInfo.xcprivacy` が App Store Connect のプライバシー表示と
/// 一致しているかを確認する（#167）。
struct PrivacyManifestTests {

    private static let expectedTypes: Set<String> = [
        "NSPrivacyCollectedDataTypeProductInteraction",
        "NSPrivacyCollectedDataTypeCoarseLocation",
        "NSPrivacyCollectedDataTypeOtherDiagnosticData"
    ]

    private static let analytics =
        "NSPrivacyCollectedDataTypePurposeAnalytics"
    private static let appFunctionality =
        "NSPrivacyCollectedDataTypePurposeAppFunctionality"

    private func manifestURL() throws -> URL {
        if let bundled = Bundle.main.url(
            forResource: "PrivacyInfo",
            withExtension: "xcprivacy"
        ) {
            return bundled
        }

        // ユニットテストのホストに同梱されていない場合はリポジトリから読む。
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return projectRoot
            .appendingPathComponent("CustomSoundAlarm/PrivacyInfo.xcprivacy")
    }

    private func manifest() throws -> [String: Any] {
        let data = try Data(contentsOf: manifestURL())
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try #require(plist as? [String: Any])
    }

    private func collectedTypes(
        in manifest: [String: Any]
    ) -> [String: [String: Any]] {
        let entries = manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        return Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            guard let type = entry["NSPrivacyCollectedDataType"] as? String else {
                return nil
            }
            return (type, entry)
        })
    }

    @Test
    func collectedDataTypesMatchAppStoreConnect() throws {
        let manifest = try manifest()
        let types = collectedTypes(in: manifest)

        #expect(Set(types.keys) == Self.expectedTypes)

        for type in Self.expectedTypes {
            let entry = try #require(types[type], "missing collected type: \(type)")
            #expect(
                entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == false,
                "\(type) must not be linked to the user"
            )
            #expect(
                entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false,
                "\(type) must not be used for tracking"
            )

            let purposes = try #require(
                entry["NSPrivacyCollectedDataTypePurposes"] as? [String],
                "missing purposes: \(type)"
            )
            #expect(
                Set(purposes) == [Self.analytics],
                "\(type) purposes must be Analytics only, got \(purposes)"
            )
            #expect(
                !purposes.contains(Self.appFunctionality),
                "\(type) must not declare App Functionality"
            )
        }
    }

    @Test
    func trackingIsDisabled() throws {
        let manifest = try manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
    }
}
