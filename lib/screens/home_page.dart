import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../widgets/custom_menu_card.dart';

import 'add_class_page.dart';
import 'schedule_page.dart';
import 'fingerprint_list_page.dart';
import 'log_page.dart';
import 'register_fingerprint_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  MqttServerClient? _mqttClient;
  bool _mqttConnected = false;
  bool _mqttLoading = false;
  String _lockerStatus = "Tidak Ada Kelas";
  String _activeClass = "";
  List<String> _usedFingerprintIds = [];

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _mqttClient?.disconnect();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await Future.wait([
      _loadUsedFingerprintIds(),
      _checkActiveClassAndStatus(),
    ]);
    await _setupMQTT();
  }

  Future<void> _setupMQTT() async {
    if (_mqttLoading || _mqttConnected) return;

    try {
      setState(() => _mqttLoading = true);

      final clientId = 'flutter_client_${DateTime.now().millisecondsSinceEpoch}';
      _mqttClient = MqttServerClient('10.10.10.10', clientId);

      _mqttClient!
        ..port = 1883
        ..secure = false
        ..keepAlivePeriod = 60
        ..socketTimeout = 10
        ..logging(on: false)
        ..onConnected = _onMqttConnected
        ..onDisconnected = _onMqttDisconnected;

      final connMess = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      _mqttClient!.connectionMessage = connMess;

      try {
        await _mqttClient!.connect().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            _mqttClient?.disconnect();
            if (mounted) {
              setState(() {
                _mqttConnected = false;
                _mqttLoading = false;
              });
            }
            return null;
          },
        );

        if (mounted) {
          final isConnected = _mqttClient?.connectionStatus?.state == MqttConnectionState.connected;
          setState(() {
            _mqttConnected = isConnected;
            _mqttLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _mqttConnected = false;
            _mqttLoading = false;
          });
        }
      }
    } catch (e) {
      _mqttClient?.disconnect();
      if (mounted) {
        setState(() {
          _mqttConnected = false;
          _mqttLoading = false;
        });
      }
    }
  }

  void _onMqttConnected() {
    if (mounted) {
      setState(() {
        _mqttConnected = true;
        _mqttLoading = false;
      });
    }
  }

  void _onMqttDisconnected() {
    if (mounted) {
      setState(() {
        _mqttConnected = false;
        _mqttLoading = false;
      });
    }
  }

  Future<void> _loadUsedFingerprintIds() async {
    try {
      final snapshot = await _dbRef.child("fingerprints").get().timeout(
        const Duration(seconds: 10),
      );
      if (snapshot.exists && mounted) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        setState(() {
          _usedFingerprintIds = data.keys.toList();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _usedFingerprintIds = [];
        });
      }
    }
  }

  Future<void> _checkActiveClassAndStatus() async {
    try {
      final now = DateTime.now();
      final currentDay = _getDayName(now.weekday).toLowerCase();
      final currentTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

      print("Current Day: $currentDay");
      print("Current Time: $currentTime");

      final classSnapshot = await _dbRef.child("classes").get().timeout(
        const Duration(seconds: 10),
      );
      final scheduleSnapshot = await _dbRef.child("schedules").get().timeout(
        const Duration(seconds: 10),
      );

      String activeClass = "";
      String status = "Tidak Ada Kelas";

      if (classSnapshot.exists && scheduleSnapshot.exists) {
        final classes = Map<String, dynamic>.from(classSnapshot.value as Map);
        final scheduleData = Map<String, dynamic>.from(scheduleSnapshot.value as Map);
        
        print("Classes: $classes");
        print("Schedule Data: $scheduleData");
        
        for (var classEntry in classes.entries) {
          final className = classEntry.key;
          final safeClassName = className.replaceAll(RegExp(r'\s+'), '_');
          
          print("Checking class: $className (safe: $safeClassName)");
          
          if (scheduleData.containsKey(safeClassName)) {
            final classSchedule = Map<String, dynamic>.from(scheduleData[safeClassName] as Map);
            print("Class schedule for $safeClassName: $classSchedule");
            
            if (classSchedule.containsKey(currentDay)) {
              final scheduleRange = classSchedule[currentDay].toString();
              print("Schedule range for $currentDay: $scheduleRange");
              
              if (scheduleRange.contains('-')) {
                final parts = scheduleRange.split('-');
                if (parts.length == 2) {
                  final startTime = parts[0].trim();
                  final endTime = parts[1].trim();
                  
                  print("Start time: $startTime, End time: $endTime");
                  
                  if (_isTimeInRange(currentTime, startTime, endTime)) {
                    activeClass = className;
                    status = "Kelas $className Aktif";
                    print("Found active class: $className");
                    break;
                  }
                }
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _activeClass = activeClass;
          _lockerStatus = status;
        });
        print("Final status: $status, Active class: $activeClass");
      }
    } catch (e) {
      print("Error checking active class: $e");
      if (mounted) {
        setState(() {
          _activeClass = "";
          _lockerStatus = "Error";
        });
      }
    }
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return 'senin';
      case 2: return 'selasa';
      case 3: return 'rabu';
      case 4: return 'kamis';
      case 5: return 'jumat';
      case 6: return 'sabtu';
      case 7: return 'minggu';
      default: return 'unknown';
    }
  }

  bool _isTimeInRange(String currentTime, String startTime, String endTime) {
    try {
      final current = _timeToMinutes(currentTime);
      final start = _timeToMinutes(startTime);
      final end = _timeToMinutes(endTime);
      
      print("Time comparison - Current: $current, Start: $start, End: $end");
      print("Is in range: ${current >= start && current <= end}");
      
      return current >= start && current <= end;
    } catch (e) {
      print("Error parsing time: $e");
      return false;
    }
  }

  int _timeToMinutes(String time) {
    final parts = time.split(':');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    return hours * 60 + minutes;
  }

  Future<void> _navigateToAddClass() async {
    await _loadUsedFingerprintIds();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddClassPage()),
    );
    if (result == true) {
      await _loadUsedFingerprintIds();
    }
  }

  void _navigateToSchedule() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SchedulePage()),
    );
  }

  void _navigateToFingerList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FingerprintListPage(activeClass: _activeClass),
      ),
    ).then((_) => _loadUsedFingerprintIds());
  }

  void _navigateToLogPage() {
    if (_mqttLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sedang menghubungkan MQTT. Tunggu sebentar...")),
      );
      return;
    }

    if (!_mqttConnected || _mqttClient == null) {
      _showMqttDialog();
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LogPage(mqttClient: _mqttClient!),
      ),
    );
  }

  void _navigateToRegisterFingerprint() {
    if (_mqttLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sedang menghubungkan MQTT. Tunggu sebentar...")),
      );
      return;
    }

    if (!_mqttConnected || _mqttClient == null) {
      _showMqttDialog();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RegisterFingerprintPage(mqttClient: _mqttClient!),
      ),
    ).then((_) => _loadUsedFingerprintIds());
  }

  void _showMqttDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Koneksi MQTT"),
        content: const Text("MQTT belum terkoneksi. Apakah Anda ingin mencoba lagi?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _setupMQTT();
            },
            child: const Text("Coba Lagi"),
          ),
        ],
      ),
    );
  }

  Color get _statusColor {
    if (_lockerStatus.contains('Aktif')) {
      return Colors.green;
    } else if (_lockerStatus == 'Tidak Ada Kelas') {
      return Colors.orange;
    } else if (_lockerStatus == 'Error') {
      return Colors.red;
    } else {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'Smart Locker',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_mqttLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  Icon(
                    _mqttConnected ? Icons.wifi : Icons.wifi_off,
                    color: _mqttConnected ? Colors.lightGreenAccent : Colors.redAccent,
                    size: 20,
                  ),
                const SizedBox(width: 4),
                Text(
                  _mqttLoading ? 'Connecting...' : (_mqttConnected ? 'Online' : 'Offline'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _mqttLoading
                        ? Colors.orangeAccent
                        : (_mqttConnected ? Colors.lightGreenAccent : Colors.redAccent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _loadUsedFingerprintIds(),
            _checkActiveClassAndStatus(),
          ]);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        _statusColor.withOpacity(0.1),
                        _statusColor.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.lock,
                        size: 32,
                        color: _statusColor,
                      ),
                    ),
                    title: const Text(
                      'Status Loker',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          child: Container(
                            key: ValueKey(_lockerStatus),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _lockerStatus,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_activeClass.isNotEmpty)
                          Text(
                            'Kelas Aktif: $_activeClass',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        Text(
                          'Fingerprint terdaftar: ${_usedFingerprintIds.length}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        await Future.wait([
                          _checkActiveClassAndStatus(),
                          _loadUsedFingerprintIds(),
                        ]);
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.1,
                ),
                children: [
                  CustomMenuCard(
                    icon: Icons.group_add,
                    label: "Tambah Kelas",
                    onTap: _navigateToAddClass,
                  ),
                  CustomMenuCard(
                    icon: Icons.schedule,
                    label: "Jadwal",
                    onTap: _navigateToSchedule,
                  ),
                  CustomMenuCard(
                    icon: Icons.fingerprint,
                    label: "Daftar Sidik Jari",
                    onTap: _navigateToRegisterFingerprint,
                  ),
                  CustomMenuCard(
                    icon: Icons.list_alt,
                    label: "List Sidik Jari",
                    onTap: _navigateToFingerList,
                  ),
                  CustomMenuCard(
                    icon: Icons.receipt_long,
                    label: "Log Aktivitas",
                    onTap: _navigateToLogPage,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}