import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/solicitud_service.dart';

/// Historial de solicitudes del Cliente: fecha de la solicitud, qué
/// pidió, cuándo le respondieron y el alias de quien respondió. Nunca
/// el contenido de la respuesta — eso solo se puede ver una vez, desde
/// la pantalla principal, y no queda registro de él en ningún lado.
class HistorialSolicitudesScreen extends StatefulWidget {
  final Usuario usuario;
  const HistorialSolicitudesScreen({super.key, required this.usuario});

  @override
  State<HistorialSolicitudesScreen> createState() =>
      _HistorialSolicitudesScreenState();
}

class _HistorialSolicitudesScreenState
    extends State<HistorialSolicitudesScreen> {
  List<Solicitud> _historial = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final historial =
          await SolicitudService.historialDeCliente(widget.usuario.alias);
      if (!mounted) return;
      setState(() {
        _historial = historial;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el historial. Revisa tu conexión.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de solicitudes'),
        actions: [
          IconButton(
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: SafeArea(child: _buildCuerpo()),
    );
  }

  Widget _buildCuerpo() {
    if (_cargando) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!,
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    if (_historial.isEmpty) {
      return const Center(
        child: Text('Todavía no has hecho ninguna solicitud',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _historial.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final s = _historial[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.descripcion,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  _Badge(texto: s.estado.etiqueta),
                ],
              ),
              const SizedBox(height: 8),
              Text('Solicitado: ${_formatearFecha(s.fechaCreacion)}',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
              if (s.respuestaFecha != null)
                Text(
                  'Respondido: ${_formatearFecha(s.respuestaFecha!)}'
                  '${s.colaboradorAlias != null ? ' · por ${s.colaboradorAlias}' : ''}',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatearFecha(String iso) {
    final fecha = DateTime.tryParse(iso);
    if (fecha == null) return iso;
    final local = fecha.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(local.day)}/${dos(local.month)}/${local.year} '
        '${dos(local.hour)}:${dos(local.minute)}';
  }
}

class _Badge extends StatelessWidget {
  final String texto;
  const _Badge({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto.toUpperCase(),
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
