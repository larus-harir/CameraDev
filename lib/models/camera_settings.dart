class CameraSettings {
  final bool showCapturePreview;
  final bool askBeforeSaving;
  final bool showGrid;

  const CameraSettings({
    this.showCapturePreview = false,
    this.askBeforeSaving = false,
    this.showGrid = false,
  });

  CameraSettings copyWith({
    bool? showCapturePreview,
    bool? askBeforeSaving,
    bool? showGrid,
  }) =>
      CameraSettings(
        showCapturePreview: showCapturePreview ?? this.showCapturePreview,
        askBeforeSaving: askBeforeSaving ?? this.askBeforeSaving,
        showGrid: showGrid ?? this.showGrid,
      );
}
