import Foundation
import Darwin

enum MediaControlProcess {
    static func run(_ arguments: [String]) -> Data? {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/media-control")
        return run(executable: URL(fileURLWithPath: "/usr/bin/perl"),
                   arguments: [helper.path] + arguments, timeout: 3)
    }

    /// Called only on the media worker queue; never waits in the event tap or UI run loop.
    static func run(executable: URL, arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              data.count <= 65_536 else { return nil }
        return data
    }
}
