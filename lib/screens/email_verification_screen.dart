import 'dart:async';

import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../services/auth_service.dart';
import '../services/email_verification_service.dart';
import '../widgets/app_buttons.dart';
import 'register_success_dialog.dart';

/// Datos del formulario de registro, en espera de que se verifique el
/// correo antes de crear la cuenta de verdad en la base de datos local.
class DatosRegistroPendiente {
  final String nombre;
  final int edad;
  final String correo;
  final String contrasena;
  final bool aceptoPoliticas;
  final bool declaraMayorEdad;

  const DatosRegistroPendiente({
    required this.nombre,
    required this.edad,
    required this.correo,
    required this.contrasena,
    required this.aceptoPoliticas,
    required this.declaraMayorEdad,
  });
}

/// Pide el código de 6 dígitos enviado al correo del formulario de
/// registro. La cuenta solo se crea en SQLite después de verificar el
/// código correctamente (ver `backend/` para el servicio que lo envía).
class EmailVerificationScreen extends StatefulWidget {
  final DatosRegistroPendiente datos;
  const EmailVerificationScreen({super.key, required this.datos});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _codigoCtrl = TextEditingController();
  bool _enviandoCodigo = true;
  bool _verificando = false;
  String? _error;
  int _segundosParaReenviar = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _enviarCodigo();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _enviarCodigo() async {
    setState(() {
      _enviandoCodigo = true;
      _error = null;
    });
    try {
      await EmailVerificationService.enviarCodigo(widget.datos.correo);
      _iniciarConteoReenvio();
    } on EmailVerificationException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo conectar con el servidor de '
          'verificación. Revisa tu conexión e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _enviandoCodigo = false);
    }
  }

  void _iniciarConteoReenvio() {
    setState(() => _segundosParaReenviar = 30);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_segundosParaReenviar <= 1) {
        t.cancel();
        setState(() => _segundosParaReenviar = 0);
      } else {
        setState(() => _segundosParaReenviar--);
      }
    });
  }

  Future<void> _verificarYRegistrar() async {
    setState(() {
      _verificando = true;
      _error = null;
    });
    try {
      await EmailVerificationService.verificarCodigo(
        widget.datos.correo,
        _codigoCtrl.text,
      );

      final usuario = await AuthService.registrar(
        nombre: widget.datos.nombre,
        edad: widget.datos.edad,
        correo: widget.datos.correo,
        contrasena: widget.datos.contrasena,
        aceptoPoliticas: widget.datos.aceptoPoliticas,
        declaraMayorEdad: widget.datos.declaraMayorEdad,
      );

      if (!mounted) return;
      await mostrarDialogoAliasCreado(context, usuario.alias);
      if (!mounted) return;
      Navigator.of(context)
        ..pop()
        ..pop();
    } on EmailVerificationException catch (e) {
      setState(() => _error = e.mensaje);
    } on AuthException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error =
          'No se pudo conectar con el servidor. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verifica tu correo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                _enviandoCodigo
                    ? 'Enviando el código a ${widget.datos.correo}...'
                    : 'Enviamos un código de 6 dígitos a '
                        '${widget.datos.correo}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13.5),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codigoCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  letterSpacing: 8,
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '000000',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: (_segundosParaReenviar > 0 || _enviandoCodigo)
                      ? null
                      : _enviarCodigo,
                  child: Text(
                    _segundosParaReenviar > 0
                        ? 'Reenviar código (${_segundosParaReenviar}s)'
                        : 'Reenviar código',
                    style: const TextStyle(color: AppColors.accentText, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'VERIFICAR Y CREAR CUENTA',
                isLoading: _verificando,
                onPressed: _verificarYRegistrar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
