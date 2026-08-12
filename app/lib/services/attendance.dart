import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';

/// Raised when the device cannot supply what a check-in needs, with a message
/// written for the staff member rather than the developer.
class CaptureException implements Exception {
  CaptureException(this.message, {this.canOpenSettings = false});
  final String message;

  /// True when the fix is in the OS settings screen (permission denied forever).
  final bool canOpenSettings;

  @override
  String toString() => message;
}

/// A captured check-in: the selfie bytes plus the GPS fix taken at the same time.
class AttendanceCapture {
  AttendanceCapture({
    required this.bytes,
    required this.filename,
    required this.mimeType,
    this.latitude,
    this.longitude,
    this.accuracy,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
  final double? latitude;
  final double? longitude;
  final double? accuracy;

  bool get hasLocation => latitude != null && longitude != null;
}

class AttendanceService {
  AttendanceService(this.api);
  final Api api;

  final ImagePicker _picker = ImagePicker();

  /// Takes the selfie, then reads the GPS fix.
  ///
  /// The photo is captured first deliberately: the camera takes a few seconds to
  /// open and shoot, which gives the GPS time to settle, so the subsequent fix is
  /// usually far more accurate than one requested cold.
  Future<AttendanceCapture> capture() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      // Downscale on device: a full-resolution phone photo is several MB and
      // rural uploads are slow, while this is ample as proof of presence.
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 80,
    );
    if (photo == null) {
      throw CaptureException('Check-in cancelled — a photo is required.');
    }

    final bytes = await photo.readAsBytes();
    final position = await _readPosition();

    return AttendanceCapture(
      bytes: bytes,
      filename: photo.name.isEmpty ? 'selfie.jpg' : photo.name,
      mimeType: photo.mimeType ?? _mimeFromName(photo.name),
      latitude: position?.latitude,
      longitude: position?.longitude,
      accuracy: position?.accuracy,
    );
  }

  /// Obtains a GPS fix, surfacing each failure mode as its own message so the
  /// user knows whether to enable location, grant permission, or move outdoors.
  Future<Position?> _readPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw CaptureException(
        'Location is turned off. Please switch on location and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw CaptureException(
        'Location permission is permanently denied. Enable it for NESF Core in '
        'your phone settings to mark attendance.',
        canOpenSettings: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw CaptureException(
        'Attendance needs your location to confirm where you checked in.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Indoors a high-accuracy fix can hang; give up and let the caller
          // decide rather than blocking the check-in indefinitely.
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      // A last known fix is better than nothing, and the server records the
      // accuracy so a poor fix is visible on the record.
      return Geolocator.getLastKnownPosition();
    }
  }

  Future<void> openLocationSettings() => Geolocator.openAppSettings();

  Future<Map<String, dynamic>> today() async =>
      await api.get('/attendance/today') as Map<String, dynamic>;

  Future<Map<String, dynamic>> checkIn(
    AttendanceCapture capture, {
    String? workMode,
    String? place,
    String? notes,
  }) async {
    return await api.upload(
      '/attendance/check-in',
      field: 'selfie',
      filename: capture.filename,
      bytes: capture.bytes,
      contentType: capture.mimeType,
      extra: {
        if (capture.latitude != null) 'lat': '${capture.latitude}',
        if (capture.longitude != null) 'lng': '${capture.longitude}',
        if (capture.accuracy != null) 'accuracy': '${capture.accuracy}',
        if (workMode != null) 'work_mode': workMode,
        if (place != null && place.isNotEmpty) 'place': place,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    ) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> checkOut(
    AttendanceCapture capture, {
    String? place,
    String? notes,
  }) async {
    return await api.upload(
      '/attendance/check-out',
      field: 'selfie',
      filename: capture.filename,
      bytes: capture.bytes,
      contentType: capture.mimeType,
      extra: {
        if (capture.latitude != null) 'lat': '${capture.latitude}',
        if (capture.longitude != null) 'lng': '${capture.longitude}',
        if (place != null && place.isNotEmpty) 'place': place,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    ) as Map<String, dynamic>;
  }

  /// Stores the current position as the employee's attendance base, which the
  /// server compares future check-ins against.
  Future<void> setBaseHere(int employeeId, {String? label}) async {
    final position = await _readPosition();
    if (position == null) {
      throw CaptureException('Could not read your location. Please try again outdoors.');
    }
    await api.put('/employees/$employeeId/base-location', {
      'base_lat': position.latitude,
      'base_lng': position.longitude,
      if (label != null) 'base_label': label,
    });
  }

  static String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
