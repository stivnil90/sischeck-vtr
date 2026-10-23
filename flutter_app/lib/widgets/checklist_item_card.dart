// lib/widgets/checklist_item_card.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';

class ChecklistItemCard extends StatelessWidget {
  final ChecklistItemConfig config;
  final ChecklistAnswer answer;
  final Function(String status) onStatusChanged;
  final Function(String text) onDescriptionChanged;
  final Function(File photo) onPhotoCaptured;

  const ChecklistItemCard({
    super.key,
    required this.config,
    required this.answer,
    required this.onStatusChanged,
    required this.onDescriptionChanged,
    required this.onPhotoCaptured,
  });

  Future<void> _captureAlterationPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1200,
    );

    if (picked != null) {
      onPhotoCaptured(File(picked.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOk = answer.status == 'OK';
    final isAlteracao = answer.status == 'ALTERACAO';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAlteracao ? const Color(0xFFEF4444) : const Color(0xFF1E293B),
          width: isAlteracao ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.titulo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (config.exigeFotoSeAlterado)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          'EXIGE FOTO SE ALTERADO',
                          style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Botões Táticos OK / Alteração
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusBtn(
                    label: 'OK',
                    isSelected: isOk,
                    activeColor: const Color(0xFF10B981),
                    activeTextColor: const Color(0xFF0F172A),
                    onTap: () => onStatusChanged('OK'),
                  ),
                  const SizedBox(width: 6),
                  _StatusBtn(
                    label: 'Alteração',
                    isSelected: isAlteracao,
                    activeColor: const Color(0xFFEF4444),
                    activeTextColor: Colors.white,
                    onTap: () => onStatusChanged('ALTERACAO'),
                  ),
                ],
              ),
            ],
          ),

          // Seção de Avaria Expandida
          if (isAlteracao) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF450A0A).withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    initialValue: answer.descricao,
                    onChanged: onDescriptionChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Descreva detalhadamente a avaria / alteração...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFEF4444)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: const Color(0xFFEF4444).withOpacity(0.5)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _captureAlterationPhoto,
                          icon: Icon(
                            answer.localPhotoPath != null ? Icons.check_circle : Icons.camera_alt,
                            color: const Color(0xFFEF4444),
                            size: 16,
                          ),
                          label: Text(
                            answer.localPhotoPath != null ? 'Foto Anexada (Alterar)' : 'Foto da Avaria',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFEF4444)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      if (answer.localPhotoPath != null) ...[
                        const SizedBox(width: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 38,
                            height: 38,
                            child: Image.file(
                              File(answer.localPhotoPath!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBtn extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color activeColor;
  final Color activeTextColor;
  final VoidCallback onTap;

  const _StatusBtn({
    required this.label,
    required this.isSelected,
    required this.activeColor,
    required this.activeTextColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? activeTextColor : Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
