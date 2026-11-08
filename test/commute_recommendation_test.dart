import 'package:flutter_test/flutter_test.dart';
import 'package:tamaraw_time/src/commute.dart';

void main() {
  test('driving buffer defaults to 30 minutes and applies only to driving', () {
    expect(trafficBufferMinutes(const {}), 30);
    expect(drivingAdjustedMinutes(22, const {}), 52);
    expect(drivingAdjustedMinutes(22, const {'trafficBufferMinutes': 15}), 37);
  });

  test('custom driving buffer stays bounded and does not mutate estimates', () {
    const settings = {'trafficBufferMinutes': 45};
    expect(drivingAdjustedMinutes(18, settings), 63);
    expect(trafficBufferMinutes(const {'trafficBufferMinutes': 999}), 480);
    expect(trafficBufferMinutes(const {'trafficBufferMinutes': -1}), 0);
  });
}
