import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../models/solicitud.dart';
import '../services/solicitud_service.dart';

/// Muestra la respuesta del colaborador UNA SOLA VEZ: el contenido se
/// pide al backend al abrir esta pantalla (que lo borra de su lado en
/// ese mismo momento) y solo vive en memoria mientras esta pantalla
/// está abierta — nunca se escribe a disco ni se guarda en ningún lado
/// del dispositivo. Al salir (atrás, cerrar, lo que sea) no hay forma
/// de volver a verla.
class VerRespuestaScreen extends StatefulWidget {
  final int solicitudId;
  final String clienteAlias;
  const VerRespuestaScreen({
    super.key,
    required this.solicitudId,
    required this.clienteAlias,
  });

  @override
  State<VerRespuestaScreen> createState() => _VerRespuestaScreenState();
}

class _VerRespuestaScreenState extends State<VerRespuestaScreen> {
  RespuestaSolicitud? _respuesta;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final respuesta = await SolicitudService.verRespuesta(
        solicitudId: widget.solicitudId,
        clienteAlias: widget.clienteAlias,
      );
      if (!mounted) return;
      setState(() {
        _respuesta = respuesta;
        _cargando = false;
      });
    } on SolicitudException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo conectar con el servidor. Inténtalo de nuevo.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respuesta del colaborador')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(child: _buildContenido()),
        ),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const CircularProgressIndicator(color: AppColors.accent);
    }

    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 40),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      );
    }

    final respuesta = _respuesta!;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.visibility_off_outlined,
                    color: AppColors.accent, size: 16),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Solo puedes ver esto una vez. Al salir, desaparece.',
                    style: TextStyle(color: AppColors.accent, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (respuesta.tipo == TipoSolicitud.texto)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                respuesta.texto ?? '',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            )
          else if (respuesta.imagenBase64 != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                base64Decode(respuesta.imagenBase64!),
                fit: BoxFit.contain,
              ),
            ),
        ],
      ),
    );
  }
}
