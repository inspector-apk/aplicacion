import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/documentos_legales.dart';

const String kDeclaracionMayoriaEdad = 'Declaro que soy mayor de 18 años.';

/// Sección legal del registro: lista los documentos (términos, políticas
/// de uso, tratamiento de datos y normatividad) para que el usuario los
/// abra, y los dos checkboxes obligatorios para poder crear la cuenta.
class PolicySection extends StatelessWidget {
  final bool aceptoPoliticas;
  final bool declaraMayorEdad;
  final ValueChanged<bool> onAceptoPoliticasChanged;
  final ValueChanged<bool> onDeclaraMayorEdadChanged;

  /// Recibe la posición del documento en [kDocumentosLegales].
  final ValueChanged<int> onVerDocumento;

  const PolicySection({
    super.key,
    required this.aceptoPoliticas,
    required this.declaraMayorEdad,
    required this.onAceptoPoliticasChanged,
    required this.onDeclaraMayorEdadChanged,
    required this.onVerDocumento,
  });

  TextSpan _link(String texto, int indice) {
    return TextSpan(
      text: texto,
      style: const TextStyle(
        color: AppColors.accentText,
        decoration: TextDecoration.underline,
        fontWeight: FontWeight.w600,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => onVerDocumento(indice),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Términos, políticas y normatividad',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Léelos antes de crear tu cuenta. Toca cada uno para abrirlo.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          for (var i = 0; i < kDocumentosLegales.length; i++)
            InkWell(
              onTap: () => onVerDocumento(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(kDocumentosLegales[i].icono,
                        color: AppColors.accentText, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        kDocumentosLegales[i].titulo,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.textMuted, size: 20),
                  ],
                ),
              ),
            ),
          const Divider(height: 1, color: AppColors.border),
          // Sin InkWell envolvente: el texto incluye links tapables
          // propios, así que solo el checkbox alterna el valor para no
          // competir por el mismo gesto con los links.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: aceptoPoliticas,
                  onChanged: (v) => onAceptoPoliticasChanged(v ?? false),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                        children: [
                          const TextSpan(text: 'He leído y acepto los '),
                          _link('Términos y condiciones', 0),
                          const TextSpan(text: ', las '),
                          _link('Políticas de uso', 1),
                          const TextSpan(text: ' y el '),
                          _link('Tratamiento de datos personales', 2),
                          const TextSpan(text: ', conforme a la '),
                          _link('normatividad aplicable', 3),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _PolicyCheckbox(
            value: declaraMayorEdad,
            onChanged: onDeclaraMayorEdadChanged,
            child: const Text(
              kDeclaracionMayoriaEdad,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget child;

  const _PolicyCheckbox({
    required this.value,
    required this.onChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
