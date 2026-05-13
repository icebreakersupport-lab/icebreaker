import Flutter
import UIKit
import UserNotifications

class SceneDelegate: FlutterSceneDelegate {

  // iOS treats the APNs `badge` field as an absolute set, not an increment.
  // Our `sendIcebreakerPush` Cloud Function pushes `badge: 1` on every send,
  // which leaves the dot stuck on the icon long after the user has opened
  // the app and viewed the icebreaker.  Clearing it on every scene-active
  // (cold launch + every foreground resume) matches what the user expects:
  // open the app, the badge goes away.
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    } else {
      UIApplication.shared.applicationIconBadgeNumber = 0
    }
  }
}
