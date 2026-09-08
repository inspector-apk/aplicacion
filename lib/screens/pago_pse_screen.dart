import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_colors.dart';
import '../core/precios.dart';
import '../models/solicitud.dart';
import '../services/pago_pse_service.dart';
import '../widgets/app_buttons.dart';

/// Resultado de un pago real por PSE ya aprobado.
class ResultadoPago {
  final String referencia;
  final String metodo;
  const ResultadoPago({required this.referencia, required this.metodo});
}

const _tiposDocumento = {
  'CC': 'Cédula de ciudadanía',
  'CE': 'Cédula de extranjería',
  'NIT': 'NIT',
  'PP': 'Pasaporte',
  'TI': 'Tarjeta de identidad',
};

/// Pago real con PSE, procesado por Wompi. A diferencia del resto de la
/// app (ficticia), este paso mueve dinero de verdad si el backend está
/// configurado con llaves de producción — en sandbox es simulado.
class PagoPseScreen extends StatefulWidget {
  final Categoria categoria;
  final Set<TipoSolicitud> tipos;
  final Urgencia urgencia;
  final String correoCliente;

  const PagoPseScreen({
    super.key,
    required this.categoria,
    required this.tipos,
    required this.urgencia,
    required this.correoCliente,
  });

  @override
  State<PagoPseScreen> createState() => _PagoPseScreenState();
}

enum _Paso { formulario, esperandoBanco, verificando }

class _PagoPseScreenState extends State<PagoPseScreen> {
  _Paso _paso = _Paso.formulario;
  bool _cargandoBancos = true;
  String? _errorBancos;
  List<BancoPSE> _bancos = [];

  String _tipoPersona = 'natural';
  String _tipoDocumento = 'CC';
  BancoPSE? _bancoSeleccionado;
  final _documentoCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();

  String? _error;
  bool _procesando = false;
  String? _referenciaActual;
  Timer? _timerPolling;
  int _segundosEsperando = 0;

  @override
  void initState() {
    super.initState();
    _correoCtrl.text = widget.correoCliente;
    _cargarBancos();
  }

  @override
  void dispose() {
    _timerPolling?.cancel();
    _documentoCtrl.dispose();
    _correoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarBancos() async {
    setState(() {
      _cargandoBancos = true;
      _errorBancos = null;
    });
    try {
      final bancos = await PagoPseService.bancosDisponibles();
      if (!mounted) return;
      setState(() {
        _bancos = bancos;
        _cargandoBancos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorBancos = e is PagoPseException
            ? e.mensaje
            : 'No se pudo conectar con el servidor de pagos.';
        _cargandoBancos = false;
      });
    }
  }

  Future<void> _iniciarPago() async {
    setState(() => _error = null);
    if (_bancoSeleccionado == null) {
      setState(() => _error = 'Selecciona tu banco');
      return;
    }
    if (_documentoCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Escribe tu número de documento');
      return;
    }
    if (!_correoCtrl.text.contains('@')) {
      setState(() => _error = 'Escribe un correo válido');
      return;
    }

    setState(() => _procesando = true);
    final valorTotal =
        calcularValorTotal(widget.categoria, widget.tipos, widget.urgencia);
    try {
      final (referencia, urlBanco) = await PagoPseService.crearPago(
        clienteAlias: widget.correoCliente,
        montoCentavos: valorTotal * 100,
        correo: _correoCtrl.text.trim(),
        codigoBanco: _bancoSeleccionado!.codigo,
        tipoPersona: _tipoPersona,
        tipoDocumento: _tipoDocumento,
        numeroDocumento: _documentoCtrl.text.trim(),
        descripcion: 'Solicitud Inspector',
      );
      _referenciaActual = referencia;
      final abierto = await launchUrl(Uri.parse(urlBanco),
          mode: LaunchMode.externalApplication);
      if (!abierto) throw PagoPseException('No se pudo abrir el navegador');
      if (!mounted) return;
      setState(() {
        _paso = _Paso.esperandoBanco;
        _procesando = false;
        _segundosEsperando = 0;
      });
      _empezarPolling(referencia);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _procesando = false;
        _error = e is PagoPseException
            ? e.mensaje
            : 'No se pudo iniciar el pago. Revisa tu conexión.';
      });
    }
  }

  void _empezarPolling(String referencia) {
    _timerPolling?.cancel();
    _timerPolling = Timer.periodic(const Duration(seconds: 3), (_) async {
      _segundosEsperando += 3;
      // Después de 10 minutos se deja de insistir automáticamente; el
      // botón "Ya autoricé el pago" sigue disponible para reintentar.
      if (_segundosEsperando > 600) {
        _timerPolling?.cancel();
        return;
      }
      await _consultarEstado(referencia, mostrarError: false);
    });
  }

  Future<void> _consultarEstado(String referencia,
      {bool mostrarError = true}) async {
    try {
      final estado = await PagoPseService.estadoDePago(referencia);
      if (!mounted) return;
      if (estado == 'APPROVED') {
        _timerPolling?.cancel();
        Navigator.of(context).pop(ResultadoPago(
          referencia: referencia,
          metodo: 'PSE · ${_bancoSeleccionado?.nombre ?? ''}',
        ));
      } else if (estado == 'DECLINED' || estado == 'VOIDED' || estado == 'ERROR') {
        _timerPolling?.cancel();
        setState(() {
          _paso = _Paso.formulario;
          _error = 'El pago no fue aprobado (${estado.toLowerCase()}). Intenta de nuevo.';
        });
      }
      // PENDING: se sigue esperando, no hace falta hacer nada.
    } catch (_) {
      if (mostrarError && mounted) {
        setState(() => _error = 'No se pudo consultar el estado del pago.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final valorTotal =
        calcularValorTotal(widget.categoria, widget.tipos, widget.urgencia);

    return Scaffold(
      appBar: AppBar(title: const Text('Pagar con PSE')),
      body: SafeArea(
        child: _paso == _Paso.esperandoBanco
            ? _vistaEsperandoBanco(valorTotal)
            : _vistaFormulario(valorTotal),
      ),
    );
  }

  Widget _vistaEsperandoBanco(int valorTotal) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.accent),
          const SizedBox(height: 24),
          const Text(
            'Esperando la confirmación de tu banco',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16),
          ),
          const SizedBox(height: 10),
          Text(
            'Completa la autenticación en la ventana del banco que se abrió. '
            'Cuando termines, vuelve aquí — esta pantalla se actualiza sola.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Text(formatearPesos(valorTotal),
              style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 20)),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 28),
          OutlinedButton(
            onPressed: () =>
                _consultarEstado(_referenciaActual!, mostrarError: true),
            child: const Text('Ya autoricé el pago, verificar ahora'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              _timerPolling?.cancel();
              setState(() => _paso = _Paso.formulario);
            },
            child: const Text('Cancelar e intentar de nuevo'),
          ),
        ],
      ),
    );
  }

  Widget _vistaFormulario(int valorTotal) {
    if (_cargandoBancos) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_errorBancos != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 36),
              const SizedBox(height: 12),
              Text(_errorBancos!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              OutlinedButton(
                  onPressed: _cargarBancos, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.account_balance_outlined,
                  color: AppColors.textMuted, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pago real por PSE, procesado por Wompi. Te llevaremos a '
                  'la página segura de tu banco para autenticarlo.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Tipo de persona',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'natural', label: Text('Natural')),
            ButtonSegment(value: 'juridica', label: Text('Jurídica')),
          ],
          selected: {_tipoPersona},
          onSelectionChanged: (s) => setState(() => _tipoPersona = s.first),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _tipoDocumento,
          decoration: const InputDecoration(labelText: 'Tipo de documento'),
          dropdownColor: AppColors.surfaceVariant,
          style: const TextStyle(color: AppColors.textPrimary),
          items: _tiposDocumento.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() => _tipoDocumento = v!),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _documentoCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(labelText: 'Número de documento'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _correoCtrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(labelText: 'Correo (para el comprobante)'),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<BancoPSE>(
          initialValue: _bancoSeleccionado,
          decoration: const InputDecoration(labelText: 'Banco'),
          dropdownColor: AppColors.surfaceVariant,
          style: const TextStyle(color: AppColors.textPrimary),
          isExpanded: true,
          items: _bancos
              .map((b) => DropdownMenuItem(value: b, child: Text(b.nombre)))
              .toList(),
          onChanged: (v) => setState(() => _bancoSeleccionado = v),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ],
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Text('Total a pagar',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const Spacer(),
              Text(
                formatearPesos(valorTotal),
                style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 17),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: 'PAGAR ${formatearPesos(valorTotal)} CON PSE',
          isLoading: _procesando,
          onPressed: _procesando ? null : _iniciarPago,
        ),
      ],
    );
  }
}
