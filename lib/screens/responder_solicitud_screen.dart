import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_colors.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/solicitud_service.dart';
import '../widgets/app_buttons.dart';

/// Pantalla donde el Colaborador responde una solicitud que aceptó:
/// texto si la solicitud pedía texto, o una foto (galería o cámara) si
/// pedía imagen. Al enviar, la solicitud queda completada.
class ResponderSolicitudScreen extends StatefulWidget {
  final Solicitud solicitud;
  final Usuario usuario;
  const ResponderSolicitudScreen({
    super.key,
    required this.solicitud,
    required this.usuario,
  });

  @override
  State<ResponderSolicitudScreen> createState() =>
      _ResponderSolicitudScreenState();
}

class _ResponderSolicitudScreenState extends State<ResponderSolicitudScreen> {
  final _textoCtrl = TextEditingController();
  File? _imagenSeleccionada;
  bool _enviando = false;
  String? _error;

  bool get _esTexto => widget.solicitud.tipo == TipoSolicitud.texto;

  @override
  void dispose() {
    _textoCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirImagen(ImageSource origen) async {
    final picker = ImagePicker();
    final archivo = await picker.pickImage(
      source: origen,
      maxWidth: 1600,
      imageQuality: 70,
    );
    if (archivo == null) return;
    setState(() => _imagenSeleccionada = File(archivo.path));
  }

  Future<void> _enviar() async {
    setState(() => _error = null);

    String? texto;
    String? imagenBase64;

    if (_esTexto) {
      if (_textoCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Escribe tu respuesta');
        return;
      }
      texto = _textoCtrl.text.trim();
    } else {
      if (_imagenSeleccionada == null) {
        setState(() => _error = 'Elige o toma una foto');
        return;
      }
      final bytes = await _imagenSeleccionada!.readAsBytes();
      imagenBase64 = base64Encode(bytes);
    }

    setState(() => _enviando = true);
    try {
      await SolicitudService.responderSolicitud(
        solicitudId: widget.solicitud.id!,
        colaboradorAlias: widget.usuario.alias,
        texto: texto,
        imagenBase64: imagenBase64,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SolicitudException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() =>
          _error = 'No se pudo conectar con el servidor. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Responder solicitud')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              widget.solicitud.descripcion,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.solicitud.localidad,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 24),
            if (_esTexto) ...[
              const Text(
                'Escribe tu respuesta',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _textoCtrl,
                maxLines: 6,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Tu respuesta para el cliente',
                  helperText: 'El cliente solo podrá leer esto una vez',
                ),
              ),
            ] else ...[
              const Text(
                'Adjunta una foto',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'El cliente solo podrá ver esta foto una vez',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (_imagenSeleccionada != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    _imagenSeleccionada!,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_outlined,
                      color: AppColors.textMuted, size: 40),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlineActionButton(
                      label: 'CÁMARA',
                      onPressed: () => _elegirImagen(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlineActionButton(
                      label: 'GALERÍA',
                      onPressed: () => _elegirImagen(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'ENVIAR RESPUESTA',
              isLoading: _enviando,
              onPressed: _enviar,
            ),
          ],
        ),
      ),
    );
  }
}
