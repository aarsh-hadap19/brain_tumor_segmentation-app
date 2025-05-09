import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';

void main() {
  runApp(const BrainTumorSegmentationApp());
}

class BrainTumorSegmentationApp extends StatelessWidget {
  const BrainTumorSegmentationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brain Tumor Segmentation',
      theme: ThemeData(
        primaryColor: const Color(0xFF2D8CFF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2D8CFF),
          primary: const Color(0xFF2D8CFF),
          secondary: const Color(0xFF60A5FA),
          surface: Colors.white,
          background: const Color(0xFFF5F9FF),
        ),
        fontFamily: 'Poppins',
        scaffoldBackgroundColor: const Color(0xFFF5F9FF),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D8CFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final List<File?> _mriImages = [null, null, null, null];
  final List<String> _mriTypes = ['T1', 'T1CE', 'T2', 'FLAIR'];
  bool _isLoading = false;
  String? _errorMessage;
  List<Uint8List>? _resultImages;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(int index) async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _mriImages[index] = File(pickedFile.path);
      });
    }
  }

  bool _canProcess() {
    return _mriImages.every((image) => image != null);
  }

  Future<void> _processImages() async {
    if (!_canProcess()) {
      setState(() {
        _errorMessage = 'Please upload all four MRI images.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _resultImages = null;
    });

    try {
      // Create a temporary directory to store the zipped files
      final tempDir = await getTemporaryDirectory();
      final patientDir = Directory('${tempDir.path}/patient_folder');

      // Create or clear the directory
      if (await patientDir.exists()) {
        await patientDir.delete(recursive: true);
      }
      await patientDir.create();

      // Copy images to the patient folder
      for (int i = 0; i < _mriImages.length; i++) {
        final File newFile = File('${patientDir.path}/${_mriTypes[i]}.jpg');
        await _mriImages[i]!.copy(newFile.path);
      }

      // Zip the directory
      final zipFile = File('${tempDir.path}/patient_folder.zip');
      if (await zipFile.exists()) {
        await zipFile.delete();
      }

      // Create the zip archive
      final archive = Archive();
      for (int i = 0; i < _mriImages.length; i++) {
        final fileBytes = await _mriImages[i]!.readAsBytes();
        final archiveFile = ArchiveFile('${_mriTypes[i]}.jpg', fileBytes.length, fileBytes);
        archive.addFile(archiveFile);
      }

      final zipData = ZipEncoder().encode(archive);
      await zipFile.writeAsBytes(zipData!);

      // Send the zip file to the API
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://8fb0561436f3441450.gradio.live/predict'),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          zipFile.path,
          filename: 'patient_folder.zip',
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<Uint8List> results = [];

        // Process the returned images
        // The API returns 5 images: 4 segmented images and 1 Grad-CAM
        final List<dynamic> imageData = responseData['images'] ?? [];

        for (final imageBase64 in imageData) {
          final imageBytes = base64Decode(imageBase64.split(',').last);
          results.add(imageBytes);
        }

        setState(() {
          _resultImages = results;
          _isLoading = false;
        });

        // Navigate to results page
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResultsPage(resultImages: _resultImages!),
            ),
          );
        }
      } else {
        throw Exception('Failed to process images: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Brain Tumor Segmentation',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const LoadingScreen()
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Card(
                margin: EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MRI Analysis',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D8CFF),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Upload all four MRI image types to analyze for brain tumor segmentation.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // MRI Image Upload Section
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: 4,
                itemBuilder: (context, index) {
                  return MriUploadCard(
                    mriType: _mriTypes[index],
                    image: _mriImages[index],
                    onTap: () => _pickImage(index),
                  );
                },
              ),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 24),

              // Process Button
              ElevatedButton(
                onPressed: _canProcess() ? _processImages : null,
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Process Images',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MriUploadCard extends StatelessWidget {
  final String mriType;
  final File? image;
  final VoidCallback onTap;

  const MriUploadCard({
    super.key,
    required this.mriType,
    required this.image,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                mriType,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D8CFF),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F0FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: image == null
                      ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap to upload',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                      : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      image!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                image == null ? 'Not uploaded' : 'Uploaded',
                style: TextStyle(
                  fontSize: 12,
                  color: image == null ? Colors.red : Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2D8CFF)),
            strokeWidth: 5,
          ),
          const SizedBox(height: 24),
          const Text(
            'Processing MRI Images',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D8CFF),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a moment...',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class ResultsPage extends StatelessWidget {
  final List<Uint8List> resultImages;

  const ResultsPage({
    super.key,
    required this.resultImages,
  });

  @override
  Widget build(BuildContext context) {
    final String gradCamTitle = 'Grad-CAM Analysis';
    final List<String> segmentedTitles = [
      'T1 Segmentation',
      'T1CE Segmentation',
      'T2 Segmentation',
      'FLAIR Segmentation',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Segmentation Results',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Card(
                margin: EdgeInsets.only(bottom: 24),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Analysis Complete',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D8CFF),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Below are the segmentation results and Grad-CAM analysis for the provided MRI images.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Grad-CAM Analysis
              if (resultImages.length >= 5)
                ResultImageCard(
                  title: gradCamTitle,
                  imageData: resultImages[4],
                  description: 'Gradient-weighted Class Activation Mapping helps visualize regions the model focused on for the tumor prediction.',
                ),

              const SizedBox(height: 24),

              // Segmented Images
              for (int i = 0; i < 4 && i < resultImages.length; i++) ...[
                ResultImageCard(
                  title: segmentedTitles[i],
                  imageData: resultImages[i],
                  description: 'Segmentation highlights the tumor regions in the ${segmentedTitles[i].split(' ').first} MRI scan.',
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Return to Upload Screen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ResultImageCard extends StatelessWidget {
  final String title;
  final Uint8List imageData;
  final String description;

  const ResultImageCard({
    super.key,
    required this.title,
    required this.imageData,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D8CFF),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                imageData,
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            ),
          ],
        ),
      ),
    );
  }
}