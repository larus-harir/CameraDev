class CameraSettings {
  final bool showCapturePreview;
  final bool askBeforeSaving;
  final bool showGrid;
  final bool saveOriginalAlongsideFilter;

  const CameraSettings({
    this.showCapturePreview = false,
    this.askBeforeSaving = false,
    this.showGrid = false,
    this.saveOriginalAlongsideFilter = false,
  });

  CameraSettings copyWith({
    bool? showCapturePreview,
    bool? askBeforeSaving,
    bool? showGrid,
    bool? saveOriginalAlongsideFilter,
  }) =>
      CameraSettings(
        showCapturePreview: showCapturePreview ?? this.showCapturePreview,
        askBeforeSaving: askBeforeSaving ?? this.askBeforeSaving,
        showGrid: showGrid ?? this.showGrid,
        saveOriginalAlongsideFilter: saveOriginalAlongsideFilter ?? this.saveOriginalAlongsideFilter,
      );
}
