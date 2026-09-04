// 이 파일은 원격 제어 없이 선택한 로봇의 현재 위치와 주행 상태를 지도 위에 표시합니다.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/robot_status.dart';
import '../models/vica_map.dart';
import '../providers/settings_provider.dart';
import '../providers/supervisor_provider.dart';
import '../ros/ros_bridge_client.dart';
import '../widgets/map_canvas.dart';
import '../widgets/vica_ui.dart';

class CurrentLocationScreen extends StatefulWidget {
  const CurrentLocationScreen({super.key});

  @override
  State<CurrentLocationScreen> createState() => _CurrentLocationScreenState();
}

class _CurrentLocationScreenState extends State<CurrentLocationScreen> {
  static const _compactDropdownDecoration = InputDecoration(
    labelText: '연결된 로봇',
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  );

  String? _selectedRobotId;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final supervisor = context.watch<SupervisorProvider>();
    final robots = supervisor.robots;
    final robot = _selectedRobot(robots);
    final map = robot == null
        ? supervisor.selectedMap
        : _findMapById(supervisor.maps, robot.mapId);
    final locations = supervisor.locationsFor(map?.mapId);

    return VicaPage(
      title: '현재 위치',
      children: [
        if (supervisor.connectionState != RosConnectionState.connected)
          VicaDisconnectedNotice(detail: supervisor.connectionDetail),
        VicaCard(
          child: DropdownButtonFormField<String>(
            initialValue: robot?.robotId,
            decoration: _compactDropdownDecoration,
            // isExpanded가 없으면 드롭다운이 로봇 이름의 원래 폭을 그대로 요구해
            // 좁은 창에서 카드 밖으로 179px까지 삐져나갔습니다.
            isExpanded: true,
            items: robots
                .map(
                  (item) => DropdownMenuItem(
                    value: item.robotId,
                    child: Text(
                      item.robotName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: robots.isEmpty
                ? null
                : (value) => setState(() => _selectedRobotId = value),
          ),
        ),
        ResponsiveMapFrame(
          map: map,
          child: map == null
              ? const ColoredBox(
                  color: VicaColors.softBlue,
                  child: Center(child: Text('현재 map_id와 일치하는 지도가 없습니다.')),
                )
              : MapCanvas(
                  map: map,
                  settings: settings,
                  locations: locations,
                  robot: robot,
                ),
        ),
        const SizedBox(height: 16),
        if (robot == null)
          const VicaCard(child: Text('아직 로봇 상태를 수신하지 않았습니다.'))
        else
          VicaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(robot.robotName,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 14),
                VicaInfoRow(label: 'x', value: robot.x.toStringAsFixed(3)),
                VicaInfoRow(label: 'y', value: robot.y.toStringAsFixed(3)),
                VicaInfoRow(label: 'yaw', value: robot.yaw.toStringAsFixed(2)),
                VicaInfoRow(label: 'map_id', value: robot.mapId),
                VicaInfoRow(label: '현재 위치명', value: robot.currentLocation),
                VicaInfoRow(label: '목적지', value: robot.currentGoal),
                VicaInfoRow(label: '주행 상태', value: robot.status),
                VicaInfoRow(label: '오류 사유', value: robot.errorReason),
                VicaInfoRow(label: '대기 사유', value: robot.waitingReason),
                VicaInfoRow(
                  label: '마지막 수신',
                  value: robot.timestamp.toLocal().toString(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  RobotStatus? _selectedRobot(List<RobotStatus> robots) {
    if (robots.isEmpty) {
      return null;
    }
    for (final robot in robots) {
      if (robot.robotId == _selectedRobotId) {
        return robot;
      }
    }
    return robots.first;
  }

  VicaMap? _findMapById(List<VicaMap> maps, String mapId) {
    for (final map in maps) {
      if (map.mapId == mapId) {
        return map;
      }
    }
    return null;
  }
}
