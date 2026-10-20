import 'package:flutter_test/flutter_test.dart';
import 'package:raad/services/app_version.dart';

void main() {
  test('0.4.2 release is newer than the previous installed build', () {
    expect(AppVersion.compare('v0.4.2', '0.4.1+5'), 1);
    expect(AppVersion.isNewer('v0.4.2', '0.4.1+5'), isTrue);
    expect(AppVersion.isValid('0.4.2'), isTrue);
  });

  test('a newer patch release is detected when build numbers differ', () {
    expect(AppVersion.compare('v0.4.1', '0.4.0+4'), 1);
    expect(AppVersion.isNewer('v0.4.1', '0.4.0+4'), isTrue);
  });

  test('build metadata does not incorrectly mark the same release as newer', () {
    expect(AppVersion.compare('v0.4.1', '0.4.1+5'), 0);
    expect(AppVersion.isNewer('v0.4.1', '0.4.1+5'), isFalse);
  });

  test('numeric components compare numerically rather than lexically', () {
    expect(AppVersion.compare('v0.4.10', '0.4.9+5'), 1);
    expect(AppVersion.compare('v1.0.0', '0.99.99'), 1);
  });

  test('older release is not advertised as an update', () {
    expect(AppVersion.compare('v0.3.9', '0.4.0+4'), -1);
    expect(AppVersion.isNewer('v0.3.9', '0.4.0+4'), isFalse);
  });

  test('malformed release tags are not silently converted to version zero', () {
    expect(AppVersion.isValid('latest'), isFalse);
    expect(AppVersion.compare('latest', '0.4.0+4'), isNull);
  });
}
