import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// Device facts and a timestamped memory estimate. No host name or unique hardware identifier is read.
public enum FlareDiagnostics {
    public static func deviceContext() -> [String: FlareValue] {
        var context: [String: FlareValue] = [
            "os_version": .string(ProcessInfo.processInfo.operatingSystemVersionString),
            "memory_sampled_at": .string(ISO8601DateFormatter().string(from: Date())),
        ]
        if let total = Int64(exactly: ProcessInfo.processInfo.physicalMemory) {
            context["memory_total_bytes"] = .integer(total)
        }

        #if os(macOS)
            context["os"] = "macOS"
        #elseif os(iOS)
            context["os"] = "iOS"
        #elseif os(tvOS)
            context["os"] = "tvOS"
        #elseif os(Linux)
            context["os"] = "Linux"
        #endif

        #if arch(arm64)
            context["architecture"] = "arm64"
        #elseif arch(x86_64)
            context["architecture"] = "x86_64"
        #elseif arch(arm)
            context["architecture"] = "arm"
        #elseif arch(i386)
            context["architecture"] = "x86"
        #endif

        #if canImport(Darwin)
            #if os(macOS)
                let modelKey = "hw.model"
            #else
                let modelKey = "hw.machine"
            #endif
            if let model = systemString(modelKey) {
                context["model"] = .string(model)
            }
            if let available = availableMemoryEstimate() {
                context["memory_available_estimate_bytes"] = .integer(available)
                context["memory_available_method"] = "free_plus_inactive_pages"
            }
        #endif
        return context
    }

    #if canImport(Darwin)
        private static func systemString(_ name: String) -> String? {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size <= 256 else { return nil }
            var bytes = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
            let value = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return value.isEmpty ? nil : value
        }

        private static func availableMemoryEstimate() -> Int64? {
            let host = mach_host_self()
            defer { mach_port_deallocate(mach_task_self_, host) }
            var pageSize: vm_size_t = 0
            guard host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }

            // The original VM info structure has a stable layout across macOS SDK revisions.
            // Its free count already includes speculative pages, so those must not be added twice.
            var statistics = vm_statistics_data_t()
            let capacity = MemoryLayout<vm_statistics_data_t>.size / MemoryLayout<integer_t>.size
            var count = mach_msg_type_number_t(capacity)
            let status = withUnsafeMutablePointer(to: &statistics) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                    host_statistics(host, HOST_VM_INFO, $0, &count)
                }
            }
            guard status == KERN_SUCCESS else { return nil }
            return availableBytes(
                freePages: UInt64(statistics.free_count), inactivePages: UInt64(statistics.inactive_count),
                pageSize: UInt64(pageSize), totalBytes: ProcessInfo.processInfo.physicalMemory
            )
        }
    #endif

    static func availableBytes(freePages: UInt64, inactivePages: UInt64, pageSize: UInt64, totalBytes: UInt64) -> Int64?
    {
        guard pageSize > 0 else { return nil }
        let (pages, addedOverflow) = freePages.addingReportingOverflow(inactivePages)
        guard !addedOverflow else { return nil }
        let (bytes, multipliedOverflow) = pages.multipliedReportingOverflow(by: pageSize)
        guard !multipliedOverflow else { return nil }
        return Int64(exactly: min(bytes, totalBytes))
    }
}
