import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manhua_reader/services/screen_awake.dart';
import 'package:manhua_reader/services/volume_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asks the platform to keep the screen awake', () async {
    const channel = MethodChannel('manhua/screen');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await ScreenAwake.setEnabled(true);
    await ScreenAwake.setEnabled(false);

    expect(calls.map((call) => call.method), [
      'setKeepScreenOn',
      'setKeepScreenOn',
    ]);
    expect(calls.map((call) => call.arguments), [true, false]);
  });

  test('enables Android volume keys and routes page events', () async {
    const channel = MethodChannel('manhua/reader');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      VolumeKeys.stop();
      messenger.setMockMethodCallHandler(channel, null);
    });

    await VolumeKeys.setEnabled(true);
    expect(calls.single.method, 'setVolumeKeysEnabled');
    expect(calls.single.arguments, true);

    var next = 0;
    var previous = 0;
    VolumeKeys.listen(onNext: () => next++, onPrevious: () => previous++);
    final codec = const StandardMethodCodec();
    await messenger.handlePlatformMessage(
      'manhua/reader',
      codec.encodeMethodCall(const MethodCall('nextPage')),
      (_) {},
    );
    await messenger.handlePlatformMessage(
      'manhua/reader',
      codec.encodeMethodCall(const MethodCall('previousPage')),
      (_) {},
    );
    expect(next, 1);
    expect(previous, 1);
  });
}
