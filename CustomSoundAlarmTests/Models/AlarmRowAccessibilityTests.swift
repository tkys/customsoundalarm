import Testing
import Foundation
@testable import CustomSoundAlarm

struct AlarmRowAccessibilityTests {

    @Test
    func toggleLabel_includesTimeAndLabel() {
        #expect(AlarmRowAccessibility.toggleLabel(time: "07:00", label: "アラーム") == "07:00 アラーム")
    }

    @Test
    func toggleLabel_emptyLabelUsesTimeOnly() {
        #expect(AlarmRowAccessibility.toggleLabel(time: "07:00", label: "") == "07:00")
        #expect(AlarmRowAccessibility.toggleLabel(time: "07:00", label: "   ") == "07:00")
    }
}
