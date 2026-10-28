import Foundation
import Darwin

// Isolated test entry point: validate, extract or install synthetic fixtures.
// It never terminates a process, launches an app or reads user preferences.
do {
    let args = CommandLine.arguments
    guard args.count >= 5 else { throw AppUpdateInstallError.rejected("Missing harness arguments.") }
    let operation = args[1]
    let candidate = URL(fileURLWithPath: args[2])
    let active = URL(fileURLWithPath: args[3])
    let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(contentsOf: URL(fileURLWithPath: args[4])))
    var result = ["operation": operation, "accepted": "true"]
    switch operation {
    case "validate":
        try AppUpdateInstaller.validate(candidate: candidate, activeApp: active, manifest: manifest)
    case "prepare":
        guard args.count == 6 else { throw AppUpdateInstallError.rejected("Missing extraction directory.") }
        let prepared = try AppUpdateInstaller.prepare(archive: candidate, manifest: manifest, activeApp: active,
                                                      workDirectory: URL(fileURLWithPath: args[5]))
        result["candidate"] = prepared.path
    case "install", "fail-before-commit":
        guard args.count == 6 else { throw AppUpdateInstallError.rejected("Missing installation directory.") }
        let job = AppUpdateJob(candidate: candidate, activeApp: active, manifest: manifest,
                               workDirectory: URL(fileURLWithPath: args[5]), parentPID: getpid(),
                               oldExecutableSHA256: try AppUpdateInstaller.sha256(AppUpdateInstaller.executable(active)))
        let beforeCommit: (() throws -> Void)? = operation == "fail-before-commit" ? {
            throw AppUpdateInstallError.rejected("Synthetic precommit failure.")
        } : nil
        let backup = try AppUpdateInstaller.install(job, beforeCommit: beforeCommit)
        result["backup"] = backup.path
    default:
        throw AppUpdateInstallError.rejected("Unknown harness operation.")
    }
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
