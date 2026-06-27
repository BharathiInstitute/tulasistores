/// Global error handling utilities
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:retaillite/core/services/connectivity_service.dart';
import 'package:retaillite/core/services/error_logging_service.dart';
import 'package:retaillite/features/staff/services/auto_attendance_service.dart';

/// Check if Crashlytics is supported (not web and not Windows)
bool get _supportsCrashlytics => !kIsWeb && !Platform.isWindows;

/// Error types for categorization
enum AppErrorType {
  network,
  authentication,
  permission,
  validation,
  server,
  unknown,
}

/// Application error model
class AppError implements Exception {
  final String message;
  final String? details;
  final AppErrorType type;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const AppError({
    required this.message,
    this.details,
    this.type = AppErrorType.unknown,
    this.originalError,
    this.stackTrace,
  });

  /// Create from any exception
  factory AppError.from(dynamic error, [StackTrace? stackTrace]) {
    if (error is AppError) return error;

    String message = 'Something went wrong';
    AppErrorType type = AppErrorType.unknown;

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('connection')) {
      message = 'Network error. Please check your connection.';
      type = AppErrorType.network;
    } else if (errorString.contains('permission') ||
        errorString.contains('denied')) {
      message = 'Permission denied. Please grant required permissions.';
      type = AppErrorType.permission;
    } else if (errorString.contains('auth') ||
        errorString.contains('credential') ||
        errorString.contains('password')) {
      message = 'Authentication failed. Please try again.';
      type = AppErrorType.authentication;
    } else if (errorString.contains('invalid') ||
        errorString.contains('format')) {
      message = 'Invalid data. Please check your input.';
      type = AppErrorType.validation;
    }

    return AppError(
      message: message,
      details: error.toString(),
      type: type,
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() => message;
}

/// Global error handler with full context extraction
class ErrorHandler extends WidgetsBindingObserver {
  ErrorHandler._();

  static bool _initialized = false;
  static final ErrorHandler _instance = ErrorHandler._();
  static StreamSubscription<dynamic>? _connectivitySub;

  /// Current app lifecycle state
  static AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  static String get currentLifecycleState => _lifecycleState.name;

  /// Session ID (generated once per app launch)
  static late final String _sessionId;

  /// Initialize global error handling
  static void initialize() {
    if (_initialized) return;

    // Generate session ID
    _sessionId = _generateSessionId();
    ErrorLoggingService.setSessionId(_sessionId);

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(_instance);

    // Handle Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);

      // Extract rich context from FlutterErrorDetails
      final metadata = _extractFlutterErrorContext(details);

      if (_supportsCrashlytics) {
        // Mobile: Crashlytics + Firestore
        FirebaseCrashlytics.instance.recordFlutterError(details);
      }

      // ALL platforms: Log to Firestore with full context
      ErrorLoggingService.logError(
        error: details.exception,
        stackTrace: details.stack,
        severity: details.silent ? ErrorSeverity.warning : ErrorSeverity.error,
        metadata: metadata,
      );
    };

    // Handle async errors (platform dispatcher)
    PlatformDispatcher.instance.onError = (error, stack) {
      final metadata = _buildContextMetadata();
      metadata['errorType'] = _parseErrorType(error.toString());

      if (_supportsCrashlytics) {
        FirebaseCrashlytics.instance.recordError(error, stack);
      }

      // ALL platforms: Firestore
      ErrorLoggingService.logError(
        error: error,
        stackTrace: stack,
        metadata: metadata,
      );
      return true;
    };

    // Listen for connectivity changes to flush offline queue
    _connectivitySub = ConnectivityService.statusStream.listen((status) {
      if (status == ConnectivityStatus.online) {
        ErrorLoggingService.flushOfflineQueue();
      }
    });

    _initialized = true;
    debugPrint(
      '✅ ErrorHandler initialized (${kIsWeb
          ? "Web"
          : Platform.isWindows
          ? "Windows"
          : "Native"} mode, session: $_sessionId)',
    );
  }

  /// Dispose subscriptions (for cleanup / testing)
  static void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Extract rich context from FlutterErrorDetails
  static Map<String, dynamic> _extractFlutterErrorContext(
    FlutterErrorDetails details,
  ) {
    final metadata = _buildContextMetadata();

    // Widget context (e.g., "while building MyWidget")
    final context = details.context;
    if (context != null) {
      metadata['widgetContext'] = context.toString();
    }

    // Library (e.g., "rendering library", "widgets library")
    if (details.library != null) {
      metadata['library'] = details.library!;
    }

    // Error type parsed from exception
    metadata['errorType'] = _parseErrorType(details.exception.toString());

    // Widget tree info from informationCollector
    if (details.informationCollector != null) {
      try {
        final info = details.informationCollector!()
            .map((node) => node.toString())
            .join('\n');
        // Truncate to 2000 chars to avoid bloating Firestore
        metadata['widgetInfo'] = info.length > 2000
            ? '${info.substring(0, 2000)}\n... (truncated)'
            : info;
      } catch (_) {
        // informationCollector can throw
      }
    }

    return metadata;
  }

  /// Build common context metadata (shared by all error types)
  static Map<String, dynamic> _buildContextMetadata() {
    final metadata = <String, dynamic>{};

    // Screen size
    try {
      final views = WidgetsBinding.instance.renderViews;
      if (views.isNotEmpty) {
        final size = views.first.size;
        metadata['screenWidth'] = size.width;
        metadata['screenHeight'] = size.height;
      }
    } catch (e) {
      debugPrint('⚠️ Metadata: screen size read failed: $e');
    }

    // Connectivity
    metadata['connectivity'] = ConnectivityService.currentStatus.name;

    // Lifecycle
    metadata['lifecycleState'] = _lifecycleState.name;

    // Build mode
    metadata['buildMode'] = kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug';

    // Session
    metadata['sessionId'] = _sessionId;

    return metadata;
  }

  /// Parse error type from error message
  static String _parseErrorType(String error) {
    if (error.contains('RenderFlex overflowed')) return 'RenderFlex overflow';
    if (error.contains('RenderBox was not laid out')) return 'Layout error';
    if (error.contains('setState()')) return 'setState after dispose';
    if (error.contains('Null check')) return 'Null check error';
    if (error.contains('RangeError')) return 'Range error';
    if (error.contains('TypeError')) return 'Type error';
    if (error.contains('FormatException')) return 'Format exception';
    if (error.contains('SocketException')) return 'Network error';
    if (error.contains('TimeoutException')) return 'Timeout';
    if (error.contains('FirebaseException')) return 'Firebase error';
    if (error.contains('PlatformException')) return 'Platform error';
    if (error.contains('LateInitializationError')) return 'Late init error';
    if (error.contains('StateError')) return 'State error';
    if (error.contains('NoSuchMethodError')) return 'Method not found';
    // Fallback: first word up to colon or newline
    final match = RegExp(r'^(\w+(?:Error|Exception)?)').firstMatch(error);
    return match?.group(1) ?? 'Unknown';
  }

  /// Generate a simple session ID
  static String _generateSessionId() {
    final now = DateTime.now();
    final random = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '-$random';
  }

  /// Lifecycle observer
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;

    // Auto check-out attendance when app goes to background or closes
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      AutoAttendanceService.autoCheckOut();
    }

    // Mark clean exit when app is detached (closing)
    if (state == AppLifecycleState.detached) {
      ErrorLoggingService.markCleanExit();
    }
  }

  /// Report a caught error (use this for try-catch blocks)
  static void report(dynamic error, [StackTrace? stack]) {
    final metadata = _buildContextMetadata();
    metadata['errorType'] = _parseErrorType(error.toString());

    if (_supportsCrashlytics) {
      FirebaseCrashlytics.instance.recordError(error, stack);
    }

    ErrorLoggingService.logError(
      error: error,
      stackTrace: stack,
      metadata: metadata,
    );
  }

  /// Report a non-fatal error with custom message
  static void reportWithMessage(
    String message,
    dynamic error, [
    StackTrace? stack,
  ]) {
    if (kDebugMode) {
      debugPrint('⚠️ $message: $error');
    }

    final metadata = _buildContextMetadata();
    metadata['errorType'] = _parseErrorType(error.toString());

    ErrorLoggingService.logError(
      error: '$message: $error',
      stackTrace: stack,
      severity: ErrorSeverity.warning,
      metadata: metadata,
    );

    if (_supportsCrashlytics) {
      FirebaseCrashlytics.instance.log(message);
      FirebaseCrashlytics.instance.recordError(error, stack);
    }
  }

  /// Set user identifier for crash reports
  static Future<void> setUser(String? userId, {String? email}) async {
    if (_supportsCrashlytics && userId != null) {
      await FirebaseCrashlytics.instance.setUserIdentifier(userId);
      if (email != null) {
        await FirebaseCrashlytics.instance.setCustomKey('email', email);
      }
    }
  }

  /// Log a custom message/breadcrumb
  static void log(String message) {
    if (_supportsCrashlytics) {
      FirebaseCrashlytics.instance.log(message);
    }
    if (kDebugMode) {
      debugPrint('📝 $message');
    }
  }

  /// Show error to user via SnackBar
  static void showError(BuildContext context, dynamic error) {
    final appError = AppError.from(error);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(_getErrorIcon(appError.type), color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(appError.message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        // Only show error details in debug mode to prevent leaking internals
        action: kDebugMode && appError.details != null
            ? SnackBarAction(
                label: 'Details',
                textColor: Colors.white,
                onPressed: () => _showErrorDetails(context, appError),
              )
            : null,
      ),
    );
  }

  static IconData _getErrorIcon(AppErrorType type) {
    switch (type) {
      case AppErrorType.network:
        return Icons.wifi_off;
      case AppErrorType.authentication:
        return Icons.lock_outline;
      case AppErrorType.permission:
        return Icons.block;
      case AppErrorType.validation:
        return Icons.error_outline;
      case AppErrorType.server:
        return Icons.cloud_off;
      case AppErrorType.unknown:
        return Icons.warning_amber;
    }
  }

  static void _showErrorDetails(BuildContext context, AppError error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Type: ${error.type.name}'),
              const SizedBox(height: 8),
              Text('Message: ${error.message}'),
              if (error.details != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Details:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    error.details!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Error boundary widget — intercepts Flutter framework errors in the
/// subtree and shows a fallback UI instead of a red error screen.
///
/// Usage:
/// ```dart
/// ErrorBoundary(
///   child: MyScreen(),
///   errorBuilder: (details) => Text('Oops: ${details.exception}'),
/// )
/// ```
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(FlutterErrorDetails)? errorBuilder;

  const ErrorBoundary({super.key, required this.child, this.errorBuilder});

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  FlutterErrorDetails? _error;

  /// Previous FlutterError.onError handler (restored on dispose)
  FlutterExceptionHandler? _previousHandler;

  @override
  void initState() {
    super.initState();
    // Intercept Flutter errors so we can capture build errors
    // from this subtree. The original handler is still called so
    // Crashlytics + ErrorLoggingService logging continues.
    _previousHandler = FlutterError.onError;
    FlutterError.onError = _handleFlutterError;
  }

  @override
  void dispose() {
    // Restore original handler
    FlutterError.onError = _previousHandler;
    super.dispose();
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    // Forward to the original handler first (logging + Crashlytics)
    _previousHandler?.call(details);

    // Then show fallback UI
    if (mounted) {
      setState(() => _error = details);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(_error!) ?? _defaultErrorWidget();
    }

    return widget.child;
  }

  Widget _defaultErrorWidget() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error?.exceptionAsString() ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
