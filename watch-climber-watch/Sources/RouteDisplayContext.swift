import Foundation

/// View-only projection. Never writes to the location monitor or recorded hike.
struct RouteDisplayContext {
    let liveFix: Fix?
    let liveMatch: RouteMatch?
    let position: RoutePosition
    let isInspecting: Bool

    var isOnCourse: Bool { liveMatch.map { $0.offsetM <= 100 } ?? false }
    var profileCurrentDistanceM: Double? { isOnCourse ? liveMatch?.distanceM : nil }

    init(route: PlannedRoute, fix: Fix?, now: Date, progressHintM: Double, inspection: RouteInspection) {
        if let fix, fix.usable,
           now.timeIntervalSince(fix.date) >= -5,
           now.timeIntervalSince(fix.date) < 30 {
            liveFix = fix
            liveMatch = route.nearest(to: fix.latitude, longitude: fix.longitude, progressHintM: progressHintM)
        } else {
            liveFix = nil
            liveMatch = nil
        }
        isInspecting = inspection.distanceM != nil
        let followed = liveMatch.flatMap { $0.offsetM <= 100 ? $0.distanceM : nil }
        position = route.position(at: inspection.distanceM ?? followed ?? 0)
    }
}
