import CoreLocation
import EventKit
import Flutter
import UserNotifications

/// Location reminders + calendar reading.
///
/// Geofences use UNLocationNotificationTrigger: iOS itself watches the
/// region and shows the notification, even when Aria isn't running, with
/// only "When In Use" permission. userInfo carries flutter_local_notifications'
/// keys so taps and Done/Snooze route through the same Dart handler.
final class AriaPlaces: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private let events = EKEventStore()
  private var pendingAuth: [FlutterResult] = []
  private var pendingLocation: [FlutterResult] = []
  static let prefix = "aria.geo."

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  // MARK: permission

  private func status() -> String {
    switch manager.authorizationStatus {
    case .authorizedAlways: return "always"
    case .authorizedWhenInUse: return "whenInUse"
    case .denied: return "denied"
    case .restricted: return "restricted"
    default: return "notDetermined"
    }
  }

  func locationPermission(_ result: @escaping FlutterResult) { result(status()) }

  func requestLocationPermission(_ result: @escaping FlutterResult) {
    if manager.authorizationStatus != .notDetermined { result(status()); return }
    pendingAuth.append(result)
    manager.requestWhenInUseAuthorization()
  }

  func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
    guard m.authorizationStatus != .notDetermined else { return }
    let s = status()
    pendingAuth.forEach { $0(s) }
    pendingAuth.removeAll()
  }

  // MARK: current location

  func currentLocation(_ result: @escaping FlutterResult) {
    let st = manager.authorizationStatus
    guard st == .authorizedWhenInUse || st == .authorizedAlways else { result(nil); return }
    pendingLocation.append(result)
    manager.requestLocation()
  }

  func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let l = locations.last else { return }
    let v: [String: Any] = ["lat": l.coordinate.latitude, "lng": l.coordinate.longitude,
                            "accuracy": l.horizontalAccuracy]
    pendingLocation.forEach { $0(v) }
    pendingLocation.removeAll()
  }

  func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
    pendingLocation.forEach { $0(nil) }
    pendingLocation.removeAll()
  }

  // MARK: geofences

  /// Replaces every Aria geofence notification with [fences].
  func setGeofences(_ args: [String: Any], result: @escaping FlutterResult) {
    let fences = args["fences"] as? [[String: Any]] ?? []
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { pending in
      let old = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
      center.removePendingNotificationRequests(withIdentifiers: old)
      var added = 0
      let group = DispatchGroup()
      // iOS monitors at most 20 regions per app.
      for f in fences.prefix(20) {
        guard let id = f["id"] as? String, let lat = f["lat"] as? Double,
              let lng = f["lng"] as? Double else { continue }
        let radius = min(max(f["radius"] as? Double ?? 150, 100), 1000)
        let region = CLCircularRegion(
          center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
          radius: radius, identifier: Self.prefix + id)
        let arrive = (f["on"] as? String ?? "arrive") == "arrive"
        region.notifyOnEntry = arrive
        region.notifyOnExit = !arrive
        let content = UNMutableNotificationContent()
        content.title = f["title"] as? String ?? "Reminder"
        content.body = f["body"] as? String ?? ""
        content.sound = .default
        content.categoryIdentifier = f["category"] as? String ?? "reminder"
        content.threadIdentifier = id
        let nid = f["notificationId"] as? Int ?? abs(id.hashValue % 2_000_000_000)
        content.userInfo = [
          "NotificationId": nid, "payload": f["payload"] as? String ?? "",
          "presentAlert": true, "presentSound": true, "presentBadge": false,
          "presentBanner": true, "presentList": true,
        ]
        let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
        let req = UNNotificationRequest(identifier: Self.prefix + id, content: content, trigger: trigger)
        group.enter()
        center.add(req) { err in
          if err == nil { added += 1 }
          group.leave()
        }
      }
      group.notify(queue: .main) { result(added) }
    }
  }

  // MARK: calendar

  private static func calendarGranted() -> Bool {
    let st = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, *) { return st == .fullAccess }
    return st == .authorized
  }

  func calendarPermission(_ result: @escaping FlutterResult) {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .notDetermined: result("notDetermined")
    default: result(Self.calendarGranted() ? "granted" : "denied")
    }
  }

  func requestCalendarPermission(_ result: @escaping FlutterResult) {
    let done: (Bool, Error?) -> Void = { ok, _ in DispatchQueue.main.async { result(ok ? "granted" : "denied") } }
    if #available(iOS 17.0, *) {
      events.requestFullAccessToEvents(completion: done)
    } else {
      events.requestAccess(to: .event, completion: done)
    }
  }

  func calendarEvents(_ args: [String: Any], result: @escaping FlutterResult) {
    guard Self.calendarGranted() else { result([]); return }
    let from = Date(timeIntervalSince1970: (args["from"] as? Double ?? 0) / 1000)
    let to = Date(timeIntervalSince1970: (args["to"] as? Double ?? 0) / 1000)
    let pred = events.predicateForEvents(withStart: from, end: to, calendars: nil)
    let list = events.events(matching: pred).prefix(200).map { e -> [String: Any] in
      [
        "id": e.eventIdentifier ?? UUID().uuidString,
        "title": e.title ?? "",
        "start": e.startDate.timeIntervalSince1970 * 1000,
        "end": e.endDate.timeIntervalSince1970 * 1000,
        "allDay": e.isAllDay,
        "calendar": e.calendar?.title ?? "",
        "location": e.location ?? "",
      ]
    }
    result(Array(list))
  }
}
