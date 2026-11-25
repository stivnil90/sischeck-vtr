// lib/widgets/camera_angle_card.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CameraAngleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final File? photoFile;
  final Function(File) onPhotoCaptured;

  const CameraAngleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.photoFile,
    required this.onPhotoCaptured,
  });

  Future<void> _pickImage(BuildContext context) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );

    if (picked != null) {
      onPhotoCaptured(File(picked.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoFile != null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasPhoto ? const Color(0xFF10B981) : const Color(0xFF334155),
          width: hasPhoto ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preview da Imagem ou Placeholder
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: hasPhoto
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(photoFile!, fit: BoxFit.cover),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF10B981)),
                            ),
                            child: const Text(
                              'REGISTRADA',
                              style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      color: const Color(0xFF1E293B),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: const Color(0xFFF59E0B), size: 28),
                          const SizedBox(height: 4),
                          Text(
                            title.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),

          // Botão Disparador de Câmera
          ElevatedButton.icon(
            onPressed: () => _pickImage(context),
            icon: Icon(
              hasPhoto ? Icons.refresh : Icons.camera_alt,
              size: 15,
              color: hasPhoto ? Colors.white : const Color(0xFF0F172A),
            ),
            label: Text(
              hasPhoto ? 'Refazer Foto' : 'Tirar Foto',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: hasPhoto ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: hasPhoto ? const Color(0xFF334155) : const Color(0xFFF59E0B),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}
