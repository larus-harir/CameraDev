import 'package:flutter/material.dart';
import 'screens/camera_screen.dart';

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
          scaffoldBackgroundColor: Colors.black,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFD8B88A),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const CameraScreen(),
      );
}
