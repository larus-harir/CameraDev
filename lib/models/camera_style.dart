/// The visual camera body is independent from photo/video capture.
enum CameraStyle { digital, film }

extension CameraStyleLabels on CameraStyle {
  String get title => this == CameraStyle.digital ? 'DIGITAL' : 'FILM';
  String get subtitle => this == CameraStyle.digital ? 'DIGICAM / 2000s' : '35MM / ANALOG';
}
