import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/queue_summary.dart';
import '../models/upload_status.dart';
import '../models/upload_task.dart';
import 'notification_options.dart';

/// Manages background and foreground notifications displaying real-time upload progress.
class UploadNotificationManager {
  final NotificationConfig config;
  final FlutterLocalNotificationsPlugin _notificationsPlugin;

  bool _isInitialized = false;
  DateTime _lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _wasUploading = false;
  int _lastCompletedCount = 0;
  int _lastFailedCount = 0;
  int _lastPausedCount = 0;
  int _lastCancelledCount = 0;
  int _lastActiveCount = 0;
  int _lastEnqueuedCount = 0;

  // Session / Batch tracking
  int _sessionStartCompletedCount = 0;
  bool _sessionActive = false;
  bool _isFirstSessionNotification = false;
  UploadTask? _lastCompletedTask;

  Timer? _throttleTimer;
  QueueSummary? _pendingSummary;
  UploadTask? _pendingTask;

  UploadNotificationManager({
    this.config = const NotificationConfig(),
    FlutterLocalNotificationsPlugin? notificationsPlugin,
  }) : _notificationsPlugin =
           notificationsPlugin ?? FlutterLocalNotificationsPlugin();

  /// Initializes the local notification plugin and channel settings.
  Future<void> init() async {
    if (!config.enabled || _isInitialized) return;

    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentAlert: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _notificationsPlugin.initialize(initSettings);

      // Create Android channel and request permission
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidImplementation != null) {
        final channel = AndroidNotificationChannel(
          config.channelId,
          config.channelName,
          description: config.channelDescription,
          importance: Importance.defaultImportance,
          showBadge: true,
          enableVibration: false,
          playSound: false,
        );
        await androidImplementation.createNotificationChannel(channel);
        await androidImplementation.requestNotificationsPermission();
      }

      // Request iOS / macOS permissions
      await requestPermissions();

      _isInitialized = true;
      debugPrint('[UploadNotificationManager] Initialized successfully.');
    } catch (e) {
      debugPrint('[UploadNotificationManager] init error: $e');
    }
  }

  /// Requests notification permissions from the OS.
  Future<bool> requestPermissions() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final android = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.requestNotificationsPermission() ?? false;
      } else if (!kIsWeb && Platform.isIOS) {
        final ios = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      } else if (!kIsWeb && Platform.isMacOS) {
        final macos = _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        return await macos?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (e) {
      debugPrint('[UploadNotificationManager] requestPermissions error: $e');
    }
    return true;
  }

  /// Displays an immediate test notification to verify OS notification permissions and UI display.
  Future<void> sendTestNotification() async {
    if (!_isInitialized) {
      await init();
    }

    const androidDetails = AndroidNotificationDetails(
      'upload_channel',
      'Upload Progress',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showProgress: true,
      maxProgress: 100,
      progress: 65,
      ongoing: false,
      autoCancel: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
      subtitle: '65% • 3.2 MB/s',
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      config.summaryNotificationId,
      'Upload Notification Test',
      '65% • 3.2 MB/s • 3.5 MB of 5.4 MB',
      notificationDetails,
    );
    debugPrint('[UploadNotificationManager] Test notification dispatched.');
  }

  /// Updates or posts the upload progress notification.
  /// Throttled automatically to adhere to [NotificationConfig.throttleInterval].
  void updateProgress({
    required QueueSummary summary,
    UploadTask? activeTask,
    bool forceImmediate = false,
  }) {
    if (!config.enabled || !_isInitialized) return;

    _pendingSummary = summary;
    _pendingTask = activeTask;

    final now = DateTime.now();
    final elapsed = now.difference(_lastUpdateTime);

    final hasActiveOrPending =
        summary.activeTasks > 0 || summary.enqueuedTasks > 0;

    // Start a new upload session when activity begins from idle
    if (hasActiveOrPending && !_sessionActive) {
      _sessionActive = true;
      _sessionStartCompletedCount = summary.completedTasks;
      _lastCompletedTask = null;
      _isFirstSessionNotification = true;
    }

    if (activeTask != null && activeTask.status == UploadStatus.completed) {
      _lastCompletedTask = activeTask;
    }

    final isNowUploading = summary.isUploading;
    final stateChanged =
        (isNowUploading != _wasUploading) ||
        (summary.completedTasks != _lastCompletedCount) ||
        (summary.failedTasks != _lastFailedCount) ||
        (summary.pausedTasks != _lastPausedCount) ||
        (summary.cancelledTasks != _lastCancelledCount) ||
        (summary.activeTasks != _lastActiveCount) ||
        (summary.enqueuedTasks != _lastEnqueuedCount);

    _wasUploading = isNowUploading;
    _lastCompletedCount = summary.completedTasks;
    _lastFailedCount = summary.failedTasks;
    _lastPausedCount = summary.pausedTasks;
    _lastCancelledCount = summary.cancelledTasks;
    _lastActiveCount = summary.activeTasks;
    _lastEnqueuedCount = summary.enqueuedTasks;

    if (forceImmediate || stateChanged || elapsed >= config.throttleInterval) {
      _throttleTimer?.cancel();
      _throttleTimer = null;
      _lastUpdateTime = now;
      _sendNotification(summary, activeTask);
    } else if (_throttleTimer == null) {
      final remaining = config.throttleInterval - elapsed;
      _throttleTimer = Timer(remaining, () {
        _throttleTimer = null;
        _lastUpdateTime = DateTime.now();
        if (_pendingSummary != null) {
          _sendNotification(_pendingSummary!, _pendingTask);
        }
      });
    }
  }

  Future<void> _sendNotification(QueueSummary summary, UploadTask? task) async {
    try {
      final isUploading = summary.isUploading;
      final isPaused = summary.hasPaused && !isUploading;
      final isFailed = summary.hasFailed && !isUploading && !summary.hasPaused;

      final completedInSession =
          summary.completedTasks - _sessionStartCompletedCount;
      final isCompleted = _sessionActive &&
          completedInSession > 0 &&
          !isUploading &&
          summary.enqueuedTasks == 0 &&
          !summary.hasPaused &&
          !summary.hasFailed;

      // If idle and nothing active, paused, failed, or newly completed in this session: dismiss notification
      if (!isUploading && !isPaused && !isFailed && !isCompleted) {
        _sessionActive = false;
        await cancelNotification();
        return;
      }

      final isStartAlert = _isFirstSessionNotification && config.alertOnStart;
      if (_isFirstSessionNotification) {
        _isFirstSessionNotification = false;
      }

      final shouldAlert = isStartAlert || isCompleted || isFailed;
      final shouldPlaySound = config.playSound && shouldAlert;

      final effectiveCompletedTask = _lastCompletedTask ?? task;

      String title;
      String body;

      if (isCompleted) {
        if (config.titleFormatter != null) {
          title = config.titleFormatter!(effectiveCompletedTask, summary);
        } else {
          title = completedInSession == 1
              ? 'Upload Complete'
              : 'Uploads Completed';
        }

        if (config.bodyFormatter != null) {
          body = config.bodyFormatter!(effectiveCompletedTask, summary);
        } else {
          body = (completedInSession == 1 && effectiveCompletedTask != null)
              ? '${effectiveCompletedTask.fileName} uploaded successfully.'
              : 'All $completedInSession files uploaded successfully.';
        }
      } else {
        title = config.titleFormatter?.call(task, summary) ??
            config.defaultTitle(task, summary);
        body = config.bodyFormatter?.call(task, summary) ??
            config.defaultBody(task, summary);
      }

      final progressPercent = summary.overallProgressPercent;

      final androidDetails = AndroidNotificationDetails(
        config.channelId,
        config.channelName,
        channelDescription: config.channelDescription,
        importance: shouldAlert
            ? Importance.high
            : Importance.defaultImportance,
        priority: shouldAlert
            ? Priority.high
            : Priority.defaultPriority,
        showProgress: isUploading,
        maxProgress: 100,
        progress: progressPercent,
        ongoing: isUploading,
        autoCancel: !isUploading,
        onlyAlertOnce: true,
        playSound: config.playSound,
        icon: config.smallIcon,
      );

      final darwinSubtitle = isUploading
          ? '$progressPercent% • ${summary.formattedSpeed}'
          : (isPaused
              ? 'Upload Paused'
              : (isFailed
                  ? 'Upload Failed'
                  : (completedInSession == 1
                      ? 'Upload Complete'
                      : '$completedInSession files uploaded')));

      // On iOS: notify actively with banner and sound on start, completion, or failure; update quietly while uploading
      final darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: shouldAlert,
        presentList: true,
        presentBadge: true,
        presentSound: shouldPlaySound,
        interruptionLevel: shouldAlert
            ? InterruptionLevel.active
            : InterruptionLevel.passive,
        subtitle: darwinSubtitle,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _notificationsPlugin.show(
        config.summaryNotificationId,
        title,
        body,
        notificationDetails,
      );

      // Session finished after posting completion
      if (isCompleted) {
        _sessionActive = false;
      }

      debugPrint(
        '[UploadNotificationManager] Notification sent: "$title" - "$body"',
      );
    } catch (e) {
      debugPrint(
        '[UploadNotificationManager] Error showing upload notification: $e',
      );
    }
  }

  /// Cancels and dismisses active upload notifications.
  Future<void> cancelNotification() async {
    if (!_isInitialized) return;
    try {
      await _notificationsPlugin.cancel(config.summaryNotificationId);
    } catch (_) {}
  }

  /// Disposes timers and resources.
  void dispose() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
  }
}
