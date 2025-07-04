import 'dart:convert';
import 'dart:io';
import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CountPage extends StatefulWidget {
  const CountPage({Key? key}) : super(key: key);

  @override
  State<CountPage> createState() => _CountPageState();
}

class _CountPageState extends State<CountPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _image;
  int? _objectCount;
  bool _isLoading = false;
  bool _isSaving = false;

  // Firebase instances
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = pickedFile;
        _objectCount = null;
      });
    }
  }

  void _resetCount() {
    setState(() {
      _image = null;
      _objectCount = null;
    });
  }

  Future<void> _sendImageToBackend() async {
    if (_image == null) return;

    setState(() => _isLoading = true);

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('http://192.168.198.72:5000/predict'),
    );

    request.files.add(await http.MultipartFile.fromPath(
      'file',
      _image!.path,
    ));

    try {
      var response = await request.send();

      if (response.statusCode == 200) {
        var responseBody = await response.stream.bytesToString();
        var jsonResponse = jsonDecode(responseBody);

        int count = jsonResponse['pipe_count'];
        String imageHex = jsonResponse['image'];
        List<int> imageBytes = hex.decode(imageHex);

        final tempDir = await getTemporaryDirectory();
        final filePath =
            '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.png';
        File file = File(filePath);
        await file.writeAsBytes(imageBytes);

        setState(() {
          _image = XFile(filePath);
          _objectCount = count;
          _isLoading = false;
        });

        imageCache.clear();
        imageCache.clearLiveImages();

        // Automatically save to Firebase after processing
        await _saveToFirebase(file, count);
      } else {
        print('Error: ${response.statusCode}');
        setState(() => _isLoading = false);
        _showErrorSnackBar('Failed to process image. Please try again.');
      }
    } catch (e) {
      print('Exception: $e');
      setState(() => _isLoading = false);
      _showErrorSnackBar('Network error. Please check your connection.');
    }
  }

  Future<void> _saveToFirebase(File processedImage, int count) async {
    try {
      setState(() => _isSaving = true);

      // Get current user
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        _showErrorSnackBar('Please sign in to save results.');
        setState(() => _isSaving = false);
        return;
      }

      String uid = currentUser.uid;
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String fileName = 'processed_images/$uid/${timestamp}_processed.png';

      // Upload image to Firebase Storage
      UploadTask uploadTask = _storage.ref().child(fileName).putFile(processedImage);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      // Save metadata to Firestore
      await _firestore.collection('pipe_counts').add({
        'uid': uid,
        'pipe_count': count,
        'image_url': downloadUrl,
        'image_path': fileName,
        'timestamp': FieldValue.serverTimestamp(),
        'created_at': DateTime.now().toIso8601String(),
      });

      await _firestore.collection('users').doc(uid).set({
        'counts_used': FieldValue.increment(1),
      }, SetOptions(merge: true));
      

      setState(() => _isSaving = false);
      _showSuccessSnackBar('Results saved successfully!');
    } catch (e) {
      print('Firebase save error: $e');
      setState(() => _isSaving = false);
      _showErrorSnackBar('Failed to save results. Please try again.');
    }
  }

  Future<void> _saveCurrentResult() async {
    if (_image == null || _objectCount == null) {
      _showErrorSnackBar('No results to save.');
      return;
    }

    File imageFile = File(_image!.path);
    await _saveToFirebase(imageFile, _objectCount!);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF9D78F9),
              Color(0xFF78BDF9),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10), // Back button brought down by 2 pixels
              // Back arrow only
              Row(
                children: [
                  const SizedBox(width: 25),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 0),
              // Camera icon in the center
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_enhance,
                  color: Colors.white,
                  size: 35,
                ),
              ),
              const SizedBox(height: 8),
              // Header text - increased sizes
              const Text(
                "Object Counter",
                style: TextStyle(
                  fontSize: 26, // Increased by 2
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "AI-powered object detection and counting",
                style: TextStyle(
                  fontSize: 16, // Increased by 2
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 12),
              // White card container with positive margin only
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(25, 0, 25, 30), // Changed from -8 to 0
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(25),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Image Display Area - Balanced size
                      Expanded(
                        flex: 3, // Back to 3 for better balance
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: _image != null
                                    ? Image.file(
                                        File(_image!.path),
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.contain,
                                      )
                                    : Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.image_outlined,
                                            size: 64,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'No image selected',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey.shade500,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Choose from gallery or camera',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey.shade400,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                              if (_isLoading || _isSaving)
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(102),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          _isLoading ? "Processing..." : "Saving...",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: _buildActionButton(
                              icon: Icons.image_outlined,
                              text: "Gallery",
                              onTap: () => _pickImage(ImageSource.gallery),
                              isEnabled: !_isLoading && !_isSaving,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildActionButton(
                              icon: Icons.camera_alt_outlined,
                              text: "Camera",
                              onTap: () => _pickImage(ImageSource.camera),
                              isEnabled: !_isLoading && !_isSaving,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildActionButton(
                              icon: Icons.send_outlined,
                              text: "Analyze",
                              onTap: (_image != null && !_isLoading && !_isSaving) ? _sendImageToBackend : null,
                              isEnabled: _image != null && !_isLoading && !_isSaving,
                              isPrimary: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildActionButton(
                              icon: Icons.refresh_outlined,
                              text: "Reset",
                              onTap: (_image != null && !_isLoading && !_isSaving) ? _resetCount : null,
                              isEnabled: _image != null && !_isLoading && !_isSaving,
                              isDestructive: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16), // Reduced spacing

                      // Improved Result Display - Cleaner and more subtle
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16), // Reduced padding
                        decoration: BoxDecoration(
                          color: _objectCount != null ? Colors.grey.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12), // Smaller radius
                          border: Border.all(
                            color: _objectCount != null ? const Color(0xFF9D78F9).withAlpha(51) : Colors.grey.shade200,
                            width: _objectCount != null ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Icon on the left
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _objectCount != null 
                                    ? const Color(0xFF9D78F9).withAlpha(26)
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _objectCount != null ? Icons.analytics_outlined : Icons.search_outlined,
                                size: 20,
                                color: _objectCount != null 
                                    ? const Color(0xFF9D78F9)
                                    : Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Text content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Pipe Count",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: _objectCount != null 
                                          ? Colors.grey.shade700
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _objectCount != null ? "$_objectCount pipes detected" : "No analysis yet",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Count number on the right
                            if (_objectCount != null)
                              Text(
                                "$_objectCount",
                                style: const TextStyle(
                                  fontSize: 20, // Much smaller than before
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF9D78F9),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String text,
    required VoidCallback? onTap,
    required bool isEnabled,
    bool isPrimary = false,
    bool isDestructive = false,
    bool isSecondary = false,
  }) {
    Color getButtonColor() {
      if (!isEnabled) return Colors.grey.shade300;
      if (isPrimary) return const Color(0xFF9D78F9);
      if (isDestructive) return Colors.red.shade400;
      if (isSecondary) return Colors.green.shade400;
      return Colors.grey.shade100;
    }

    Color getTextColor() {
      if (!isEnabled) return Colors.grey.shade500;
      if (isPrimary || isDestructive || isSecondary) return Colors.white;
      return Colors.grey.shade700;
    }

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: (isPrimary || isSecondary) && isEnabled
            ? null
            : getButtonColor(),
        gradient: isPrimary && isEnabled
            ? const LinearGradient(
                colors: [Color(0xFF9D78F9), Color(0xFF78BDF9)],
              )
            : isSecondary && isEnabled
                ? LinearGradient(
                    colors: [Colors.green.shade400, Colors.green.shade600],
                  )
                : null,
        borderRadius: BorderRadius.circular(16),
        border: !isPrimary && !isDestructive && !isSecondary
            ? Border.all(color: Colors.grey.shade300)
            : null,
        boxShadow: isPrimary && isEnabled
            ? [
                BoxShadow(
                  color: const Color(0xFF9D78F9).withAlpha(77),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : isDestructive && isEnabled
                ? [
                    BoxShadow(
                      color: Colors.red.shade400.withAlpha(77),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : isSecondary && isEnabled
                    ? [
                        BoxShadow(
                          color: Colors.green.shade400.withAlpha(77),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: getTextColor(),
              ),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: getTextColor(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}