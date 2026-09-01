import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../core/app_colors.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/deteccion_ia_service.dart';
import '../services/solicitud_service.dart';
import '../widgets/app_buttons.dart';

/// A partir de este % de IA se le pide al colaborador confirmar
/// explícitamente que la foto es real antes de dejarlo enviarla.
const int _kUmbralConfirmacionIA = 60;

/// Duración máxima de audio/video que se puede adjuntar en una
/// respuesta, para no generar archivos demasiado pesados (viajan en
/// base64 dentro del cuerpo de la petición).
const Duration _kDuracionMaximaMedia = Duration(minutes: 2);

/// Pantalla donde el Colaborador responde una solicitud que aceptó: uno
/// o varios de texto, foto, audio o video, según lo que haya pedido la
/// solicitud. Al enviar (con contenido para TODO lo pedido), la
/// solicitud queda completada.
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
  File? _audioSeleccionado;
  File? _videoSeleccionado;
  VideoPlayerController? _controladorVideoPreview;
  bool _enviando = false;
  String? _error;

  bool _analizandoIA = false;
  ResultadoDeteccionIA? _resultadoIA;
  String? _errorAnalisisIA;
  bool _confirmoFotoReal = false;

  final _grabador = AudioRecorder();
  final _reproductorAudioPreview = AudioPlayer();
  bool _grabando = false;
  bool _reproduciendoPreviewAudio = false;
  Duration _duracionGrabada = Duration.zero;
  Timer? _cronometroGrabacion;

  List<TipoSolicitud> get _tipos => widget.solicitud.tipos;

  bool get _requiereConfirmacionIA =>
      _resultadoIA != null && _resultadoIA!.iaPorcentaje >= _kUmbralConfirmacionIA;

  @override
  void dispose() {
    _textoCtrl.dispose();
    _cronometroGrabacion?.cancel();
    _grabador.dispose();
    _reproductorAudioPreview.dispose();
    _controladorVideoPreview?.dispose();
    super.dispose();
  }

  // ---------- Imagen ----------

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
  /// parece generada por IA. Todo corre en el celular, sobre los
  /// metadatos de la propia foto — no llama a ningún servicio externo
  /// ni requiere conexión (ver `lib/services/deteccion_ia_service.dart`).
  Future<void> _analizarImagenSeleccionada() async {
    final archivo = _imagenSeleccionada;
    if (archivo == null) return;
    setState(() {
      _analizandoIA = true;
      _errorAnalisisIA = null;
    });
    try {
      final bytes = await archivo.readAsBytes();
      final resultado = await DeteccionIAService.analizarImagen(bytes);
      if (!mounted) return;
      setState(() => _resultadoIA = resultado);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorAnalisisIA = 'No se pudo analizar la foto.');
    } finally {
      if (mounted) setState(() => _analizandoIA = false);
    }
  }

  // ---------- Audio ----------

  Future<void> _alternarGrabacion() async {
    if (_grabando) {
      final ruta = await _grabador.stop();
      _cronometroGrabacion?.cancel();
      if (!mounted) return;
      setState(() {
        _grabando = false;
        if (ruta != null) _audioSeleccionado = File(ruta);
      });
      return;
    }

    if (!await _grabador.hasPermission()) {
      setState(() => _error = 'Necesitas dar permiso de micrófono para grabar audio');
      return;
    }
    final dir = await getTemporaryDirectory();
    final ruta =
        '${dir.path}/respuesta_audio_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _grabador.start(const RecordConfig(), path: ruta);
    setState(() {
      _grabando = true;
      _audioSeleccionado = null;
      _duracionGrabada = Duration.zero;
    });
    _cronometroGrabacion = Timer.periodic(const Duration(seconds: 1), (_) async {
      final nueva = _duracionGrabada + const Duration(seconds: 1);
      if (nueva >= _kDuracionMaximaMedia) {
        await _alternarGrabacion(); // se autodetiene al llegar al máximo
        return;
      }
      if (mounted) setState(() => _duracionGrabada = nueva);
    });
  }

  Future<void> _reproducirPreviewAudio() async {
    final archivo = _audioSeleccionado;
    if (archivo == null) return;
    if (_reproduciendoPreviewAudio) {
      await _reproductorAudioPreview.pause();
    } else {
      await _reproductorAudioPreview.play(DeviceFileSource(archivo.path));
      _reproductorAudioPreview.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _reproduciendoPreviewAudio = false);
      });
    }
    if (mounted) {
      setState(() => _reproduciendoPreviewAudio = !_reproduciendoPreviewAudio);
    }
  }

  // ---------- Video ----------

  Future<void> _elegirVideo(ImageSource origen) async {
    final picker = ImagePicker();
    final archivo = await picker.pickVideo(
      source: origen,
      maxDuration: _kDuracionMaximaMedia,
    );
    if (archivo == null) return;
    final controlador = VideoPlayerController.file(File(archivo.path));
    await controlador.initialize();
    if (!mounted) return;
    setState(() {
      _controladorVideoPreview?.dispose();
      _videoSeleccionado = File(archivo.path);
      _controladorVideoPreview = controlador;
    });
  }

  // ---------- Envío ----------

  Future<void> _enviar() async {
    setState(() => _error = null);

    if (_analizandoIA) {
      setState(() => _error = 'Espera a que termine el análisis de la foto');
      return;
    }

    String? texto;
    String? imagenBase64;
    String? audioBase64;
    String? videoBase64;

    for (final t in _tipos) {
      switch (t) {
        case TipoSolicitud.texto:
          if (_textoCtrl.text.trim().isEmpty) {
            setState(() => _error = 'Escribe tu respuesta de texto');
            return;
          }
          texto = _textoCtrl.text.trim();
          break;
        case TipoSolicitud.imagen:
          if (_imagenSeleccionada == null) {
            setState(() => _error = 'Elige o toma una foto');
            return;
          }
          if (_requiereConfirmacionIA && !_confirmoFotoReal) {
            setState(() => _error =
                'Esta foto parece generada por IA: confirma que es real antes de enviarla');
            return;
          }
          imagenBase64 = base64Encode(await _imagenSeleccionada!.readAsBytes());
          break;
        case TipoSolicitud.audio:
          if (_audioSeleccionado == null) {
            setState(() => _error = 'Graba una nota de audio');
            return;
          }
          audioBase64 = base64Encode(await _audioSeleccionado!.readAsBytes());
          break;
        case TipoSolicitud.video:
          if (_videoSeleccionado == null) {
            setState(() => _error = 'Graba o adjunta un video');
            return;
          }
          videoBase64 = base64Encode(await _videoSeleccionado!.readAsBytes());
          break;
      }
    }

    setState(() => _enviando = true);
    try {
      await SolicitudService.responderSolicitud(
        solicitudId: widget.solicitud.id!,
        colaboradorAlias: widget.usuario.alias,
        texto: texto,
        imagenBase64: imagenBase64,
        audioBase64: audioBase64,
        videoBase64: videoBase64,
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
              widget.solicitud.direccion.isNotEmpty
                  ? '${widget.solicitud.localidad} · ${widget.solicitud.direccion}'
                  : widget.solicitud.localidad,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            for (final t in _tipos) ...[
              const SizedBox(height: 24),
              _seccionPara(t),
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
              onPressed: _analizandoIA || _grabando ? null : _enviar,
            ),
          ],
        ),
      ),
    );
  }

  Widget _seccionPara(TipoSolicitud t) {
    switch (t) {
      case TipoSolicitud.texto:
        return _seccionTexto();
      case TipoSolicitud.imagen:
        return _seccionImagen();
      case TipoSolicitud.audio:
        return _seccionAudio();
      case TipoSolicitud.video:
        return _seccionVideo();
    }
  }

  Widget _seccionTexto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Escribe tu respuesta',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700),
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
      ],
    );
  }

  Widget _seccionImagen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Adjunta una foto',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700),
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
          _placeholder(Icons.image_outlined),
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
            onConfirmarChanged: (v) => setState(() => _confirmoFotoReal = v),
          ),
        ],
      ],
    );
  }

  Widget _seccionAudio() {
    final minutos = _duracionGrabada.inMinutes.toString().padLeft(2, '0');
    final segundos = (_duracionGrabada.inSeconds % 60).toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Graba una nota de audio',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'El cliente solo podrá escucharla una vez · máx. '
          '${_kDuracionMaximaMedia.inMinutes} min',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: _grabando ? AppColors.error : AppColors.border),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _alternarGrabacion,
                icon: Icon(
                  _grabando ? Icons.stop_circle : Icons.fiber_manual_record,
                  color: AppColors.error,
                  size: 40,
                ),
              ),
              const SizedBox(width: 8),
              if (_grabando)
                Text('Grabando... $minutos:$segundos',
                    style: const TextStyle(
                        color: AppColors.error, fontWeight: FontWeight.w600))
              else if (_audioSeleccionado != null)
                Expanded(
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _reproducirPreviewAudio,
                        icon: Icon(
                          _reproduciendoPreviewAudio
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                          color: AppColors.accent,
                        ),
                      ),
                      const Text('Audio grabado — listo para enviar',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12.5)),
                    ],
                  ),
                )
              else
                const Expanded(
                  child: Text('Toca para empezar a grabar',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12.5)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _seccionVideo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Graba o adjunta un video',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'El cliente solo podrá verlo una vez · máx. '
          '${_kDuracionMaximaMedia.inMinutes} min',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 14),
        if (_controladorVideoPreview != null &&
            _controladorVideoPreview!.value.isInitialized)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: _controladorVideoPreview!.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_controladorVideoPreview!),
                  IconButton(
                    iconSize: 48,
                    color: Colors.white,
                    icon: Icon(_controladorVideoPreview!.value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill),
                    onPressed: () {
                      setState(() {
                        _controladorVideoPreview!.value.isPlaying
                            ? _controladorVideoPreview!.pause()
                            : _controladorVideoPreview!.play();
                      });
                    },
                  ),
                ],
              ),
            ),
          )
        else
          _placeholder(Icons.videocam_outlined),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlineActionButton(
                label: 'GRABAR',
                onPressed: () => _elegirVideo(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlineActionButton(
                label: 'GALERÍA',
                onPressed: () => _elegirVideo(ImageSource.gallery),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _placeholder(IconData icon) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.textMuted, size: 40),
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
    final colorIA = esSospechosa
        ? AppColors.error
        : (r.concluyente ? AppColors.success : AppColors.textMuted);

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
                esSospechosa
                    ? Icons.warning_amber_rounded
                    : (r.concluyente ? Icons.verified_outlined : Icons.help_outline),
                color: colorIA,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  esSospechosa
                      ? 'Esta foto parece generada por IA'
                      : (r.concluyente
                          ? 'La foto parece real'
                          : 'No se pudo determinar el origen de la foto'),
                  style: TextStyle(
                      color: colorIA, fontWeight: FontWeight.w700, fontSize: 13),
                ),
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
          const SizedBox(height: 8),
          const Text(
            'Estimación automática basada en los datos de la foto, hecha en '
            'el celular. No es una verificación certera.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
          ),
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
