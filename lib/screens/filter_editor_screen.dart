import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/filter_preset.dart';
import '../services/filter_service.dart';
import '../services/photo_storage_service.dart';
import '../widgets/filter_selector.dart';

class FilterEditorScreen extends StatefulWidget {
  final File source;
  const FilterEditorScreen({super.key, required this.source});
  @override
  State<FilterEditorScreen> createState() => _FilterEditorScreenState();
}

class _FilterEditorScreenState extends State<FilterEditorScreen> {
  final _filter = FilterService();
  final _storage = PhotoStorageService();
  Uint8List? _sourceBytes;
  String _id = 'preset_01';
  double _strength = 1.0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.source.readAsBytes().then((bytes) {
      if (mounted) setState(() => _sourceBytes = bytes);
    }).catchError((Object error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사진을 열지 못했습니다: $error')));
    });
  }

  Future<void> _save() async {
    if (_saving || _sourceBytes == null) return;
    setState(() => _saving = true);
    try {
      final result = await _filter.apply(_sourceBytes!, CameraFilters.byId(_id), _strength);
      await _storage.saveToGallery(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('필터 사진을 새 파일로 저장했습니다.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('사진 필터 편집'), actions: [
      TextButton(onPressed: _saving ? null : _save,
        child: Text(_saving ? '저장 중...' : '새 사진 저장')),
    ]),
    body: _sourceBytes == null
      ? const Center(child: CircularProgressIndicator())
      : Column(children: [
          Expanded(child: Center(child: ColorFiltered(
            colorFilter: CameraFilters.colorFilter(CameraFilters.byId(_id), _strength),
            child: Image.memory(_sourceBytes!, fit: BoxFit.contain),
          ))),
          FilterSelector(selectedId: _id, strength: _strength,
            onSelected: (v) => setState(() => _id = v),
            onStrengthChanged: (v) => setState(() => _strength = v)),
        ]),
  );
}
