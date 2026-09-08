import Foundation
import Testing

@testable import Flare

struct FlareDiagnosticsTests {
    @Test func memoryFormattingUsesReadableUnitsWithTwoDecimalPlaces() {
        #expect(FlareDiagnostics.readableBytes(3_690_988) == "3.52 MB")
        #expect(FlareDiagnostics.readableBytes(1_342_177_280) == "1.25 GB")
        #expect(FlareDiagnostics.readableBytes(51_539_607_552) == "48.00 GB")
        #expect(FlareDiagnostics.readableBytes(0) == "0 B")
        #expect(FlareDiagnostics.readableBytes(-1) == nil)
    }

    @Test func applicationContextDisplaysMemoryAndRetainsItsSamplingTime() {
        let context = FlareDiagnostics.applicationContext(from: [
            "model": "Mac16,1", "memory_total_bytes": 51_539_607_552,
            "memory_available_estimate_bytes": 1_342_177_280, "memory_sampled_at": "before-crash",
        ])
        #expect(context["memory_total"] == "48.00 GB")
        #expect(context["memory_available_estimate"] == "1.25 GB")
        #expect(context["memory_sampled_at"] == "before-crash")
        #expect(context["memory_total_bytes"] == nil)
        #expect(context["memory_available_estimate_bytes"] == nil)
        #expect(context["model"] == "Mac16,1")
    }

    @Test func deviceSnapshotContainsTotalMemoryAndSamplingTime() {
        let snapshot = FlareDiagnostics.deviceContext()
        #expect(snapshot["memory_total_bytes"] == .integer(Int64(ProcessInfo.processInfo.physicalMemory)))
        #expect(snapshot["memory_sampled_at"] != nil)
        #expect(snapshot["os_version"] != nil)
        #expect(snapshot["host_name"] == nil)
        #expect(snapshot["serial_number"] == nil)
        #if os(macOS)
            #expect(snapshot["model"] != nil)
            #expect(snapshot["memory_available_estimate_bytes"] != nil)
        #endif
    }

    @Test func availableMemoryUsesFreeAndInactivePagesAndRespectsPhysicalMemory() {
        #expect(
            FlareDiagnostics.availableBytes(freePages: 2, inactivePages: 3, pageSize: 4096, totalBytes: 100_000)
                == 20_480)
        #expect(
            FlareDiagnostics.availableBytes(freePages: 2, inactivePages: 3, pageSize: 4096, totalBytes: 10_000)
                == 10_000)
    }

    @Test func invalidMemoryCountersAreOmittedWithoutOverflowing() {
        #expect(
            FlareDiagnostics.availableBytes(freePages: .max, inactivePages: 1, pageSize: 4096, totalBytes: .max) == nil)
        #expect(
            FlareDiagnostics.availableBytes(freePages: .max, inactivePages: 0, pageSize: 4096, totalBytes: .max) == nil)
        #expect(FlareDiagnostics.availableBytes(freePages: 1, inactivePages: 1, pageSize: 0, totalBytes: .max) == nil)
    }
}
