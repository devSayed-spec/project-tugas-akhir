import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mqtt_client/mqtt_client.dart';

class RegisterFingerprintPage extends StatefulWidget {
  final MqttClient mqttClient;
  const RegisterFingerprintPage({super.key, required this.mqttClient});

  @override
  State<RegisterFingerprintPage> createState() => _RegisterFingerprintPageState();
}

class _RegisterFingerprintPageState extends State<RegisterFingerprintPage> {
  final DatabaseReference db = FirebaseDatabase.instance.ref();
  List<String> classList = [];
  String? selectedClass;
  Map<String, String> studentMap = {}; // ID -> Nama
  Map<String, Map<String, Map<String, String>>> fingerprintsMap = {}; // MahasiswaID -> {Jempol Kanan_<timestamp>: {...}, Jempol Kiri_<timestamp>: {...}}
  bool isLoading = false;
  bool isLoadingData = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final List<String> fingerOptions = ['Jempol Kanan', 'Jempol Kiri'];
  String? selectedFinger;
  final List<String> sensorOptions = ['Sensor 1', 'Sensor 2'];
  String? selectedSensor;

  @override
  void initState() {
    super.initState();
    fetchClasses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchClasses() async {
    setState(() => isLoadingData = true);
    try {
      final snapshot = await db.child('classes').get();
      if (snapshot.exists && mounted) {
        final classesData = snapshot.value;
        if (classesData is Map) {
          final classes = Map<String, dynamic>.from(classesData);
          setState(() {
            classList = classes.keys.toList()..sort();
          });
        }
      }
    } catch (e, st) {
      debugPrint("Error fetching classes: $e\n$st");
      if (mounted) {
        _showErrorSnackBar("Gagal memuat daftar kelas. Silakan coba lagi.", e);
      }
    } finally {
      if (mounted) {
        setState(() => isLoadingData = false);
      }
    }
  }

  Future<void> fetchStudentsAndFingerprints() async {
    if (selectedClass == null) return;

    setState(() => isLoadingData = true);
    try {
      debugPrint("🔍 Fetching data for class: $selectedClass");

      final studentsSnap = await db.child('classes/$selectedClass/students').get();
      final fingerprintsSnap = await db.child('classes/$selectedClass/fingerprints').get();

      debugPrint("📚 Students snapshot exists: ${studentsSnap.exists}");
      debugPrint("👆 Fingerprints snapshot exists: ${fingerprintsSnap.exists}");

      if (studentsSnap.exists) {
        debugPrint("📝 Students raw data: ${studentsSnap.value}");
      }

      final students = await _processStudentsData(studentsSnap);
      final fps = await _processFingerprintsData(fingerprintsSnap);

      debugPrint("✅ Processed students: $students");
      debugPrint("✅ Processed fingerprints: $fps");

      if (mounted) {
        setState(() {
          studentMap = students;
          fingerprintsMap = fps;
          _searchQuery = '';
          _searchController.clear();
        });
      }
    } catch (e, st) {
      debugPrint("❌ Error fetching students and fingerprints: $e\n$st");
      if (mounted) {
        _showErrorSnackBar("Gagal memuat daftar mahasiswa dan sidik jari. Silakan coba lagi.", e);
      }
    } finally {
      if (mounted) {
        setState(() => isLoadingData = false);
      }
    }
  }

  Future<Map<String, String>> _processStudentsData(DataSnapshot studentsSnap) async {
    Map<String, String> students = {};

    if (studentsSnap.exists) {
      final studentsValue = studentsSnap.value;
      debugPrint("🔄 Processing students data type: ${studentsValue.runtimeType}");
      debugPrint("🔄 Students raw value: $studentsValue");

      if (studentsValue is Map) {
        final studentsData = Map<String, dynamic>.from(studentsValue);
        debugPrint("🔄 Students data as Map: $studentsData");

        studentsData.forEach((key, value) {
          if (value != null) {
            students[key] = value.toString();
            debugPrint("✅ Added student: $key -> ${value.toString()}");
          }
        });
      } else if (studentsValue is List) {
        final studentsList = List<dynamic>.from(studentsValue);
        for (int i = 0; i < studentsList.length; i++) {
          if (studentsList[i] != null) {
            students[i.toString()] = studentsList[i].toString();
            debugPrint("✅ Added student from list: $i -> ${studentsList[i].toString()}");
          }
        }
      }
    } else {
      debugPrint("⚠ No students data found");
    }

    debugPrint("🎯 Final students map: $students");
    return students;
  }

  Future<Map<String, Map<String, Map<String, String>>>> _processFingerprintsData(DataSnapshot fingerprintsSnap) async {
    Map<String, Map<String, Map<String, String>>> fps = {};

    if (fingerprintsSnap.exists) {
      final fingerprintsValue = fingerprintsSnap.value;
      if (fingerprintsValue is Map) {
        final fingerprintsData = Map<String, dynamic>.from(fingerprintsValue);

        for (var studentEntry in fingerprintsData.entries) {
          String studentId = studentEntry.key;
          final fingerMapRaw = studentEntry.value;
          if (fingerMapRaw is Map) {
            final fingerMap = Map<String, dynamic>.from(fingerMapRaw);
            Map<String, Map<String, String>> fingerDataPerStudent = {};

            for (var fingerEntry in fingerMap.entries) {
              String fingerName = fingerEntry.key;
              final detail = fingerEntry.value;
              if (detail is Map) {
                final detailMap = Map<String, dynamic>.from(detail);
                String name = detailMap['name']?.toString() ?? '';
                String finger = detailMap['finger']?.toString() ?? '';
                String sensor = detailMap['sensor']?.toString() ?? '';
                if (name.isNotEmpty && finger.isNotEmpty) {
                  fingerDataPerStudent[fingerName] = {
                    'name': name,
                    'finger': finger,
                    'sensor': sensor,
                  };
                }
              }
            }
            if (fingerDataPerStudent.isNotEmpty) {
              fps[studentId] = fingerDataPerStudent;
            }
          }
        }
      }
    }
    return fps;
  }

  void _showErrorSnackBar(String message, dynamic error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: "Detail",
          onPressed: () => _showErrorDialog(error),
        ),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  void _showErrorDialog(dynamic error) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Detail Kesalahan"),
        content: SingleChildScrollView(child: Text(error.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Tutup"),
          ),
        ],
      ),
    );
  }

  Future<void> registerFingerprint(String studentId, String studentName) async {
    if (selectedClass == null) return;

    final existingFingerprintsForStudent = fingerprintsMap[studentId] ?? {};

    if (existingFingerprintsForStudent.length >= 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$studentName sudah memiliki maksimal 2 sidik jari")),
        );
      }
      return;
    }

    final registeredFingers = existingFingerprintsForStudent.keys.map((key) => key.split('_')[0]).toList();

    final confirm = await _showRegistrationDialog(studentName, registeredFingers);
    if (confirm != true || selectedFinger == null || selectedSensor == null) return;

    await _performRegistration(studentId, studentName);
  }

  Future<bool?> _showRegistrationDialog(String studentName, List<String> existingFingers) async {
    selectedFinger = null;
    selectedSensor = null;

    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("Konfirmasi Pendaftaran Sidik Jari"),
          content: _buildRegistrationDialogContent(studentName, existingFingers, setStateDialog),
          actions: _buildRegistrationDialogActions(),
        ),
      ),
    );
  }

  Widget _buildRegistrationDialogContent(String studentName, List<String> existingFingers, StateSetter setStateDialog) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Nama: $studentName", style: const TextStyle(fontWeight: FontWeight.bold)),
        Text("Kelas: $selectedClass", style: const TextStyle(fontWeight: FontWeight.bold)),
        if (existingFingers.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            "Jari yang sudah terdaftar: ${existingFingers.join(', ')}",
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange.shade700,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: selectedFinger,
          items: fingerOptions.map((f) {
            final isAlreadyRegistered = existingFingers.contains(f);
            return DropdownMenuItem(
              value: f,
              enabled: !isAlreadyRegistered,
              child: Text(
                f,
                style: TextStyle(
                  color: isAlreadyRegistered ? Colors.grey : Colors.black,
                ),
              ),
            );
          }).toList(),
          onChanged: (val) => setStateDialog(() => selectedFinger = val),
          decoration: const InputDecoration(
            labelText: 'Pilih Jari',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: selectedSensor,
          items: sensorOptions.map((s) {
            return DropdownMenuItem(
              value: s,
              child: Text(s),
            );
          }).toList(),
          onChanged: (val) => setStateDialog(() => selectedSensor = val),
          decoration: const InputDecoration(
            labelText: 'Pilih Sensor',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoContainer(),
      ],
    );
  }

  Widget _buildInfoContainer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Pastikan sensor sidik jari siap untuk registrasi!",
              style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRegistrationDialogActions() {
    return [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text("Batal"),
      ),
      ElevatedButton.icon(
        onPressed: (selectedFinger == null || selectedSensor == null) ? null : () => Navigator.pop(context, true),
        icon: const Icon(Icons.fingerprint, size: 18),
        label: const Text("Daftarkan"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
    ];
  }

  Future<void> _performRegistration(String studentId, String studentName) async {
    setState(() => isLoading = true);

    try {
      if (studentName.trim().isEmpty || selectedFinger!.trim().isEmpty || selectedSensor!.trim().isEmpty) {
        throw Exception("Nama siswa, jari, atau sensor yang dipilih tidak valid.");
      }

      await _saveFingerprintToDatabase(studentId, studentName);
      await _sendMqttMessage(studentId, studentName);

      if (mounted) {
        _showSuccessMessage(studentName, selectedFinger!, selectedSensor!);
        await fetchStudentsAndFingerprints();
      }
    } catch (e, st) {
      debugPrint("Gagal mendaftar sidik jari: $e\n$st");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal mendaftar sidik jari: ${e.toString()}"),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _saveFingerprintToDatabase(String studentId, String studentName) async {
    final fingerKey = "${selectedFinger!.trim()}_${DateTime.now().millisecondsSinceEpoch}"; // Kunci unik dengan timestamp
    final sensorNumber = selectedSensor == 'Sensor 1' ? '1' : '2';

    final fingerprintData = {
      'name': studentName.trim(),
      'finger': selectedFinger!.trim(),
      'sensor': sensorNumber,
      'createdAt': ServerValue.timestamp, // Menyimpan waktu pembuatan
    };

    await db.child('classes/$selectedClass/fingerprints/$studentId/$fingerKey').set(fingerprintData);
  }

  Future<void> _sendMqttMessage(String studentId, String studentName) async {
    String fingerType;
    if (selectedFinger == "Jempol Kanan") {
      fingerType = "kanan";
    } else if (selectedFinger == "Jempol Kiri") {
      fingerType = "kiri";
    } else {
      throw Exception("Jenis jempol tidak valid: $selectedFinger");
    }

    final sensorNumber = selectedSensor == 'Sensor 1' ? '1' : '2';

    final builder = MqttClientPayloadBuilder();
    builder.addString("$selectedClass:$studentId:$studentName:$fingerType:$sensorNumber");

    widget.mqttClient.publishMessage(
      "smartlocker/enroll",
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  void _showSuccessMessage(String studentName, String finger, String sensor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("✓ Sidik jari $finger untuk $studentName berhasil didaftarkan pada $sensor"),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> deleteFingerprint(String studentId) async {
    if (selectedClass == null) return;

    final studentFingerprints = fingerprintsMap[studentId] ?? {};
    if (studentFingerprints.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Tidak ada sidik jari untuk dihapus")),
        );
      }
      return;
    }

    final selectedFingerToDelete = await _showDeleteFingerprintDialog(studentId, studentFingerprints);
    if (selectedFingerToDelete == null) return;

    setState(() => isLoading = true);

    try {
      // Hapus dari Firebase (classes/<className>/fingerprints)
      await db.child('classes/$selectedClass/fingerprints/$studentId/$selectedFingerToDelete').remove();

      // Kirim perintah hapus ke Arduino via MQTT
      final fingerprintData = studentFingerprints[selectedFingerToDelete]!;
      final sensorNumber = fingerprintData['sensor']!;
      final fingerType = fingerprintData['finger']!.contains('Kanan') ? 'kanan' : 'kiri';
      final studentName = fingerprintData['name']!;

      final builder = MqttClientPayloadBuilder();
      builder.addString("$selectedClass:$studentId:$studentName:$fingerType:$sensorNumber");

      widget.mqttClient.publishMessage(
        "smartlocker/delete",
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✓ Sidik jari $selectedFingerToDelete untuk ID $studentId berhasil dihapus"),
            backgroundColor: Colors.green.shade700,
          ),
        );
        await fetchStudentsAndFingerprints();
      }
    } catch (e, st) {
      debugPrint("Gagal menghapus sidik jari: $e\n$st");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal menghapus sidik jari: ${e.toString()}"),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<String?> _showDeleteFingerprintDialog(String studentId, Map<String, Map<String, String>> fingerprints) async {
    String? selectedFingerToDelete;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("Hapus Sidik Jari"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Pilih sidik jari untuk dihapus dari ID $studentId"),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedFingerToDelete,
                items: fingerprints.keys.map((fingerKey) {
                  final fingerName = fingerKey.split('_')[0]; // Ambil nama jari tanpa timestamp
                  return DropdownMenuItem(
                    value: fingerKey,
                    child: Text(fingerName),
                  );
                }).toList(),
                onChanged: (val) => setStateDialog(() => selectedFingerToDelete = val),
                decoration: const InputDecoration(
                  labelText: 'Pilih Jari',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              onPressed: selectedFingerToDelete == null
                  ? null
                  : () => Navigator.pop(context, selectedFingerToDelete),
              child: const Text("Hapus"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentsList() {
    if (selectedClass == null) return const SizedBox.shrink();

    final filteredStudents = studentMap.entries
        .where((entry) => entry.value.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Container(
      decoration: _buildContainerDecoration(),
      child: Column(
        children: [
          _buildStudentsListHeader(),
          _buildSearchField(),
          _buildStudentsListBody(filteredStudents),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  BoxDecoration _buildContainerDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.1),
          spreadRadius: 1,
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  Widget _buildStudentsListHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.people, color: Colors.blue, size: 20),
          const SizedBox(width: 8),
          Text(
            "Daftar Mahasiswa ($selectedClass)",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          labelText: 'Cari Mahasiswa',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onChanged: (val) {
          setState(() {
            _searchQuery = val.toLowerCase();
          });
        },
      ),
    );
  }

  Widget _buildStudentsListBody(List<MapEntry<String, String>> filteredStudents) {
    if (isLoadingData) {
      return _buildLoadingIndicator();
    } else if (studentMap.isEmpty) {
      return _buildEmptyStudentsMessage();
    } else if (filteredStudents.isEmpty) {
      return _buildNoSearchResultsMessage();
    } else {
      return _buildStudentsListView(filteredStudents);
    }
  }

  Widget _buildLoadingIndicator() {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 8),
          Text("Memuat data mahasiswa..."),
        ],
      ),
    );
  }

  Widget _buildEmptyStudentsMessage() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            "Tidak ada mahasiswa di kelas $selectedClass",
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResultsMessage() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            "Tidak ditemukan mahasiswa dengan kata kunci '$_searchQuery'",
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsListView(List<MapEntry<String, String>> filteredStudents) {
    return SizedBox(
      height: 400,
      child: ListView.builder(
        itemCount: filteredStudents.length,
        itemBuilder: (context, index) {
          final entry = filteredStudents[index];
          final studentName = entry.value;
          final studentId = entry.key;
          final studentFingerprints = fingerprintsMap[studentId] ?? {};
          final fingerprintCount = studentFingerprints.length;
          final hasFingerprint = fingerprintCount > 0;
          final canRegister = fingerprintCount < 2;

          final registeredFingers = studentFingerprints.entries.map((e) {
            return "${e.key.split('_')[0]} (Sensor ${e.value['sensor']})"; // Ambil nama jari tanpa timestamp
          }).join(', ');

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasFingerprint ? Colors.green.shade100 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                hasFingerprint ? Icons.fingerprint : Icons.person_outline,
                color: hasFingerprint ? Colors.green : Colors.grey.shade600,
              ),
            ),
            title: Text(
              studentName,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("ID: $studentId"),
                if (hasFingerprint && registeredFingers.isNotEmpty)
                  Text(
                    "Jari terdaftar: $registeredFingers",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: (isLoading || !canRegister)
                      ? null
                      : () => registerFingerprint(studentId, studentName),
                  icon: Icon(
                    hasFingerprint ? Icons.check_circle : Icons.fingerprint,
                    size: 16,
                  ),
                  label: Text(canRegister ? "Daftar Sidik Jari" : "Penuh ($fingerprintCount/2)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canRegister ? Colors.blue : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                if (hasFingerprint)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => deleteFingerprint(studentId),
                    tooltip: "Hapus Sidik Jari",
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildClassSelector() {
    return Container(
      decoration: _buildContainerDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.class_, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Pilih Kelas",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selectedClass,
                  hint: Text(
                    "-- Pilih Kelas --",
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  items: classList.map((className) => DropdownMenuItem(
                    value: className,
                    child: Text(className),
                  )).toList(),
                  onChanged: (isLoadingData || isLoading) ? null : (val) {
                    setState(() {
                      selectedClass = val;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                    if (val != null) {
                      fetchStudentsAndFingerprints();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Mendaftarkan sidik jari..."),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Registrasi Sidik Jari"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildClassSelector(),
                const SizedBox(height: 16),
                _buildStudentsList(),
                const SizedBox(height: 80),
              ],
            ),
          ),
          if (isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }
}