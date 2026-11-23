import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_mode.dart';
import 'core/app_settings.dart';
import 'core/layout_breakpoints.dart';
import 'core/log_filter.dart';
import 'providers/app_mode_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/supervisor_provider.dart';
import 'providers/ui_preferences_provider.dart';
import 'ros/ros_bridge_client.dart';
import 'widgets/confirm_logout.dart';
import 'widgets/delivery_notice_dialog.dart';
import 'widgets/drive_stop_button.dart';
import 'widgets/duplicate_run_banner.dart';
import 'widgets/goal_alert_dialog.dart';
import 'widgets/help_alert_dialog.dart';
import 'widgets/patrol_alarm_dialog.dart';
import 'widgets/patrol_ui.dart';
import 'widgets/ros_connection_tile.dart';
import 'widgets/route_dialogs.dart';
import 'widgets/voice_alert_snack.dart';
import 'widgets/vica_ui.dart';
import 'screens/current_location_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/delivery_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/login_screen.dart';
import 'screens/map_locations_screen.dart';
import 'screens/mapping_shell.dart';
import 'screens/mode_select_screen.dart';
import 'screens/patrol_screen.dart';
import 'screens/save_location_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/system_diagnostics_screen.dart';

/// 앱 전체가 쓰는 글꼴. pubspec.yaml의 `fonts: family:`와 반드시 같아야 한다.
const String kVicaFontFamily = 'NanumGothic';

/// 앱 전체 테마. 시험도 이것을 써야 실제 화면과 같은 규칙으로 그려집니다.
ThemeData vicaTheme() {
  return ThemeData(
    fontFamily: kVicaFontFamily,
    scaffoldBackgroundColor: VicaColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: VicaColors.primary,
      surface: VicaColors.background,
    ),
    useMaterial3: true,
    splashFactory: NoSplash.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: VicaSlidePageTransitionsBuilder(),
        TargetPlatform.iOS: VicaSlidePageTransitionsBuilder(),
        TargetPlatform.linux: VicaSlidePageTransitionsBuilder(),
        TargetPlatform.macOS: VicaSlidePageTransitionsBuilder(),
        TargetPlatform.windows: VicaSlidePageTransitionsBuilder(),
        TargetPlatform.fuchsia: VicaSlidePageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: VicaColors.card,
      foregroundColor: VicaColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kVicaFontFamily,
        color: VicaColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        color: VicaColors.text,
        fontSize: 26,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        color: VicaColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
      titleSmall: TextStyle(
        color: VicaColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      bodyMedium: TextStyle(
        color: VicaColors.muted,
        fontSize: 16,
        height: 1.4,
        letterSpacing: 0,
      ),
      bodySmall: TextStyle(
        color: VicaColors.muted,
        fontSize: 13,
        height: 1.3,
        letterSpacing: 0,
      ),
      labelSmall: TextStyle(
        color: VicaColors.textTertiary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: VicaColors.surfaceSunken,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(kVicaFieldRadius)),
        borderSide: BorderSide(color: VicaColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(kVicaFieldRadius)),
        borderSide: BorderSide(color: VicaColors.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VicaColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(46),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VicaColors.text,
        backgroundColor: VicaColors.card,
        side: const BorderSide(color: VicaColors.borderStrong),
        minimumSize: const Size.fromHeight(46),
        shape: const StadiumBorder(),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VicaColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: VicaColors.accentTint,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kVicaFieldRadius),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: kVicaFontFamily,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? VicaColors.primaryDark
              : VicaColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? VicaColors.primaryDark
              : VicaColors.muted,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: VicaColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kVicaCardRadius),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: kVicaFontFamily,
        color: VicaColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: kVicaFontFamily,
        color: VicaColors.muted,
        fontSize: 14,
        height: 1.5,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: VicaColors.text,
      contentTextStyle: const TextStyle(
        fontFamily: kVicaFontFamily,
        color: Colors.white,
        fontSize: 14,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kVicaFieldRadius),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: VicaColors.border,
      thickness: 1,
      space: 1,
    ),
  );
}

class VicaSupervisorApp extends StatelessWidget {
  const VicaSupervisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VICA_SUPERVISOR',
      debugShowCheckedModeBanner: false,
      theme: vicaTheme(),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.watch<AuthProvider>().isLoggedIn;
    final modeProvider = context.watch<AppModeProvider>();

    if (!isLoggedIn) {
      if (modeProvider.isSelected) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          modeProvider.clear();
        });
      }
      return const LoginScreen();
    }

    return switch (modeProvider.mode) {
      null => const ModeSelectScreen(),
      AppMode.drive => const SupervisorShell(),
      AppMode.mapping => const MappingShell(),
    };
  }
}

class SupervisorShell extends StatefulWidget {
  const SupervisorShell({super.key});

  @override
  State<SupervisorShell> createState() => _SupervisorShellState();
}

class _SupervisorShellState extends State<SupervisorShell> {
  int _index = 0;

  /// 마지막으로 띄운 음성 연결 알림 번호(SupervisorProvider.voiceAlertSeq).
  int _voiceAlertSeqShown = 0;

  @override
  void initState() {
    super.initState();
    final tab = context.read<AppModeProvider>().takeLandingTab();
    final index = tab == null ? -1 : _titles.indexOf(tab);
    if (index >= 0) {
      _index = index;
    }
  }

  /// 설정 화면의 저장 버튼은 헤더(AppBar)에 있습니다. 화면 밖에서 저장을
  final _settingsKey = GlobalKey<SettingsScreenState>();

  /// 경비 탭의 '경비 기록 N건'으로 알림 및 로그에 들어갈 때 처음 고를 분류. 그 화면을
  LogFilter? _logsJumpFilter;

  /// 도킹 실패 팝업의 '도크 위치 다시 잡기'(2026-11-19, 목업 92)로 지도 설정에 들어갈 때 도크 위치
  int _dockPanelRequest = 0;

  List<Widget> get _screens => [
        DashboardScreen(
          onOpenDiagnostics: () =>
              setState(() => _index = _systemDiagnosticsIndex),
        ),
        SaveLocationScreen(
          onOpenDrive: () => setState(() => _index = _driveIndex),
          dockPanelRequest: _dockPanelRequest,
        ),
        const MapLocationsScreen(),
        const DeliveryScreen(),
        PatrolScreen(
          onOpenRecords: () => setState(() {
            _logsJumpFilter = LogFilter.patrol;
            _index = _logsIndex;
          }),
        ),
        const CurrentLocationScreen(),
        const SystemDiagnosticsScreen(),
        LogsScreen(initialFilter: _logsJumpFilter ?? LogFilter.all),
        SettingsScreen(key: _settingsKey),
        _MoreScreen(
          onSelect: (title) => setState(() => _index = _titles.indexOf(title)),
          onLogout: () => confirmLogout(context),
        ),
      ];

  static int get _systemDiagnosticsIndex => _titles.indexOf('시스템 진단');
  static int get _settingsIndex => _titles.indexOf('설정');
  static int get _moreIndex => _titles.indexOf('더보기');
  static int get _logsIndex => _titles.indexOf('알림 및 로그');
  static int get _mapSettingsIndex => _titles.indexOf('지도 설정');
  static int get _driveIndex => _titles.indexOf('원격 주행');

  /// 하단 탭에 직접 올라가는 화면 수. 이 뒤의 화면은 '더보기' 탭이 대표합니다.
  static const int _bottomTabCount = 5;

  static const _titles = [
    '대시보드',
    '지도 설정',
    '원격 주행',
    '물류 배송',
    '경비',
    '현재 위치',
    '시스템 진단',
    '알림 및 로그',
    '설정',
    '더보기',
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final sidebarExpanded =
        context.watch<UiPreferencesProvider>().sidebarExpanded;
    final username = context.watch<AuthProvider>().currentUsername ?? '';

    final alert = supervisor.pendingGoalAlert;
    if (alert != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        supervisor.consumeGoalAlert();
        showVicaDialog<void>(
          context: context,
          builder: (_) => GoalAlertDialog(
            event: alert,
            onRedoDock: () {
              if (!mounted) {
                return;
              }
              setState(() {
                _dockPanelRequest += 1;
                _index = _mapSettingsIndex;
              });
            },
          ),
        );
      });
    }

    if (supervisor.voiceAlertSeq != _voiceAlertSeqShown) {
      _voiceAlertSeqShown = supervisor.voiceAlertSeq;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        for (final event in supervisor.takeVoiceAlerts()) {
          messenger.showSnackBar(voiceAlertSnackBar(event));
        }
      });
    }

    if (supervisor.helpPopupPending) {
      final helpId = supervisor.activeHelp!.helpId;
      supervisor.markHelpPopupShown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        showVicaDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => HelpAlertDialog(helpId: helpId),
        );
      });
    }
    final helpNotice = supervisor.pendingHelpNotice;
    if (helpNotice != null) {
      supervisor.consumeHelpNotice();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(helpNotice)));
      });
    }

    if (supervisor.patrolPopupPending) {
      final alarmId = supervisor.patrolAlarm!.alarmId;
      supervisor.markPatrolPopupShown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        showVicaDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PatrolAlarmDialog(alarmId: alarmId),
        );
      });
    }
    final patrolNotice = supervisor.pendingPatrolNotice;
    if (patrolNotice != null) {
      supervisor.consumePatrolNotice();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showPatrolToast(context, patrolNotice);
        }
      });
    }

    final deliveryNotice = supervisor.pendingDeliveryNotice;
    if (deliveryNotice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        supervisor.consumeDeliveryNotice();
        showVicaDialog<void>(
          context: context,
          builder: (_) => DeliveryNoticeDialog(notice: deliveryNotice),
        );
      });
    }

    final routeAlert = supervisor.pendingRouteAlert;
    if (routeAlert != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        supervisor.consumeRouteAlert();
        showVicaDialog<void>(
          context: context,
          builder: (_) => RouteApplyFailedDialog(reason: routeAlert),
        );
      });
    }
    final routeToast = supervisor.pendingRouteToast;
    if (routeToast != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        supervisor.consumeRouteToast();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(routeToast)));
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSidebar = constraints.maxWidth >= VicaBreakpoints.medium;

        final index = useSidebar && _index == _moreIndex ? 0 : _index;
        if (index != _logsIndex) {
          _logsJumpFilter = null;
        }
        if (index != _mapSettingsIndex) {
          _dockPanelRequest = 0;
        }

        return PopScope(
          canPop: !supervisor.emergencyOverlayVisible,
          child: Stack(
            children: [
              Scaffold(
                appBar: useSidebar
                    ? null
                    : _buildPhoneAppBar(
                        index: index,
                        settings: settings,
                        supervisor: supervisor,
                      ),
                body: SafeArea(
                  child: useSidebar
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDesktopSidebar(
                              expanded: sidebarExpanded,
                              username: username,
                              index: index,
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  _buildDesktopHeader(
                                    index: index,
                                    settings: settings,
                                    supervisor: supervisor,
                                  ),
                                  const DuplicateRunBanner(),
                                  Expanded(
                                      child: VicaScreenSwitcher(
                                          index: index,
                                          child: _screens[index])),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            const DuplicateRunBanner(),
                            Expanded(
                                child: VicaScreenSwitcher(
                                    index: index, child: _screens[index])),
                          ],
                        ),
                ),
                bottomNavigationBar:
                    useSidebar ? null : _buildBottomNavigation(index),
              ),
              if (supervisor.emergencyOverlayVisible)
                Positioned.fill(
                  child: _EmergencyStopOverlay(
                    settings: settings,
                    supervisor: supervisor,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildPhoneAppBar({
    required int index,
    required AppSettings settings,
    required SupervisorProvider supervisor,
  }) {
    return AppBar(
      toolbarHeight: 66,
      titleSpacing: 20,
      title: _PageTitle(title: _titles[index]),
      actions: [
        if (index == _settingsIndex) ...[
          SettingsSaveButton(
            onPressed: () => _settingsKey.currentState?.save(),
          ),
          const SizedBox(width: 6),
        ],
        PhoneModeButton(onChangeMode: () => _changeMode(context)),
        PressScale(
            child: IconButton(
          onPressed: () => setState(() => _index = _settingsIndex),
          icon: const Icon(Icons.settings_outlined),
          tooltip: '설정',
        )),
        const SizedBox(width: 2),
        _EmergencyStopButton(
          compact: true,
          enabled: !supervisor.emergencyOverlayVisible,
          onPressed: () => supervisor.activateEmergencyStop(settings),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildBottomNavigation(int index) {
    final selected = index < _bottomTabCount ? index : _bottomTabCount;
    final theme = NavigationBarTheme.of(context);
    return NavigationBarTheme(
      data: theme.copyWith(
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => theme.labelTextStyle?.resolve(states)?.copyWith(
                fontSize: 10,
              ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => theme.iconTheme?.resolve(states)?.copyWith(size: 20),
        ),
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: NavigationBar(
          selectedIndex: selected,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (value) => setState(() {
            _index = value < _bottomTabCount ? value : _moreIndex;
          }),
          destinations: [
            for (final item in _navigationItems.take(_bottomTabCount))
              NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon),
                label: item.label,
              ),
            const NavigationDestination(
              icon: Icon(Icons.menu),
              label: '더보기',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopHeader({
    required int index,
    required AppSettings settings,
    required SupervisorProvider supervisor,
  }) {
    return AppBar(
      primary: false,
      automaticallyImplyLeading: false,
      backgroundColor: VicaColors.background,
      toolbarHeight: 76,
      titleSpacing: 32,
      title: _PageTitle(title: _titles[index], large: true),
      actions: [
        if (index == _settingsIndex) ...[
          SettingsSaveButton(
            onPressed: () => _settingsKey.currentState?.save(),
          ),
          const SizedBox(width: 12),
        ],
        RosSilenceBuilder(
          builder: (context, silent) => _LiveChip(
            state: supervisor.connectionState,
            silent: silent,
          ),
        ),
        const SizedBox(width: 12),
        if (supervisor.modeStatus?.driveOn ?? false) ...[
          const DriveStopButton(),
          const SizedBox(width: 12),
        ],
        PressScale(
            child: OutlinedButton.icon(
          onPressed: () => _changeMode(context),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('모드 바꾸기'),
        )),
        const SizedBox(width: 12),
        _EmergencyStopButton(
          compact: false,
          enabled: !supervisor.emergencyOverlayVisible,
          onPressed: () => supervisor.activateEmergencyStop(settings),
        ),
        const SizedBox(width: 32),
      ],
    );
  }

  Widget _buildDesktopSidebar({
    required bool expanded,
    required String username,
    required int index,
  }) {
    final onDark = Colors.white.withValues(alpha: 0.78);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      child: SizedBox(
        key: const ValueKey('desktop_sidebar'),
        width: expanded ? 240 : 80,
        child: Material(
          color: VicaColors.text,
          borderRadius: BorderRadius.circular(kVicaCardRadius),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildSidebarHeader(expanded, onDark),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _navigationItems.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 4),
                  itemBuilder: (context, itemIndex) => _buildSidebarDestination(
                    index: itemIndex,
                    selected: index == itemIndex,
                    item: _navigationItems[itemIndex],
                    expanded: expanded,
                    onDark: onDark,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 12),
                child: Divider(color: Colors.white.withValues(alpha: 0.12)),
              ),
              _buildSidebarAccountArea(
                expanded: expanded,
                username: username,
                onDark: onDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarDestination({
    required int index,
    required bool selected,
    required _NavigationItem item,
    required bool expanded,
    required Color onDark,
  }) {
    final foreground = selected ? VicaColors.primaryDark : onDark;
    final destination = PressScale(
        child: Material(
      color: selected ? VicaColors.accentTint : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _index = index),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 46,
          child: Row(
            mainAxisAlignment:
                expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              if (expanded) const SizedBox(width: 14),
              Icon(
                selected ? item.selectedIcon : item.icon,
                size: 21,
                color: foreground,
              ),
              if (expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ],
          ),
        ),
      ),
    ));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: expanded
          ? destination
          : Tooltip(message: item.label, child: destination),
    );
  }

  Widget _buildSidebarHeader(bool expanded, Color onDark) {
    final toggleButton = PressScale(
        child: IconButton(
      onPressed: () => context.read<UiPreferencesProvider>().toggleSidebar(),
      icon: Icon(expanded ? Icons.menu_open : Icons.menu, size: 20),
      color: onDark,
      tooltip: expanded ? '사이드 메뉴 접기' : '사이드 메뉴 펼치기',
      visualDensity: VisualDensity.compact,
    ));
    const logo = _BrandMark(size: 40);

    if (expanded) {
      return SizedBox(
        height: 76,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
          child: Row(
            children: [
              logo,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VICA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'SUPERVISOR',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              toggleButton,
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 104,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          logo,
          const SizedBox(height: 4),
          toggleButton,
        ],
      ),
    );
  }

  Widget _buildSidebarAccountArea({
    required bool expanded,
    required String username,
    required Color onDark,
  }) {
    final avatar = CircleAvatar(
      radius: 17,
      backgroundColor: VicaColors.accentTint,
      child: Text(
        _usernameInitial(username),
        style: const TextStyle(
          color: VicaColors.primaryDark,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    final logoutButton = PressScale(
        child: IconButton(
      onPressed: () => confirmLogout(context),
      icon: const Icon(Icons.logout, size: 18),
      color: onDark,
      tooltip: '로그아웃',
      style: IconButton.styleFrom(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        shape: const CircleBorder(),
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
    ));

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Tooltip(message: '로그인 계정: $username', child: avatar),
            const SizedBox(height: 10),
            logoutButton,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '관리자',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          logoutButton,
        ],
      ),
    );
  }

  String _usernameInitial(String username) {
    return username.isEmpty ? '?' : username[0].toUpperCase();
  }

  /// 모드 선택 화면으로 돌아갑니다.
  Future<void> _changeMode(BuildContext context) async {
    final supervisor = context.read<SupervisorProvider>();

    final goal = supervisor.primaryRobot?.currentGoal.trim() ?? '';
    if (goal.isNotEmpty) {
      await _blockDialog(
        context,
        icon: Icons.near_me_outlined,
        title: '주행 중입니다',
        body: "'$goal'(으)로 주행 중입니다. 모드를 바꾸면 취소·일시정지 버튼에 "
            '닿을 수 없으니 먼저 주행을 끝내거나 취소해 주세요.',
      );
      return;
    }

    final mapping = supervisor.mappingStatus;
    if (mapping != null && mapping.busy) {
      await _blockDialog(
        context,
        icon: Icons.place_outlined,
        title: '매핑이 진행 중입니다',
        body: '${mapping.state.label}입니다.\n'
            '지도 모드에서 저장하거나 종료한 뒤에 모드를 바꿔 주세요.',
      );
      return;
    }

    final draft = supervisor.draftLocation;
    if (draft != null) {
      final leave = await showVicaConfirm(
        context,
        icon: Icons.place_outlined,
        iconColor: VicaColors.warning,
        title: '저장하지 않은 장소가 있습니다',
        body: "'${draft.name}'을(를) 아직 ROS2에 저장하지 않았습니다. "
            '모드를 바꾸면 사라집니다.',
        cancelLabel: '남아서 저장',
        confirmLabel: '버리고 나가기',
        confirmIcon: Icons.delete_outline,
        danger: true,
      );
      if (!leave || !context.mounted) {
        return;
      }
      supervisor.setDraftLocation(null);
    }

    if (supervisor.routeDirty) {
      if (!context.mounted) {
        return;
      }
      final leave = await showRouteLeaveDialog(context);
      if (!leave || !context.mounted) {
        return;
      }
    }
    if (supervisor.routeEditing) {
      supervisor.cancelRouteEdit();
    }

    context.read<AppModeProvider>().clear();
  }

  Future<void> _blockDialog(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return showVicaNotice(
      context,
      icon: icon,
      title: title,
      body: body,
      okIcon: Icons.check,
    );
  }

  /// 사이드바(전부)와 하단 탭(앞 다섯 개)이 같은 목록을 씁니다. 순서는 _titles 와
  static const _navigationItems = [
    _NavigationItem(
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_rounded,
      label: '대시보드',
    ),
    _NavigationItem(
      icon: Icons.place_outlined,
      selectedIcon: Icons.place,
      label: '지도',
    ),
    _NavigationItem(
      icon: Icons.near_me_outlined,
      selectedIcon: Icons.near_me,
      label: '주행',
    ),
    _NavigationItem(
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      label: '배송',
    ),
    _NavigationItem(
      icon: Icons.shield_outlined,
      selectedIcon: Icons.shield,
      label: '경비',
    ),
    _NavigationItem(
      icon: Icons.my_location_outlined,
      selectedIcon: Icons.my_location,
      label: '현재 위치',
    ),
    _NavigationItem(
      icon: Icons.monitor_heart_outlined,
      selectedIcon: Icons.monitor_heart,
      label: '시스템 진단',
    ),
    _NavigationItem(
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
      label: '알림 및 로그',
    ),
    _NavigationItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: '설정',
    ),
  ];
}

class _NavigationItem {
  const _NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 사이드바 로고. 사이드바가 어두워 흰 둥근 바탕 위에 올립니다.
class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => VicaLogo(size: size, framed: true);
}

/// AppBar 안의 제목. 폰은 20, 넓은 창은 26.
class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, this.large = false});

  final String title;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: large ? 26 : 20,
        fontWeight: FontWeight.w900,
        color: VicaColors.text,
        height: 1.15,
      ),
    );
  }
}

/// 헤더의 '실시간 수신 중' 알약. 연결 상태를 그대로 옮긴 표시일 뿐 누를 수 없습니다.
class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.state, this.silent = false});

  final RosConnectionState state;

  /// 소켓은 붙었는데 5초 넘게 받은 것이 없음(2026-11-17 rosbridge 처리 스레드 사망).
  final bool silent;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      RosConnectionState.connected when silent => ('응답 없음', VicaColors.warning),
      RosConnectionState.connected => ('온라인', VicaColors.green),
      RosConnectionState.connecting => ('접속 중', VicaColors.primary),
      RosConnectionState.failed => ('접속 실패', VicaColors.muted),
      RosConnectionState.disconnected => ('오프라인', VicaColors.muted),
    };
    return VicaStatusChip(label: label, color: color);
  }
}

/// 비상정지 버튼. 폰은 빨간 원(아이콘만), 넓은 창은 라벨이 붙은 알약.
class _EmergencyStopButton extends StatelessWidget {
  const _EmergencyStopButton({
    required this.compact,
    required this.enabled,
    required this.onPressed,
  });

  final bool compact;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final disabledColor = VicaColors.red.withValues(alpha: 0.4);
    if (compact) {
      return Tooltip(
        message: '비상정지',
        child: SizedBox(
          width: 32,
          height: 32,
          child: PressScale(
              child: FilledButton(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: VicaColors.red,
              foregroundColor: Colors.white,
              disabledBackgroundColor: disabledColor,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              size: 17,
              semanticLabel: '비상정지',
            ),
          )),
        ),
      );
    }
    return PressScale(
        child: FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: VicaColors.red,
        foregroundColor: Colors.white,
        disabledBackgroundColor: disabledColor,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      icon: const Icon(Icons.warning_amber_rounded, size: 18),
      label: const Text('비상정지'),
    ));
  }
}

/// 폰의 '더보기' 탭. 하단 탭에 못 올린 화면 네 개와 로그아웃.
class _MoreScreen extends StatelessWidget {
  const _MoreScreen({
    required this.onSelect,
    required this.onLogout,
  });

  final ValueChanged<String> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return VicaPage(
      children: [
        _MoreTile(
          icon: Icons.my_location_outlined,
          title: '현재 위치',
          subtitle: '로봇이 보고하는 위치와 원본값',
          onTap: () => onSelect('현재 위치'),
        ),
        _MoreTile(
          icon: Icons.monitor_heart_outlined,
          title: '시스템 진단',
          subtitle: '결함 · 준비 상태 · 상태 변화 이력',
          onTap: () => onSelect('시스템 진단'),
        ),
        _MoreTile(
          icon: Icons.notifications_outlined,
          title: '알림 및 로그',
          subtitle: '종류별 알림 기록',
          onTap: () => onSelect('알림 및 로그'),
        ),
        _MoreTile(
          icon: Icons.settings_outlined,
          title: '설정',
          subtitle: '계정 · 네트워크 · ROS 토픽',
          onTap: () => onSelect('설정'),
        ),
        _MoreTile(
          icon: Icons.logout,
          title: '로그아웃',
          subtitle: '계정에서 나가기',
          onTap: onLogout,
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: VicaColors.card,
        border: Border.all(color: VicaColors.border),
        borderRadius: BorderRadius.circular(kVicaCardRadius),
      ),
      child: PressScale(
          child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kVicaCardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kVicaCardRadius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                VicaIconCircle(icon: icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: VicaColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: VicaColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: VicaColors.textTertiary),
              ],
            ),
          ),
        ),
      )),
    );
  }
}

class _EmergencyStopOverlay extends StatelessWidget {
  const _EmergencyStopOverlay({
    required this.settings,
    required this.supervisor,
  });

  final AppSettings settings;
  final SupervisorProvider supervisor;

  @override
  Widget build(BuildContext context) {
    final state = supervisor.emergencyStopState;
    final isBusy = state == EmergencyStopState.activating ||
        state == EmergencyStopState.releasing;
    final isFailure = state == EmergencyStopState.activationFailed ||
        state == EmergencyStopState.releaseFailed;
    final title = switch (state) {
      EmergencyStopState.activating => '비상정지 요청 중',
      EmergencyStopState.active => '비상정지 활성화됨',
      EmergencyStopState.releasing => '비상정지 해제 중',
      EmergencyStopState.activationFailed => '비상정지 활성화 실패',
      EmergencyStopState.releaseFailed => '비상정지 해제 실패',
      EmergencyStopState.inactive => '',
    };
    final accent = isFailure ? VicaColors.warning : VicaColors.red;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ModalBarrier(
          dismissible: false,
          color: Colors.black54,
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Material(
                color: VicaColors.card,
                elevation: 16,
                shadowColor: Colors.black45,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kVicaCardRadius),
                  side: BorderSide(color: accent, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VicaIconCircle(
                        icon: isBusy
                            ? Icons.bolt
                            : (isFailure
                                ? Icons.warning_amber_rounded
                                : Icons.warning_amber_rounded),
                        color: accent,
                        filled: true,
                        size: 64,
                        iconSize: 32,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        supervisor.emergencyStopMessage,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (supervisor.emergencyCalledAdmin) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: VicaColors.accentTint,
                            borderRadius:
                                BorderRadius.circular(kVicaFieldRadius),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.notifications_active_outlined,
                                size: 18,
                                color: VicaColors.primaryDark,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  vicaKeepWords(vicaBreakAtSentences(
                                    supervisor.emergencyTipped
                                        ? '비카가 넘어져 관리자를 호출했습니다. '
                                            '비카를 세운 뒤 해제해 주세요.'
                                        : '비상정지로 비카가 관리자를 호출했습니다. '
                                            '확인이 필요합니다.',
                                  )),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                    fontWeight: FontWeight.w800,
                                    color: VicaColors.primaryDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (isBusy)
                        SizedBox(
                          width: double.infinity,
                          child: PressScale(
                              child: OutlinedButton.icon(
                            onPressed: null,
                            icon: const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            label: const Text('응답 대기 중'),
                          )),
                        )
                      else
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: PressScale(
                                  child: FilledButton.icon(
                                onPressed: () => _handleAction(state),
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                ),
                                icon: Icon(
                                  isFailure ? Icons.refresh : Icons.check,
                                  size: 18,
                                ),
                                label: Text(_actionLabel(state)),
                              )),
                            ),
                            if (state ==
                                EmergencyStopState.activationFailed) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: PressScale(
                                    child: OutlinedButton.icon(
                                  onPressed:
                                      supervisor.dismissEmergencyStopFailure,
                                  icon: const Icon(Icons.close, size: 18),
                                  label: const Text('취소하고 돌아가기'),
                                )),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _actionLabel(EmergencyStopState state) {
    return switch (state) {
      EmergencyStopState.active => '비상정지 해제',
      EmergencyStopState.releaseFailed => '해제 다시 시도',
      EmergencyStopState.activationFailed => '비상정지 다시 시도',
      _ => '',
    };
  }

  void _handleAction(EmergencyStopState state) {
    switch (state) {
      case EmergencyStopState.active:
        supervisor.resetEmergencyStop(settings);
        return;
      case EmergencyStopState.releaseFailed:
        supervisor.retryEmergencyStopRelease(settings);
        return;
      case EmergencyStopState.activationFailed:
        supervisor.retryEmergencyStop(settings);
        return;
      case EmergencyStopState.inactive:
      case EmergencyStopState.activating:
      case EmergencyStopState.releasing:
        return;
    }
  }
}
