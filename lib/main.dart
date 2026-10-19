import 'package:flutter/material.dart';
import 'screens/camera_screen.dart';
import 'widgets/camera_chrome.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VintageCameraApp());
}

class VintageCameraApp extends StatelessWidget {
  const VintageCameraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Vintage Camera',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: CameraPalette.base,
          colorScheme: ColorScheme.fromSeed(
            seedColor: CameraPalette.brass,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: CameraPalette.panel,
            foregroundColor: CameraPalette.cream,
            titleTextStyle: TextStyle(fontSize: 16, letterSpacing: 1,
              color: CameraPalette.cream, fontWeight: FontWeight.w600),
          ),
          sliderTheme: const SliderThemeData(
            activeTrackColor: CameraPalette.brass,
            thumbColor: CameraPalette.brass,
          ),
          dividerColor: CameraPalette.stroke,
          snackBarTheme: const SnackBarThemeData(
            backgroundColor: CameraPalette.raised,
            contentTextStyle: TextStyle(color: CameraPalette.cream),
          ),
        ),
        home: const CameraScreen(),
      );
}
