import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/filter_preset.dart';

/// Export-only video filter. Approximates the Lightroom-inspired photo preset.
/// FFmpeg color filters are not pixel-identical to the photo engine.
class VideoFilterService {
  Future<String> render(String input, FilterPreset preset, double strength,
      {String ratio = '16:9', bool portrait = true, Uint8List? frameArtwork}) async {
    final hasColorFilter = preset.id != 'original' && strength > 0;
    // CameraX's default video output is 16:9. Avoid transcoding untouched
    // recordings in the common Original + 16:9 case.
    if (!hasColorFilter && ratio == '16:9' && frameArtwork == null) return input;
    final amount = strength.clamp(0.0, 1.0);
    final dir = await getTemporaryDirectory();
    final output = p.join(dir.path, 'export_${DateTime.now().microsecondsSinceEpoch}.mp4');
    final exposure = (preset.exposure * amount / 5).clamp(-1.0, 1.0);
    final contrast = (1 + (preset.contrast + preset.dehaze * 0.3 + preset.clarity * 0.2) * amount / 100).clamp(0.2, 2.0);
    final saturation = (1 + (preset.saturation + preset.vibrance * 0.4) * amount / 100).clamp(0.0, 3.0);
    final gamma = (1 + (preset.shadows * 0.2 - preset.highlights * 0.2) * amount / 100).clamp(0.5, 2.0);
    final red = ((preset.temperature + preset.tint * 0.35) * amount / 300).clamp(-1.0, 1.0);
    final green = (-preset.tint * amount / 300).clamp(-1.0, 1.0);
    final blue = ((-preset.temperature + preset.tint * 0.35) * amount / 300).clamp(-1.0, 1.0);
    final brightness = (exposure + (preset.whites + preset.blacks) * amount / 1200).clamp(-1.0, 1.0);
    final filters = <String>[];
    // FFmpeg applies the camera recording's display rotation on decode, so
    // choose the frame ratio using the UI orientation frozen at record start.
    final ratioValue = switch (ratio) {
      '4:3' => portrait ? 3 / 4 : 4 / 3,
      '1:1' => 1.0,
      _ => portrait ? 9 / 16 : 16 / 9,
    };
    final desired = ratioValue.toStringAsFixed(7);
    // Center crop and ensure even dimensions for yuv420p/H.264.
    // In a -vf argument, single-quoted FFmpeg expressions protect commas.
    filters.add("crop=w='trunc(min(iw,ih*$desired)/2)*2':"
        "h='trunc(min(ih,iw/$desired)/2)*2'");
    filters.add('setsar=1');
    if (hasColorFilter) {
      filters.add('eq=brightness=$brightness:contrast=$contrast:saturation=$saturation:gamma=$gamma');
      filters.add('colorbalance=rs=$red:gs=$green:bs=$blue');
    }
    final vignette = (-preset.vignette * amount / 100).clamp(0.0, 1.0);
    if (hasColorFilter && vignette > 0.001) filters.add('vignette=angle=${(0.15 + vignette * 0.6).toStringAsFixed(3)}');
    final grain = (preset.grain * amount * 0.4).round().clamp(0, 40);
    if (hasColorFilter && grain > 0) filters.add('noise=alls=$grain:allf=t');
    // Never upscale an already cropped clip (better speed and quality).
    // Only limit dimensions above 1920x1080.
    filters.add("scale=w='min(iw,1920)':h='min(ih,1080)':"
        'force_original_aspect_ratio=decrease:force_divisible_by=2');
    final vf = filters.join(',');
    String quote(String value) => '"${value.replaceAll('"', '\\"')}"';
    String? overlayPath;
    if (frameArtwork != null) {
      overlayPath = p.join(dir.path, 'frame_${DateTime.now().microsecondsSinceEpoch}.png');
      await File(overlayPath).writeAsBytes(frameArtwork, flush: true);
    }
    final command = overlayPath == null
        ? '-hide_banner -loglevel error -y -i ${quote(input)} '
          '-vf ${quote(vf)} -map 0:v:0 -map 0:a? -c:v libx264 -preset veryfast '
          '-crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart ${quote(output)}'
        : '-hide_banner -loglevel error -y -i ${quote(input)} -loop 1 -i ${quote(overlayPath)} '
          '-filter_complex ${quote('[0:v]$vf[base];[1:v][base]scale2ref=w=main_w:h=main_h[ov][scaled];'
              '[scaled][ov]overlay=x=0:y=0:shortest=1,format=yuv420p[out]')} '
          '-map [out] -map 0:a? -c:v libx264 -preset veryfast '
          '-crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart ${quote(output)}';
    try {
      final session = await FFmpegKit.execute(command);
      final result = await session.getReturnCode();
      if (!ReturnCode.isSuccess(result) || !await File(output).exists()) {
        final logs = await session.getOutput();
        throw StateError('동영상 필터/프레임 처리 실패: $logs');
      }
      return output;
    } finally {
      if (overlayPath != null) {
        try { await File(overlayPath).delete(); } catch (_) {}
      }
    }
  }
}
