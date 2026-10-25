import Testing
import Foundation
@testable import CustomSoundAlarm

struct BackupSoundResolverTests {

    @Test
    func variantFileName() {
        #expect(BackupSoundResolver.variantFileName(for: "") == nil)
        #expect(BackupSoundResolver.variantFileName(for: "UUID.caf") == "UUID.loud.caf")
        #expect(BackupSoundResolver.variantFileName(for: "PresetBeep.caf") == "PresetBeep.loud.caf")
    }

    @Test
    func resolve_usesVariantWhenAvailable() {
        #expect(BackupSoundResolver.resolve(
            sourceFileName: "UUID.caf",
            availableVariantFileName: "UUID.loud.caf",
            fallbackFileName: "PresetBackupLoud.caf"
        ) == "UUID.loud.caf")
    }

    @Test
    func resolve_fallsBackWhenVariantMissing() {
        #expect(BackupSoundResolver.resolve(
            sourceFileName: "UUID.caf",
            availableVariantFileName: nil,
            fallbackFileName: "PresetBackupLoud.caf"
        ) == "PresetBackupLoud.caf")
    }

    @Test
    func resolve_defaultSoundUsesFallback() {
        #expect(BackupSoundResolver.resolve(
            sourceFileName: "",
            availableVariantFileName: "anything.loud.caf",
            fallbackFileName: "PresetBackupLoud.caf"
        ) == "PresetBackupLoud.caf")
    }
}
