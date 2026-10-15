import 'dart:ui';
import 'package:flutter/foundation.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'repository.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (!_supported || _isInitialized) return;

    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
      },
    );

    // Request permissions
    if (_supported) {
      final androidImplementation = _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.requestNotificationsPermission();
      await androidImplementation?.requestExactAlarmsPermission();
    }

    _isInitialized = true;
  }

  /// Cancels all existing notifications and schedules a new one based on the nearest due_at.
  Future<void> scheduleNextReviewReminder() async {
    if (!_supported) return;
    if (!_isInitialized) await init();

    await _flutterLocalNotificationsPlugin.cancelAll();

    final repo = const Repository();

    try {
      final dueConcepts = await repo.dueConcepts();
      if (dueConcepts.isEmpty) return;

      DateTime? earliestDue;
      for (final concept in dueConcepts) {
        if (concept.dueAt != null) {
          if (earliestDue == null || concept.dueAt!.isBefore(earliestDue)) {
            earliestDue = concept.dueAt;
          }
        }
      }

      if (earliestDue == null) return;

      final now = DateTime.now();
      var scheduledTime = earliestDue;

      if (scheduledTime.isBefore(now)) {
        return;
      }

      final scheduledDate = tz.TZDateTime.from(scheduledTime, tz.local);

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id: 0,
        title: 'Time to Review!',
        body: 'You have concepts due for review. Keep your streak alive!',
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'spaced_repetition_channel',
            'Review Reminders',
            channelDescription: 'Notifications for spaced repetition reviews',
            importance: Importance.high,
            priority: Priority.high,
            color: Color(0xFF0F5B45), // ViaX instrument green
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      // Ignored if unauthenticated or failure
    }
  }

  Future<void> testNotification() async {
    if (!_supported) return;
    if (!_isInitialized) await init();

    await _flutterLocalNotificationsPlugin.show(
      id: 1,
      title: 'Test Reminder ⚡',
      body: 'If you see this, push notifications are successfully wired up!',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'test_channel',
          'Test Notifications',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFF0F5B45),
        ),
      ),
    );
  }
}
