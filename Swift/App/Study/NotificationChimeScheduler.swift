import Foundation
import Observation
import StudyCore
import UIKit
import UserNotifications

/// Study⇄rest chimes as local notifications with sound, delivered even when
/// the app is closed. iOS keeps at most 64 pending requests per app; the plan
/// is bounded (7 days, ≤ 60).
///
/// Request ids are derived from each chime's content (same formula as the
/// Flutter app), so a re-plan only touches what differs: after some chimes
/// fired only the new tail is added, and requests iOS dropped (notifications
/// were off) are simply added again.
///
/// Permission is asked the first time there is something to chime (HIG: ask
/// in context, not at launch).
@MainActor
@Observable
final class NotificationChimeScheduler: ChimeScheduler {
    enum Permission { case unknown, notDetermined, allowed, denied }

    /// Observed by the screens that explain why no chime will sound.
    private(set) var permission: Permission = .unknown

    // Completion handlers below are @Sendable: UserNotifications calls them on
    // its own queue, and a main-actor closure there would trap in Swift 6.
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private let presenter = ForegroundPresenter()
    /// Latest plan not yet applied; earlier unapplied plans are dropped.
    @ObservationIgnored private var pendingPlan: [Chime]?
    @ObservationIgnored private var draining = false

    static let categoryId = "chime"

    init() {
        // Sound and banner while the app is in front, too.
        center.delegate = presenter
        // With previews hidden (lock screen), show a neutral line instead of
        // the block name.
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryId, actions: [], intentIdentifiers: [],
                                   hiddenPreviewsBodyPlaceholder: "勉強と休憩の切り替え",
                                   options: []),
        ])
        refreshAuthorization()
    }

    /// Re-reads the permission (the user may have changed it in Settings).
    func refreshAuthorization() {
        Task { permission = await currentPermission() }
    }

    /// Opens this app's notification settings.
    func openSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func replaceAll(_ chimes: [Chime]) {
        pendingPlan = chimes
        guard !draining else { return }
        draining = true
        Task {
            // Applies only the newest plan, one at a time.
            while let plan = pendingPlan {
                pendingPlan = nil
                if !plan.isEmpty { await askIfNeeded() }
                await sync(plan)
            }
            draining = false
        }
    }

    private func askIfNeeded() async {
        guard await currentPermission() == .notDetermined else { return }
        let center = center
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            center.requestAuthorization(options: [.alert, .sound]) { @Sendable granted, error in
                if let error { print("notification permission failed: \(error)") }
                cont.resume(returning: granted)
            }
        }
        permission = await currentPermission()
    }

    private func currentPermission() async -> Permission {
        let center = center
        let status = await withCheckedContinuation { (cont: CheckedContinuation<UNAuthorizationStatus, Never>) in
            center.getNotificationSettings { @Sendable settings in
                cont.resume(returning: settings.authorizationStatus)
            }
        }
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    private func sync(_ chimes: [Chime]) async {
        let now = Date()
        var wanted: [(id: Int, item: (Chime, Date))] = []
        for c in chimes {
            guard let at = c.at.date(), at > now else { continue }
            let ms = Int64((at.timeIntervalSince1970 * 1000).rounded())
            wanted.append((chimeId(c, epochMillis: ms), (c, at)))
        }
        let identifiers = await pendingIdentifiers()
        // Anything that is not one of our numeric ids is stale too.
        let foreign = identifiers.filter { Int($0) == nil }
        let diff = diffChimes(pendingIds: Set(identifiers.compactMap { Int($0) }), wanted: wanted)
        let cancel = foreign + diff.cancel.map(String.init)
        let center = center
        if !cancel.isEmpty { center.removePendingNotificationRequests(withIdentifiers: cancel) }
        for (id, (chime, at)) in diff.add {
            let content = UNMutableNotificationContent()
            content.title = chime.title
            content.body = chime.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryId
            content.threadIdentifier = Self.categoryId
            let interval = at.timeIntervalSinceNow
            guard interval > 0 else { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: String(id), content: content, trigger: trigger)
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                center.add(request) { @Sendable error in
                    if let error { print("chime schedule failed: \(error)") }
                    cont.resume()
                }
            }
        }
    }

    private func pendingIdentifiers() async -> [String] {
        let center = center
        return await withCheckedContinuation { cont in
            center.getPendingNotificationRequests { @Sendable requests in
                cont.resume(returning: requests.map(\.identifier))
            }
        }
    }
}

/// Shows chimes as banner + sound while the app is in the foreground.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
