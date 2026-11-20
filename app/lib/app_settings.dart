import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// What the window's close button does.
enum CloseAction { ask, tray, quit }

/// How a new account signs in: with the email and password form or through
/// the in-app browser on supported platforms.
enum SignInMethod { api, browser }

/// The app's own preferences (language, theme, close button), kept in
/// `app-settings.json` in the data folder beside the core's files. The VPN
/// settings belong to the core.
class AppSettings extends ChangeNotifier {
  AppSettings({this.file});

  final File? file;

  /// A language code (`en` or `fa`), or empty for the system language.
  String language = '';
  ThemeMode themeMode = ThemeMode.system;
  CloseAction closeAction = CloseAction.ask;

  /// True until the user finished the welcome page.
  bool firstRun = false;

  /// Android's first-run routing suggestion, prepared before the welcome
  /// page opens. Empty means no region; null keeps desktop suggestions.
  /// This is derived locally for this run and is not saved as a preference.
  String? firstRunRegion;

  /// Shows the public IP (the address websites see). Off by default: the
  /// location is shown by its country either way.
  bool showPublicIp = false;

  /// Android: the per-app mode switch on the home screen (all apps,
  /// selected apps, proxy). Off by default: most people never change it,
  /// and it takes the room the location and quota cards want.
  bool showAppModeSwitch = false;

  /// How a new account signs in (the accounts page's row).
  SignInMethod signInMethod = SignInMethod.api;

  /// When the user closed the "account running out" notice; it stays away
  /// for a day after.
  DateTime? lowQuotaDismissedAt;

  /// The newer version whose notice the user closed; a later one shows.
  String dismissedUpdate = '';

  /// The last successful look for a newer version, and the newer version it
  /// found ("" for none) with its page, so the notice outlasts a restart.
  DateTime? updateCheckedAt;
  String updateVersion = '';
  String updateUrl = '';
  Map<String, Object?> updateDetails = const {};
  List<Map<String, Object?>> announcementCache = const [];
  Map<String, int> announcementSeen = const {};
  Map<String, int> announcementAcknowledged = const {};
  Future<void> _saveTail = Future.value();

  /// Starts the app in the tray when the user signs in to Windows; on
  /// unless the user turned it off.
  bool autostart = true;

  /// Whether a start with the computer ([autostart]) opens the window, or
  /// waits in the tray as it always has.
  bool autostartShowsWindow = false;

  /// Connects by itself when started with the computer ([autostart]); off
  /// until the user turns it on. The core decides how (Daemon.AutoConnect).
  bool autoConnect = false;

  /// The home page's card when TUN mode refused a program's call or game
  /// (UDP); on unless the user turned it off.
  bool udpNotice = true;

  /// The columns the Logs page's Connections tab hides (ConnectionsView):
  /// at first all but the time, the destination, the rule, and the
  /// protocol. Kept in this file.
  Set<String> hiddenConnectionColumns = {'inbound', 'traffic', 'duration'};

  /// The only UI languages, in the order the language menu lists them.
  static const supportedLanguages = ['en', 'fa'];

  /// Languages written right to left.
  static const rtlLanguages = {'fa'};

  /// The locale of a language code such as 'fa' or 'zh_Hant'.
  static Locale localeOf(String language) {
    final parts = language.split('_');
    return parts.length == 2
        ? Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1])
        : Locale(language);
  }

  /// Uses Persian when the system locale is Persian; all other system
  /// languages fall back to English.
  static String languageFor(Locale locale) =>
      supportedLanguages.contains(locale.languageCode)
          ? locale.languageCode
          : 'en';

  /// Uses the first supported system language; otherwise English.
  static String languageForList(List<Locale>? locales) {
    for (final locale in locales ?? const <Locale>[]) {
      if (supportedLanguages.contains(locale.languageCode)) {
        return locale.languageCode;
      }
    }
    return 'en';
  }

  /// The core's routing regions (`routing.region`); empty is none.
  static const regions = ['ir', 'cn', 'ru', 'af', 'tr', 'id', 'br', ''];

  /// Prefer the current network country, then the SIM's country, then the
  /// system country. A known unsupported country means no regional bypass:
  /// an Iranian SIM roaming in another country must not imply Iran.
  static String regionForCountries(Iterable<String?> countries) {
    for (final value in countries) {
      final country = (value ?? '').trim().toLowerCase();
      if (!RegExp(r'^[a-z]{2}$').hasMatch(country)) continue;
      return regions.contains(country) ? country : '';
    }
    return '';
  }

  Locale? get locale => language.isEmpty ? null : localeOf(language);

  /// Persian suggests Iran; English has no language-based region.
  static String? regionForLanguage(String language) =>
      language == 'fa' ? 'ir' : null;

  /// The region to offer first: from [language], else from the system's
  /// country ([countryCode], such as IR), else none.
  static String suggestedRegion(String language, String? countryCode) {
    final byLanguage = regionForLanguage(language);
    if (byLanguage != null) return byLanguage;
    final country = (countryCode ?? '').toLowerCase();
    return regions.contains(country) ? country : '';
  }

  static Future<AppSettings> load(String dataDir) async {
    final s = AppSettings(
      file: File('$dataDir${Platform.pathSeparator}app-settings.json'),
    );
    try {
      final j = jsonDecode(await s.file!.readAsString());
      if (j is Map<String, Object?>) {
        if (j['language'] case final String l
            when supportedLanguages.contains(l)) {
          s.language = l;
        }
        s.themeMode =
            ThemeMode.values.asNameMap()[j['theme']] ?? ThemeMode.system;
        s.closeAction =
            CloseAction.values.asNameMap()[j['close']] ?? CloseAction.ask;
        s.firstRun = j['welcome_done'] != true;
        s.showPublicIp = j['show_public_ip'] == true;
        s.showAppModeSwitch = j['show_app_mode_switch'] == true;
        s.signInMethod =
            SignInMethod.values.asNameMap()[j['signin_method']] ??
            s.signInMethod;
        if (j['dismissed_update'] case final String v) s.dismissedUpdate = v;
        if (j['update_version'] case final String v) s.updateVersion = v;
        if (j['update_url'] case final String v) s.updateUrl = v;
        if (j['update_details'] case final Map<String, Object?> v) {
          s.updateDetails = v;
        }
        if (j['announcement_cache'] case final List<Object?> v) {
          s.announcementCache = v.whereType<Map<String, Object?>>().toList();
        }
        Map<String, int> history(Object? v) => v is Map<String, Object?>
            ? {
                for (final e in v.entries)
                  if (e.value is int) e.key: e.value! as int,
              }
            : {};
        s.announcementSeen = history(j['announcement_seen']);
        s.announcementAcknowledged = history(j['announcement_acknowledged']);
        s.updateCheckedAt = switch (j['update_checked_at']) {
          final String t => DateTime.tryParse(t),
          _ => null,
        };
        s.lowQuotaDismissedAt = switch (j['low_quota_dismissed_at']) {
          final String t => DateTime.tryParse(t),
          _ => null,
        };
        s.autostart = j['autostart'] != false;
        s.autostartShowsWindow = j['autostart_shows_window'] == true;
        s.autoConnect = j['auto_connect'] == true;
        s.udpNotice = j['udp_notice'] != false;
        if (j['hidden_connection_columns'] case final List<Object?> v) {
          s.hiddenConnectionColumns = {...v.whereType<String>()};
        }
      }
    } on FileSystemException {
      // First run: defaults, and the welcome page.
      s.firstRun = true;
    } on FormatException {
      // A broken file: defaults, rewritten on the next change.
    }
    return s;
  }

  void update({
    String? language,
    ThemeMode? themeMode,
    CloseAction? closeAction,
    SignInMethod? signInMethod,
    bool? firstRun,
    bool? showPublicIp,
    bool? showAppModeSwitch,
    DateTime? lowQuotaDismissedAt,
    String? dismissedUpdate,
    DateTime? updateCheckedAt,
    String? updateVersion,
    String? updateUrl,
    Map<String, Object?>? updateDetails,
    List<Map<String, Object?>>? announcementCache,
    Map<String, int>? announcementSeen,
    Map<String, int>? announcementAcknowledged,
    bool? autostart,
    bool? autostartShowsWindow,
    bool? autoConnect,
    bool? udpNotice,
    Set<String>? hiddenConnectionColumns,
  }) {
    this.hiddenConnectionColumns =
        hiddenConnectionColumns ?? this.hiddenConnectionColumns;
    this.udpNotice = udpNotice ?? this.udpNotice;
    this.autostart = autostart ?? this.autostart;
    this.autostartShowsWindow =
        autostartShowsWindow ?? this.autostartShowsWindow;
    this.autoConnect = autoConnect ?? this.autoConnect;
    this.showPublicIp = showPublicIp ?? this.showPublicIp;
    this.showAppModeSwitch = showAppModeSwitch ?? this.showAppModeSwitch;
    this.lowQuotaDismissedAt = lowQuotaDismissedAt ?? this.lowQuotaDismissedAt;
    this.dismissedUpdate = dismissedUpdate ?? this.dismissedUpdate;
    this.updateCheckedAt = updateCheckedAt ?? this.updateCheckedAt;
    this.updateVersion = updateVersion ?? this.updateVersion;
    this.updateUrl = updateUrl ?? this.updateUrl;
    this.updateDetails = updateDetails ?? this.updateDetails;
    this.announcementCache = announcementCache ?? this.announcementCache;
    this.announcementSeen = announcementSeen ?? this.announcementSeen;
    this.announcementAcknowledged =
        announcementAcknowledged ?? this.announcementAcknowledged;
    this.firstRun = firstRun ?? this.firstRun;
    this.language = language ?? this.language;
    this.themeMode = themeMode ?? this.themeMode;
    this.closeAction = closeAction ?? this.closeAction;
    this.signInMethod = signInMethod ?? this.signInMethod;
    notifyListeners();
    _saveTail = _saveTail.then((_) => _save());
  }

  Future<void> _save() async {
    final f = file;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'language': language,
          'theme': themeMode.name,
          'close': closeAction.name,
          'signin_method': signInMethod.name,
          'welcome_done': !firstRun,
          'show_public_ip': showPublicIp,
          'show_app_mode_switch': showAppModeSwitch,
          'low_quota_dismissed_at': lowQuotaDismissedAt?.toIso8601String(),
          'dismissed_update': dismissedUpdate,
          'update_checked_at': updateCheckedAt?.toIso8601String(),
          'update_version': updateVersion,
          'update_url': updateUrl,
          'update_details': updateDetails,
          'announcement_cache': announcementCache,
          'announcement_seen': announcementSeen,
          'announcement_acknowledged': announcementAcknowledged,
          'autostart': autostart,
          'autostart_shows_window': autostartShowsWindow,
          'auto_connect': autoConnect,
          'udp_notice': udpNotice,
          'hidden_connection_columns': hiddenConnectionColumns.toList(),
        }),
      );
    } on FileSystemException {
      // Not fatal: the choice holds until the app quits.
    }
  }
}
