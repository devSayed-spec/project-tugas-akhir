import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

class FingerprintListPage extends StatefulWidget {
  final String? activeClass;
  
  const FingerprintListPage({Key? key, this.activeClass}) : super(key: key);

  @override
  _FingerprintListPageState createState() => _FingerprintListPageState();
}

class _FingerprintListPageState extends State<FingerprintListPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  List<FingerprintData> fingerprintList = [];
  bool isLoading = true;
  String? errorMessage;

  StreamSubscription<DatabaseEvent>? _fingerprintsSubscription;

  @override
  void initState() {
    super.initState();
    _loadFingerprintData();
    _setupRealtimeUpdates();
  }

  @override
  void dispose() {
    _fingerprintsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadFingerprintData() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      print('Fetching fingerprint mapping data...');
      final fingerprintMappingSnapshot = await _database.child('fingerprint_mapping').get();

      if (!fingerprintMappingSnapshot.exists) {
        print('No fingerprint mapping data found');
        setState(() {
          fingerprintList = [];
          isLoading = false;
          errorMessage = 'Tidak ada data sidik jari di Firebase.';
        });
        return;
      }

      List<FingerprintData> tempList = [];
      final mappingValue = fingerprintMappingSnapshot.value;
      
      // Debug: Print the actual structure
      print('Firebase data type: ${mappingValue.runtimeType}');
      print('Firebase data: $mappingValue');

      // Handle different data structures
      Map<dynamic, dynamic>? mappingData;
      
      if (mappingValue is Map) {
        mappingData = Map<dynamic, dynamic>.from(mappingValue);
      } else if (mappingValue is List) {
        // Convert List to Map if needed
        mappingData = {};
        for (int i = 0; i < mappingValue.length; i++) {
          if (mappingValue[i] != null) {
            mappingData[i.toString()] = mappingValue[i];
          }
        }
      } else {
        throw Exception('Unexpected data type: ${mappingValue.runtimeType}');
      }

      if (mappingData.isEmpty) {
        setState(() {
          fingerprintList = [];
          isLoading = false;
          errorMessage = 'Data mapping kosong.';
        });
        return;
      }

      // Iterasi melalui sensor1 dan sensor2
      mappingData.forEach((sensorKey, sensorValue) {
        print('Processing sensor: $sensorKey');
        
        if (sensorKey.toString().startsWith('sensor') && sensorValue != null) {
          String sensorNumber = sensorKey.toString().replaceAll('sensor', '');
          
          // Handle sensor data
          Map<dynamic, dynamic>? sensorData;
          if (sensorValue is Map) {
            sensorData = Map<dynamic, dynamic>.from(sensorValue);
          } else if (sensorValue is List) {
            sensorData = {};
            for (int i = 0; i < sensorValue.length; i++) {
              if (sensorValue[i] != null) {
                sensorData[i.toString()] = sensorValue[i];
              }
            }
          }
          
          if (sensorData != null) {
            // Iterasi melalui setiap fingerprint ID dalam sensor
            sensorData.forEach((fingerprintId, fingerprintValue) {
              if (fingerprintValue != null) {
                try {
                  Map<dynamic, dynamic> fingerprintInfo;
                  if (fingerprintValue is Map) {
                    fingerprintInfo = Map<dynamic, dynamic>.from(fingerprintValue);
                  } else {
                    print('Skipping invalid fingerprint data: $fingerprintValue');
                    return;
                  }
                  
                  final studentId = fingerprintInfo['studentId']?.toString() ?? 'Unknown';
                  final studentName = fingerprintInfo['studentName']?.toString() ?? 'Unknown';
                  final className = fingerprintInfo['class']?.toString() ?? 'Unknown';
                  final fingerType = fingerprintInfo['fingerType']?.toString() ?? 'Unknown';
                  final enrolledAtStr = fingerprintInfo['enrolledAt']?.toString() ?? '';
                  
                  DateTime registeredAt = DateTime.now();
                  if (enrolledAtStr.isNotEmpty) {
                    try {
                      // Konversi dari epoch seconds ke DateTime
                      registeredAt = DateTime.fromMillisecondsSinceEpoch(
                        int.parse(enrolledAtStr) * 1000
                      );
                    } catch (e) {
                      print('Error parsing enrolledAt: $e');
                    }
                  }
                  
                  tempList.add(FingerprintData(
                    id: fingerprintId.toString(),
                    studentId: studentId,
                    studentName: studentName,
                    className: className,
                    fingerType: fingerType,
                    sensorNumber: sensorNumber,
                    registeredAt: registeredAt,
                  ));
                  
                  print('Added fingerprint: ID=$fingerprintId, Student=$studentName, Sensor=$sensorNumber');
                } catch (e) {
                  print('Error processing fingerprint $fingerprintId: $e');
                }
              }
            });
          }
        }
      });

      // Urutkan berdasarkan waktu registrasi (terbaru dulu)
      tempList.sort((a, b) => b.registeredAt.compareTo(a.registeredAt));

      // Filter berdasarkan kelas aktif jika ada
      if (widget.activeClass != null && widget.activeClass!.isNotEmpty) {
        tempList = tempList.where((fingerprint) => 
          fingerprint.className.toLowerCase() == widget.activeClass!.toLowerCase()
        ).toList();
      }

      setState(() {
        fingerprintList = tempList;
        isLoading = false;
      });

      print('Loaded ${tempList.length} fingerprints for class: ${widget.activeClass ?? 'All'}');

    } catch (e, stackTrace) {
      print('Error loading fingerprint data: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        errorMessage = 'Error loading data: $e';
        isLoading = false;
      });
    }
  }

  void _setupRealtimeUpdates() {
    _fingerprintsSubscription = _database.child('fingerprint_mapping').onValue.listen(
      (event) {
        print('Realtime update detected');
        _loadFingerprintData();
      },
      onError: (error) {
        print('Realtime listener error: $error');
        setState(() {
          errorMessage = 'Realtime update error: $error';
        });
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Daftar Sidik Jari'),
            if (widget.activeClass != null && widget.activeClass!.isNotEmpty)
              Text(
                'Kelas: ${widget.activeClass}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFingerprintData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Memuat data sidik jari...'),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFingerprintData,
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      );
    }

    if (fingerprintList.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fingerprint, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Tidak ada sidik jari untuk kelas ini',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Sidik jari akan muncul saat kelas sedang aktif',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.info, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.activeClass != null && widget.activeClass!.isNotEmpty
                          ? 'Kelas ${widget.activeClass}: ${fingerprintList.length} sidik jari'
                          : 'Total: ${fingerprintList.length} sidik jari terdaftar',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.blue,
                      ),
                    ),
                    if (widget.activeClass != null && widget.activeClass!.isNotEmpty)
                      const Text(
                        'Menampilkan sidik jari untuk kelas yang sedang aktif',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: fingerprintList.length,
            itemBuilder: (context, index) {
              final fingerprint = fingerprintList[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: fingerprint.sensorNumber == '1' 
                        ? Colors.blue.shade100 
                        : Colors.green.shade100,
                    child: Text(
                      fingerprint.id,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: fingerprint.sensorNumber == '1' 
                            ? Colors.blue 
                            : Colors.green,
                      ),
                    ),
                  ),
                  title: Text(
                    fingerprint.studentName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID Siswa: ${fingerprint.studentId}'),
                      Text('Kelas: ${fingerprint.className}'),
                      Text('Jari: ${fingerprint.fingerType}'),
                      Text(
                        'Sensor: ${fingerprint.sensorNumber} | Terdaftar: ${_formatDate(fingerprint.registeredAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// Data model untuk fingerprint
class FingerprintData {
  final String id;
  final String studentId;
  final String studentName;
  final String className;
  final String fingerType;
  final String sensorNumber;
  final DateTime registeredAt;

  FingerprintData({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.fingerType,
    required this.sensorNumber,
    required this.registeredAt,
  });
}