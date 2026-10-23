package dev.kcw.physical_lens_bridge;

import android.content.Context;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CameraMetadata;
import android.os.Build;
import android.util.SizeF;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Read-only Camera2 inventory. NEVER opens a competing camera session.
 * The selected camera ID is opened by Flutter camera_android (Camera2).
 */
public final class PhysicalLensBridgePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private Context applicationContext;
    private MethodChannel channel;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        applicationContext = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "vintage_camera/physical_lenses");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
        applicationContext = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!"inventory".equals(call.method)) {
            result.notImplemented();
            return;
        }
        try {
            result.success(inventory());
        } catch (SecurityException e) {
            result.error("CAMERA_PERMISSION", "Camera permission required: " + e.getMessage(), null);
        } catch (CameraAccessException e) {
            result.error("CAMERA2_ACCESS", e.toString(), null);
        } catch (RuntimeException e) {
            result.error("CAMERA2_INVENTORY", e.toString(), null);
        }
    }

    @NonNull
    private Map<String, Object> inventory() throws CameraAccessException {
        CameraManager manager = (CameraManager) applicationContext.getSystemService(Context.CAMERA_SERVICE);
        String[] directlyOpenableIds = manager.getCameraIdList();
        Set<String> openable = new HashSet<>(Arrays.asList(directlyOpenableIds));
        Set<String> all = new HashSet<>(openable);
        // Discover physical sensors hidden behind a logical multi-camera.
        // They MUST NOT be advertised as selectable unless Camera2 reports an
        // independently openable camera ID as well.
        if (Build.VERSION.SDK_INT >= 28) {
            for (String id : directlyOpenableIds) {
                try {
                    all.addAll(manager.getCameraCharacteristics(id).getPhysicalCameraIds());
                } catch (Exception ignored) { }
            }
        }
        List<String> sorted = new ArrayList<>(all);
        sorted.sort((a, b) -> {
            try { return Integer.compare(Integer.parseInt(a), Integer.parseInt(b)); }
            catch (NumberFormatException ex) { return a.compareTo(b); }
        });
        List<Map<String, Object>> lenses = new ArrayList<>();
        for (String id : sorted) {
            Map<String, Object> info = new LinkedHashMap<>();
            info.put("id", id);
            info.put("openable", openable.contains(id));
            try {
                CameraCharacteristics c = manager.getCameraCharacteristics(id);
                Integer facing = c.get(CameraCharacteristics.LENS_FACING);
                info.put("facing", facing == null ? "unknown" :
                        facing == CameraMetadata.LENS_FACING_BACK ? "back" :
                        facing == CameraMetadata.LENS_FACING_FRONT ? "front" : "external");
                float[] focalLengths = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS);
                SizeF sensorSize = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE);
                double focalMm = focalLengths != null && focalLengths.length > 0 ? focalLengths[0] : 0d;
                info.put("focalMm", focalMm);
                if (focalMm > 0d && sensorSize != null && sensorSize.getWidth() > 0 && sensorSize.getHeight() > 0) {
                    double sensorDiagonal = Math.hypot(sensorSize.getWidth(), sensorSize.getHeight());
                    info.put("focal35mm", Math.round((43.2666153 * focalMm / sensorDiagonal) * 10.0) / 10.0);
                } else {
                    info.put("focal35mm", 0d);
                }
                if (Build.VERSION.SDK_INT >= 28) {
                    info.put("logical", !c.getPhysicalCameraIds().isEmpty());
                } else {
                    info.put("logical", false);
                }
                int[] capabilities = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES);
                boolean backwardCompatible = false;
                if (capabilities != null) {
                    for (int capability : capabilities) {
                        if (capability == CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE) {
                            backwardCompatible = true;
                            break;
                        }
                    }
                }
                info.put("backwardCompatible", backwardCompatible);
                Integer orientation = c.get(CameraCharacteristics.SENSOR_ORIENTATION);
                info.put("orientation", orientation == null ? 0 : orientation);
            } catch (Exception e) {
                info.put("facing", "unknown");
                info.put("focalMm", 0d);
                info.put("focal35mm", 0d);
                info.put("logical", false);
                info.put("backwardCompatible", false);
                info.put("orientation", 0);
                info.put("inspectionError", e.toString());
            }
            lenses.add(info);
        }
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("manufacturer", Build.MANUFACTURER);
        response.put("model", Build.MODEL);
        response.put("api", Build.VERSION.SDK_INT);
        response.put("cameras", lenses);
        return response;
    }
}
