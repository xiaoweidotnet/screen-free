import AppKit
import Foundation

struct DesktopIconPreferenceSnapshot: Codable, Equatable, Sendable {
    var hadExplicitValue: Bool
    var iconsVisible: Bool
}

struct RecordingDesktopIconPresentation {
    private(set) var isPresenting = false
    private var previousPreference: DesktopIconPreferenceSnapshot?

    mutating func begin(
        currentPreference: DesktopIconPreferenceSnapshot,
        hideDesktopIcons: Bool
    ) -> Bool {
        guard !isPresenting else { return false }
        isPresenting = true
        guard hideDesktopIcons, currentPreference.iconsVisible else {
            previousPreference = nil
            return false
        }
        previousPreference = currentPreference
        return true
    }

    mutating func finish() -> DesktopIconPreferenceSnapshot? {
        guard isPresenting else { return nil }
        isPresenting = false
        defer { previousPreference = nil }
        return previousPreference
    }
}

enum DesktopIconPresentationError: LocalizedError {
    case cannotUpdateFinder

    var errorDescription: String? {
        "Desktop icons could not be hidden safely."
    }
}

@MainActor
final class FinderDesktopIconController {
    private static let finderBundleID = "com.apple.finder"
    private static let finderPreferenceKey = "CreateDesktop"
    private static let recoveryKey = "desktopIconRecoverySnapshot"

    private var presentation = RecordingDesktopIconPresentation()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recoverIfNeeded() {
        guard let data = defaults.data(forKey: Self.recoveryKey),
              let snapshot = try? JSONDecoder().decode(
                  DesktopIconPreferenceSnapshot.self,
                  from: data
              ) else {
            return
        }
        do {
            try apply(snapshot)
            defaults.removeObject(forKey: Self.recoveryKey)
        } catch {
            // Keep the recovery record. A later launch can retry after Finder
            // preferences become writable.
        }
    }

    func begin(hideDesktopIcons: Bool) throws {
        let current = currentPreference()
        guard presentation.begin(
            currentPreference: current,
            hideDesktopIcons: hideDesktopIcons
        ) else {
            return
        }
        let data = try JSONEncoder().encode(current)
        defaults.set(data, forKey: Self.recoveryKey)
        defaults.synchronize()
        do {
            try apply(
                DesktopIconPreferenceSnapshot(
                    hadExplicitValue: true,
                    iconsVisible: false
                )
            )
        } catch {
            _ = presentation.finish()
            defaults.removeObject(forKey: Self.recoveryKey)
            throw error
        }
    }

    func finish() {
        guard let previous = presentation.finish() else { return }
        do {
            try apply(previous)
            defaults.removeObject(forKey: Self.recoveryKey)
        } catch {
            // The persisted recovery record deliberately remains until a
            // future launch can restore the exact prior Finder preference.
        }
    }

    private func currentPreference() -> DesktopIconPreferenceSnapshot {
        let value = CFPreferencesCopyValue(
            Self.finderPreferenceKey as CFString,
            Self.finderBundleID as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        if let number = value as? NSNumber {
            return DesktopIconPreferenceSnapshot(
                hadExplicitValue: true,
                iconsVisible: number.boolValue
            )
        }
        return DesktopIconPreferenceSnapshot(
            hadExplicitValue: false,
            iconsVisible: true
        )
    }

    private func apply(
        _ snapshot: DesktopIconPreferenceSnapshot
    ) throws {
        let value: CFPropertyList? = snapshot.hadExplicitValue
            ? NSNumber(value: snapshot.iconsVisible)
            : nil
        CFPreferencesSetValue(
            Self.finderPreferenceKey as CFString,
            value,
            Self.finderBundleID as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        guard CFPreferencesSynchronize(
            Self.finderBundleID as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) else {
            throw DesktopIconPresentationError.cannotUpdateFinder
        }
        NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.finderBundleID
        ).forEach { _ = $0.terminate() }
    }
}
