// 이 파일은 로봇 진단 등급과 준비 상태의 표시 규칙을 정의합니다.
//
// 값은 vica_interfaces의 RobotFault.SEVERITY_*, RobotHealth.READINESS_*,
// RobotHealth.STATE_*와 같아야 합니다. 로봇 쪽이 바뀌면 여기도 함께 바꿔야 합니다.
//
// 문구 자체는 로봇이 만들어 보냅니다(fault.detail, fault.suggestedAction).
// 이 파일은 등급 이름과 색상만 정합니다.
import 'package:flutter/material.dart';

import '../widgets/vica_ui.dart';

/// 결함 등급. RobotFault.msg의 SEVERITY_* 상수와 값이 같습니다.
///
/// **비상 정지는 이 축에 없습니다.** E-stop은 STOP보다 한 단계 심각한 것이 아니라
/// 종류가 다릅니다 — 래치가 걸리고 관리자 reset이 있어야 풀리며 emergency_stop_node가
/// 소유합니다. 그 사실은 [RobotHealthState.estopped]와 RobotFault.latched가 나타냅니다.
/// 등급에 섞으면 모터 진단 하나가 "비상 정지"로 표시되어 관리자가 있지도 않은 버튼을
/// 찾게 됩니다.
enum FaultSeverity {
  ok(0, 'OK', '정상'),
  warn(1, 'WARN', '주의'),
  degraded(2, 'DEGRADED', '기능 저하'),
  stop(3, 'STOP', '주행 불가'),
  fault(4, 'FAULT', '원인 불명');

  const FaultSeverity(this.value, this.code, this.label);

  final int value;

  /// 로그·개발자용 영문 코드.
  final String code;

  /// 관리자에게 보여주는 한국어 이름.
  final String label;

  /// 알 수 없는 값은 fault로 봅니다. 조용히 ok로 떨어뜨리면 위험을 놓칩니다.
  static FaultSeverity fromValue(int value) {
    for (final severity in FaultSeverity.values) {
      if (severity.value == value) {
        return severity;
      }
    }
    return FaultSeverity.fault;
  }

  /// 주행을 막는 등급인지. 앱은 이 값으로 판정하지 않고 표시만 합니다.
  bool get blocksDriving => value >= FaultSeverity.stop.value;

  Color get color {
    switch (this) {
      case FaultSeverity.ok:
        return VicaColors.green;
      case FaultSeverity.warn:
        return const Color(0xFFE0A800);
      case FaultSeverity.degraded:
        return const Color(0xFFE07B39);
      case FaultSeverity.stop:
      case FaultSeverity.fault:
        return VicaColors.red;
    }
  }

  IconData get icon {
    switch (this) {
      case FaultSeverity.ok:
        return Icons.check_circle_outline;
      case FaultSeverity.warn:
        return Icons.info_outline;
      case FaultSeverity.degraded:
        return Icons.warning_amber_outlined;
      case FaultSeverity.stop:
        return Icons.do_not_disturb_on_outlined;
      case FaultSeverity.fault:
        return Icons.help_outline;
    }
  }
}

/// 컴포넌트 준비 상태. RobotHealth.msg의 READINESS_* 상수와 값이 같습니다.
///
/// [unknown]은 "정상"이 아니라 **관측 수단이 없다**는 뜻입니다. 예를 들어 Smart Handle은
/// 아두이노에서 젯슨으로 올라오는 통신이 없어 서보·LED·진동이 실제로 동작했는지 확인할
/// 방법이 없습니다. 이것을 초록불로 표시하면 관리자에게 잘못된 안심을 줍니다.
enum ComponentReadiness {
  unknown(0, '관측 불가'),
  notReady(1, '준비 안 됨'),
  ready(2, '정상');

  const ComponentReadiness(this.value, this.label);

  final int value;
  final String label;

  /// 알 수 없는 값은 unknown으로 봅니다.
  static ComponentReadiness fromValue(int value) {
    for (final readiness in ComponentReadiness.values) {
      if (readiness.value == value) {
        return readiness;
      }
    }
    return ComponentReadiness.unknown;
  }

  Color get color {
    switch (this) {
      case ComponentReadiness.unknown:
        return VicaColors.muted;
      case ComponentReadiness.notReady:
        return VicaColors.red;
      case ComponentReadiness.ready:
        return VicaColors.green;
    }
  }
}

/// 로봇 전체 상태. RobotHealth.msg의 STATE_* 상수와 값이 같습니다.
enum RobotHealthState {
  starting(0, '기동 중'),
  ready(1, '준비 완료'),
  degraded(2, '일부 기능 저하'),
  stopped(3, '주행 불가'),
  estopped(4, '비상 정지'),
  fault(5, '원인 불명');

  const RobotHealthState(this.value, this.label);

  final int value;
  final String label;

  /// 알 수 없는 값은 fault로 봅니다.
  static RobotHealthState fromValue(int value) {
    for (final state in RobotHealthState.values) {
      if (state.value == value) {
        return state;
      }
    }
    return RobotHealthState.fault;
  }

  Color get color {
    switch (this) {
      case RobotHealthState.starting:
        return VicaColors.muted;
      case RobotHealthState.ready:
        return VicaColors.green;
      case RobotHealthState.degraded:
        return const Color(0xFFE07B39);
      case RobotHealthState.stopped:
      case RobotHealthState.estopped:
      case RobotHealthState.fault:
        return VicaColors.red;
    }
  }
}

/// 컴포넌트 이름을 관리자에게 보여줄 한국어로 바꿉니다.
///
/// 로봇이 보내는 이름은 fault_catalog.py의 COMPONENTS와 같습니다. 모르는 이름은
/// 버리지 않고 원문을 그대로 보여줍니다 — 새 컴포넌트가 추가됐을 때 조용히 사라지면
/// 안 됩니다.
String componentLabel(String component) {
  const labels = {
    'motor': '모터',
    'safety': '안전 제어',
    'localization': '위치 추정',
    'navigation': '자율 주행',
    'lidar': 'LiDAR',
    // nvblox 를 쓰지 않게 되면서 감시 대상이 카메라 점군으로 바뀌었습니다
    // (2026-08-31). 컴포넌트 키는 그대로 perception 입니다 — RobotHealth.msg 의
    // perception_readiness 필드 이름이라 바꾸면 세 저장소 계약이 흔들립니다.
    'perception': '카메라 인식',
    // '안내 장치'에서 바꿨습니다(2026-09-02 실기). 아두이노 하나에 핸들 안내와
    // 초음파가 함께 물려 있어, 이 항목이 빨개지면 둘 다 멈춘 것입니다. 이름이
    // 그것을 바로 말해 줘야 관리자가 무엇을 잃었는지 압니다.
    'guidance': '핸들 및 초음파',
    // 이 항목은 **노드가 떠 있는지만** 봅니다(2026-09-02 사용자 판정).
    // 노드가 멀쩡히 실행 중이어도 마이크에서 소리가 안 들어올 수 있고, 그때
    // "멈춰"를 외쳐도 로봇은 못 듣습니다. 오디오는 ROS 토픽이 아니라 콜백
    // 안으로 직행해 밖에서는 볼 수 없습니다(vica_architecture.md 13.3절).
    //
    // 그 한계를 이름에 적습니다. 결함 문구에만 적으면 **정상일 때는 안 보여서**
    // 초록불이 "음성 정상"으로 읽힙니다 — 이 앱이 가장 피해야 하는 오해입니다.
    // 마이크 입력 카운터가 음성 노드에 들어오면 괄호를 뗍니다.
    'voice': '음성 (노드 실행만 확인)',
    'app': '앱 연결',
    'computer': '컴퓨터',
    'monitor': '상태 감시',
  };
  return labels[component] ?? component;
}
