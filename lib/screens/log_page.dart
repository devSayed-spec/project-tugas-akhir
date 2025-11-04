import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

class LogPage extends StatefulWidget {
  final MqttServerClient mqttClient;
  const LogPage({required this.mqttClient, super.key});

  @override
  _LogPageState createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  List<Map<String, dynamic>> logList = [];
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>? _subscription;
  Timer? _connectionTimer;
  bool _isMqttConnected = false;
  bool _isLoading = true;

  // Topik MQTT yang digunakan
  final List<String> _logTopics = [
    'smartlocker/fingerprint/success',
    'smartlocker/fingerprint/fail',
    'smartlocker/fingerprint/denied',
    'smartlocker/fingerprint/duplicate',
    'smartlocker/fingerprint/tidak_terdaftar',
  ];

  // Key untuk SharedPreferences
  static const String _logStorageKey = 'smartlocker_logs';
  static const int _maxLogCount = 1000; // Batas jumlah log

  @override
  void initState() {
    super.initState();
    _initializeLogPage();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _connectionTimer?.cancel();
    super.dispose();
  }

  // Inisialisasi halaman log
  Future<void> _initializeLogPage() async {
    await _loadStoredLogs();
    _checkMqttConnection();
    _subscribeToLogTopics();
  }

  // Memuat log dari SharedPreferences
  Future<void> _loadStoredLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedLogsJson = prefs.getString(_logStorageKey);

      if (storedLogsJson != null && storedLogsJson.isNotEmpty) {
        final List<dynamic> decodedLogs = json.decode(storedLogsJson);
        List<Map<String, dynamic>> validLogs = [];

        for (var log in decodedLogs) {
          if (log is Map<String, dynamic> && log.containsKey('action') && log.containsKey('timestamp')) {
            validLogs.add(log);
          }
        }

        validLogs.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

        setState(() {
          logList = validLogs;
          _isLoading = false;
        });

        print("✅ Memuat ${logList.length} log tersimpan");
        if (validLogs.length != decodedLogs.length) {
          await _saveLogsToStorage();
          print("🔧 Membersihkan log yang tidak valid, menyimpan ${validLogs.length} log");
        }
      } else {
        setState(() {
          _isLoading = false;
        });
        print("📝 Tidak ada log tersimpan ditemukan");
      }
    } catch (e) {
      print("❌ Kesalahan saat memuat log tersimpan: $e");
      setState(() {
        logList = [];
        _isLoading = false;
      });

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_logStorageKey);
        print("🔧 Menghapus data log yang rusak");
      } catch (clearError) {
        print("❌ Kesalahan saat menghapus data rusak: $clearError");
      }
    }
  }

  // Menyimpan log ke SharedPreferences
  Future<void> _saveLogsToStorage() async {
    try {
      List<Map<String, dynamic>> logsToSave = logList;
      if (logList.length > _maxLogCount) {
        logsToSave = logList.take(_maxLogCount).toList();
        setState(() {
          logList = logsToSave;
        });
        print("🔧 Memotong log menjadi $_maxLogCount entri");
      }

      final prefs = await SharedPreferences.getInstance();
      final logsJson = json.encode(logsToSave);
      await prefs.setString(_logStorageKey, logsJson);
      print("✅ Log disimpan ke penyimpanan (${logsToSave.length} entri)");
    } catch (e) {
      print("❌ Kesalahan saat menyimpan log: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("⚠️ Gagal menyimpan log: ${e.toString()}"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // Menambahkan log baru
  void _addNewLog(Map<String, dynamic> newLog) {
    if (!newLog.containsKey('action') || !newLog.containsKey('timestamp')) {
      print("❌ Data log tidak valid: $newLog");
      return;
    }

    // Cegah duplikasi log dalam waktu singkat
    final newTimestamp = newLog['timestamp'] as int;
    final duplicateLog = logList.firstWhere(
      (log) => (log['action'] == newLog['action']) && 
               ((newTimestamp - (log['timestamp'] ?? 0)).abs() < 1000),
      orElse: () => <String, dynamic>{},
    );

    if (duplicateLog.isNotEmpty) {
      print("⚠️ Log duplikat terdeteksi, dilewati: ${newLog['action']}");
      return;
    }

    setState(() {
      logList.insert(0, newLog);
    });

    _saveLogsToStorage();
    print("📝 Log baru ditambahkan: ${newLog['action']} pada ${_formatTimestamp(newTimestamp)}");
  }

  // Memeriksa koneksi MQTT
  void _checkMqttConnection() {
    final client = widget.mqttClient;
    setState(() {
      _isMqttConnected = client.connectionStatus?.state == MqttConnectionState.connected;
    });

    _connectionTimer?.cancel();
    _connectionTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final isConnected = client.connectionStatus?.state == MqttConnectionState.connected;
      if (_isMqttConnected != isConnected) {
        setState(() {
          _isMqttConnected = isConnected;
        });

        if (isConnected) {
          print("🔄 MQTT tersambung kembali, berlangganan ulang ke topik");
          _subscribeToLogTopics();
        } else {
          print("⚠️ MQTT terputus");
        }
      }
    });
  }

  // Berlangganan ke topik MQTT
  void _subscribeToLogTopics() {
    final client = widget.mqttClient;

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      print("⚠️ MQTT tidak tersambung, tidak dapat berlangganan ke topik log");
      return;
    }

    try {
      _subscription?.cancel();

      for (String topic in _logTopics) {
        client.subscribe(topic, MqttQos.atLeastOnce);
        print("✅ Berlangganan ke $topic");
      }

      _subscription = client.updates?.listen(
        (List<MqttReceivedMessage<MqttMessage?>>? messages) {
          if (messages == null || messages.isEmpty) return;

          for (var recMessage in messages) {
            final topic = recMessage.topic;

            if (_logTopics.contains(topic)) {
              try {
                final MqttPublishMessage mqttMessage = recMessage.payload as MqttPublishMessage;
                final payload = MqttPublishPayload.bytesToStringAsString(mqttMessage.payload.message);

                print("📨 Menerima log dari $topic: $payload");

                if (mounted && payload.isNotEmpty) {
                  final newLog = {
                    'action': payload.trim(),
                    'topic': topic,
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                  };
                  _addNewLog(newLog);
                }
              } catch (payloadError) {
                print("❌ Kesalahan memproses payload pesan: $payloadError");
              }
            }
          }
        },
        onError: (error) {
          print("❌ Kesalahan langganan MQTT: $error");
        },
        onDone: () {
          print("📡 Langganan MQTT ditutup");
        },
      );
    } catch (e) {
      print("❌ Kesalahan saat menyiapkan langganan MQTT: $e");
    }
  }

  // Format timestamp
  String _formatTimestamp(int timestamp) {
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      final second = date.second.toString().padLeft(2, '0');

      return "$day/$month/${date.year} $hour:$minute:$second";
    } catch (e) {
      return "Waktu tidak valid";
    }
  }

  // Menghapus semua log
  void _clearLogs() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text("Hapus Semua Log"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Apakah Anda yakin ingin menghapus semua ${logList.length} log?"),
              SizedBox(height: 8),
              Text(
                "Tindakan ini tidak dapat dibatalkan dan semua riwayat aktivitas akan hilang permanen.",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _performClearLogs();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text("Hapus Semua"),
            ),
          ],
        );
      },
    );
  }

  // Melaksanakan penghapusan log
  Future<void> _performClearLogs() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text("Menghapus log..."),
              ],
            ),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.remove(_logStorageKey);

      if (success) {
        setState(() {
          logList.clear();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text("✅ Semua log berhasil dihapus"),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        }

        print("✅ Berhasil menghapus ${logList.length} log dari penyimpanan dan UI");
      } else {
        throw Exception("Gagal menghapus data dari SharedPreferences");
      }
    } catch (e) {
      print("❌ Kesalahan saat menghapus log: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text("❌ Gagal menghapus log: ${e.toString()}")),
              ],
            ),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: "Coba Lagi",
              textColor: Colors.white,
              onPressed: () => _performClearLogs(),
            ),
          ),
        );
      }
    }
  }

  // Mengekspor log
  Future<void> _exportLogs() async {
    if (logList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Tidak ada log untuk diekspor"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      String exportData = "No,Timestamp,Formatted_Time,Action,Topic,Status\n";

      for (int i = 0; i < logList.length; i++) {
        final log = logList[i];
        final timestamp = log['timestamp'] ?? 0;
        final action = (log['action'] ?? '').replaceAll(',', ';').replaceAll('\n', ' ');
        final topic = log['topic'] ?? '';
        final formattedTime = _formatTimestamp(timestamp);
        final status = _getTopicLabel(topic);

        exportData += "${i + 1},$timestamp,\"$formattedTime\",\"$action\",$topic,$status\n";
      }

      final now = DateTime.now();
      final dateStr = "${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}";

      print("Data ekspor siap: ${exportData.length} karakter");
      print("📊 Ringkasan ekspor: ${logList.length} log dari Smart Locker pada $dateStr");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("📊 Data siap diekspor (${logList.length} log) - $dateStr"),
            backgroundColor: Colors.blue,
            action: SnackBarAction(
              label: "Info",
              textColor: Colors.white,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text("Informasi Ekspor"),
                    content: Text(
                      "Data log berhasil diformat dalam format CSV.\n\n"
                      "Total: ${logList.length} entri log\n"
                      "Periode: ${logList.isNotEmpty ? _formatTimestamp(logList.last['timestamp']) : 'N/A'} - ${logList.isNotEmpty ? _formatTimestamp(logList.first['timestamp']) : 'N/A'}\n\n"
                      "Untuk menyimpan ke file, gunakan plugin seperti share_plus atau file_picker.",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("OK"),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      print("❌ Kesalahan saat mengekspor log: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Gagal mengekspor log: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Menentukan warna log
  Color _getLogColor(String action) {
    final actionLower = action.toLowerCase();
    if (actionLower.contains("✅") || actionLower.contains("berhasil") || actionLower.contains("akses diberikan") || actionLower.contains("success")) {
      return Colors.green;
    } else if (actionLower.contains("❌") || actionLower.contains("error") || actionLower.contains("ditolak") || actionLower.contains("gagal") || actionLower.contains("fail") || actionLower.contains("denied")) {
      return Colors.red;
    } else if (actionLower.contains("⚠") || actionLower.contains("warning") || actionLower.contains("duplikat") || actionLower.contains("duplicate")) {
      return Colors.orange;
    } else if (actionLower.contains("🎉") || actionLower.contains("terdaftar") || actionLower.contains("registered")) {
      return Colors.blue;
    }
    return Colors.grey;
  }

  // Menentukan ikon log
  IconData _getLogIcon(String action) {
    final actionLower = action.toLowerCase();
    if (actionLower.contains("✅") || actionLower.contains("berhasil") || actionLower.contains("akses diberikan") || actionLower.contains("success")) {
      return Icons.check_circle;
    } else if (actionLower.contains("❌") || actionLower.contains("error") || actionLower.contains("ditolak") || actionLower.contains("gagal") || actionLower.contains("fail") || actionLower.contains("denied")) {
      return Icons.error;
    } else if (actionLower.contains("⚠") || actionLower.contains("warning") || actionLower.contains("duplikat") || actionLower.contains("duplicate")) {
      return Icons.warning;
    } else if (actionLower.contains("🎉") || actionLower.contains("terdaftar") || actionLower.contains("registered")) {
      return Icons.celebration;
    } else if (actionLower.contains("terbuka") || actionLower.contains("akses disetujui")) {
      return Icons.lock_open;
    } else if (actionLower.contains("sidik jari") || actionLower.contains("fingerprint")) {
      return Icons.fingerprint;
    } else if (actionLower.contains("tidak terdaftar") || actionLower.contains("not registered")) {
      return Icons.person_off;
    }
    return Icons.info;
  }

  // Menentukan label topik
  String _getTopicLabel(String topic) {
    switch (topic) {
      case 'smartlocker/fingerprint/success':
        return 'BERHASIL';
      case 'smartlocker/fingerprint/fail':
        return 'GAGAL';
      case 'smartlocker/fingerprint/denied':
        return 'DITOLAK';
      case 'smartlocker/fingerprint/duplicate':
        return 'DUPLIKAT';
      case 'smartlocker/fingerprint/tidak_terdaftar':
        return 'TIDAK TERDAFTAR';
      default:
        return 'TIDAK DIKETAHUI';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Log Aktivitas"),
          backgroundColor: Colors.blue,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Memuat log tersimpan..."),
              SizedBox(height: 8),
              Text(
                "Mohon tunggu sebentar",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Log Aktivitas (${logList.length})"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isMqttConnected ? Icons.wifi : Icons.wifi_off,
                  color: _isMqttConnected ? Colors.lightGreen : Colors.redAccent,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  _isMqttConnected ? "Online" : "Offline",
                  style: TextStyle(
                    color: _isMqttConnected ? Colors.lightGreen : Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (logList.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _exportLogs,
              tooltip: "Ekspor log",
            ),
          if (logList.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _clearLogs,
              tooltip: "Hapus semua log",
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isMqttConnected ? Colors.green.shade50 : Colors.red.shade50,
              border: Border(
                bottom: BorderSide(
                  color: _isMqttConnected ? Colors.green.shade200 : Colors.red.shade200,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isMqttConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _isMqttConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isMqttConnected
                            ? "✅ Sistem terhubung - Log realtime aktif"
                            : "⚠️ Sistem tidak terhubung - Menunggu koneksi...",
                        style: TextStyle(
                          color: _isMqttConnected ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        "${_logTopics.length} topik • ${logList.length} log tersimpan • Maks: $_maxLogCount log",
                        style: TextStyle(
                          color: _isMqttConnected ? Colors.green.shade600 : Colors.red.shade600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: logList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Belum ada log aktivitas",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isMqttConnected
                              ? "Gunakan sensor sidik jari untuk melihat log di sini"
                              : "Pastikan perangkat terhubung ke internet",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        if (!_isMqttConnected)
                          ElevatedButton.icon(
                            onPressed: () {
                              _checkMqttConnection();
                              _subscribeToLogTopics();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text("Coba Koneksi Ulang"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: logList.length,
                    itemBuilder: (context, index) {
                      final log = logList[index];
                      final action = log["action"] ?? "Aksi tidak diketahui";
                      final topic = log["topic"] ?? "";
                      final timestamp = log["timestamp"] ?? 0;
                      final color = _getLogColor(action);
                      final icon = _getLogIcon(action);

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        elevation: 1,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.1),
                            child: Icon(icon, color: color, size: 18),
                          ),
                          title: Text(
                            action,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(
                                _formatTimestamp(timestamp),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              if (topic.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _getTopicLabel(topic),
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "#${logList.length - index}",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade400,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (index < 3)
                                Icon(
                                  Icons.fiber_new,
                                  size: 12,
                                  color: Colors.orange.shade600,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}