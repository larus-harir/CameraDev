import 'package:shared_preferences/shared_preferences.dart';
import '../models/camera_settings.dart';

class SettingsService {
  Future<(String, double)> loadFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('filterId') ?? 'original',
      (prefs.getDouble('filterStrength') ?? 1.0).clamp(0.0, 1.0));
  }

  Future<void> saveFilter(String id, double strength) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('filterId', id);
    await prefs.setDouble('filterStrength', strength);
  }

  Future<CameraSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return CameraSettings(
      showCapturePreview: prefs.getBool('showCapturePreview') ?? false,
      askBeforeSaving: prefs.getBool('askBeforeSaving') ?? false,
      showGrid: prefs.getBool('showGrid') ?? false,
      saveOriginalAlongsideFilter: prefs.getBool('saveOriginalAlongsideFilter') ?? false,
    );
  }

  Future<void> save(CameraSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showCapturePreview', settings.showCapturePreview);
    await prefs.setBool('askBeforeSaving', settings.askBeforeSaving);
    await prefs.setBool('showGrid', settings.showGrid);
    await prefs.setBool('saveOriginalAlongsideFilter', settings.saveOriginalAlongsideFilter);
  }
}
