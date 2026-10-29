import Testing
import Foundation
@testable import CustomSoundAlarm

@MainActor
struct BackupLoudVariantServiceTests {

    private var directory: URL {
        AudioConverter.shared.soundsDirectory
    }

    private func touch(_ name: String) throws {
        try Data("x".utf8).write(to: directory.appendingPathComponent(name))
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    private func removeIfExists(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    @Test
    func cleanup_keepsUsedVariantAndDeletesUnusedOrOrphan() throws {
        let names = [
            "UITestKeep.caf", "UITestKeep.loud.caf",
            "UITestUnused.caf", "UITestUnused.loud.caf",
            "UITestMissing.loud.caf"
        ]
        removeIfExists(names)
        defer { removeIfExists(names) }

        try touch("UITestKeep.caf")
        try touch("UITestKeep.loud.caf")
        try touch("UITestUnused.caf")
        try touch("UITestUnused.loud.caf")
        try touch("UITestMissing.loud.caf")

        let entry = AlarmEntry(soundFileName: "UITestKeep.caf", backupMinutes: 15)
        BackupLoudVariantService.cleanupUnusedVariants(
            entries: [entry],
            availableSourceFileNames: ["UITestKeep.caf", "UITestUnused.caf"]
        )

        #expect(exists("UITestKeep.loud.caf"))
        #expect(!exists("UITestUnused.loud.caf"), "未使用の variant は消える")
        #expect(!exists("UITestMissing.loud.caf"), "元音源が無い variant は消える")
    }

    @Test
    func cleanup_deletesVariantWhenBackupIsOff() throws {
        let names = ["UITestOff.caf", "UITestOff.loud.caf"]
        removeIfExists(names)
        defer { removeIfExists(names) }

        try touch("UITestOff.caf")
        try touch("UITestOff.loud.caf")

        let entry = AlarmEntry(soundFileName: "UITestOff.caf", backupMinutes: nil)
        BackupLoudVariantService.cleanupUnusedVariants(
            entries: [entry],
            availableSourceFileNames: ["UITestOff.caf"]
        )

        #expect(!exists("UITestOff.loud.caf"))
    }

    @Test
    func deleteVariant_removesGeneratedFile() throws {
        let names = ["UITestDelete.caf", "UITestDelete.loud.caf"]
        removeIfExists(names)
        defer { removeIfExists(names) }

        try touch("UITestDelete.caf")
        try touch("UITestDelete.loud.caf")

        BackupLoudVariantService.deleteVariant(for: "UITestDelete.caf")

        #expect(!exists("UITestDelete.loud.caf"))
        #expect(exists("UITestDelete.caf"), "元の音源は消さない")
    }

    @Test
    func sourceInfo_distinguishesPresetAndImported() throws {
        let preset = try #require(BackupLoudVariantService.sourceInfo(for: "PresetBeep.caf"))
        #expect(preset.source == .preset)

        let names = ["UITestImported.caf"]
        removeIfExists(names)
        defer { removeIfExists(names) }
        try touch("UITestImported.caf")

        let imported = try #require(BackupLoudVariantService.sourceInfo(for: "UITestImported.caf"))
        #expect(imported.source == .imported)

        #expect(BackupLoudVariantService.sourceInfo(for: "") == nil)
        #expect(BackupLoudVariantService.sourceInfo(for: "UITestNope.caf") == nil)
    }

    // MARK: - Version (#134)

    @Test
    func metadataVersion_detectsOldGeneration() throws {
        let variant = "UITestVersion.loud.caf"
        let names = ["UITestVersion.caf", variant, "UITestVersion.loud.json"]
        removeIfExists(names)
        defer { removeIfExists(names) }

        try touch("UITestVersion.caf")
        try touch(variant)
        let metadataURL = directory.appendingPathComponent("UITestVersion.loud.json")
        try JSONEncoder().encode(LoudVariantMetadata(version: 1)).write(to: metadataURL)

        #expect(LoudVariantMetadata.shouldRegenerate(
            BackupLoudVariantService.metadata(for: variant)
        ))
        #expect(BackupLoudVariantService.existingVariantFileName(for: "UITestVersion.caf") == nil)

        try JSONEncoder().encode(
            LoudVariantMetadata(version: LoudVariantGenerator.version)
        ).write(to: metadataURL)

        #expect(!LoudVariantMetadata.shouldRegenerate(
            BackupLoudVariantService.metadata(for: variant)
        ))
        #expect(BackupLoudVariantService.existingVariantFileName(for: "UITestVersion.caf") == variant)
    }

    @Test
    func metadataVersion_missingMeansRegenerate() {
        #expect(LoudVariantMetadata.shouldRegenerate(nil))
    }
}
