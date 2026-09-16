// 이 파일은 rosbridge 주소, 지도 서버 주소, topic 이름, 동기화와 좌표 보정 설정을 편집합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../providers/settings_provider.dart';
import '../widgets/vica_ui.dart';

/// 설정 화면을 독립된 페이지로 띄웁니다.
///
/// 주행 모드는 사이드 메뉴에 '설정'이 있지만, 모드 선택 화면과 지도 모드에는
/// 그 메뉴가 없습니다. 그런데 rosbridge 주소가 틀리면 **그 두 화면에서 아무것도
/// 할 수 없습니다** — 연결이 안 되니 스택 상태 점도, 매핑 시작도 안 됩니다.
/// 주소를 고치려고 주행 모드까지 들어갔다 나오지 않아도 되게 합니다.
///
/// SettingsScreen 을 그대로 씁니다. 설정은 앱 전체에 하나뿐이라 화면마다 다른
/// 편집기를 두면 어느 쪽이 진짜인지 헷갈립니다.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 저장 버튼이 앱바(헤더)에 있어 화면 밖에서 저장을 불러야 합니다.
  /// 주행 모드의 셸(app.dart)과 같은 방식입니다.
  final _screenKey = GlobalKey<SettingsScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        actions: [
          SettingsSaveButton(
            onPressed: () => _screenKey.currentState?.save(),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(child: SettingsScreen(key: _screenKey)),
    );
  }
}

/// 설정 화면입니다.
///
/// 항목마다 입력칸을 펼쳐 두면 스무 개 가까운 상자가 줄지어 서서 화면이
/// 무겁습니다. 값은 한 줄(라벨 · 값 · >)로만 보여 주고, 행을 탭했을 때만
/// 입력칸을 시트로 띄웁니다. 입력칸과 저장 절차는 그대로입니다 — 시트가 같은
/// TextEditingController 를 쓰므로 헤더의 '저장' 버튼이 예전처럼 한 번에 모읍니다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

/// 공개 State 입니다. 셸(app.dart)이 헤더의 저장 버튼에서 [save] 를 부르려고
/// GlobalKey 로 붙잡습니다 — 저장 버튼이 화면 밖(AppBar)에 있기 때문입니다.
class SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _settings;
  final Map<String, TextEditingController> _controllers = {};

  // 좌표 보정과 고급 설정은 처음 맞출 때 말고는 손댈 일이 없는 값입니다.
  // 접어 두고 제목을 눌러야 펼쳐집니다 — 늘 펼쳐 두면 스무 줄이 화면을 채워
  // 자주 고치는 주소 두 줄이 묻힙니다.
  bool _coordinateExpanded = false;
  bool _advancedExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings = context.watch<SettingsProvider>().settings;
    _syncControllers(_settings);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VicaPage(
      children: [
        const _SettingsCard(
          icon: Icons.settings_outlined,
          title: '계정 정보',
          children: [
            // 로그인 계정은 여기서 바꾸지 않습니다. 값만 보여 주고 탭을 받지 않습니다.
            _ValueRow(label: '관리자 정보', value: 'admin'),
          ],
        ),
        _SettingsCard(
          icon: Icons.link,
          title: '네트워크 및 ROS',
          children: [
            _editable('mapHttpBaseUrl', '지도 이미지 URL', technical: true),
            _editable('rosBridgeUrl', 'ROS Bridge 주소', technical: true),
          ],
        ),
        _SettingsCard(
          icon: Icons.adjust,
          title: '좌표 보정',
          expanded: _coordinateExpanded,
          onToggle: () =>
              setState(() => _coordinateExpanded = !_coordinateExpanded),
          children: [
            _editable('xOffset', 'x 보정값', number: true),
            _editable('yOffset', 'y 보정값', number: true),
            _editable('yawOffset', 'yaw 보정값', number: true),
            _editable('mapScale', '지도 스케일 보정값', number: true),
            _SwitchRow(
              label: '지도 Y축 반전',
              value: _settings.flipMapY,
              onChanged: (value) => setState(
                () => _settings = _settings.copyWith(flipMapY: value),
              ),
            ),
          ],
        ),
        _SettingsCard(
          icon: Icons.monitor_heart_outlined,
          title: '고급 설정',
          expanded: _advancedExpanded,
          onToggle: () =>
              setState(() => _advancedExpanded = !_advancedExpanded),
          children: [
            _SwitchRow(
              label: '지도 목록 자동 요청',
              value: _settings.autoRequestMapList,
              onChanged: (value) => setState(
                () => _settings = _settings.copyWith(autoRequestMapList: value),
              ),
            ),
            _SwitchRow(
              label: '장소 목록 자동 요청',
              value: _settings.autoRequestLocationList,
              onChanged: (value) => setState(
                () => _settings =
                    _settings.copyWith(autoRequestLocationList: value),
              ),
            ),
            const _GroupLabel('지도'),
            _editable(
              'mapListRequestTopic',
              '지도 목록 요청 topic',
              technical: true,
            ),
            _editable('mapListTopic', '지도 목록 topic', technical: true),
            const _GroupLabel('장소'),
            _editable(
              'locationListRequestTopic',
              '장소 목록 요청 topic',
              technical: true,
            ),
            _editable('locationListTopic', '장소 목록 topic', technical: true),
            _editable('saveLocationTopic', '장소 저장 topic', technical: true),
            _editable(
              'deleteLocationRequestTopic',
              '장소 삭제 요청 topic',
              technical: true,
            ),
            const _GroupLabel('주행 · 배송'),
            _editable(
              'missionRequestService',
              '목적지 주행 요청 service',
              technical: true,
            ),
            _editable(
              'missionDeliveryService',
              '물류 배송 요청 service',
              technical: true,
            ),
            _editable('robotStatusTopic', '로봇 상태 topic', technical: true),
            const _GroupLabel('비상정지'),
            _editable(
              'emergencyActivateService',
              '비상정지 활성화 service',
              technical: true,
            ),
            _editable(
              'emergencyResetService',
              '비상정지 해제 service',
              technical: true,
            ),
            _editable(
              'emergencyStateTopic',
              '비상정지 상태 topic',
              technical: true,
            ),
            _editable(
              'emergencyServiceTimeoutSeconds',
              '비상정지 응답 제한시간',
              number: true,
              unit: '초',
            ),
          ],
        ),
      ],
    );
  }

  /// 입력칸 하나를 '라벨 · 값 · >' 한 줄로 그립니다. 탭하면 수정 시트가 열립니다.
  ///
  /// [technical] 은 URL·topic 처럼 사람이 읽는 글이 아닌 값입니다. 옅게 그려
  /// 라벨보다 뒤로 물러나게 합니다. [unit] 은 값 뒤에 붙는 단위입니다.
  Widget _editable(
    String key,
    String label, {
    bool number = false,
    bool technical = false,
    String unit = '',
  }) {
    final text = _c(key).text;
    return _ValueRow(
      label: label,
      value: unit.isEmpty ? text : '$text$unit',
      technical: technical,
      onTap: () => _edit(key, label, number: number, unit: unit),
    );
  }

  /// 기존 입력칸을 시트에 담아 띄웁니다.
  ///
  /// 시트는 화면과 같은 controller 를 쓰므로 '확인'으로 닫으면 값이 그대로
  /// 남습니다. '취소'나 바깥 탭으로 닫으면 열기 전 값으로 되돌립니다 — 그래야
  /// 한 글자 지우다 만 값이 조용히 저장되지 않습니다.
  Future<void> _edit(
    String key,
    String label, {
    required bool number,
    required String unit,
  }) async {
    final controller = _c(key);
    final before = controller.text;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: VicaColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kVicaCardRadius),
        ),
      ),
      builder: (sheetContext) => _EditSheet(
        controller: controller,
        label: label,
        number: number,
        unit: unit,
      ),
    );
    if (confirmed != true) {
      controller.text = before;
    } else {
      _syncHost(key);
    }
    if (mounted) {
      // 행에 보이는 값은 controller 를 읽어 그리므로 다시 그려야 바뀝니다.
      setState(() {});
    }
  }

  /// 지도 이미지 URL 과 ROS Bridge 주소는 같은 젯슨을 가리킵니다. 한쪽의
  /// 호스트(IP)를 고치면 다른 쪽도 같은 호스트로 맞춥니다 — 둘을 따로 고치다
  /// 한쪽을 빠뜨리면 지도만 안 뜨거나 연결만 안 되는 식으로 어긋납니다.
  /// 포트와 경로는 서로 다르므로 호스트만 옮깁니다. 저장은 여전히 헤더의
  /// 저장 버튼이 합니다.
  static const _pairedUrlKeys = {
    'rosBridgeUrl': 'mapHttpBaseUrl',
    'mapHttpBaseUrl': 'rosBridgeUrl',
  };

  void _syncHost(String editedKey) {
    final otherKey = _pairedUrlKeys[editedKey];
    if (otherKey == null) {
      return;
    }
    final edited = Uri.tryParse(_c(editedKey).text.trim());
    final other = Uri.tryParse(_c(otherKey).text.trim());
    if (edited == null || other == null) {
      return;
    }
    // 주소가 아직 덜 적혔거나(호스트 없음) 이미 같으면 건드리지 않습니다.
    if (edited.host.isEmpty ||
        other.host.isEmpty ||
        edited.host == other.host) {
      return;
    }
    _c(otherKey).text = other.replace(host: edited.host).toString();
  }

  TextEditingController _c(String key) => _controllers[key]!;

  void _syncControllers(AppSettings settings) {
    final values = {
      'rosBridgeUrl': settings.rosBridgeUrl,
      'mapHttpBaseUrl': settings.mapHttpBaseUrl,
      'mapListRequestTopic': settings.mapListRequestTopic,
      'mapListTopic': settings.mapListTopic,
      'locationListRequestTopic': settings.locationListRequestTopic,
      'locationListTopic': settings.locationListTopic,
      'saveLocationTopic': settings.saveLocationTopic,
      'deleteLocationRequestTopic': settings.deleteLocationRequestTopic,
      'missionRequestService': settings.missionRequestService,
      'missionDeliveryService': settings.missionDeliveryService,
      'robotStatusTopic': settings.robotStatusTopic,
      'emergencyActivateService': settings.emergencyActivateService,
      'emergencyResetService': settings.emergencyResetService,
      'emergencyStateTopic': settings.emergencyStateTopic,
      'emergencyServiceTimeoutSeconds':
          settings.emergencyServiceTimeoutSeconds.toString(),
      'xOffset': settings.xOffset.toString(),
      'yOffset': settings.yOffset.toString(),
      'yawOffset': settings.yawOffset.toString(),
      'mapScale': settings.mapScale.toString(),
    };
    for (final entry in values.entries) {
      _controllers.putIfAbsent(
        entry.key,
        () => TextEditingController(text: entry.value),
      );
      if (_controllers[entry.key]!.text.isEmpty) {
        _controllers[entry.key]!.text = entry.value;
      }
    }
  }

  // 입력된 문자열을 AppSettings로 변환해 저장합니다.
  Future<void> save() async {
    final next = _settings.copyWith(
      rosBridgeUrl: _c('rosBridgeUrl').text.trim(),
      mapHttpBaseUrl: _c('mapHttpBaseUrl').text.trim(),
      mapListRequestTopic: _c('mapListRequestTopic').text.trim(),
      mapListTopic: _c('mapListTopic').text.trim(),
      locationListRequestTopic: _c('locationListRequestTopic').text.trim(),
      locationListTopic: _c('locationListTopic').text.trim(),
      saveLocationTopic: _c('saveLocationTopic').text.trim(),
      deleteLocationRequestTopic: _c('deleteLocationRequestTopic').text.trim(),
      missionRequestService: _c('missionRequestService').text.trim(),
      missionDeliveryService: _c('missionDeliveryService').text.trim(),
      robotStatusTopic: _c('robotStatusTopic').text.trim(),
      emergencyActivateService: _c('emergencyActivateService').text.trim(),
      emergencyResetService: _c('emergencyResetService').text.trim(),
      emergencyStateTopic: _c('emergencyStateTopic').text.trim(),
      emergencyServiceTimeoutSeconds:
          int.tryParse(_c('emergencyServiceTimeoutSeconds').text.trim()) ?? 8,
      xOffset: double.tryParse(_c('xOffset').text.trim()) ?? 0,
      yOffset: double.tryParse(_c('yOffset').text.trim()) ?? 0,
      yawOffset: double.tryParse(_c('yawOffset').text.trim()) ?? 0,
      mapScale: double.tryParse(_c('mapScale').text.trim()) ?? 1,
    );
    await context.read<SettingsProvider>().update(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장했습니다.')),
      );
    }
  }
}

/// 헤더(AppBar)에 놓는 저장 버튼입니다. 셸이 설정 화면일 때만 넣고, 누르면
/// [SettingsScreenState.save] 를 부릅니다. 앱바 높이에 맞춰 알약을 낮게 만듭니다.
class SettingsSaveButton extends StatelessWidget {
  const SettingsSaveButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.check, size: 18),
      label: const Text('저장'),
    );
  }
}

/// 원형 아이콘과 제목이 머리에 있고, 그 아래 행이 1px 선으로 나뉘는 카드입니다.
///
/// 선은 행 사이에만 긋습니다. 그룹 제목 바로 아래 행은 제목이 경계 노릇을
/// 하므로 선을 생략합니다 — 선과 제목이 겹치면 칸이 두 번 나뉜 것처럼 보입니다.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.children,
    this.expanded = true,
    this.onToggle,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  /// [onToggle] 이 있으면 접을 수 있는 카드입니다. 제목 줄 오른쪽에 화살표가
  /// 붙고, [expanded] 가 false 면 행을 그리지 않습니다.
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && children[i - 1] is! _GroupLabel) {
        items.add(
          const Divider(
            height: 1,
            thickness: 1,
            indent: 18,
            endIndent: 18,
            color: VicaColors.border,
          ),
        );
      }
      items.add(children[i]);
    }

    return VicaCard(
      padding: EdgeInsets.zero,
      // 행의 InkWell 물결은 '가장 가까운 Material' 위에 그려집니다. 카드 뒤의
      // Scaffold 가 그것이면 물결이 흰 카드에 가려 보이지 않으므로 카드 안에
      // 투명한 Material 을 한 겹 둡니다. 모서리로 물결이 새지 않게 잘라 냅니다.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kVicaCardRadius),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, 16, 18, expanded ? 8 : 16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: VicaColors.accentTint,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 20, color: VicaColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (onToggle != null)
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 22,
                        color: VicaColors.muted,
                      ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              ...items,
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

/// '라벨 · 값 · >' 한 줄입니다. [onTap] 이 없으면 값만 보여 주고 > 도 그리지 않습니다.
///
/// 라벨은 줄 폭의 60% 까지만 차지하고 그보다 길면 줄을 바꿉니다. 값은 남는
/// 폭을 오른쪽 정렬로 쓰고, 넘치면 말줄임표로 자릅니다 — 전체 값은 행을 탭해
/// 시트에서 봅니다. 값에게 폭을 먼저 주면 짧은 라벨도 두 줄로 접혀 표가
/// 울퉁불퉁해집니다.
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.technical = false,
    this.onTap,
  });

  final String label;
  final String value;
  final bool technical;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, color: VicaColors.text),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: technical ? VicaColors.muted : VicaColors.text,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: VicaColors.textTertiary,
              ),
            ],
          ],
        );
      },
    );
    final padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      child: row,
    );
    if (onTap == null) {
      return padded;
    }
    return InkWell(onTap: onTap, child: padded);
  }
}

/// 라벨과 스위치 한 줄입니다. 값 행과 같은 좌우 여백을 씁니다.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, color: VicaColors.text),
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: VicaColors.primary,
          ),
        ],
      ),
    );
  }
}

/// 고급 설정 안에서 topic·service 를 묶는 작은 그룹 제목입니다.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: VicaColors.textTertiary,
        ),
      ),
    );
  }
}

/// 행을 탭했을 때 뜨는 수정 시트입니다. 화면이 쓰던 입력칸을 그대로 담습니다.
class _EditSheet extends StatelessWidget {
  const _EditSheet({
    required this.controller,
    required this.label,
    required this.number,
    required this.unit,
  });

  final TextEditingController controller;
  final String label;
  final bool number;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 키보드가 올라오면 그만큼 아래를 비워 입력칸이 가려지지 않게 합니다.
      padding: EdgeInsets.fromLTRB(
        24,
        4,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            controller: controller,
            label: label,
            number: number,
            suffixText: unit,
            autofocus: true,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('확인'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.number = false,
    this.suffixText = '',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final bool number;
  final String suffixText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffixText.isEmpty ? null : suffixText,
        ),
      ),
    );
  }
}
