/// Central configuration for the Direct client app.
class AppConfig {
  /// Default server URL used by the app.
  /// Users will automatically connect to this URL without needing to enter anything manually.
  ///
  /// For local development over Wi-Fi, you can use: 'http://192.168.0.160:8080'
  /// For production (e.g. Render / Railway / Cloud VPS), set this to your cloud URL:
  /// e.g. 'https://direct-relay.onrender.com'
  static const String defaultServerUrl = 'http://192.168.0.160:8080';

  /// Set to true to show the server settings gear icon on the Login screen (for developers/testing).
  /// Set to false for a clean production release so end-users never see server settings.
  static const bool enableServerConfigUI = true;
}
