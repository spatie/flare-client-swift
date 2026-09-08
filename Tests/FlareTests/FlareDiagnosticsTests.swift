import Foundation
import Testing

@testable import Flare

struct FlareDiagnosticsTests {
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
