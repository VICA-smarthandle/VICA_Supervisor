// 이 파일은 앱 테마, 로그인 분기, 화면 크기별 Navigation 구성을 담당합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_settings.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/supervisor_provider.dart';
import 'providers/ui_preferences_provider.dart';
import 'widgets/vica_ui.dart';
import 'screens/current_location_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/login_screen.dart';
import 'screens/map_locations_screen.dart';
import 'screens/robot_management_screen.dart';
import 'screens/save_location_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/system_diagnostics_screen.dart';

class VicaSupervisorApp extends StatelessWidget {
  const VicaSupervisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VICA_Supervisor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'NanumGothic',
        scaffoldBackgroundColor: VicaColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: VicaColors.primary,
          surface: VicaColors.background,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFBF9FF),
          foregroundColor: VicaColors.text,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: VicaColors.text,
            fontSize: 17,
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
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Color(0xFFF8FAFD),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: VicaColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: VicaColors.primary, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: VicaColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.watch<AuthProvider>().isLoggedIn;
    return isLoggedIn ? const SupervisorShell() : const LoginScreen();
  }
}

class SupervisorShell extends StatefulWidget {
  const SupervisorShell({super.key});

  @override
  State<SupervisorShell> createState() => _SupervisorShellState();
}

class _SupervisorShellState extends State<SupervisorShell> {
  int _index = 0;

  // 대시보드 배너가 진단 화면으로 보내려면 콜백이 필요해 const 리스트를 게터로 바꿨습니다.
  List<Widget> get _screens => [
        DashboardScreen(
          onOpenDiagnostics: () =>
              setState(() => _index = _systemDiagnosticsIndex),
        ),
        const SaveLocationScreen(),
        const MapLocationsScreen(),
        const CurrentLocationScreen(),
        const RobotManagementScreen(),
        const SystemDiagnosticsScreen(),
        const LogsScreen(),
        const SettingsScreen(),
      ];

  // AppBar 바로가기와 배너가 참조하는 인덱스입니다. 화면 순서를 바꿀 때 함께 바꿔야
  // 하므로 숫자를 코드에 직접 쓰지 않습니다.
  static const _dashboardIndex = 0;
  static const _saveLocationIndex = 1;
  static const _systemDiagnosticsIndex = 5;
  static const _settingsIndex = 7;

  static const _titles = [
    '대시보드',
    '장소 저장',
    '원격 주행',
    '현재 위치',
    '로봇 관리',
    '시스템 진단',
    '알림 및 로그',
    '설정',
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final sidebarExpanded =
        context.watch<UiPreferencesProvider>().sidebarExpanded;
    final username = context.watch<AuthProvider>().currentUsername ?? '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final useNavigationRail = constraints.maxWidth >= 900;

        return PopScope(
          canPop: !supervisor.emergencyOverlayVisible,
          child: Stack(
            children: [
              Scaffold(
                appBar: AppBar(
                  title: Text(_titles[_index]),
                  leading: useNavigationRail
                      ? null
                      : Builder(
                          builder: (context) => IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () => Scaffold.of(context).openDrawer(),
                          ),
                        ),
                  actions: [
                    // 어느 화면에서든 장소 저장으로 한 번에 이동합니다.
                    IconButton(
                      onPressed: () =>
                          setState(() => _index = _saveLocationIndex),
                      icon: const Icon(Icons.add_location_alt_outlined),
                      tooltip: '장소 저장',
                    ),
                    // 비상정지는 라벨 없이 빨간 원형으로 두어 한눈에 구분되게 합니다.
                    // 라벨이 없으므로 Tooltip과 semanticLabel로 의미를 전달합니다.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Tooltip(
                        message: '비상정지',
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: FilledButton(
                            onPressed: supervisor.emergencyOverlayVisible
                                ? null
                                : () =>
                                    supervisor.activateEmergencyStop(settings),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.red.shade200,
                              shape: const CircleBorder(),
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(40, 40),
                            ),
                            child: const Icon(
                              Icons.warning_rounded,
                              size: 20,
                              semanticLabel: '비상정지',
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (useNavigationRail) ...[
                      IconButton(
                        onPressed: () =>
                            setState(() => _index = _dashboardIndex),
                        icon: const Icon(Icons.home_outlined),
                        tooltip: '대시보드',
                      ),
                      IconButton(
                        onPressed: () =>
                            setState(() => _index = _settingsIndex),
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: '설정',
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
                drawer:
                    useNavigationRail ? null : _buildNavigationDrawer(username),
                body: SafeArea(
                  child: useNavigationRail
                      ? Row(
                          children: [
                            _buildDesktopSidebar(
                              expanded: sidebarExpanded,
                              username: username,
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: _screens[_index]),
                          ],
                        )
                      : _screens[_index],
                ),
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

  Drawer _buildNavigationDrawer(String username) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: NavigationDrawer(
                selectedIndex: _index,
                onDestinationSelected: (value) {
                  Navigator.of(context).pop();
                  setState(() => _index = value);
                },
                children: const [
                  SizedBox(height: 20),
                  Padding(
                    padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
                    child: Text(
                      'VICA',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  ..._navigationDrawerDestinations,
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: VicaColors.softBlue,
                child: Text(
                  _usernameInitial(username),
                  style: const TextStyle(
                    color: VicaColors.primaryDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              title: Text(
                username,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(Icons.logout),
              title: const Text('로그아웃'),
              onTap: () {
                Navigator.of(context).pop();
                _confirmLogout();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar({
    required bool expanded,
    required String username,
  }) {
    return Material(
      color: const Color(0xFFFBF9FF),
      child: SizedBox(
        key: const ValueKey('desktop_sidebar'),
        width: expanded ? 240 : 80,
        child: Column(
          children: [
            _buildSidebarHeader(expanded),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _desktopNavigationItems.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) => _buildSidebarDestination(
                  index: index,
                  item: _desktopNavigationItems[index],
                  expanded: expanded,
                ),
              ),
            ),
            const Divider(height: 1),
            _buildSidebarAccountArea(
              expanded: expanded,
              username: username,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarDestination({
    required int index,
    required _SidebarNavigationItem item,
    required bool expanded,
  }) {
    final selected = _index == index;
    final destination = Material(
      color: selected ? VicaColors.softBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _index = index),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment:
                expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              if (expanded) const SizedBox(width: 16),
              Icon(
                selected ? item.selectedIcon : item.icon,
                color: selected ? VicaColors.primaryDark : VicaColors.muted,
              ),
              if (expanded) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          selected ? VicaColors.primaryDark : VicaColors.text,
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
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 10),
      child: expanded
          ? destination
          : Tooltip(message: item.label, child: destination),
    );
  }

  Widget _buildSidebarHeader(bool expanded) {
    final toggleButton = IconButton(
      onPressed: () => context.read<UiPreferencesProvider>().toggleSidebar(),
      icon: const Icon(Icons.menu),
      tooltip: expanded ? '사이드 메뉴 접기' : '사이드 메뉴 펼치기',
    );

    if (expanded) {
      return SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'VICA',
                  style: TextStyle(
                    color: VicaColors.primaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              toggleButton,
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 94,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'VICA',
            style: TextStyle(
              color: VicaColors.primaryDark,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          toggleButton,
        ],
      ),
    );
  }

  Widget _buildSidebarAccountArea({
    required bool expanded,
    required String username,
  }) {
    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: VicaColors.softBlue,
      child: Text(
        _usernameInitial(username),
        style: const TextStyle(
          color: VicaColors.primaryDark,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Tooltip(message: '로그인 계정: $username', child: avatar),
            const SizedBox(height: 8),
            IconButton(
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout),
              tooltip: '로그아웃',
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(
        children: [
          Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout),
              label: const Text('로그아웃'),
            ),
          ),
        ],
      ),
    );
  }

  String _usernameInitial(String username) {
    return username.isEmpty ? '?' : username[0].toUpperCase();
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃하면 다음 실행 시 로그인 화면이 표시됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (shouldLogout != true || !mounted) {
      return;
    }

    await context.read<SupervisorProvider>().disconnect();
    if (!mounted) {
      return;
    }
    await context.read<AuthProvider>().logout();
  }

  static const _navigationDrawerDestinations = [
    NavigationDrawerDestination(
      icon: Icon(Icons.dashboard),
      label: Text('대시보드'),
    ),
    NavigationDrawerDestination(
      icon: Icon(Icons.add_location),
      label: Text('장소 저장'),
    ),
    NavigationDrawerDestination(
      icon: Icon(Icons.navigation),
      label: Text('원격 주행'),
    ),
    NavigationDrawerDestination(
      icon: Icon(Icons.my_location),
      label: Text('현재 위치'),
    ),
    NavigationDrawerDestination(
      icon: Icon(Icons.precision_manufacturing),
      label: Text('로봇 관리'),
    ),
    NavigationDrawerDestination(
      icon: Icon(Icons.monitor_heart),
      label: Text('시스템 진단'),
    ),
    NavigationDrawerDestination(
      icon: Icon(Icons.notifications),
      label: Text('알림 및 로그'),
    ),
    NavigationDrawerDestination(
      icon: Icon(Icons.settings),
      label: Text('설정'),
    ),
  ];

  static const _desktopNavigationItems = [
    _SidebarNavigationItem(
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      label: '대시보드',
    ),
    _SidebarNavigationItem(
      icon: Icons.add_location_outlined,
      selectedIcon: Icons.add_location,
      label: '장소 저장',
    ),
    _SidebarNavigationItem(
      icon: Icons.navigation_outlined,
      selectedIcon: Icons.navigation,
      label: '원격 주행',
    ),
    _SidebarNavigationItem(
      icon: Icons.my_location_outlined,
      selectedIcon: Icons.my_location,
      label: '현재 위치',
    ),
    _SidebarNavigationItem(
      icon: Icons.precision_manufacturing_outlined,
      selectedIcon: Icons.precision_manufacturing,
      label: '로봇 관리',
    ),
    _SidebarNavigationItem(
      icon: Icons.monitor_heart_outlined,
      selectedIcon: Icons.monitor_heart,
      label: '시스템 진단',
    ),
    _SidebarNavigationItem(
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
      label: '알림 및 로그',
    ),
    _SidebarNavigationItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: '설정',
    ),
  ];
}

class _SidebarNavigationItem {
  const _SidebarNavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
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
              child: Card(
                elevation: 16,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isFailure
                        ? Colors.orange.shade700
                        : Colors.red.shade700,
                    width: 3,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: isFailure
                            ? Colors.orange.shade700
                            : Colors.red.shade700,
                        child: Icon(
                          isFailure
                              ? Icons.warning_amber_rounded
                              : Icons.warning_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        supervisor.emergencyStopMessage,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (isBusy)
                        const CircularProgressIndicator()
                      else
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => _handleAction(state),
                                style: FilledButton.styleFrom(
                                  backgroundColor: isFailure
                                      ? Colors.orange.shade800
                                      : Colors.red.shade800,
                                ),
                                icon: Icon(
                                  isFailure ? Icons.refresh : Icons.lock_open,
                                ),
                                label: Text(_actionLabel(state)),
                              ),
                            ),
                            if (state ==
                                EmergencyStopState.activationFailed) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      supervisor.dismissEmergencyStopFailure,
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('취소하고 돌아가기'),
                                ),
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
