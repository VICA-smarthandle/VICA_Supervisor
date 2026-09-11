import 'package:flutter/material.dart';

import '../widgets/vica_ui.dart';

/// 결함 등급. RobotFault.msg의 SEVERITY_* 상수와 값이 같습니다.
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
String componentLabel(String component) {
  const labels = {
    'motor': '모터',
    'safety': '안전 제어',
    'localization': '위치 추정',
    'navigation': '자율 주행',
    'lidar': 'LiDAR',
    'perception': '3D 인식',
    'guidance': '안내 장치',
    'voice': '음성',
    'app': '앱 연결',
    'computer': '컴퓨터',
    'monitor': '상태 감시',
  };
  return labels[component] ?? component;
}
