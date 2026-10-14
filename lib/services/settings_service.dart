import 'package:shared_preferences/shared_preferences.dart';
import '../models/camera_settings.dart';

class SettingsService {
  Future<CameraSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CameraSettings(
      showCapturePreview: prefs.getBool('showCapturePreview') ?? false,
      askBeforeSaving: prefs.getBool('askBeforeSaving') ?? false,
      showGrid: prefs.getBool('showGrid') ?? false,
    );
  }

  Future<void> save(CameraSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showCapturePreview', settings.showCapturePreview);
    await prefs.setBool('askBeforeSaving', settings.askBeforeSaving);
    await prefs.setBool('showGrid', settings.showGrid);
  }
}
