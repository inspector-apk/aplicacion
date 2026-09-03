import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Miniatura de la imagen de referencia que el cliente adjuntó al crear
/// la solicitud (opcional). Al tocarla, se ve en grande.
class ImagenReferenciaThumb extends StatelessWidget {
  final String imagenBase64;
  const ImagenReferenciaThumb({super.key, required this.imagenBase64});

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(imagenBase64);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          child: InteractiveViewer(child: Image.memory(bytes)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Imagen de referencia del cliente',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              height: 120,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
  }
}
