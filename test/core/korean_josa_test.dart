// 장소 이름 뒤 조사 고르기(2026-11-14, 경비 화면의 '화장실로 가는 중'·'작업실을 뺐습니다').
import 'package:flutter_test/flutter_test.dart';
import 'package:vica_supervisor/core/korean_josa.dart';

void main() {
  test('로/으로 — 받침이 없거나 ㄹ 받침이면 로', () {
    expect(josaRo('입구'), '로');
    expect(josaRo('화장실'), '로');
    expect(josaRo('안내소'), '로');
    expect(josaRo('식당'), '으로');
    expect(josaRo('휴게실'), '로');
    expect(josaRo('민원실'), '로');
    expect(josaRo('창구'), '로');
    expect(josaRo('복도 끝'), '으로');
  });

  test('을/를', () {
    expect(josaEulReul('작업실'), '을');
    expect(josaEulReul('입구'), '를');
    expect(josaEulReul('식당'), '을');
    expect(josaEulReul('침입 감지'), '를');
    expect(josaEulReul('불 켜짐'), '을');
  });

  test('숫자로 끝나면 한자음으로 읽는다', () {
    // 방2(이), 407호 는 받침 없음. 방1(일)·방7(칠)·방8(팔)은 ㄹ 받침.
    expect(josaRo('방2'), '로');
    expect(josaRo('407호'), '로');
    expect(josaRo('방1'), '로');
    expect(josaRo('방3'), '으로');
    expect(josaRo('방6'), '으로');
    expect(josaRo('방10'), '으로');
    expect(josaEulReul('방2'), '를');
    expect(josaEulReul('방3'), '을');
    expect(josaEulReul('방1'), '을');
  });

  test('닫는 괄호는 건너뛰고 그 앞 글자를 본다', () {
    expect(josaRo('화장실(남)'), '으로');
    expect(josaEulReul('화장실(여)'), '를');
  });

  test('읽는 법을 모르는 글자로 끝나면 둘 다 적는다', () {
    expect(josaRo('Room A'), '(으)로');
    expect(josaEulReul('Lobby'), '을(를)');
    expect(josaRo(''), '(으)로');
  });
}
