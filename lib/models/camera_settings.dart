class CameraSettings {
  final bool showCapturePreview;
  final bool askBeforeSaving;
  final bool showGrid;
  final bool saveOriginalAlongsideFilter;
  final bool addFilmFrameToExports;
  final bool addDigitalFrameToExports;

  const CameraSettings({
    this.showCapturePreview = false,
    this.askBeforeSaving = false,
    this.showGrid = false,
    this.saveOriginalAlongsideFilter = false,
    this.addFilmFrameToExports = false,
    this.addDigitalFrameToExports = false,
  });

  CameraSettings copyWith({
    bool? showCapturePreview,
    bool? askBeforeSaving,
    bool? showGrid,
    bool? saveOriginalAlongsideFilter,
    bool? addFilmFrameToExports,
    bool? addDigitalFrameToExports,
  }) =>
      CameraSettings(
        showCapturePreview: showCapturePreview ?? this.showCapturePreview,
        askBeforeSaving: askBeforeSaving ?? this.askBeforeSaving,
        showGrid: showGrid ?? this.showGrid,
        saveOriginalAlongsideFilter: saveOriginalAlongsideFilter ?? this.saveOriginalAlongsideFilter,
        addFilmFrameToExports: addFilmFrameToExports ?? this.addFilmFrameToExports,
        addDigitalFrameToExports: addDigitalFrameToExports ?? this.addDigitalFrameToExports,
      );
}
