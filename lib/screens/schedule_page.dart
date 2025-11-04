import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final dbRef = FirebaseDatabase.instance.ref();
  Map<String, Map<String, dynamic>> schedules = {}; // {safeClassName: {day: scheduleRange}}

  @override
  void initState() {
    super.initState();
    _fetchSchedules();
  }

  Future<void> _fetchSchedules() async {
    final classSnapshot = await dbRef.child('classes').get();
    final scheduleSnapshot = await dbRef.child('schedules').get();
    print("Class Snapshot exists: ${classSnapshot.exists}");
    print("Schedule Snapshot exists: ${scheduleSnapshot.exists}");
    print("Class Data: ${classSnapshot.value}");
    print("Schedule Data: ${scheduleSnapshot.value}");

    if (classSnapshot.exists) {
      final classes = Map<String, dynamic>.from(classSnapshot.value as Map);
      final scheduleData = scheduleSnapshot.exists
          ? Map<String, dynamic>.from(scheduleSnapshot.value as Map)
          : {};
      print("Processed Classes: $classes");
      print("Processed Schedules: $scheduleData");

      final temp = <String, Map<String, dynamic>>{};
      classes.forEach((className, _) {
        final safeClassName = className.replaceAll(RegExp(r'\s+'), '_');
        if (scheduleData.containsKey(className)) {
          temp[safeClassName] = Map<String, dynamic>.from(scheduleData[className]);
        } else {
          temp[safeClassName] = {};
        }
      });

      setState(() {
        schedules = temp;
        print("Updated Schedules: $schedules");
      });
    } else {
      print("No classes found in Firebase");
    }
  }

  // Convert TimeOfDay to 24-hour format string (HH:MM)
  String _timeOfDayTo24Hour(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Convert 24-hour format string to TimeOfDay
  TimeOfDay? _parseTimeOfDay(String time) {
    try {
      final parts = time.split(":");
      if (parts.length == 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (_) {}
    return null;
  }

  // Format time for display (12-hour format)
  String _formatTimeForDisplay(String time24) {
    final timeOfDay = _parseTimeOfDay(time24);
    if (timeOfDay != null) {
      return timeOfDay.format(context);
    }
    return time24;
  }

  // Convert safe class name to display name (ganti underscore dengan spasi)
  String _displayClassName(String safeClassName) {
    return safeClassName.replaceAll('_', ' ');
  }

  Future<void> _addDay(String className) async {
    final dayController = TextEditingController();
    final startController = TextEditingController();
    final endController = TextEditingController();

    TimeOfDay? startTime;
    TimeOfDay? endTime;

    // Gunakan nama kelas yang aman untuk Firebase
    final safeClassName = className.replaceAll(RegExp(r'\s+'), '_');

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Tambah Hari ke ${_displayClassName(className)}"),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: "Hari"),
                items: const [
                  DropdownMenuItem(value: "senin", child: Text("Senin")),
                  DropdownMenuItem(value: "selasa", child: Text("Selasa")),
                  DropdownMenuItem(value: "rabu", child: Text("Rabu")),
                  DropdownMenuItem(value: "kamis", child: Text("Kamis")),
                  DropdownMenuItem(value: "jumat", child: Text("Jumat")),
                  DropdownMenuItem(value: "sabtu", child: Text("Sabtu")),
                  DropdownMenuItem(value: "minggu", child: Text("Minggu")),
                ],
                onChanged: (value) {
                  dayController.text = value ?? '';
                },
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: startTime ?? TimeOfDay.now(),
                  );
                  if (picked != null) {
                    startTime = picked;
                    startController.text = _timeOfDayTo24Hour(picked);
                  }
                },
                child: AbsorbPointer(
                  child: TextField(
                    controller: startController,
                    decoration: const InputDecoration(
                      labelText: "Jam Mulai (24 jam)",
                      suffixIcon: Icon(Icons.access_time),
                      hintText: "08:00",
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: endTime ?? TimeOfDay.now(),
                  );
                  if (picked != null) {
                    endTime = picked;
                    endController.text = _timeOfDayTo24Hour(picked);
                  }
                },
                child: AbsorbPointer(
                  child: TextField(
                    controller: endController,
                    decoration: const InputDecoration(
                      labelText: "Jam Selesai (24 jam)",
                      suffixIcon: Icon(Icons.access_time),
                      hintText: "10:00",
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              final day = dayController.text.trim().toLowerCase();
              final start = startController.text.trim();
              final end = endController.text.trim();
              
              if (day.isNotEmpty && start.isNotEmpty && end.isNotEmpty) {
                if (_parseTimeOfDay(start) == null || _parseTimeOfDay(end) == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Format waktu tidak valid')),
                  );
                  return;
                }
                
                final scheduleRange = '$start-$end';
                await dbRef.child('schedules/$safeClassName/$day').set(scheduleRange);
                
                Navigator.pop(context);
                _fetchSchedules();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Hari $day berhasil ditambahkan ke ${_displayClassName(className)}')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Semua field harus diisi')),
                );
              }
            },
            child: const Text("Simpan"),
          ),
        ],
      ),
    );
  }

  Future<void> _editSchedule(String className, String oldDay, String currentRange) async {
    final dayController = TextEditingController(text: oldDay);
    final startController = TextEditingController();
    final endController = TextEditingController();

    String startTime24 = '';
    String endTime24 = '';
    TimeOfDay? startTime;
    TimeOfDay? endTime;

    final safeClassName = className.replaceAll(RegExp(r'\s+'), '_');

    if (currentRange.contains('-')) {
      final parts = currentRange.split('-');
      if (parts.length == 2) {
        startTime24 = parts[0].trim();
        endTime24 = parts[1].trim();
        startTime = _parseTimeOfDay(startTime24);
        endTime = _parseTimeOfDay(endTime24);
        startController.text = startTime24;
        endController.text = endTime24;
      }
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Edit Jadwal ${_displayClassName(className)}"),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: "Hari"),
                value: oldDay,
                items: const [
                  DropdownMenuItem(value: "senin", child: Text("Senin")),
                  DropdownMenuItem(value: "selasa", child: Text("Selasa")),
                  DropdownMenuItem(value: "rabu", child: Text("Rabu")),
                  DropdownMenuItem(value: "kamis", child: Text("Kamis")),
                  DropdownMenuItem(value: "jumat", child: Text("Jumat")),
                  DropdownMenuItem(value: "sabtu", child: Text("Sabtu")),
                  DropdownMenuItem(value: "minggu", child: Text("Minggu")),
                ],
                onChanged: (value) {
                  dayController.text = value ?? '';
                },
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: startTime ?? TimeOfDay.now(),
                  );
                  if (picked != null) {
                    startTime = picked;
                    startController.text = _timeOfDayTo24Hour(picked);
                  }
                },
                child: AbsorbPointer(
                  child: TextField(
                    controller: startController,
                    decoration: const InputDecoration(
                      labelText: "Jam Mulai (24 jam)",
                      suffixIcon: Icon(Icons.access_time),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: endTime ?? TimeOfDay.now(),
                  );
                  if (picked != null) {
                    endTime = picked;
                    endController.text = _timeOfDayTo24Hour(picked);
                  }
                },
                child: AbsorbPointer(
                  child: TextField(
                    controller: endController,
                    decoration: const InputDecoration(
                      labelText: "Jam Selesai (24 jam)",
                      suffixIcon: Icon(Icons.access_time),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await dbRef.child('schedules/$safeClassName/$oldDay').remove();
              Navigator.pop(context);
              _fetchSchedules();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Jadwal ${_displayClassName(className)} di hari $oldDay berhasil dihapus')),
              );
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              final newDay = dayController.text.trim().toLowerCase();
              final newStart = startController.text.trim();
              final newEnd = endController.text.trim();
              
              if (newDay.isNotEmpty && newStart.isNotEmpty && newEnd.isNotEmpty) {
                if (_parseTimeOfDay(newStart) == null || _parseTimeOfDay(newEnd) == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Format waktu tidak valid')),
                  );
                  return;
                }
                
                if (oldDay != newDay) {
                  await dbRef.child('schedules/$safeClassName/$oldDay').remove();
                }
                
                final scheduleRange = '$newStart-$newEnd';
                await dbRef.child('schedules/$safeClassName/$newDay').set(scheduleRange);
                
                Navigator.pop(context);
                _fetchSchedules();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Jadwal ${_displayClassName(className)} di hari $newDay berhasil diperbarui')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Semua field harus diisi')),
                );
              }
            },
            child: const Text("Simpan"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Jadwal Kelas"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSchedules,
            tooltip: "Refresh",
          ),
        ],
      ),
      body: schedules.isEmpty
          ? const Center(child: Text("Belum ada kelas"))
          : ListView(
              children: schedules.entries.map((entry) {
                final safeClassName = entry.key;
                final days = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ExpansionTile(
                    title: Text(_displayClassName(safeClassName), style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => _addDay(safeClassName),
                      tooltip: "Tambah Hari",
                    ),
                    children: days.isEmpty
                        ? [
                            const ListTile(
                              leading: Icon(Icons.info_outline),
                              title: Text("Belum ada jadwal"),
                            ),
                          ]
                        : days.entries.map((dayEntry) {
                            final day = dayEntry.key;
                            final scheduleRange = dayEntry.value.toString();

                            String displayText = scheduleRange;
                            if (scheduleRange.contains('-')) {
                              final parts = scheduleRange.split('-');
                              if (parts.length == 2) {
                                final startDisplay = _formatTimeForDisplay(parts[0].trim());
                                final endDisplay = _formatTimeForDisplay(parts[1].trim());
                                displayText = '$startDisplay - $endDisplay';
                              }
                            }

                            return ListTile(
                              leading: const Icon(Icons.access_time),
                              title: Text("${day.capitalize()}: $displayText"),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editSchedule(safeClassName, day, scheduleRange),
                                tooltip: "Edit Jadwal",
                              ),
                            );
                          }).toList(),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// Extension untuk capitalize string
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}