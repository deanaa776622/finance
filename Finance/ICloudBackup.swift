import BackgroundTasks
import Foundation

/// One copy of the asset records in iCloud Drive. A daily slot, plus a manual copy.
enum ICloudBackup {
    static let enabledKey = "icloudBackupOn"
    static let minutesKey = "icloudBackupMinutes"
    static let defaultMinutes = 22 * 60
    private static let taskID = "com.deanaa776622.finance.backup"
    private static let lastKey = "icloudBackupLast"
    private static let dailyKey = "icloudBackupDay"

    enum Failure: Error {
        case noAccount, empty, busy, failed
    }

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let result = copy(scheduled: true)
            scheduleNext()
            if case .success = result {
                refresh.setTaskCompleted(success: true)
            } else {
                refresh.setTaskCompleted(success: false)
            }
        }
    }

    static func refreshSchedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        scheduleNext()
        backupIfDue()
    }

    /// Runs the daily copy once the clock has passed today's time and today's copy is still missing.
    static func backupIfDue() {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard nowMinutes >= storedMinutes else { return }
        guard UserDefaults.standard.string(forKey: dailyKey) != dayKey(Date()) else { return }
        Task.detached { _ = copy(scheduled: true) }
    }

    static func backupNow() async -> Result<Date, Failure> {
        await Task.detached(priority: .utility) { copy(scheduled: false) }.value
    }

    static var lastBackup: Date? {
        let raw = UserDefaults.standard.double(forKey: lastKey)
        return raw == 0 ? nil : Date(timeIntervalSince1970: raw)
    }

    private static var storedMinutes: Int {
        UserDefaults.standard.object(forKey: minutesKey) as? Int ?? defaultMinutes
    }

    private static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = nextSlot()
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func nextSlot() -> Date {
        let cal = Calendar.current
        let now = Date()
        var parts = cal.dateComponents([.year, .month, .day], from: now)
        parts.hour = storedMinutes / 60
        parts.minute = storedMinutes % 60
        parts.second = 5
        let today = cal.date(from: parts) ?? now
        let done = UserDefaults.standard.string(forKey: dailyKey) == dayKey(now)
        if !done, today <= now { return now.addingTimeInterval(15) }
        if today > now { return today }
        return cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private static func copy(scheduled: Bool) -> Result<Date, Failure> {
        guard BackupGate.enter() else { return .failure(.busy) }
        defer { BackupGate.leave() }
        let source = Portfolio.recordsFile
        guard FileManager.default.fileExists(atPath: source.path) else { return .failure(.empty) }
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return .failure(.noAccount)
        }
        let folder = root.appendingPathComponent("Documents", isDirectory: true)
        let dest = folder.appendingPathComponent("portfolio.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try Data(contentsOf: source)
            try write(data, to: dest)
        } catch {
            return .failure(.failed)
        }
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastKey)
        if scheduled { UserDefaults.standard.set(dayKey(now), forKey: dailyKey) }
        return .success(now)
    }

    private static func write(_ data: Data, to dest: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordination: NSError?
        var writing: Error?
        coordinator.coordinate(writingItemAt: dest, options: .forReplacing, error: &coordination) { url in
            do { try data.write(to: url, options: .atomic) } catch { writing = error }
        }
        if let coordination { throw coordination }
        if let writing { throw writing }
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

private enum BackupGate {
    static let lock = NSLock()
    static var running = false

    static func enter() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if running { return false }
        running = true
        return true
    }

    static func leave() {
        lock.lock()
        running = false
        lock.unlock()
    }
}
