import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/precios.dart';
import '../models/solicitud.dart';
import '../models/usuario.dart';
import '../services/solicitud_service.dart';

/// Pantalla de "Ganancias" del Colaborador: suma FICTICIA (no hay
/// dinero real de por medio) de lo que ha "ganado" por cada solicitud
/// completada, más el detalle de cada una como si fuera una lista de
/// transacciones. El pago se simula como transferido a la cuenta
/// bancaria ficticia configurada en el perfil.
class GananciasScreen extends StatefulWidget {
  final Usuario usuario;
  const GananciasScreen({super.key, required this.usuario});

  @override
  State<GananciasScreen> createState() => _GananciasScreenState();
}

class _GananciasScreenState extends State<GananciasScreen> {
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
          await SolicitudService.historialDeColaborador(widget.usuario.alias);
      if (!mounted) return;
      setState(() {
        _historial = historial;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar tus ganancias. Revisa tu conexión.';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ganancias'),
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

    final completadas =
        _historial.where((s) => s.estado == EstadoSolicitud.completada).toList();
    final totalGanado =
        completadas.fold<int>(0, (suma, s) => suma + s.valorTotal);
    final enCurso = _historial
        .where((s) =>
            s.estado == EstadoSolicitud.aceptada ||
            s.estado == EstadoSolicitud.pendiente)
        .length;

    final tieneCuenta = (widget.usuario.numeroCuentaFicticia ?? '').isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.accentDim],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ganancias totales (simuladas)',
                  style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                formatearPesos(totalGanado),
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 30),
              ),
              const SizedBox(height: 4),
              Text(
                '${completadas.length} solicitudes completadas'
                '${enCurso > 0 ? ' · $enCurso en curso' : ''}',
                style: const TextStyle(color: Colors.black87, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(
                tieneCuenta
                    ? Icons.account_balance_outlined
                    : Icons.warning_amber_rounded,
                color: tieneCuenta ? AppColors.success : AppColors.error,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tieneCuenta
                      ? 'Se transfiere (simulado) a ${widget.usuario.bancoFicticio ?? 'tu cuenta'} '
                          '•••• ${_ultimosDigitos(widget.usuario.numeroCuentaFicticia!)}'
                      : 'No tienes una cuenta bancaria configurada — agrégala desde tu perfil.',
                  style: TextStyle(
                    color:
                        tieneCuenta ? AppColors.textSecondary : AppColors.error,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Transacciones',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (completadas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('Todavía no has completado ninguna solicitud',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          )
        else
          ...completadas.map((s) => _TransaccionCard(solicitud: s)),
      ],
    );
  }

  String _ultimosDigitos(String numero) {
    final soloDigitos = numero.replaceAll(RegExp(r'\D'), '');
    if (soloDigitos.length <= 4) return soloDigitos;
    return soloDigitos.substring(soloDigitos.length - 4);
  }
}

class _TransaccionCard extends StatelessWidget {
  final Solicitud solicitud;
  const _TransaccionCard({required this.solicitud});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_downward_rounded,
                color: AppColors.success, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${solicitud.categoria.etiqueta} · ${solicitud.tiposEtiqueta}',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatearFecha(solicitud.respuestaFecha ?? solicitud.fechaActualizacion),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '+${formatearPesos(solicitud.valorTotal)}',
            style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w800,
                fontSize: 14),
          ),
        ],
      ),
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
