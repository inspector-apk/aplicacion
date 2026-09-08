import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/app_routes.dart';
import '../services/auth_service.dart';
import '../widgets/app_buttons.dart';
import '../widgets/policy_section.dart';
import 'email_verification_screen.dart';
import 'policy_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _edadCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _contrasenaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  bool _ocultarContrasena = true;
  bool _ocultarConfirmar = true;
  bool _aceptoPoliticas = false;
  bool _declaraMayorEdad = false;
  bool _cargando = false;

  static final RegExp _emailRegex =
      RegExp(r'^[\w\.\-+]+@[\w\-]+\.[a-zA-Z]{2,}$');

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _edadCtrl.dispose();
    _correoCtrl.dispose();
    _contrasenaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  bool get _politicasCompletas => _aceptoPoliticas && _declaraMayorEdad;

  Future<void> _continuarAVerificacion() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_politicasCompletas) return;

    setState(() => _cargando = true);
    try {
      final correo = _correoCtrl.text.trim();
      await AuthService.verificarCorreoDisponible(correo);

      if (!mounted) return;
      await Navigator.of(context).push(
        AppRoutes.slide(
          EmailVerificationScreen(
            datos: DatosRegistroPendiente(
              nombre: _nombreCtrl.text,
              edad: int.parse(_edadCtrl.text.trim()),
              correo: correo,
              contrasena: _contrasenaCtrl.text,
              aceptoPoliticas: _aceptoPoliticas,
              declaraMayorEdad: _declaraMayorEdad,
            ),
          ),
        ),
      );
    } on AuthException catch (e) {
      _mostrarError(e.mensaje);
    } catch (_) {
      _mostrarError('No se pudo conectar con el servidor. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: () => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              TextFormField(
                controller: _nombreCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  helperText: 'Tu nombre y apellido, como te identificas',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Ingresa tu nombre completo'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _edadCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Edad',
                  helperText: 'Tu edad en años (debes declarar si eres mayor '
                      'de 18 más abajo)',
                ),
                validator: (v) {
                  final edad = int.tryParse((v ?? '').trim());
                  if (edad == null) return 'Ingresa una edad válida';
                  if (edad < 1 || edad > 120) return 'Ingresa una edad válida';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _correoCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  helperText: 'Te enviaremos un código para verificarlo '
                      'antes de crear la cuenta',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Ingresa tu correo electrónico';
                  }
                  if (!_emailRegex.hasMatch(v.trim())) {
                    return 'Ingresa un correo electrónico válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contrasenaCtrl,
                obscureText: _ocultarContrasena,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  helperText: 'Mínimo 6 caracteres',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _ocultarContrasena
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _ocultarContrasena = !_ocultarContrasena),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.length < 6) {
                    return 'Mínimo 6 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmarCtrl,
                obscureText: _ocultarConfirmar,
                decoration: InputDecoration(
                  labelText: 'Confirmar contraseña',
                  helperText: 'Escribe la misma contraseña otra vez',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _ocultarConfirmar
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        setState(() => _ocultarConfirmar = !_ocultarConfirmar),
                  ),
                ),
                validator: (v) {
                  if (v != _contrasenaCtrl.text) {
                    return 'Las contraseñas no coinciden';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              PolicySection(
                aceptoPoliticas: _aceptoPoliticas,
                declaraMayorEdad: _declaraMayorEdad,
                onAceptoPoliticasChanged: (v) =>
                    setState(() => _aceptoPoliticas = v),
                onDeclaraMayorEdadChanged: (v) =>
                    setState(() => _declaraMayorEdad = v),
                onVerPolitica: () {
                  Navigator.of(context)
                      .push(AppRoutes.slide(const PolicyScreen()));
                },
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'VERIFICAR CORREO Y CONTINUAR',
                isLoading: _cargando,
                onPressed: _politicasCompletas ? _continuarAVerificacion : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
