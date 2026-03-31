import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'driver_tracking_screen.dart';
import 'login_screen.dart';

class DriverRouteScreen extends StatefulWidget {
  final String busId;
  final String busName;
  final String busNumber;

  const DriverRouteScreen({
    super.key,
    required this.busId,
    required this.busName,
    required this.busNumber,
  });

  @override
  State<DriverRouteScreen> createState() => _DriverRouteScreenState();
}

class _DriverRouteScreenState extends State<DriverRouteScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  final TextEditingController _stopInputController = TextEditingController();

  final List<String> _stopsList = [];

  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isLoading = true;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadExistingRoute();
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _stopInputController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingRoute() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('buses')
          .doc(widget.busId)
          .get();

      final data = doc.data();
      if (data != null) {
        final start = data['start'] as String?;
        final end = data['end'] as String?;
        final stops = (data['stops'] as List?)
            ?.map((e) => e.toString())
            .toList();

        if (start != null) {
          _startController.text = start;
        }

        if (end != null) {
          _endController.text = end;
        }

        if (stops != null && stops.isNotEmpty) {
          _stopsList
            ..clear()
            ..addAll(stops);
        }
      }
    } catch (e) {
      _statusMessage = 'Could not load previous route details.';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _addStop() {
    final stop = _stopInputController.text.trim();

    if (stop.isEmpty) return;

    if (_stopsList.any(
      (existingStop) => existingStop.toLowerCase() == stop.toLowerCase(),
    )) {
      setState(() {
        _statusMessage = 'This stop is already added.';
      });
      return;
    }

    setState(() {
      _stopsList.add(stop);
      _stopInputController.clear();
      _statusMessage = null;
    });
  }

  void _removeStop(int index) {
    setState(() {
      _stopsList.removeAt(index);
      _statusMessage = null;
    });
  }

  Future<void> _saveRoute() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    final start = _startController.text.trim();
    final end = _endController.text.trim();
    final stops = List<String>.from(_stopsList);

    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection('buses')
          .doc(widget.busId)
          .set({
            'routeName': '$start - $end',
            'start': start,
            'end': end,
            'stops': stops,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Route saved successfully.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Route saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _statusMessage = 'Failed to save route. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _openInGoogleMaps() async {
    final start = _startController.text.trim();
    final end = _endController.text.trim();
    final stops = List<String>.from(_stopsList);

    if (start.isEmpty || end.isEmpty) {
      setState(() {
        _statusMessage = 'Enter both start and end locations first.';
      });
      return;
    }

    String url =
        'https://www.google.com/maps/dir/?api=1'
        '&origin=${Uri.encodeComponent(start)}'
        '&destination=${Uri.encodeComponent(end)}'
        '&travelmode=driving';

    if (stops.isNotEmpty) {
      url += '&waypoints=${stops.map(Uri.encodeComponent).join('|')}';
    }

    final uri = Uri.parse(url);

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!launched) {
      setState(() {
        _statusMessage = 'Could not open Google Maps.';
      });
    }
  }

  Future<void> _deleteBus() async {
    if (_isDeleting) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete this bus?'),
          content: const Text(
            'All data for this bus will be removed from the database. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Yes',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    setState(() {
      _isDeleting = true;
      _statusMessage = null;
    });

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      // Bus + route details are stored here.
      batch.delete(db.collection('buses').doc(widget.busId));
      // Live tracking location for this bus.
      batch.delete(db.collection('bus_locations').doc(widget.busId));

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bus deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Failed to delete bus. Please try again.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delete failed'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _openLiveTracking() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverTrackingScreen(busId: widget.busId),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: const Color(0xFF0B1120),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.blueAccent, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  Widget _buildStopChip(String stop, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${index + 1}. $stop',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _removeStop(index),
            child: const Icon(Icons.close, size: 18, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        elevation: 0,
        title: const Text('Driver Route'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.blueAccent),
              )
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B1120),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.06),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.busName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Bus Number: ${widget.busNumber}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              // Bus ID is intentionally hidden in UI.
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Route details',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter the route information for this bus and manage live tracking.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _startController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('Starting point'),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter starting point';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _endController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('Ending point'),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter ending point';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _stopInputController,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('Add intermediate stop'),
                          onFieldSubmitted: (_) => _addStop(),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.blueAccent),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _addStop,
                            child: const Text(
                              'Add Stop',
                              style: TextStyle(
                                color: Colors.blueAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (_stopsList.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B1120),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.05),
                              ),
                            ),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(
                                _stopsList.length,
                                (index) =>
                                    _buildStopChip(_stopsList[index], index),
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        if (_statusMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.06),
                              ),
                            ),
                            child: Text(
                              _statusMessage!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Colors.blueAccent,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onPressed: _openInGoogleMaps,
                                child: const Text(
                                  'Open Maps',
                                  style: TextStyle(
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onPressed: _isSaving ? null : _saveRoute,
                                child: _isSaving
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Save Route',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: _openLiveTracking,
                            child: const Text(
                              'Open Live Tracking',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: _isDeleting ? null : _deleteBus,
                            icon: _isDeleting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.delete_outline),
                            label: Text(
                              _isDeleting ? 'Deleting...' : 'Delete Bus',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
