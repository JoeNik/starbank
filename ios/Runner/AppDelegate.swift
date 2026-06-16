import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var aliyunOAuthChannel: FlutterMethodChannel?
  private var initialAliyunOAuthUri: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let url = launchOptions?[.url] as? URL {
      initialAliyunOAuthUri = extractAliyunOAuthUri(url)
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "star_bank/aliyun_oauth",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "getInitialUri" {
          result(self?.initialAliyunOAuthUri)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      aliyunOAuthChannel = channel
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard let uri = extractAliyunOAuthUri(url) else {
      return super.application(app, open: url, options: options)
    }
    initialAliyunOAuthUri = uri
    aliyunOAuthChannel?.invokeMethod("oauthRedirect", arguments: uri)
    return true
  }

  private func extractAliyunOAuthUri(_ url: URL) -> String? {
    guard url.scheme == "starbank" else { return nil }
    guard url.host == "aliyundrive" else { return nil }
    guard url.path.hasPrefix("/oauth") else { return nil }
    return url.absoluteString
  }
}
