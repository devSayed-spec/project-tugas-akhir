import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class AddStudentsToClassPage extends StatefulWidget {
  const AddStudentsToClassPage({super.key});

  @override
  State<AddStudentsToClassPage> createState() => _AddStudentsToClassPageState();
}

class _AddStudentsToClassPageState extends State<AddStudentsToClassPage> {
  final _studentNameController = TextEditingController();
  final List<String> existingStudents = [];
  final List<String> newStudents = [];
  final List<String> availableClasses = [];

  final dbRef = FirebaseDatabase.instance.ref();

  String? selectedClass;
  bool _isLoading = false;
  bool _isLoadingClasses = true;

  @override
  void initState() {
    super.initState();
    _loadAvailableClasses();
  }

  Future<void> _loadAvailableClasses() async {
    try {
      final snapshot = await dbRef.child('classes').get();
      if (snapshot.exists) {
        final classesData = Map<String, dynamic>.from(snapshot.value as Map);
        final classList = classesData.keys.toList();

        debugPrint("🏫 Available classes: $classList");

        setState(() {
          availableClasses.clear();
          availableClasses.addAll(classList);
          _isLoadingClasses = false;
        });

        debugPrint("✅ Loaded ${availableClasses.length} classes");
      } else {
        setState(() {
          _isLoadingClasses = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error loading classes: $e");
      setState(() {
        _isLoadingClasses = false;
      });
      _showErrorMessage("Gagal memuat daftar kelas");
    }
  }

  Future<void> _loadExistingStudents(String className) async {
    try {
      debugPrint("🔍 Loading students for class: $className");

      final snapshot = await dbRef.child('classes/$className/students').get();

      setState(() {
        existingStudents.clear();
      });

      if (snapshot.exists && snapshot.value != null) {
        debugPrint("📋 Raw students data: ${snapshot.value}");

        // Pastikan data diolah sebagai daftar yang dapat diubah
        final studentsData = snapshot.value;
        if (studentsData is List) {
          final studentsList = studentsData.cast<String>().toList();
          setState(() {
            existingStudents.addAll(studentsList);
          });
        } else if (studentsData is Map) {
          // Jika data disimpan sebagai Map (key-value), konversi ke List
          final studentsList = studentsData.values.map((v) => v.toString()).toList();
          setState(() {
            existingStudents.addAll(studentsList);
          });
        }

        debugPrint("👥 Parsed students: $existingStudents");
        debugPrint("✅ Successfully loaded ${existingStudents.length} students");
      } else {
        debugPrint("⚠️ No students found for class $className");
        setState(() {
          existingStudents.clear();
        });
      }
    } catch (e) {
      debugPrint("❌ Error loading existing students: $e");
      _showErrorMessage("Gagal memuat daftar mahasiswa: ${e.toString()}");
    }
  }

  void _onClassSelected(String? className) {
    debugPrint("🎯 Class selected: '$className'");

    if (className != null && className.isNotEmpty) {
      setState(() {
        selectedClass = className;
        newStudents.clear();
        _studentNameController.clear();
      });

      debugPrint("📚 Loading students for selected class: '$className'");
      _loadExistingStudents(className);
    } else {
      debugPrint("⚠️ No class selected or className is empty");
    }
  }

  void _addStudent() {
    final name = _studentNameController.text.trim();
    if (name.isEmpty) return;

    // Cek apakah mahasiswa sudah ada di kelas
    if (existingStudents.contains(name)) {
      _showErrorMessage("Mahasiswa '$name' sudah ada di kelas ini");
      return;
    }

    // Cek apakah mahasiswa sudah ditambahkan ke daftar baru
    if (newStudents.contains(name)) {
      _showErrorMessage("Mahasiswa '$name' sudah ada di daftar yang akan ditambahkan");
      return;
    }

    setState(() {
      newStudents.add(name);
      _studentNameController.clear();
    });
  }

  void _removeNewStudent(String studentName) {
    setState(() {
      newStudents.remove(studentName);
    });
  }

  Future<void> _saveNewStudentsToFirebase() async {
    if (selectedClass == null) {
      _showErrorMessage("Pilih kelas terlebih dahulu");
      return;
    }

    if (newStudents.isEmpty) {
      _showErrorMessage("Tambahkan minimal satu mahasiswa baru");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Ambil data mahasiswa yang sudah ada
      final snapshot = await dbRef.child('classes/$selectedClass/students').get();
      List<String> studentsList = [];

      if (snapshot.exists && snapshot.value != null) {
        final studentsData = snapshot.value;
        if (studentsData is List) {
          studentsList = studentsData.cast<String>().toList();
        } else if (studentsData is Map) {
          studentsList = studentsData.values.map((v) => v.toString()).toList();
        }
      }

      // Tambahkan mahasiswa baru
      studentsList.addAll(newStudents);

      // Update ke Firebase dengan array
      await dbRef.child('classes/$selectedClass/students').set(studentsList);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ ${newStudents.length} mahasiswa berhasil ditambahkan ke kelas $selectedClass"),
            backgroundColor: Colors.green,
          ),
        );

        // Reset form
        setState(() {
          newStudents.clear();
          _studentNameController.clear();
        });

        // Reload existing students to show updated list
        _loadExistingStudents(selectedClass!);
      }
    } catch (e) {
      debugPrint("❌ Error saat menambah mahasiswa: $e");
      _showErrorMessage("Gagal menambah mahasiswa: ${e.toString()}");
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

  @override
  void dispose() {
    _studentNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Tambah Mahasiswa ke Kelas"),
        elevation: 0,
      ),
      body: _isLoadingClasses
          ? const Center(child: CircularProgressIndicator())
          : availableClasses.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.class_, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        "Belum ada kelas tersedia",
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Buat kelas baru terlebih dahulu",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          children: [
                            // Pilih Kelas
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Pilih Kelas",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      value: selectedClass,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: "Pilih kelas",
                                      ),
                                      items: availableClasses.map((className) {
                                        return DropdownMenuItem<String>(
                                          value: className,
                                          child: Text(className),
                                        );
                                      }).toList(),
                                      onChanged: _onClassSelected,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Pilih kelas terlebih dahulu';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Mahasiswa yang sudah ada (jika kelas dipilih)
                            if (selectedClass != null) ...[
                              const SizedBox(height: 16),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Mahasiswa di kelas $selectedClass (${existingStudents.length})",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if (existingStudents.isEmpty)
                                        const Text(
                                          "Belum ada mahasiswa di kelas ini",
                                          style: TextStyle(color: Colors.grey),
                                        )
                                      else
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: existingStudents.map((name) => Chip(
                                            label: Text(name),
                                            backgroundColor: Colors.blue.shade50,
                                          )).toList(),
                                        ),
                                    ],
                                  ),
                                ),
                             ),

                              const SizedBox(height: 16),

                              // Input Mahasiswa Baru
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Tambah Mahasiswa Baru",
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
                                                hintText: "Nama mahasiswa baru",
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
                                      if (newStudents.isNotEmpty) ...[
                                        Text(
                                          "Akan ditambahkan (${newStudents.length}):",
                                          style: const TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: newStudents.map((name) => Chip(
                                            label: Text(name),
                                            onDeleted: () => _removeNewStudent(name),
                                            deleteIcon: const Icon(Icons.close, size: 18),
                                            backgroundColor: Colors.green.shade50,
                                          )).toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                             ),
                            ],
                          ],
                        ),
                      ),

                      // Tombol Simpan
                      if (selectedClass != null && newStudents.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _saveNewStudentsToFirebase,
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
                                : Text(
                                    "Tambah ${newStudents.length} Mahasiswa",
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}