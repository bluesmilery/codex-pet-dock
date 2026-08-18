import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Private on-disk locations shared by diagnostics, logs and token cache.
///
/// The helper intentionally exposes only the small set of operations needed by
/// the app.  Every directory is tightened to 0700 and every file is created or
/// replaced with 0600 permissions.  Append opens use O_NOFOLLOW so a symlink
/// planted at a log path cannot redirect writes elsewhere.
enum PrivateStorage {
    static let applicationName = "PetDock"
    static let logsDirectoryName = "Logs"
    static let diagnosticsDirectoryName = "Diagnostics"
    static let tokenCacheFileName = "token-cache.json"

    static var applicationSupportURL: URL {
        let fm = FileManager.default
        return (try? fm.url(for: .applicationSupportDirectory,
                            in: .userDomainMask,
                            appropriateFor: nil,
                            create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    static var rootURL: URL {
        applicationSupportURL.appendingPathComponent(applicationName, isDirectory: true)
    }

    static var logsURL: URL {
        rootURL.appendingPathComponent(logsDirectoryName, isDirectory: true)
    }

    static var diagnosticsURL: URL {
        rootURL.appendingPathComponent(diagnosticsDirectoryName, isDirectory: true)
    }

    static var tokenCacheURL: URL {
        rootURL.appendingPathComponent(tokenCacheFileName)
    }

    /// Ensure a directory exists and is private to the current user.
    @discardableResult
    static func ensurePrivateDirectory(_ url: URL) throws -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue, !isSymlink(url) else {
                throw StorageError.notPrivatePath
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: NSNumber(value: 0o700)])
        }
        try fm.setAttributes([.posixPermissions: NSNumber(value: 0o700)],
                             ofItemAtPath: url.path)
        return url
    }

    /// Create the standard app-private layout and return it.
    @discardableResult
    static func ensureLayout() throws -> URL {
        _ = try ensurePrivateDirectory(rootURL)
        _ = try ensurePrivateDirectory(logsURL)
        _ = try ensurePrivateDirectory(diagnosticsURL)
        return rootURL
    }

    /// Open a log-like file for append without following a symlink.
    static func openAppendFile(at url: URL) throws -> FileHandle {
        let parent = url.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory) {
            guard parentIsDirectory.boolValue, !isSymlink(parent) else {
                throw StorageError.notPrivatePath
            }
            // The app-owned Logs directory is tightened on every open.  A
            // caller-supplied fixture directory may be an OS temp directory
            // with ACLs that reject chmod; its file is still opened 0600 and
            // no external symlink is followed.
            if parent.path == logsURL.path || parent.path == diagnosticsURL.path || parent.path == rootURL.path {
                _ = try ensurePrivateDirectory(parent)
            }
        } else {
            _ = try ensurePrivateDirectory(parent)
        }
        if isSymlink(url) { throw StorageError.notPrivatePath }

        #if canImport(Darwin)
        let flags = O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW
        let fd = open(url.path, flags, mode_t(0o600))
        guard fd >= 0 else { throw StorageError.openFailed(errno) }
        do {
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)],
                                                   ofItemAtPath: url.path)
            return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        } catch {
            close(fd)
            throw error
        }
        #else
        // PetDock targets macOS; this fallback keeps the source portable for
        // static analysis on non-Darwin hosts and still rejects symlinks.
        FileManager.default.createFile(atPath: url.path, contents: nil,
                                       attributes: [.posixPermissions: NSNumber(value: 0o600)])
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
        #endif
    }

    /// Atomically replace a private file, never following a destination link.
    static func atomicWrite(_ data: Data, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        _ = try ensurePrivateDirectory(parent)
        let fm = FileManager.default
        let temp = parent.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        if isSymlink(temp) { throw StorageError.notPrivatePath }
        fm.createFile(atPath: temp.path, contents: nil,
                      attributes: [.posixPermissions: NSNumber(value: 0o600)])
        do {
            let handle = try FileHandle(forWritingTo: temp)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            try fm.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: temp.path)
            // replaceItem is atomic and replaces a symlink itself rather than
            // opening its target.  Remove an existing destination only as a
            // symlink-safe fallback for older Foundation implementations.
            if fm.fileExists(atPath: url.path), isSymlink(url) {
                try fm.removeItem(at: url)
            }
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: url)
            }
            try fm.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    static func isSymlink(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else { return false }
        return values.isSymbolicLink == true
    }

    enum StorageError: Error {
        case notPrivatePath
        case openFailed(Int32)
    }
}
