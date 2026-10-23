import 'package:flutter/material.dart';
import 'dart:io';
import 'package:camera_android/camera_android.dart';
import 'package:flutter/services.dart';
import 'screens/camera_screen.dart';
import 'widgets/camera_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // CameraX's camera enumeration may hide independently openable lenses.
  // On Android, explicitly opt in to Flutter's Camera2 backend so that a
  // CameraDescription with a Camera2 ID opens that exact native camera ID.
  if (Platform.isAndroid) AndroidCamera.registerWith();
  // Render the dark camera body behind the Android gesture/navigation area.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));
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
