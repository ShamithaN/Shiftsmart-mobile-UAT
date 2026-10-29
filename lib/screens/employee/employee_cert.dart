import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftsmart/models/empcert_model.dart';
import 'package:shiftsmart/services/employee_service.dart'; // 👈 Import this
import 'package:shiftsmart/utils/fullscreen_helper.dart';
import 'package:shiftsmart/widgets/background.dart';
import 'package:shiftsmart/widgets/emp_slidenav.dart';
import 'package:shiftsmart/widgets/uppernavbar.dart';
import 'package:url_launcher/url_launcher.dart';

class Employeecert extends StatefulWidget {
  const Employeecert({super.key});

  @override
  State<Employeecert> createState() => _EmployeecertState();
}

class _EmployeecertState extends State<Employeecert> {
  List<EmployeeCertificate> _certificates = [];
  bool _isLoading = true;
  bool _isUploading = false;

  final List<String> _docTypes = [
    "National ID",
    "RSA Certificate",
    "White Card",
    "Driver License",
    "Passport",
    "First Aid",
    "Other"
  ];

  @override
  void initState() {
    super.initState();
    enableFullScreen();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final int? empId = prefs.getInt('employeeId') ?? prefs.getInt('userId');

      if (empId != null) {
        final service = EmployeeService();
        // Fetch regular docs and resubmissions in parallel
        final results = await Future.wait([
          service.fetchEmployeeDocuments(empId),
          service.fetchEmployeeResubmissions(empId),
        ]);

        final docs = results[0];
        final resubs = results[1];

        if (mounted) {
          setState(() {
            _certificates = [...docs, ...resubs];
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
        debugPrint("❌ No Employee ID found in SharedPreferences");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading docs: $e")),
        );
      }
    }
  }

  void _showUploadOptions() {
    String selectedType = _docTypes.first;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2230),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Upload New Document",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              // Type Dropdown
              const Text("Document Type",
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButton<String>(
                  value: selectedType,
                  dropdownColor: const Color(0xFF1C2230),
                  isExpanded: true,
                  underline: const SizedBox(),
                  style: const TextStyle(color: Colors.white),
                  items: _docTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setModalState(() => selectedType = val);
                  },
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _uploadOption(
                    context,
                    icon: Icons.camera_alt,
                    label: "Camera",
                    onTap: () => _pickAndUpload(ImageSource.camera, selectedType),
                  ),
                  _uploadOption(
                    context,
                    icon: Icons.photo_library,
                    label: "Gallery",
                    onTap: () => _pickAndUpload(ImageSource.gallery, selectedType),
                  ),
                  _uploadOption(
                    context,
                    icon: Icons.file_present,
                    label: "PDF/File",
                    onTap: () => _pickAndUploadFile(selectedType),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _uploadOption(BuildContext ctx,
      {required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.blueAccent, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source, String type) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: source, imageQuality: 80);
    if (image != null) {
      _executeUpload(File(image.path), type);
    }
  }

  Future<void> _pickAndUploadFile(String type) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
    );
    if (result != null && result.files.single.path != null) {
      _executeUpload(File(result.files.single.path!), type);
    }
  }

  Future<void> _executeUpload(File file, String type) async {
    setState(() => _isUploading = true);
    try {
      final String? url = await EmployeeService().uploadDocument(file, type);
      if (url != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Document uploaded successfully!")),
          );
        }
        _loadDocuments();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to upload document.")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const EmpSidenav(currentScreen: 'EmployeeCert'),
      backgroundColor: const Color(0xFF1C2230),
      appBar: const Uppernavbar(showBackButton: false),
      floatingActionButton: FloatingActionButton(
        onPressed: _isUploading ? null : _showUploadOptions,
        backgroundColor: const Color(0xFF3498DB),
        child: _isUploading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.add, color: Colors.white),
      ),
      body: Stack(children: [
        const Background(),
        Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    "MY DOCUMENTS",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "Documents submitted during onboarding",
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  _buildDocList(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ])
      ]),
    );
  }

  Widget _buildDocList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 50.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_certificates.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 30),
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: const [
            Icon(Icons.folder_off_outlined, size: 40, color: Colors.white38),
            SizedBox(height: 10),
            Text("No documents found.",
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return Column(
      children: _certificates.map((doc) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A3240), Color(0xFF1C2230)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3498DB).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.article_rounded,
                  color: Color(0xFF3498DB),
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),

              // Name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.fileName.toUpperCase(), // Display "NATIONAL ID", etc.
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Verified Document",
                      style: TextStyle(color: Colors.greenAccent, fontSize: 11),
                    ),
                  ],
                ),
              ),

              // View Button
              SizedBox(
                height: 38,
                width: 85,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    final url = doc.documentUrl;
                    if (url.isNotEmpty && await canLaunchUrl(Uri.parse(url))) {
                      await launchUrl(Uri.parse(url),
                          mode: LaunchMode.externalApplication);
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Cannot open document")),
                        );
                      }
                    }
                  },
                  child: const Text("View",
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
