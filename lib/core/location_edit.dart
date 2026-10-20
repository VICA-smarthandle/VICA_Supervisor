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
    confirmPrompt: sameName && original.confirmPrompt.isNotEmpty
        ? original.confirmPrompt
        : edited.confirmPrompt,
    arrivalMessage: sameName && original.arrivalMessage.isNotEmpty
        ? original.arrivalMessage
        : edited.arrivalMessage,
    contactPhone: edited.contactPhone,
    doorYaw: edited.doorYaw,
    waitSpot: edited.waitSpot,
  );
}
