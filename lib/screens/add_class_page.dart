import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'add_students_to_class_page.dart';

class AddClassPage extends StatefulWidget {
  const AddClassPage({super.key});

  @override
  State<AddClassPage> createState() => _AddClassPageState();
}

class _AddClassPageState extends State<AddClassPage> {
  final _classNameController = TextEditingController();
  final _studentNameController = TextEditingController();
  final List<String> students = [];

  final dbRef = FirebaseDatabase.instance.ref();

  bool _isLoading = false;

  void _addStudent() {
    final name = _studentNameController.text.trim();
    if (name.isNotEmpty) {
      if (students.contains(name)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Mahasiswa '$name' sudah ada.")),
          );
        }
      } else {
        setState(() {
          students.add(name);
          _studentNameController.clear();
        });
      }
    }
  }

  void _removeStudent(String studentName) {
    setState(() {
      students.remove(studentName);
    });
  }

  Future<void> _saveClassToFirebase() async {
    var className = _classNameController.text.trim();

    if (className.isEmpty) {
      _showErrorMessage("Nama kelas tidak boleh kosong");
      return;
    }

    // Ganti spasi dengan underscore dan hapus karakter tidak valid
    final safeClassName = className.replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^\w]'), '');

    if (className != safeClassName) {
      _showWarningMessage("Nama kelas '$className' telah diubah menjadi '$safeClassName' untuk kompatibilitas.");
      className = safeClassName;
    }

    if (students.isEmpty) {
      _showErrorMessage("Tambahkan minimal satu mahasiswa");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final classSnapshot = await dbRef.child('classes/$className').get();
      if (classSnapshot.exists) {
        _showErrorMessage("Kelas dengan nama '$className' sudah ada");
        return;
      }

      // Ubah List<String> menjadi Map<String, String> dengan indeks
      final Map<String, String> studentsMap = {
        for (int i = 0; i < students.length; i++) i.toString(): students[i]
      };

      await dbRef.child('classes/$className').set({
        'students': studentsMap,
        'createdAt': DateTime.now().toIso8601String(),
        'fingerprints': {}, // Awalnya kosong, diisi saat pendaftaran sidik jari
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Kelas $className berhasil ditambahkan"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("❌ Error saat menyimpan ke Firebase: $e");
      _showErrorMessage("Gagal menyimpan: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showWarningMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _navigateToAddStudentsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddStudentsToClassPage(),
      ),
    );
  }

  @override
  void dispose() {
    _classNameController.dispose();
    _studentNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Tambah Kelas Baru"),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _navigateToAddStudentsPage,
            icon: const Icon(Icons.person_add),
            tooltip: "Tambah mahasiswa ke kelas yang sudah ada",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Info card untuk navigasi ke halaman tambah mahasiswa
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Ingin menambah mahasiswa ke kelas yang sudah ada?",
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ),
                    TextButton(
                      onPressed: _navigateToAddStudentsPage,
                      child: const Text("Klik di sini"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: ListView(
                children: [
                  // Input Nama Kelas
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Nama Kelas",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _classNameController,
                            decoration: const InputDecoration(
                              hintText: "Masukkan nama kelas (contoh: kelas_A)",
                              border: OutlineInputBorder(),
                              helperText: "Gunakan underscore (_) alih-alih spasi",
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Input Daftar Mahasiswa
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Daftar Mahasiswa",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _studentNameController,
                                  decoration: const InputDecoration(
                                    hintText: "Nama mahasiswa",
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => _addStudent(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.add_circle),
                                onPressed: _addStudent,
                                color: Theme.of(context).primaryColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (students.isNotEmpty) ...[
                            Text(
                              "Mahasiswa yang ditambahkan (${students.length}):",
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: students.map((name) => Chip(
                                label: Text(name),
                                onDeleted: () => _removeStudent(name),
                                deleteIcon: const Icon(Icons.close, size: 18),
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tombol Simpan
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveClassToFirebase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text("Menyimpan..."),
                        ],
                      )
                    : const Text(
                        "Simpan Kelas",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}