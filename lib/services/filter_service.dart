import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/filter_preset.dart';

class FilterService {
  // Edited JPEGs are capped to limit costly full-resolution Dart pixel loops.
  // Change to 0 to retain sensor resolution (substantially slower on phones).
  static const int maxEditedLongEdge = 3000;

  Future<Uint8List> processCapture(Uint8List jpeg, String ratio,
      FilterPreset preset, double strength, {Uint8List? frameArtwork}) => compute(_processJpeg, <Object?>[
    jpeg, ratio, CameraFilters.mixedMatrix(preset,strength), preset, strength, frameArtwork,
  ]);

  Future<Uint8List> apply(Uint8List jpeg, FilterPreset preset, double strength) {
    if (preset.id == 'original' || strength <= 0) return Future.value(jpeg);
    return compute(_processJpeg, <Object?>[
      jpeg, '', CameraFilters.mixedMatrix(preset,strength), preset, strength, null,
    ]);
  }
}

Uint8List _processJpeg(List<Object?> args) {
  final source=args[0] as Uint8List;
  final ratioName=args[1] as String;
  final matrix=args[2] as List<double>;
  final preset=args[3] as FilterPreset;
  final strength=(args[4] as double).clamp(0.0,1.0);
  final frameArtwork=args[5] as Uint8List?;
  final filtered=preset.id!='original' && strength>0;
  final decoded=img.decodeImage(source);
  if(decoded==null) throw StateError('이미지 파일을 읽을 수 없습니다.');
  var image=img.bakeOrientation(decoded);
  var needsCrop=false;
  if(ratioName.isNotEmpty){
    final ratio=ratioName=='1:1'?1.0:ratioName=='16:9'?16/9:4/3;
    final desired=image.height>image.width?1/ratio:ratio;
    final current=image.width/image.height;
    if((current-desired).abs()>0.015){
      needsCrop=true;
      var width=image.width,height=image.height;
      if(current>desired){width=(height*desired).round();}
      else{height=(width/desired).round();}
      image=img.copyCrop(image,x:(image.width-width)~/2,y:(image.height-height)~/2,width:width,height:height);
    }
  }
  if(!filtered && !needsCrop && frameArtwork == null && decoded.exif.imageIfd.orientation==null){return source;}
  // A full sensor capture may exceed 12–48 MP. Reducing edited-only exports
  // before the CPU pixel pass dramatically cuts both processing time and RAM.
  // Unmodified JPEGs still use the original camera bytes unchanged.
  const maxLongEdge = FilterService.maxEditedLongEdge;
  if (maxLongEdge > 0 && math.max(image.width, image.height) > maxLongEdge) {
    if (image.width >= image.height) {
      image = img.copyResize(image, width: maxLongEdge,
          interpolation: img.Interpolation.linear);
    } else {
      image = img.copyResize(image, height: maxLongEdge,
          interpolation: img.Interpolation.linear);
    }
  }
  if(filtered){
    final highlights=preset.highlights.clamp(-100,100)*strength/100;
    final shadows=preset.shadows.clamp(-100,100)*strength/100;
    final whites=preset.whites.clamp(-100,100)*strength/100;
    final blacks=preset.blacks.clamp(-100,100)*strength/100;
    final vibrance=preset.vibrance.clamp(-100,100)*strength/100;
    final dehaze=preset.dehaze.clamp(-100,100)*strength/100;
    final vignette=preset.vignette.clamp(-100,100)*strength/100;
    final grain=preset.grain.clamp(0,100)*strength;
    final texture=preset.texture.clamp(-100,100)*strength/100;
    final clarity=preset.clarity.clamp(-100,100)*strength/100;
    final w=image.width,h=image.height;
    // A lightweight local-contrast approximation: sample a downscaled blurred
    // luminance field. Avoid full-resolution multi-pass convolution.
    final localAmount=(texture*0.4+clarity*0.6).clamp(-1.0,1.0);
    final small=localAmount.abs()>0.001 ? img.copyResize(image,width:math.max(1,(w/24).round()).toInt()) : null;
    final rng=math.Random(9417);
    for(var y=0;y<h;y++){
      for(var x=0;x<w;x++){
        final pixel=image.getPixel(x,y);
        final r=pixel.r.toDouble(),g=pixel.g.toDouble(),b=pixel.b.toDouble();
        var nr=r*matrix[0]+g*matrix[1]+b*matrix[2]+matrix[4];
        var ng=r*matrix[5]+g*matrix[6]+b*matrix[7]+matrix[9];
        var nb=r*matrix[10]+g*matrix[11]+b*matrix[12]+matrix[14];
        final lum=(nr*.2126+ng*.7152+nb*.0722).clamp(0.0,255.0)/255;
        final dark=(1-lum)*(1-lum);
        final bright=lum*lum;
        final delta=shadows*dark*55 + highlights*bright*55
          + blacks*dark*40 + whites*bright*40;
        nr+=delta;ng+=delta;nb+=delta;
        if(vibrance!=0){
          final maxV=math.max(nr,math.max(ng,nb));
          final minV=math.min(nr,math.min(ng,nb));
          final sat=(maxV-minV)/255;
          final factor=1+vibrance*(1-sat)*0.6;
          final avg=(nr+ng+nb)/3;
          nr=avg+(nr-avg)*factor;ng=avg+(ng-avg)*factor;nb=avg+(nb-avg)*factor;
        }
        if(dehaze!=0){
          final factor=1+dehaze*0.45;
          nr=128+(nr-128)*factor;ng=128+(ng-128)*factor;nb=128+(nb-128)*factor;
        }
        if(small!=null){
          final sample=small.getPixel(math.min(small.width-1,x*small.width~/w).toInt(),
            math.min(small.height-1,y*small.height~/h).toInt());
          final local=(r*.2126+g*.7152+b*.0722)-
            (sample.r*.2126+sample.g*.7152+sample.b*.0722);
          final boost=local*localAmount*0.6;
          nr+=boost;ng+=boost;nb+=boost;
        }
        if(vignette!=0){
          final dx=(x-w/2)/(w/2),dy=(y-h/2)/(h/2);
          final edge=(dx*dx+dy*dy).clamp(0.0,1.0);
          final factor=1+vignette*edge*0.55;
          nr*=factor;ng*=factor;nb*=factor;
        }
        if(grain>0){
          final noise=(rng.nextDouble()-.5)*grain*0.65;
          nr+=noise;ng+=noise;nb+=noise;
        }
        pixel.r=nr.clamp(0,255).round();
        pixel.g=ng.clamp(0,255).round();
        pixel.b=nb.clamp(0,255).round();
      }
    }
  }
  if (frameArtwork != null) {
    final overlay = img.decodePng(frameArtwork);
    if (overlay == null) throw StateError('프레임 이미지 디코딩 실패');
    final resized = img.copyResize(overlay,
        width: image.width, height: image.height,
        interpolation: img.Interpolation.linear);
    img.compositeImage(image, resized);
  }
  return Uint8List.fromList(img.encodeJpg(image,quality:91));
}
