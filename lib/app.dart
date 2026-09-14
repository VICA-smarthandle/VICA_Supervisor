// 이 파일은 앱 테마, 로그인 분기, 화면 크기별 Navigation 구성을 담당합니다.
//
// 2026-09-14 리디자인 2단계. 화면 틀이 바뀌었다.
//   - 폰: 햄버거 드로어 → 하단 탭 5개(대시보드·지도 설정·원격 주행·물류 배송·더보기).
//     나머지 네 화면(현재 위치·시스템 진단·알림 및 로그·설정)과 모드 바꾸기·로그아웃은
//     '더보기' 탭 안 목록으로 간다. 갈 수 있는 곳은 전과 같다 — 가는 길만 바뀌었다.
//   - 태블릿·데스크톱: 어두운 사이드바 + 본문 위 페이지 헤더(제목·설명·실시간 수신 칩·
//     모드 바꾸기·비상정지). 접고 펼치기는 그대로 둔다.
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
import 'ros/ros_bridge_client.dart';
import 'widgets/vica_ui.dart';
import 'screens/current_location_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/delivery_screen.dart';
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
///
/// Gothic A1 으로 바꾸려면 (2026-09-14 디자인 결정, 폰트 파일은 아직 없음):
///   1. Gothic A1 을 받아 assets/fonts/ 에 넣는다 (SIL OFL 1.1 — NanumGothic 과
///      같은 라이선스라 지금 방식 그대로 재배포할 수 있다. LICENSE 파일도 함께)
///   2. pubspec.yaml 의 주석 처리된 GothicA1 블록을 살린다
///   3. 이 상수를 'GothicA1' 로 바꾼다
/// 파일 없이 이름만 바꾸면 APK 에서 한글이 전부 네모(□)로 나온다.
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
          backgroundColor: VicaColors.card,
          foregroundColor: VicaColors.text,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          // fontFamily를 여기 직접 넣어야 한다. ThemeData.fontFamily는 textTheme에만
          // 적용되고 appBarTheme이 들고 있는 TextStyle에는 닿지 않는다. 빠뜨렸더니
          // 햄버거 메뉴 옆 제목만 한글이 네모로 나왔다(2026-08-01 Jetson 화면 확인).
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
        // 폰 하단 탭. 고른 칸은 옅은 틸 사각형 안에 진한 틸 글자.
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
        // 팝업은 전부 같은 모서리·흰 면. 화면마다 따로 적지 않는다.
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
        // 저장 완료 같은 짧은 알림은 어두운 토스트 하나로 통일한다.
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

  /// 설정 화면의 저장 버튼은 헤더(AppBar)에 있습니다. 화면 밖에서 저장을
  /// 부르려면 그 화면의 State 에 닿아야 해서 key 로 붙잡습니다.
  final _settingsKey = GlobalKey<SettingsScreenState>();

  // 대시보드 배너가 진단 화면으로 보내려면 콜백이 필요해 const 리스트를 게터로 바꿨습니다.
  List<Widget> get _screens => [
        DashboardScreen(
          onOpenDiagnostics: () =>
              setState(() => _index = _systemDiagnosticsIndex),
        ),
        const SaveLocationScreen(),
        const MapLocationsScreen(),
        const DeliveryScreen(),
        const CurrentLocationScreen(),
        const SystemDiagnosticsScreen(),
        const LogsScreen(),
        SettingsScreen(key: _settingsKey),
        // 폰 전용 '더보기' 목록. 사이드바가 있는 넓은 창에서는 쓰이지 않습니다.
        _MoreScreen(
          onSelect: (title) => setState(() => _index = _titles.indexOf(title)),
          onChangeMode: () => _changeMode(context),
          onLogout: _confirmLogout,
        ),
      ];

  // AppBar 바로가기와 배너가 참조하는 인덱스입니다.
  //
  // 숫자를 직접 쓰지 않고 _titles 에서 찾습니다. 종전에는 5, 7 처럼 박아 두고
  // "화면 순서를 바꿀 때 함께 바꾼다"고 주석으로 약속했는데, 2026-08-21 에 화면
  // 하나(로봇 관리)를 지우면서 그 약속이 실제로 깨질 뻔했습니다. 손으로 맞추는
  // 약속은 언젠가 어긋납니다 — 찾게 하면 어긋날 수가 없습니다.
  static int get _systemDiagnosticsIndex => _titles.indexOf('시스템 진단');
  static int get _settingsIndex => _titles.indexOf('설정');
  static int get _moreIndex => _titles.indexOf('더보기');

  /// 하단 탭에 직접 올라가는 화면 수. 이 뒤의 화면은 '더보기' 탭이 대표합니다.
  static const int _bottomTabCount = 4;

  static const _titles = [
    '대시보드',
    '지도 설정',
    '원격 주행',
    '물류 배송',
    '현재 위치',
    '시스템 진단',
    '알림 및 로그',
    '설정',
    '더보기',
  ];

  /// 폰 AppBar 제목 아래 한 줄. 짧아야 합니다 — 오른쪽에 버튼 두 개가 섭니다.
  static const _subtitles = [
    '로봇 현황',
    '장소 · 홈 · 금지구역',
    '목적지 지정 · 주행 제어',
    '도착 문자 · 자동 복귀',
    '상태 원본값',
    '결함 · 준비 상태',
    '종류별 알림',
    '계정 · 네트워크 · ROS',
    '나머지 메뉴',
  ];

  /// 넓은 창 페이지 헤더의 설명문. 폰보다 자리가 넓어 문장으로 적습니다.
  static const _descriptions = [
    '로봇 현황과 최근 알림을 한눈에 확인합니다',
    '장소 · 홈 위치 · 금지구역을 지도 위에서 설정합니다',
    '목적지를 지정해 로봇을 보내고 주행을 제어합니다',
    '연락처가 저장된 장소로 물건을 보내고 도착 문자를 발송합니다',
    '로봇이 보고하는 위치와 상태 원본값을 확인합니다',
    '로봇이 보고한 상태와 결함, 항목별 준비 상태입니다',
    '로봇과 앱에서 발생한 알림을 종류별로 확인합니다',
    '계정, 네트워크, ROS 토픽과 좌표 보정값을 관리합니다',
    '나머지 메뉴',
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
        final useSidebar = constraints.maxWidth >= VicaBreakpoints.medium;

        // 사이드바가 있는 창에서 '더보기' 에 머물러 있으면(창을 넓힌 경우)
        // 대시보드로 돌립니다. 그 목록은 사이드바가 이미 다 보여줍니다.
        final index = useSidebar && _index == _moreIndex ? 0 : _index;

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
                                  Expanded(child: _screens[index]),
                                ],
                              ),
                            ),
                          ],
                        )
                      : _screens[index],
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

  // ---- 폰 ---------------------------------------------------------------

  PreferredSizeWidget _buildPhoneAppBar({
    required int index,
    required AppSettings settings,
    required SupervisorProvider supervisor,
  }) {
    return AppBar(
      toolbarHeight: 66,
      titleSpacing: 20,
      title: _PageTitle(
        title: _titles[index],
        subtitle: _subtitles[index],
      ),
      actions: [
        if (index == _settingsIndex) ...[
          SettingsSaveButton(
            onPressed: () => _settingsKey.currentState?.save(),
          ),
          const SizedBox(width: 6),
        ],
        IconButton(
          onPressed: () => _changeMode(context),
          icon: const Icon(Icons.swap_horiz),
          tooltip: '모드 바꾸기',
        ),
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
    return NavigationBar(
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
    );
  }

  // ---- 넓은 창 ------------------------------------------------------------

  Widget _buildDesktopHeader({
    required int index,
    required AppSettings settings,
    required SupervisorProvider supervisor,
  }) {
    return AppBar(
      primary: false,
      automaticallyImplyLeading: false,
      backgroundColor: VicaColors.background,
      toolbarHeight: 108,
      titleSpacing: 32,
      title: _PageTitle(
        title: _titles[index],
        subtitle: _descriptions[index],
        breadcrumb: '주행 모드',
        large: true,
      ),
      actions: [
        if (index == _settingsIndex) ...[
          SettingsSaveButton(
            onPressed: () => _settingsKey.currentState?.save(),
          ),
          const SizedBox(width: 12),
        ],
        _LiveChip(state: supervisor.connectionState),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () => _changeMode(context),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('모드 바꾸기'),
        ),
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
    // 어두운 면. 팔레트에 사이드바 전용 잉크색이 없어 글자색(text)을 면으로 씁니다.
    // 시안의 ink-900 과 밝기가 같고 색조만 조금 다릅니다.
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
    final destination = Material(
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
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 12),
      child: expanded
          ? destination
          : Tooltip(message: item.label, child: destination),
    );
  }

  Widget _buildSidebarHeader(bool expanded, Color onDark) {
    final toggleButton = IconButton(
      onPressed: () => context.read<UiPreferencesProvider>().toggleSidebar(),
      icon: Icon(expanded ? Icons.menu_open : Icons.menu, size: 20),
      color: onDark,
      tooltip: expanded ? '사이드 메뉴 접기' : '사이드 메뉴 펼치기',
      visualDensity: VisualDensity.compact,
    );
    const logo = _BrandMark(size: 36);

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
                      'Supervisor',
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
    final logoutButton = IconButton(
      onPressed: _confirmLogout,
      icon: const Icon(Icons.logout, size: 18),
      color: onDark,
      tooltip: '로그아웃',
      style: IconButton.styleFrom(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        shape: const CircleBorder(),
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
    );

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

  // ---- 공통 동작 ----------------------------------------------------------

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
        icon: Icons.near_me_outlined,
        title: '주행 중입니다',
        body: "'$goal'(으)로 주행 중입니다. 모드를 바꾸면 취소·일시정지 버튼에 "
            '닿을 수 없으니 먼저 주행을 끝내거나 취소해 주세요.',
      );
      return;
    }

    // ② 매핑 중 — 지도를 그리다 말고 나가면 저장할 방법이 없습니다.
    final mapping = supervisor.mappingStatus;
    if (mapping != null && mapping.busy) {
      await _blockDialog(
        context,
        icon: Icons.place_outlined,
        title: '매핑이 진행 중입니다',
        body: '${mapping.state.label} 상태입니다. 지도 모드에서 저장하거나 종료한 뒤에 '
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
        builder: (dialogContext) => VicaDialog(
          icon: Icons.place_outlined,
          iconColor: VicaColors.warning,
          title: '저장하지 않은 장소가 있습니다',
          body: "'${draft.name}'을(를) 아직 ROS2에 저장하지 않았습니다. "
              '모드를 바꾸면 사라집니다.',
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('남아서 저장'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: VicaColors.red),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('버리고 나가기'),
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
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => VicaDialog(
        icon: icon,
        title: title,
        body: body,
        actions: [
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => VicaDialog(
        icon: Icons.logout,
        title: '로그아웃',
        body: '로그아웃하면 다음 실행 시 로그인 화면이 표시됩니다.',
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('로그아웃'),
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

  /// 사이드바(전부)와 하단 탭(앞 네 개)이 같은 목록을 씁니다. 순서는 _titles 와
  /// 같아야 합니다 — supervisor_shell_test 가 잠급니다.
  static const _navigationItems = [
    _NavigationItem(
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view_rounded,
      label: '대시보드',
    ),
    _NavigationItem(
      icon: Icons.place_outlined,
      selectedIcon: Icons.place,
      label: '지도 설정',
    ),
    _NavigationItem(
      icon: Icons.near_me_outlined,
      selectedIcon: Icons.near_me,
      label: '원격 주행',
    ),
    _NavigationItem(
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      label: '물류 배송',
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

/// 틸 원 안의 번개. 사이드바가 씁니다(시안의 사이드바 로고는 원입니다).
class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: VicaColors.primary,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.bolt, color: Colors.white, size: size * 0.55),
    );
  }
}

/// AppBar 안의 제목 묶음. 폰은 제목+짧은 부제, 넓은 창은 경로+큰 제목+설명.
class _PageTitle extends StatelessWidget {
  const _PageTitle({
    required this.title,
    required this.subtitle,
    this.breadcrumb,
    this.large = false,
  });

  final String title;
  final String subtitle;
  final String? breadcrumb;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 경로는 Text 하나로 그립니다. 제목 글자를 따로 Text 로 두면 AppBar 안에
        // 같은 글자가 둘이 되어 find.widgetWithText(AppBar, 제목) 이 둘을 셉니다.
        if (breadcrumb != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$breadcrumb  ›  ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: VicaColors.textTertiary,
                    ),
                  ),
                  TextSpan(
                    text: title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: VicaColors.muted,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.2),
            ),
          ),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: large ? 26 : 20,
            fontWeight: FontWeight.w900,
            color: VicaColors.text,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: large ? 13 : 12,
            fontWeight: FontWeight.w500,
            color: VicaColors.muted,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// 헤더의 '실시간 수신 중' 알약. 연결 상태를 그대로 옮긴 표시일 뿐 누를 수 없습니다.
class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.state});

  final RosConnectionState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      RosConnectionState.connected => ('실시간 수신 중', VicaColors.green),
      RosConnectionState.connecting => ('연결 중', VicaColors.primary),
      RosConnectionState.failed => ('연결 실패', VicaColors.red),
      RosConnectionState.disconnected => ('연결 안 됨', VicaColors.muted),
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
      // 라벨이 없으므로 Tooltip과 semanticLabel로 의미를 전달합니다.
      return Tooltip(
        message: '비상정지',
        child: SizedBox(
          width: 42,
          height: 42,
          child: FilledButton(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: VicaColors.red,
              foregroundColor: Colors.white,
              disabledBackgroundColor: disabledColor,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              minimumSize: const Size(42, 42),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              size: 22,
              semanticLabel: '비상정지',
            ),
          ),
        ),
      );
    }
    return FilledButton.icon(
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
    );
  }
}

/// 폰의 '더보기' 탭. 하단 탭에 못 올린 화면 네 개와 모드 바꾸기·로그아웃.
class _MoreScreen extends StatelessWidget {
  const _MoreScreen({
    required this.onSelect,
    required this.onChangeMode,
    required this.onLogout,
  });

  final ValueChanged<String> onSelect;
  final VoidCallback onChangeMode;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final username = context.watch<AuthProvider>().currentUsername ?? '';
    final rosBridgeUrl =
        context.watch<SettingsProvider>().settings.rosBridgeUrl;

    return VicaPage(
      children: [
        _AccountCard(username: username, rosBridgeUrl: rosBridgeUrl),
        const SizedBox(height: 4),
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
          icon: Icons.swap_horiz,
          title: '모드 바꾸기',
          subtitle: '주행 모드 ↔ 지도 모드',
          onTap: onChangeMode,
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

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.username, required this.rosBridgeUrl});

  final String username;
  final String rosBridgeUrl;

  @override
  Widget build(BuildContext context) {
    final initial = username.isEmpty ? '?' : username[0].toUpperCase();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: VicaColors.text,
        borderRadius: BorderRadius.circular(kVicaCardRadius),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: VicaColors.primary,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '관리자 · $rosBridgeUrl',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      ),
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
                      // 물리 버튼이나 음성으로 걸린 비상정지에만 붙입니다.
                      // 그때 로봇이 이용자에게 "관리자를 부르겠다"고 말하므로,
                      // 관리자 화면도 같은 사실을 알아야 현장으로 갑니다.
                      // 관리자가 앱에서 직접 누른 경우에는 붙지 않습니다 —
                      // 부른 사람과 받는 사람이 같습니다.
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
                          child: const Row(
                            children: [
                              Icon(
                                Icons.notifications_active_outlined,
                                size: 18,
                                color: VicaColors.primaryDark,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '주행 중 비상정지로 비카가 관리자를 호출했습니다. '
                                  '확인이 필요합니다.',
                                  style: TextStyle(
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
                        // 응답을 기다리는 동안은 누를 것이 없습니다. 도는 원을
                        // 버튼 자리에 두어 화면이 굳은 것이 아님을 알립니다.
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: null,
                            icon: const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            label: const Text('응답 대기 중'),
                          ),
                        )
                      else
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
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
                                  icon: const Icon(Icons.close, size: 18),
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
