import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../core/app_colors.dart';
import '../models/solicitud.dart';
import '../services/solicitud_service.dart';

/// Muestra la respuesta del colaborador UNA SOLA VEZ: el contenido se
/// pide al backend al abrir esta pantalla (que lo borra de su lado en
/// ese mismo momento) y solo vive en memoria mientras esta pantalla
/// está abierta — nunca se escribe a disco ni se guarda en ningún lado
/// del dispositivo. Al salir (atrás, cerrar, lo que sea) no hay forma
/// de volver a verla.
///
/// Única excepción técnica: el video necesita un archivo para
/// reproducirse (`video_player` no acepta bytes en memoria), así que se
/// escribe a un archivo TEMPORAL que se borra apenas se cierra esta
/// pantalla — nunca queda guardado después de verlo.
class VerRespuestaScreen extends StatefulWidget {
  final int solicitudId;
  final String clienteAlias;
  final List<TipoSolicitud> tipos;
  const VerRespuestaScreen({
    super.key,
    required this.solicitudId,
    required this.clienteAlias,
    required this.tipos,
  });

  @override
  State<VerRespuestaScreen> createState() => _VerRespuestaScreenState();
}

class _VerRespuestaScreenState extends State<VerRespuestaScreen> {
  RespuestaSolicitud? _respuesta;
  bool _cargando = true;
  String? _error;

  final _reproductorAudio = AudioPlayer();
  VideoPlayerController? _controladorVideo;
  File? _archivoTemporalVideo;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _reproductorAudio.dispose();
    _controladorVideo?.dispose();
    // Borra el archivo temporal del video de inmediato: no debe quedar
    // guardado en el dispositivo después de cerrar esta pantalla.
    _archivoTemporalVideo?.delete().catchError((_) => _archivoTemporalVideo!);
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final respuesta = await SolicitudService.verRespuesta(
        solicitudId: widget.solicitudId,
        clienteAlias: widget.clienteAlias,
      );

      if (respuesta.videoBase64 != null) {
        await _prepararVideo(base64Decode(respuesta.videoBase64!));
      }

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

  Future<void> _prepararVideo(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final archivo = File(
        '${dir.path}/respuesta_temporal_${DateTime.now().microsecondsSinceEpoch}.mp4');
    await archivo.writeAsBytes(bytes);
    final controlador = VideoPlayerController.file(archivo);
    await controlador.initialize();
    _archivoTemporalVideo = archivo;
    _controladorVideo = controlador;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respuesta del colaborador')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : _buildContenido(),
        ),
      ),
    );
  }

  Widget _buildContenido() {
    if (_error != null) {
      return Center(
        child: Column(
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
        ),
      );
    }

    final respuesta = _respuesta!;
    return SingleChildScrollView(
      child: Column(
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
          if (respuesta.texto != null) ...[
            _EtiquetaContenido(texto: 'Texto'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                respuesta.texto!,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (respuesta.imagenBase64 != null) ...[
            _EtiquetaContenido(texto: 'Imagen'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                base64Decode(respuesta.imagenBase64!),
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (respuesta.audioBase64 != null) ...[
            _EtiquetaContenido(texto: 'Audio'),
            const SizedBox(height: 8),
            _ReproductorAudio(
              bytes: base64Decode(respuesta.audioBase64!),
              player: _reproductorAudio,
            ),
            const SizedBox(height: 20),
          ],
          if (_controladorVideo != null) ...[
            _EtiquetaContenido(texto: 'Video'),
            const SizedBox(height: 8),
            _ReproductorVideo(controlador: _controladorVideo!),
          ],
        ],
      ),
    );
  }
}

class _EtiquetaContenido extends StatelessWidget {
  final String texto;
  const _EtiquetaContenido({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _ReproductorAudio extends StatefulWidget {
  final Uint8List bytes;
  final AudioPlayer player;
  const _ReproductorAudio({required this.bytes, required this.player});

  @override
  State<_ReproductorAudio> createState() => _ReproductorAudioState();
}

class _ReproductorAudioState extends State<_ReproductorAudio> {
  bool _reproduciendo = false;

  @override
  void initState() {
    super.initState();
    widget.player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _reproduciendo = false);
    });
  }

  Future<void> _alternar() async {
    if (_reproduciendo) {
      await widget.player.pause();
    } else {
      await widget.player.play(BytesSource(widget.bytes));
    }
    if (mounted) setState(() => _reproduciendo = !_reproduciendo);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _alternar,
            icon: Icon(
              _reproduciendo
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
              color: AppColors.accent,
              size: 44,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Nota de voz del colaborador',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _ReproductorVideo extends StatefulWidget {
  final VideoPlayerController controlador;
  const _ReproductorVideo({required this.controlador});

  @override
  State<_ReproductorVideo> createState() => _ReproductorVideoState();
}

class _ReproductorVideoState extends State<_ReproductorVideo> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controlador;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(c),
            IconButton(
              iconSize: 56,
              color: Colors.white,
              icon: Icon(c.value.isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill),
              onPressed: () {
                setState(() {
                  c.value.isPlaying ? c.pause() : c.play();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
