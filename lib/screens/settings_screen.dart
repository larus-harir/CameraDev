import 'package:flutter/material.dart';
import '../models/camera_settings.dart';

class SettingsScreen extends StatefulWidget {
  final CameraSettings initialSettings;
  final Future<void> Function(CameraSettings) onSave;

  const SettingsScreen({super.key, required this.initialSettings, required this.onSave});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late CameraSettings settings;

  @override
  void initState() {
    super.initState();
    settings = widget.initialSettings;
  }

  Future<void> update(CameraSettings value) async {
    setState(() => settings = value);
    await widget.onSave(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('설정')),
        body: ListView(
          children: [
            const _Header('촬영 후 동작'),
            SwitchListTile(
              title: const Text('촬영 후 미리보기'),
              subtitle: const Text('켜면 촬영한 사진을 확인하고 저장할 수 있어요.'),
              value: settings.showCapturePreview,
              onChanged: (v) => update(settings.copyWith(showCapturePreview: v)),
            ),
            SwitchListTile(
              title: const Text('저장 전 확인'),
              subtitle: const Text('미리보기가 꺼져 있어도 저장 여부를 확인합니다.'),
              value: settings.askBeforeSaving,
              onChanged: (v) => update(settings.copyWith(askBeforeSaving: v)),
            ),
            const Divider(),
            const _Header('저장 옵션'),
            SwitchListTile(
              title: const Text('필터 + 원본 동시 저장'),
              subtitle: const Text('켜면 필터 적용본과 원본을 각각 저장합니다. Original은 1개만 저장합니다. 동영상은 필터 인코딩 후 저장되므로 시간이 걸릴 수 있습니다.'),
              value: settings.saveOriginalAlongsideFilter,
              onChanged: (v) => update(settings.copyWith(saveOriginalAlongsideFilter: v)),
            ),
            const Divider(),
            const _Header('촬영 화면'),
            SwitchListTile(
              title: const Text('3분할 그리드'),
              value: settings.showGrid,
              onChanged: (v) => update(settings.copyWith(showGrid: v)),
            ),
          ],
        ),
      );
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text, style: const TextStyle(color: Color(0xFFD8B88A), fontWeight: FontWeight.bold)),
      );
}
