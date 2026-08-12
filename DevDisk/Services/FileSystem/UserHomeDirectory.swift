import Darwin
import Foundation

enum UserHomeDirectory {
    /// App Sandbox redirects Foundation's home directory into the app container.
    /// Tool caches live under the account's real POSIX home, which remains
    /// available through the user database after the user grants disk access.
    static let current: URL = {
        guard let record = getpwuid(getuid()),
              let directory = record.pointee.pw_dir
        else { return FileManager.default.homeDirectoryForCurrentUser }
        return URL(filePath: String(cString: directory), directoryHint: .isDirectory)
            .standardizedFileURL
    }()
}
