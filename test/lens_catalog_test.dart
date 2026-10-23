import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vintage_camera/services/lens_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS camera plugin lensType is preserved by the common lens layer', () async {
    final cameras = <CameraDescription>[
      const CameraDescription(name: 'wide',
          lensDirection: CameraLensDirection.back, sensorOrientation: 90,
          lensType: CameraLensType.wide),
      const CameraDescription(name: 'ultrawide',
          lensDirection: CameraLensDirection.back, sensorOrientation: 90,
          lensType: CameraLensType.ultraWide),
      const CameraDescription(name: 'tele',
          lensDirection: CameraLensDirection.back, sensorOrientation: 90,
          lensType: CameraLensType.telephoto),
      const CameraDescription(name: 'front',
          lensDirection: CameraLensDirection.front, sensorOrientation: 270),
    ];
    final catalog = await LensCatalog.detect(cameras);
    expect(catalog.forId('ultrawide')!.title, contains('초광각'));
    expect(catalog.forId('tele')!.title, contains('망원'));
    expect(catalog.forId('wide')!.opticalFactor, 1.0);
    expect(catalog.forId('front')!.direction, CameraLensDirection.front);
    expect(catalog.choices.length, 4);
  });
}
