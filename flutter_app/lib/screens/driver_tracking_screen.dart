import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class DriverTrackingScreen extends StatefulWidget {
  final String? busId;

  const DriverTrackingScreen({super.key, this.busId});

  @override
  State<DriverTrackingScreen> createState() => _DriverTrackingScreenState();
}

class _DriverTrackingScreenState extends State<DriverTrackingScreen> {
  Timer? _timer;
  bool _isStarting = false;
  bool _isTracking = false;
  bool _isSending = false;
  bool _isSavingManual = false;
  String? _status;
  Position? _lastPosition;
  DateTime? _lastSentAt;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10, // meters
  );

  Future<void> _ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw Exception('Location services are disabled.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied.');
    }
  }

  DocumentReference<Map<String, dynamic>> _busLocationDoc(String uid) {
    final docId = widget.busId ?? uid;
    return FirebaseFirestore.instance.collection('bus_locations').doc(docId);
  }

  Future<void> _pushCurrentLocation(User user) async {
    if (_isSending) return;
    _isSending = true;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: _locationSettings,
      );
      _lastPosition = pos;

      await _busLocationDoc(user.uid).set(<String, Object?>{
        'driverUid': user.uid,
        if (widget.busId != null) 'busId': widget.busId,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'speed': pos.speed,
        'heading': pos.heading,
        'sentAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _lastSentAt = DateTime.now();
        _status = 'Live location sent';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Failed to send: $e';
      });
      rethrow;
    } finally {
      _isSending = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _toggleLiveFromChip() async {
    if (_isStarting) return;
    if (_isTracking) {
      await _stopTracking();
      return;
    }
    await _startTracking();
  }

  Future<void> _startTracking() async {
    if (_isStarting || _isTracking) return;
    setState(() {
      _isStarting = true;
      _status = null;
    });

    try {
      await _ensurePermission();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Not logged in.');
      }

      Future<void> sendNow() async {
        try {
          await _pushCurrentLocation(user);
        } catch (_) {
          // Error already surfaced via _status in _pushCurrentLocation.
        }
      }

      // Send immediately when tracking starts.
      await sendNow();

      // Auto-save current GPS periodically (while screen is open).
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        sendNow();
      });

      if (!mounted) return;
      setState(() {
        _isTracking = true;
        _status = 'Live on — auto-update every 4 seconds (tap LIVE to stop)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _saveLocationNow() async {
    if (_isSavingManual) return;
    setState(() {
      _isSavingManual = true;
    });
    try {
      await _ensurePermission();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Not logged in.');
      }
      await _pushCurrentLocation(user);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location saved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingManual = false;
        });
      }
    }
  }

  Future<void> _stopTracking() async {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;
    setState(() {
      _isTracking = false;
      _status = 'Tracking stopped';
    });
  }

  Future<void> _logout() async {
    await _stopTracking();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    final email = user?.email ?? '';
    final docId = widget.busId ?? uid;

    final pos = _lastPosition;
    final coords = pos == null
        ? '—'
        : '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Driver Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              /// DRIVER SESSION CARD
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Driver session',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      email.isEmpty ? uid : email,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Firestore doc: bus_locations/$docId',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              /// GPS CARD
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// HEADER
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Current GPS',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                        ),

                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isStarting ? null : _toggleLiveFromChip,
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _isTracking
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.white10,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _isTracking
                                      ? Colors.green.withValues(alpha: 0.4)
                                      : Colors.white24,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_isStarting) ...[
                                    const SizedBox(
                                      height: 14,
                                      width: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    _isTracking ? 'LIVE' : 'OFF',
                                    style: TextStyle(
                                      color: _isTracking
                                          ? Colors.greenAccent
                                          : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (!_isStarting) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      _isTracking
                                          ? Icons.toggle_on
                                          : Icons.toggle_off,
                                      size: 18,
                                      color: _isTracking
                                          ? Colors.greenAccent
                                          : Colors.white54,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Text(
                      coords,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      _lastSentAt == null
                          ? 'Last sent: —'
                          : 'Last sent: ${_lastSentAt!.toLocal()}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),

                    if (_status != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _status!,
                        style: TextStyle(
                          color:
                              _status!.startsWith('Failed') ||
                                  _status!.contains('error')
                              ? Colors.redAccent
                              : Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 30),

              /// Save current GPS once (manual); live updates still use LIVE/OFF chip.
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _isSavingManual ? null : _saveLocationNow,
                  icon: _isSavingManual
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _isSavingManual ? 'Saving...' : 'Save',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isTracking
                    ? 'Tap LIVE to stop automatic updates. Use Save anytime for an extra send.'
                    : 'Tap OFF to start live updates every 4 seconds.',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
