/// Template configuration for the Direct client app.
/// Copy this file to `config.dart` and specify your deployment server URL.
class AppConfig {
  /// Default server URL used by the app.
  static const String defaultServerUrl = 'https://YOUR_BACKEND_URL.onrender.com';

  /// Set to true to show the server settings gear icon on the Login screen (for developers/testing).
  /// Set to false for a clean production release so end-users never see server settings.
  static const bool enableServerConfigUI = true;
}
