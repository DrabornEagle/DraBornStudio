import AppKit
import Foundation
import Darwin

func reopen(_ app: URL, workDirectory: URL) {
    let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
    let complete = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
        if let error { try? Data(error.localizedDescription.utf8).write(to: workDirectory.appendingPathComponent("reopen-error.txt")) }
        complete.signal()
    }
    let timeout = Date().addingTimeInterval(15)
    while complete.wait(timeout: .now()) == .timedOut && Date() < timeout { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
}

var requestedJob: AppUpdateJob?
do {
    guard CommandLine.arguments.count == 2 else { throw AppUpdateInstallError.rejected("An update job is required.") }
    let file = URL(fileURLWithPath: CommandLine.arguments[1])
    try AppUpdateInstaller.privateDirectory(file.deletingLastPathComponent())
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    try AppUpdateInstaller.require((attributes[.size] as? NSNumber)?.intValue ?? Int.max < 65_536, "The update job is invalid.")
    let job = try JSONDecoder().decode(AppUpdateJob.self, from: Data(contentsOf: file))
    requestedJob = job
    try AppUpdateInstaller.require(job.workDirectory.standardizedFileURL == file.deletingLastPathComponent().standardizedFileURL && job.parentPID > 1,
                                   "The update job has an invalid parent.")
    // A cancelled quit (for example an unsaved edit) leaves the app untouched.
    let deadline = Date().addingTimeInterval(45)
    while kill(job.parentPID, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
    try AppUpdateInstaller.require(kill(job.parentPID, 0) != 0, "The app did not finish quitting. Try the update again.")
    _ = try AppUpdateInstaller.install(job)
    reopen(job.activeApp, workDirectory: job.workDirectory)
} catch {
    if CommandLine.arguments.count == 2 {
        let file = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("install-error.txt")
        try? Data(error.localizedDescription.utf8).write(to: file, options: .atomic)
    }
    if let job = requestedJob, kill(job.parentPID, 0) != 0,
       (try? AppUpdateInstaller.verifyOriginal(job)) != nil {
        // Reopen only the exact, fully verified previous executable after a
        // successful rollback. Never launch a corrupt or unrelated bundle.
        reopen(job.activeApp, workDirectory: job.workDirectory)
    }
    fputs("Update installation did not complete.\n", stderr)
    exit(1)
}
