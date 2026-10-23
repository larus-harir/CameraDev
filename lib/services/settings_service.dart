import 'package:shared_preferences/shared_preferences.dart';
import '../models/camera_settings.dart';
import '../models/camera_style.dart';

class CameraLookSelection {
  final CameraStyle style;
  final String digitalId;
  final String filmId;
  final double digitalStrength;
  final double filmStrength;
  const CameraLookSelection({
    required this.style,
    required this.digitalId,
    required this.filmId,
    required this.digitalStrength,
    required this.filmStrength,
  });
}

class SettingsService {
  Future<int> loadFilmCounter() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt('filmFrameCounter') ?? 1).clamp(1, 9999).toInt();
  }

  Future<void> saveFilmCounter(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('filmFrameCounter', count);
  }

  Future<CameraLookSelection> loadLook() async {
    final prefs = await SharedPreferences.getInstance();
    // Old CH.3 filter settings are migrated to the film side.
    return CameraLookSelection(
      style: prefs.getString('cameraStyle') == 'film'
          ? CameraStyle.film : CameraStyle.digital,
      digitalId: prefs.getString('digitalFilterId') ?? 'digital_s',
      filmId: prefs.getString('filmFilterId') ?? prefs.getString('filterId') ?? 'preset_01',
      digitalStrength: (prefs.getDouble('digitalStrength') ?? 1.0).clamp(0.0, 1.0).toDouble(),
      filmStrength: (prefs.getDouble('filmStrength') ?? prefs.getDouble('filterStrength') ?? 1.0).clamp(0.0, 1.0).toDouble(),
    );
  }

  Future<void> saveLook(CameraLookSelection look) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cameraStyle', look.style.name);
    await prefs.setString('digitalFilterId', look.digitalId);
    await prefs.setString('filmFilterId', look.filmId);
    await prefs.setDouble('digitalStrength', look.digitalStrength);
    await prefs.setDouble('filmStrength', look.filmStrength);
  }

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
      addFilmFrameToExports: prefs.getBool('addFilmFrameToExports') ?? true,
      addDigitalFrameToExports: prefs.getBool('addDigitalFrameToExports') ?? true,
    );
  }

  Future<void> save(CameraSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showCapturePreview', settings.showCapturePreview);
    await prefs.setBool('askBeforeSaving', settings.askBeforeSaving);
    await prefs.setBool('showGrid', settings.showGrid);
    await prefs.setBool('saveOriginalAlongsideFilter', settings.saveOriginalAlongsideFilter);
    await prefs.setBool('addFilmFrameToExports', settings.addFilmFrameToExports);
    await prefs.setBool('addDigitalFrameToExports', settings.addDigitalFrameToExports);
  }
}
