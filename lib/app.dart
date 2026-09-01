// 이 파일은 앱 테마, 로그인 분기, 화면 크기별 Navigation 구성을 담당합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_mode.dart';
import 'core/app_settings.dart';
import 'core/layout_breakpoints.dart';
import 'providers/app_mode_provider.dart';
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
import 'screens/mapping_shell.dart';
import 'screens/mode_select_screen.dart';
import 'screens/save_location_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/system_diagnostics_screen.dart';

/// 앱 전체가 쓰는 글꼴. pubspec.yaml의 `fonts: family:`와 반드시 같아야 한다.
///
/// 상수로 두는 이유는 `ThemeData.fontFamily`가 모든 곳에 퍼지지 않기 때문이다.
/// `textTheme`에는 자동으로 적용되지만 `appBarTheme.titleTextStyle`처럼 하위 테마가
/// 직접 들고 있는 TextStyle에는 적용되지 않는다. 그런 자리에는 이 상수를 손으로 넣는다.
/// 넣지 않으면 그 자리만 기본 글꼴(Roboto)로 그려져 한글이 네모(□)가 된다.
const String kVicaFontFamily = 'NanumGothic';

class VicaSupervisorApp extends StatelessWidget {
  const VicaSupervisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VICA_Supervisor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: kVicaFontFamily,
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
          // fontFamily를 여기 직접 넣어야 한다. ThemeData.fontFamily는 textTheme에만
          // 적용되고 appBarTheme이 들고 있는 TextStyle에는 닿지 않는다. 빠뜨렸더니
          // 햄버거 메뉴 옆 제목만 한글이 네모로 나왔다(2026-08-01 Jetson 화면 확인).
          titleTextStyle: TextStyle(
            fontFamily: kVicaFontFamily,
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
    final modeProvider = context.watch<AppModeProvider>();

    if (!isLoggedIn) {
      // 로그아웃하면 모드도 함께 비웁니다. 안 비우면 다시 로그인했을 때 모드 선택을
      // 건너뛰고 지난번 모드로 바로 들어갑니다. build 중에 상태를 바꿀 수 없어
      // 프레임이 끝난 뒤로 미룹니다.
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

  // 대시보드 배너가 진단 화면으로 보내려면 콜백이 필요해 const 리스트를 게터로 바꿨습니다.
  List<Widget> get _screens => [
        DashboardScreen(
          onOpenDiagnostics: () =>
              setState(() => _index = _systemDiagnosticsIndex),
        ),
        const SaveLocationScreen(),
        const MapLocationsScreen(),
        const CurrentLocationScreen(),
        const SystemDiagnosticsScreen(),
        const LogsScreen(),
        const SettingsScreen(),
      ];

  // AppBar 바로가기와 배너가 참조하는 인덱스입니다.
  //
  // 숫자를 직접 쓰지 않고 _titles 에서 찾습니다. 종전에는 5, 7 처럼 박아 두고
  // "화면 순서를 바꿀 때 함께 바꾼다"고 주석으로 약속했는데, 2026-08-21 에 화면
  // 하나(로봇 관리)를 지우면서 그 약속이 실제로 깨질 뻔했습니다. 손으로 맞추는
  // 약속은 언젠가 어긋납니다 — 찾게 하면 어긋날 수가 없습니다.
  static int get _dashboardIndex => _titles.indexOf('대시보드');
  static int get _saveLocationIndex => _titles.indexOf('지도 설정');
  static int get _systemDiagnosticsIndex => _titles.indexOf('시스템 진단');
  static int get _settingsIndex => _titles.indexOf('설정');

  static const _titles = [
    '대시보드',
    '지도 설정',
    '원격 주행',
    '현재 위치',
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
        final useNavigationRail =
            constraints.maxWidth >= VicaBreakpoints.medium;

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
                    IconButton(
                      onPressed: () => _changeMode(context),
                      icon: const Icon(Icons.swap_horiz),
                      tooltip: '모드 바꾸기',
                    ),
                    // 어느 화면에서든 지도 설정으로 한 번에 이동합니다.
                    IconButton(
                      onPressed: () =>
                          setState(() => _index = _saveLocationIndex),
                      icon: const Icon(Icons.add_location_alt_outlined),
                      tooltip: '지도 설정',
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

  /// 모드 선택 화면으로 돌아갑니다.
  ///
  /// 기준마다 근거가 따로 있습니다. 공통점은 "화면을 떠나면 그 일을 멈출 버튼에
  /// 손이 닿지 않는다"입니다.
  ///
  /// 젯슨 스택이 떠 있는지는 여기서 막지 않습니다. 모드 선택 화면이 카드 상태 점
  /// 으로 이미 보여주고, 돌아가는 것 자체는 위험하지 않기 때문입니다.
  Future<void> _changeMode(BuildContext context) async {
    final supervisor = context.read<SupervisorProvider>();

    // ① 주행 중 — 취소·일시정지 버튼이 이 화면에만 있습니다.
    final goal = supervisor.primaryRobot?.currentGoal.trim() ?? '';
    if (goal.isNotEmpty) {
      await _blockDialog(
        context,
        '주행 중입니다',
        "'$goal'(으)로 주행 중입니다. 모드를 바꾸면 취소·일시정지 버튼에 "
            '닿을 수 없으니 먼저 주행을 끝내거나 취소해 주세요.',
      );
      return;
    }

    // ② 매핑 중 — 지도를 그리다 말고 나가면 저장할 방법이 없습니다.
    final mapping = supervisor.mappingStatus;
    if (mapping != null && mapping.busy) {
      await _blockDialog(
        context,
        '매핑이 진행 중입니다',
        '${mapping.state.label} 상태입니다. 지도 모드에서 저장하거나 종료한 뒤에 '
            '모드를 바꿔 주세요.',
      );
      return;
    }

    // ③ 저장 안 한 임시 장소 — 막지 않고 한 번 묻습니다. 사람이 버려도 되는
    //    것인지 아는 유일한 주체입니다.
    final draft = supervisor.draftLocation;
    if (draft != null) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('저장하지 않은 장소가 있습니다'),
          content: Text(
            "'${draft.name}'을(를) 아직 ROS2에 저장하지 않았습니다. "
            '모드를 바꾸면 사라집니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('남아서 저장'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('버리고 나가기'),
            ),
          ],
        ),
      );
      if (leave != true || !context.mounted) {
        return;
      }
      supervisor.setDraftLocation(null);
    }

    context.read<AppModeProvider>().clear();
  }

  Future<void> _blockDialog(
    BuildContext context,
    String title,
    String body,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
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
      label: Text('지도 설정'),
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
      label: '지도 설정',
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
                      // 물리 버튼이나 음성으로 걸린 비상정지에만 붙입니다.
                      // 그때 로봇이 이용자에게 "관리자를 부르겠다"고 말하므로,
                      // 관리자 화면도 같은 사실을 알아야 현장으로 갑니다.
                      // 관리자가 앱에서 직접 누른 경우에는 붙지 않습니다 —
                      // 부른 사람과 받는 사람이 같습니다.
                      if (supervisor.emergencyCalledAdmin) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: VicaColors.softBlue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            '주행 중 비상정지로 비카가 관리자를 호출했습니다. '
                            '확인이 필요합니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              fontWeight: FontWeight.w800,
                              color: VicaColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
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
