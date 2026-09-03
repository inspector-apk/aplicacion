import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';
import '../core/precios.dart';
import '../models/solicitud.dart';
import '../widgets/app_buttons.dart';

/// Resultado de la pasarela de pago ficticia: solo una referencia y una
/// descripción del "método" simulado — NUNCA se procesa ni se guarda
/// ningún dato real de tarjeta, no hay pasarela de pagos de verdad
/// conectada. Es puramente decorativo, para completar el flujo de
/// "solicitar el servicio" con un paso de pago como haría una app real.
class ResultadoPagoFicticio {
  final String referencia;
  final String metodo;
  const ResultadoPagoFicticio({required this.referencia, required this.metodo});
}

/// Pantalla de pago FICTICIO antes de enviar la solicitud: pide datos
/// de una tarjeta que nunca se validan ni se envían a ningún lado (ni
/// siquiera al backend propio) — solo se usan para simular el cobro y
/// generar una referencia. No hay cargos reales de ningún tipo.
class PagoFicticioScreen extends StatefulWidget {
  final Categoria categoria;
  final Set<TipoSolicitud> tipos;

  const PagoFicticioScreen({
    super.key,
    required this.categoria,
    required this.tipos,
  });

  @override
  State<PagoFicticioScreen> createState() => _PagoFicticioScreenState();
}

class _PagoFicticioScreenState extends State<PagoFicticioScreen> {
  final _numeroCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _venceCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();

  bool _procesando = false;
  String? _error;

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _nombreCtrl.dispose();
    _venceCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  String get _soloDigitosNumero => _numeroCtrl.text.replaceAll(' ', '');

  Future<void> _pagar() async {
    setState(() => _error = null);

    if (_nombreCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el nombre en la tarjeta');
      return;
    }
    if (_soloDigitosNumero.length != 16) {
      setState(() => _error = 'El número de tarjeta debe tener 16 dígitos');
      return;
    }
    final vence = _venceCtrl.text.trim();
    final match = RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$').firstMatch(vence);
    if (match == null) {
      setState(() => _error = 'Fecha de vencimiento inválida (MM/AA)');
      return;
    }
    if (_cvvCtrl.text.trim().length != 3) {
      setState(() => _error = 'El CVV debe tener 3 dígitos');
      return;
    }

    setState(() => _procesando = true);

    // Simulación: ninguna de estas cifras viaja a ningún servidor, ni
    // siquiera al backend propio de Inspector. Solo se genera una
    // referencia falsa para dejar constancia en el historial.
    await Future.delayed(const Duration(milliseconds: 1400));

    if (!mounted) return;

    final random = Random.secure();
    final referencia = 'PAG-${List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join().toUpperCase()}';
    final ultimosCuatro = _soloDigitosNumero.substring(12);
    final metodo = 'Tarjeta •••• $ultimosCuatro';

    Navigator.of(context).pop(
      ResultadoPagoFicticio(referencia: referencia, metodo: metodo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final valorTotal = calcularValorTotal(widget.categoria, widget.tipos);

    return Scaffold(
      appBar: AppBar(title: const Text('Pago (simulado)')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.textMuted, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Esta es una pasarela de pago SIMULADA: no se realiza '
                      'ningún cobro real ni se guardan datos de tarjeta.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentDim],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.credit_card, color: Colors.black, size: 28),
                  const SizedBox(height: 18),
                  Text(
                    _numeroCtrl.text.isEmpty
                        ? '•••• •••• •••• ••••'
                        : _numeroCtrl.text.padRight(19, '•'),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _nombreCtrl.text.trim().isEmpty
                        ? 'NOMBRE APELLIDO'
                        : _nombreCtrl.text.trim().toUpperCase(),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _numeroCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(16),
                _EspaciadorTarjeta(),
              ],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Número de tarjeta',
                hintText: '0000 0000 0000 0000',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nombreCtrl,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Nombre en la tarjeta'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _venceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                      _EspaciadorVencimiento(),
                    ],
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                        labelText: 'Vence (MM/AA)', hintText: '08/29'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _cvvCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                        labelText: 'CVV', hintText: '123'),
                  ),
                ),
              ],
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
                  const Text('Total a pagar (ficticio)',
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
              label: 'PAGAR ${formatearPesos(valorTotal)}',
              isLoading: _procesando,
              onPressed: _procesando ? null : _pagar,
            ),
          ],
        ),
      ),
    );
  }
}

/// Formatea el número de tarjeta en grupos de 4 mientras se escribe.
class _EspaciadorTarjeta extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digitos = newValue.text;
    final buffer = StringBuffer();
    for (var i = 0; i < digitos.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digitos[i]);
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}

/// Formatea la fecha de vencimiento como MM/AA mientras se escribe.
class _EspaciadorVencimiento extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digitos = newValue.text;
    final buffer = StringBuffer();
    for (var i = 0; i < digitos.length; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(digitos[i]);
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}
