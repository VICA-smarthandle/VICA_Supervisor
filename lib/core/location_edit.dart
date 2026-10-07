// 이 파일은 저장된 장소를 고쳐 다시 저장할 때 무엇을 지킬지 정합니다.
//
// 확인 멘트·도착 멘트는 파일에서 손으로 다듬는 일이 있습니다. 수정 저장이 그것을 매번
// 덮으면 관리자가 연락처 하나 고칠 때마다 멘트가 되돌아갑니다. 그래서 **이름이 그대로면
// 원래 멘트를 지키고**, 이름이 바뀌었을 때만 새 값(지금은 빈 값)을 씁니다(사용자 결정
// 2026-09-03). id 와 지도도 원본을 따릅니다 — 바뀌면 같은 장소가 둘이 됩니다.
//
// 2026-10-07: 앱은 멘트를 더 만들지 않습니다("$name으로 …"는 받침 없는 이름에서 조사가
// 틀렸습니다). 비워 두면 로봇이 조사를 맞춰 채웁니다. 입구 방향·대기 장소는 화면에서
// 고친 값을 그대로 씁니다.
import '../models/location_point.dart';

LocationPoint mergeEditedLocation({
  required LocationPoint edited,
  required LocationPoint? original,
}) {
  if (original == null) {
    return edited;
  }
  final sameName = original.name.trim() == edited.name.trim();
  return LocationPoint(
    locationId: original.locationId,
    mapId: original.mapId,
    name: edited.name,
    aliases: edited.aliases,
    category1: edited.category1,
    category2: edited.category2,
    building: edited.building,
    floor: edited.floor,
    owner: edited.owner,
    authorization: edited.authorization,
    isApproachable: edited.isApproachable,
    unavailableReason: edited.unavailableReason,
    frameId: original.frameId,
    x: edited.x,
    y: edited.y,
    yaw: edited.yaw,
    // 옛 파일에 멘트가 비어 있으면 새로 만든 것을 쓴다. 비워 두면 음성이 할 말이 없다.
    confirmPrompt: sameName && original.confirmPrompt.isNotEmpty
        ? original.confirmPrompt
        : edited.confirmPrompt,
    arrivalMessage: sameName && original.arrivalMessage.isNotEmpty
        ? original.arrivalMessage
        : edited.arrivalMessage,
    contactPhone: edited.contactPhone,
    doorYaw: edited.doorYaw,
    // 대기 장소는 정보 시트에서 고치지 않습니다(지도 설정의 대기 장소 칸에서만).
    // 시트가 만든 edited 에는 원본 것이 실려 오므로 그대로 씁니다.
    waitSpot: edited.waitSpot,
  );
}
