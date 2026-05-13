import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
      _ = super.application(application, continue: userActivity, restorationHandler: restorationHandler)
      return true // 강제로 true를 반환하여 iOS가 자체적으로 사파리를 여는 Fallback 동작을 차단합니다.
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
}
