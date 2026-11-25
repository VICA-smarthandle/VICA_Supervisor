# 매니퓰레이터(나노 로봇팔) — 앱 연동과 시연 점검 (2026-11-25)

## 경로

```
앱 물류 배송 [동작]  → rosbridge → /app/arm_demo (도메인 7, ros2/arm_relay_node.py)
                                  → 랜선 → /arm/demo  (도메인 77, 나노 vica-arm 서비스)
응답 message 를 앱이 그대로 보여 줍니다. '홈 복귀 실패'가 있으면 [홈으로](→ /arm/home)가 나옵니다.
```

| 앱 서비스 | 나노 서비스 | 중계 대기 | 앱 대기 | 근거 |
|---|---|---|---|---|
| /app/arm_demo | /arm/demo | 360 s | 370 s | 나노 DEMO_TIMEOUT 180 s + 실패 뒤 저속 홈 최대 150 s |
| /app/arm_home | /arm/home | 160 s | 170 s | 비상정지 중 저속 홈 최대 150 s |
| /app/arm_status | /arm/status | 5 s | — | 앱은 부르지 않음(점검용) |

## 시연 당일 점검 (순서대로)

1. 랜선(NX 10.77.0.1 ↔ 나노 10.77.0.2) 꽂힘·고정 확인 → **물리 비상정지 버튼이 풀려 있는지** 확인 → 전원.
2. `/estop_state` 가 false (NX emergency_stop_node, 약 20 Hz).
   - 켤 때 통신 원인(motor_can_waiting)만 있으면 정지 중 3~4 s 안에 저절로 풀립니다(AutoRecoveryPolicy, 11-25 로그 13:25·14:16).
   - 버튼이 눌린 채 켰으면(11-25 12:54 부팅) 저절로 안 풀립니다 → 버튼을 풀고 앱에서 Safety reset 1회.
   - 래치 중 [동작]은 나노가 '거절: 비상정지 중'으로 답합니다.
3. `ROS_DOMAIN_ID=77 ros2 service call /arm/status std_srvs/srv/Trigger`
   → '대기 중 · 비상정지 꺼짐(도메인 7)'.
4. 팔 앞을 비우고 앱 [동작] 1회 → '시연 완료(…) → 홈'.

## 알아 둘 것

- 비상정지가 켜지면 팔은 멈춘 뒤 손끝을 6 cm 빼고 **저속으로 홈에 갑니다** — 비상정지 중에도 천천히 움직입니다.
- 랜선이 끊긴 동안 새로 뜬 NX 노드는 랜선이 돌아와도 나노를 못 찾습니다(Fast DDS 는 뜰 때 있던 주소로만 소켓을 엶).
  그때는 중계만 다시 띄웁니다: 중계 프로세스에 SIGINT → launch 가 3 s 뒤 다시 띄움.
- [홈으로]까지 실패하면 현장에서 팔을 받친 뒤 힘 빼기(나노 `~/vica_arm_kit/COMMANDS.txt` 5절). 앱에는 힘 빼기가 없습니다.
