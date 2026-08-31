import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_colors.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/deteccion_ia_service.dart';
import '../services/solicitud_service.dart';
import '../widgets/app_buttons.dart';

/// A partir de este % de IA se le pide al colaborador confirmar
/// explícitamente que la foto es real antes de dejarlo enviarla.
const int _kUmbralConfirmacionIA = 60;

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

  bool _analizandoIA = false;
  ResultadoDeteccionIA? _resultadoIA;
  String? _errorAnalisisIA;
  bool _confirmoFotoReal = false;

  bool get _esTexto => widget.solicitud.tipo == TipoSolicitud.texto;

  bool get _requiereConfirmacionIA =>
      _resultadoIA != null && _resultadoIA!.iaPorcentaje >= _kUmbralConfirmacionIA;

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
    setState(() {
      _imagenSeleccionada = File(archivo.path);
      _resultadoIA = null;
      _errorAnalisisIA = null;
      _confirmoFotoReal = false;
    });
    await _analizarImagenSeleccionada();
  }

  /// Antes de poder enviarla, se analiza la foto para detectar si
  /// parece generada por IA (ver `backend/deteccion_ia.js`).
  Future<void> _analizarImagenSeleccionada() async {
    final archivo = _imagenSeleccionada;
    if (archivo == null) return;
    setState(() {
      _analizandoIA = true;
      _errorAnalisisIA = null;
    });
    try {
      final bytes = await archivo.readAsBytes();
      final resultado =
          await DeteccionIAService.analizarImagen(base64Encode(bytes));
      if (!mounted) return;
      setState(() => _resultadoIA = resultado);
    } on DeteccionIAException catch (e) {
      if (!mounted) return;
      setState(() => _errorAnalisisIA = e.mensaje);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorAnalisisIA =
          'No se pudo analizar la foto. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _analizandoIA = false);
    }
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
      if (_analizandoIA) {
        setState(() => _error = 'Espera a que termine el análisis de la foto');
        return;
      }
      if (_requiereConfirmacionIA && !_confirmoFotoReal) {
        setState(() => _error =
            'Esta foto parece generada por IA: confirma que es real antes de enviarla');
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
              if (_imagenSeleccionada != null) ...[
                const SizedBox(height: 14),
                _PanelDeteccionIA(
                  analizando: _analizandoIA,
                  resultado: _resultadoIA,
                  error: _errorAnalisisIA,
                  confirmoFotoReal: _confirmoFotoReal,
                  onConfirmarChanged: (v) =>
                      setState(() => _confirmoFotoReal = v),
                ),
              ],
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
              onPressed: _analizandoIA ? null : _enviar,
            ),
          ],
        ),
      ),
    );
  }
}

/// Muestra el % de veracidad y el % de IA de la foto elegida, antes de
/// que el colaborador pueda enviarla.
class _PanelDeteccionIA extends StatelessWidget {
  final bool analizando;
  final ResultadoDeteccionIA? resultado;
  final String? error;
  final bool confirmoFotoReal;
  final ValueChanged<bool> onConfirmarChanged;

  const _PanelDeteccionIA({
    required this.analizando,
    required this.resultado,
    required this.error,
    required this.confirmoFotoReal,
    required this.onConfirmarChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (analizando) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: AppColors.accent),
            ),
            SizedBox(width: 12),
            Text('Analizando si la foto es generada por IA...',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ],
        ),
      );
    }

    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.textMuted, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No se pudo verificar la foto: $error. Puedes seguir y enviarla igual.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    final r = resultado;
    if (r == null) return const SizedBox.shrink();

    final esSospechosa = r.iaPorcentaje >= _kUmbralConfirmacionIA;
    final colorIA = esSospechosa ? AppColors.error : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: esSospechosa ? AppColors.error : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                esSospechosa ? Icons.warning_amber_rounded : Icons.verified_outlined,
                color: colorIA,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                esSospechosa
                    ? 'Esta foto parece generada por IA'
                    : 'La foto parece real',
                style: TextStyle(
                    color: colorIA, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _BarraPorcentaje(
              etiqueta: 'Veracidad',
              porcentaje: r.veracidadPorcentaje,
              color: AppColors.success),
          const SizedBox(height: 6),
          _BarraPorcentaje(
              etiqueta: 'Probabilidad de IA',
              porcentaje: r.iaPorcentaje,
              color: colorIA),
          if (esSospechosa) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => onConfirmarChanged(!confirmoFotoReal),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: confirmoFotoReal,
                    activeColor: AppColors.accent,
                    onChanged: (v) => onConfirmarChanged(v ?? false),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Confirmo que esta foto es real y no fue generada por IA',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 12.5),
                      ),
                    ),
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

class _BarraPorcentaje extends StatelessWidget {
  final String etiqueta;
  final int porcentaje;
  final Color color;

  const _BarraPorcentaje({
    required this.etiqueta,
    required this.porcentaje,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(etiqueta,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: porcentaje / 100,
              minHeight: 8,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text('$porcentaje%',
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ],
    );
  }
}
