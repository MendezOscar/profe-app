import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterPluginRegistrant {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // El recordatorio también se muestra con la app abierta.
    UNUserNotificationCenter.current().delegate = self
    // Con escenas (obligatorias desde Xcode 27) la ventana la crea FlutterSceneDelegate:
    // los plugins se registran en el motor de esa pantalla, no aquí.
    pluginRegistrant = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func register(with registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
  }
}
