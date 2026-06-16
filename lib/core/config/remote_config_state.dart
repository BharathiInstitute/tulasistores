/// Global Remote Config state ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â set once in main.dart, read anywhere
///
/// This avoids passing Remote Config values through constructors.
/// Values are set during app initialization and read by widgets.
library;

class RemoteConfigState {
  RemoteConfigState._();

  /// App version ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â set from main.dart at startup
  static String appVersion = '10.0.4';

  /// Announcement message from admin (empty = no announcement)
  static String announcement = '';

  /// Latest available version (for soft update nudge)
  static String latestVersion = '';

  /// Whether a newer version is available
  static bool get hasNewerVersion {
    if (latestVersion.isEmpty) return false;
    return _isVersionLower(RemoteConfigState.appVersion, latestVersion);
  }

  /// Compare two semver strings. Returns true if [current] < [minimum].
  static bool _isVersionLower(String current, String minimum) {
    if (minimum.isEmpty) return false;
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final minimumParts = minimum.split('.').map(int.parse).toList();
      for (var i = 0; i < 3; i++) {
        final c = i < currentParts.length ? currentParts[i] : 0;
        final m = i < minimumParts.length ? minimumParts[i] : 0;
        if (c < m) return true;
        if (c > m) return false;
      }
      return false; // equal
    } catch (_) {
      return false;
    }
  }
}
