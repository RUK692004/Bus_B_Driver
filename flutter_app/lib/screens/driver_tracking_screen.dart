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
  StreamSubscription<Position>? _sub;
  bool _isStarting = false;
  bool _isTracking = false;
  String? _status;
  Position? _lastPosition;
  DateTime? _lastSentAt;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

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

      final settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // meters
      );

      final docId = widget.busId ?? user.uid;
      final doc = FirebaseFirestore.instance.collection('bus_locations').doc(docId);

      _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (pos) async {
          _lastPosition = pos;
          try {
            await doc.set(
              <String, Object?>{
                'driverUid': user.uid,
                if (widget.busId != null) 'busId': widget.busId,
                'lat': pos.latitude,
                'lng': pos.longitude,
                'accuracy': pos.accuracy,
                'speed': pos.speed,
                'heading': pos.heading,
                'sentAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
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
          }
          if (!mounted) return;
          setState(() {});
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _status = 'Tracking error: $e';
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _isTracking = true;
        _status = 'Tracking started';
      });
    } catch (e) {
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

  Future<void> _stopTracking() async {
    await _sub?.cancel();
    _sub = null;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Firestore doc: bus_locations/$docId',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Current GPS',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isTracking ? Colors.green.withValues(alpha: 0.15) : Colors.white10,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _isTracking ? Colors.green.withValues(alpha: 0.4) : Colors.white12,
                          ),
                        ),
                        child: Text(
                          _isTracking ? 'LIVE' : 'OFF',
                          style: TextStyle(
                            color: _isTracking ? Colors.greenAccent : Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    coords,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _lastSentAt == null ? 'Last sent: —' : 'Last sent: ${_lastSentAt!.toLocal()}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _status!,
                      style: TextStyle(
                        color: _status!.startsWith('Failed') || _status!.contains('error')
                            ? Colors.redAccent
                            : Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTracking ? Colors.redAccent : Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isStarting
                    ? null
                    : _isTracking
                        ? _stopTracking
                        : _startTracking,
                child: _isStarting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _isTracking ? 'Stop tracking' : 'Start tracking',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

