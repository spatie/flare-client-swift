#if canImport(CrashReporter)
    import CrashReporter
    import Flare
    import Foundation

    enum NativeCrashConverter {
        static func convert(_ stored: StoredCrash) throws -> FlareReport {
            let crash = try PLCrashReport(data: stored.data)
            guard let signal = crash.signalInfo,
                let system = crash.systemInfo,
                let timestamp = system.timestamp,
                let threads = crash.threads as? [PLCrashReportThreadInfo],
                let crashedThread = threads.first(where: \.crashed)
            else {
                throw FlareCrashReporterError.invalidNativeReport
            }

            let processPath = crash.processInfo?.processPath
            let images = (crash.images as? [PLCrashReportBinaryImageInfo]) ?? []
            let applicationPath = applicationImagePath(
                imagePaths: images.compactMap(\.imageName),
                processPath: processPath,
                processName: crash.processInfo?.processName
            )
            let applicationImage = images.first { $0.imageName == applicationPath }
            let frames = (crashedThread.stackFrames as? [PLCrashReportStackFrameInfo]) ?? []
            let stacktrace = frames.map { frame -> FlareStackFrame in
                let image = crash.image(forAddress: frame.instructionPointer)
                let imageName = basename(image?.imageName)
                let offset = image.map { frame.instructionPointer &- $0.imageBaseAddress }
                return FlareStackFrame(
                    file: imageName,
                    method: frame.symbolInfo?.symbolName ?? offset.map { "\(imageName) + \(hex($0))" } ?? "unknown",
                    isApplicationFrame: applicationPath != nil && image?.imageName == applicationPath
                )
            }

            var context: [String: FlareValue] = [:]
            if let data = crash.customData {
                context = (try? JSONDecoder().decode([String: FlareValue].self, from: data)) ?? [:]
            }
            let capturedDiagnostics = context.removeValue(forKey: CrashContext.diagnosticsKey)
            context["native_crash"] = .object([
                "signal": .string(signal.name ?? "unknown"),
                "signal_code": .string(signal.code ?? "unknown"),
                "fault_address": .string(hex(signal.address)),
                "crashed_thread": .integer(Int64(crashedThread.threadNumber)),
                "symbolicated": false,
                "binary_images": .array(images.map(imageContext)),
                "threads": .array(threads.map { threadContext($0, crash: crash) }),
            ])

            let signalName = signal.name ?? "NativeCrash"
            let exceptionName = crash.exceptionInfo?.exceptionName ?? signalName
            let message =
                crash.exceptionInfo?.exceptionReason ?? "\(signalName): \(signal.code ?? "Native process crash")"
            var attributes: [String: FlareValue] = [
                "os.type": "darwin",
                "os.version": .string(system.operatingSystemVersion ?? "unknown"),
            ]
            // Older reports have no memory snapshot. An explicit device object prevents
            // the client's fresh, post-restart memory reading from being attributed to that crash.
            var device: [String: FlareValue] = [:]
            if case .object(let captured) = capturedDiagnostics { device = captured }
            if let model = crash.machineInfo?.modelName { device["model"] = .string(model) }
            attributes["context.device"] = .object(device)
            if let application = crash.applicationInfo {
                attributes["service.version"] = .string(
                    application.applicationMarketingVersion ?? application.applicationVersion ?? "unknown")
                attributes["context.application"] = .object([
                    "identifier": .string(application.applicationIdentifier ?? "unknown"),
                    "build": .string(application.applicationVersion ?? "unknown"),
                ])
            }
            if let processor = system.processorInfo {
                switch processor.type {
                case 0x0100_000C: attributes["host.arch"] = "arm64"
                case 0x0100_0007: attributes["host.arch"] = "x86_64"
                case 12: attributes["host.arch"] = "arm"
                case 7: attributes["host.arch"] = "x86"
                default: attributes["host.arch"] = .string(String(processor.type))
                }
            }

            return FlareReport(
                exceptionClass: exceptionName,
                message: message,
                code: applicationImage?.imageUUID,
                grouping: .fullStacktraceAndExceptionClassAndCode,
                handled: false,
                stacktrace: stacktrace,
                context: context,
                attributes: attributes,
                occurredAt: timestamp,
                id: stored.id
            )
        }

        static func applicationImagePath(imagePaths: [String], processPath: String?, processName: String?) -> String? {
            if let processPath, imagePaths.contains(processPath) { return processPath }
            let names = Set([processPath, processName].compactMap { $0 }.map { basename($0) })
            // SwiftPM executables may be launched through .build/debug symlinks. Only
            // use a basename match when it identifies a single image unambiguously.
            let matches = imagePaths.filter { names.contains(basename($0)) }
            return matches.count == 1 ? matches.first : nil
        }

        private static func imageContext(_ image: PLCrashReportBinaryImageInfo) -> FlareValue {
            .object([
                "name": .string(basename(image.imageName)),
                "uuid": image.imageUUID.map(FlareValue.string) ?? .null,
                "base_address": .string(hex(image.imageBaseAddress)),
                "size": .string(hex(image.imageSize)),
                "cpu_type": image.codeType.map { FlareValue.string(String($0.type)) } ?? .null,
                "cpu_subtype": image.codeType.map { FlareValue.string(String($0.subtype)) } ?? .null,
            ])
        }

        private static func threadContext(_ thread: PLCrashReportThreadInfo, crash: PLCrashReport) -> FlareValue {
            let frames = (thread.stackFrames as? [PLCrashReportStackFrameInfo]) ?? []
            return .object([
                "number": .integer(Int64(thread.threadNumber)),
                "crashed": .bool(thread.crashed),
                "frames": .array(frames.map { frameContext($0, crash: crash) }),
            ])
        }

        private static func frameContext(_ frame: PLCrashReportStackFrameInfo, crash: PLCrashReport) -> FlareValue {
            let image = crash.image(forAddress: frame.instructionPointer)
            let offset: FlareValue =
                image.map {
                    .string(hex(frame.instructionPointer &- $0.imageBaseAddress))
                } ?? .null
            return .object([
                "instruction_address": .string(hex(frame.instructionPointer)),
                "image": .string(basename(image?.imageName)),
                "image_uuid": image?.imageUUID.map(FlareValue.string) ?? .null,
                "image_offset": offset,
            ])
        }

        private static func basename(_ path: String?) -> String {
            guard let path, !path.isEmpty else { return "unknown" }
            return URL(fileURLWithPath: path).lastPathComponent
        }

        private static func hex(_ address: UInt64) -> String {
            "0x" + String(address, radix: 16)
        }
    }
#endif
