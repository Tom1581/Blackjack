import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'hilo_game.dart';
import 'hilo_text.dart';
import 'hilo_training_progress.dart';

/// What the reminder needs from the platform. Faked in tests.
abstract class ReminderScheduler {
  /// Set the plugin up; [onTap] runs when the player taps a reminder.
  Future<void> init(VoidCallback onTap);

  /// Ask to post notifications (Android 13+, iOS). True if allowed.
  Future<bool> requestPermission();

  /// Replace any pending reminder with one at [when].
  Future<void> scheduleAt(DateTime when, String title, String body);
  Future<void> cancel();

  /// The app was just launched by tapping a reminder.
  Future<bool> launchedFromReminder();
}

/// The opt-in Daily Challenge reminder.
///
/// Gentle by design, like the lobby's daily streak: one notification is ever
/// pending, for the next time the day's shoe is unplayed at the chosen hour.
/// It is rescheduled whenever the player opens Hi-Lo Training or finishes a
/// Daily, so someone who keeps playing gets a nudge a day — and someone who
/// stops gets one, not a drumbeat.
class DailyReminder {
  const DailyReminder._();

  static const hours = [9, 12, 18, 20];
  static const defaultHour = 18;

  static const _enabledKey = 'hilo_reminder_on';
  static const _hourKey = 'hilo_reminder_hour';

  static ReminderScheduler scheduler = LocalReminderScheduler();
  static DateTime Function() now = DateTime.now;

  /// Opens Hi-Lo Training; set by the app so a tapped reminder lands there.
  static VoidCallback? onOpen;

  static bool _initialised = false;

  static String hourLabel(int hour) => switch (hour) {
        0 => '12 AM',
        12 => 'Noon',
        < 12 => '$hour AM',
        _ => '${hour - 12} PM',
      };

  static Future<({bool on, int hour})> load() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_hourKey);
    return (
      on: prefs.getBool(_enabledKey) ?? false,
      hour: hour != null && hours.contains(hour) ? hour : defaultHour,
    );
  }

  /// App start: when reminders are on, set the plugin up so a tap is routed,
  /// open Hi-Lo Training if a reminder launched the app, and reschedule.
  static Future<void> start() async {
    try {
      final settings = await load();
      if (!settings.on) return;
      await _init();
      if (await scheduler.launchedFromReminder()) onOpen?.call();
      await refresh();
    } catch (error) {
      debugPrint('Daily reminder unavailable: $error');
    }
  }

  /// Switch reminders on at [hour]. False if the player refused permission,
  /// in which case they stay off.
  static Future<bool> enable(int hour) async {
    await _init();
    final allowed = await scheduler.requestPermission();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, allowed);
    await prefs.setInt(_hourKey, hour);
    if (allowed) await refresh();
    return allowed;
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    try {
      await scheduler.cancel();
    } catch (error) {
      debugPrint('Daily reminder: could not cancel ($error)');
    }
  }

  static Future<void> setHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey, hour);
    await refresh();
  }

  /// Schedule the next reminder, if reminders are on. Never throws.
  static Future<void> refresh() async {
    try {
      final settings = await load();
      if (!settings.on) return;
      await _init();
      final profile = await HiLoTrainingProgress.loadProfile();
      final at = now();
      final when = nextAt(
        at,
        settings.hour,
        playedToday: profile.playedDaily(HiLoDaily.numberFor(at)),
      );
      final day = HiLoDaily.numberFor(when);
      await scheduler.scheduleAt(when, title(day), body(day));
    } catch (error) {
      debugPrint('Daily reminder: could not schedule ($error)');
    }
  }

  /// [hour] o'clock today while that is still ahead and today's shoe is
  /// unplayed; otherwise [hour] o'clock tomorrow.
  static DateTime nextAt(DateTime now, int hour, {required bool playedToday}) {
    final today = DateTime(now.year, now.month, now.day, hour);
    if (!playedToday && now.isBefore(today)) return today;
    return DateTime(now.year, now.month, now.day + 1, hour);
  }

  static String title(int day) => 'Daily Challenge #$day is ready';

  static String body(int day) =>
      '${tableLabel(HiLoDaily.configFor(day))}. One ranked try — the same '
      'shoe as everyone.';

  static Future<void> _init() async {
    if (_initialised) return;
    await scheduler.init(() => onOpen?.call());
    _initialised = true;
  }

  @visibleForTesting
  static void resetForTest(ReminderScheduler fake) {
    scheduler = fake;
    now = DateTime.now;
    onOpen = null;
    _initialised = false;
  }
}

/// [ReminderScheduler] on flutter_local_notifications.
class LocalReminderScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _id = 4101;
  static const _payload = 'hilo_daily';

  /// A white spade (android/app/src/main/res/drawable/ic_stat_hilo.xml):
  /// Android draws a notification's small icon from its alpha alone.
  static const _icon = 'ic_stat_hilo';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'hilo_daily',
      'Daily Challenge',
      channelDescription: 'A nudge when the day\'s Hi-Lo shoe is unplayed',
      icon: _icon,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> init(VoidCallback onTap) async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == _payload) onTap();
      },
    );
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  @override
  Future<void> scheduleAt(DateTime when, String title, String body) {
    // An absolute instant in UTC: no time-zone database to load, and the
    // local hour was already worked out by DailyReminder.
    return _plugin.zonedSchedule(
      _id,
      title,
      body,
      tz.TZDateTime.from(when.toUtc(), tz.UTC),
      _details,
      // Inexact: a few minutes either way is fine for a nudge, and it needs
      // no exact-alarm permission.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: _payload,
    );
  }

  @override
  Future<void> cancel() => _plugin.cancel(_id);

  @override
  Future<bool> launchedFromReminder() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp == true &&
        details?.notificationResponse?.payload == _payload;
  }
}
