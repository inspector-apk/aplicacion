import 'package:flutter/material.dart';

/// Contacto para consultas y solicitudes sobre datos personales.
const String kCorreoContactoLegal = 'desarrollador.inspector@servialco.com';

const String kVersionDocumentosLegales = 'Versión 1.0 · septiembre de 2026';

class SeccionLegal {
  final String titulo;
  final String texto;
  const SeccionLegal(this.titulo, this.texto);
}

class DocumentoLegal {
  final String titulo;
  final String tituloCorto;
  final String resumen;
  final IconData icono;
  final List<SeccionLegal> secciones;

  const DocumentoLegal({
    required this.titulo,
    required this.tituloCorto,
    required this.resumen,
    required this.icono,
    required this.secciones,
  });
}

/// Documentos que el usuario debe conocer y aceptar al registrarse. El
/// orden importa: la pantalla de políticas abre en la pestaña que se le
/// indique por posición.
const List<DocumentoLegal> kDocumentosLegales = [
  DocumentoLegal(
    titulo: 'Términos y condiciones',
    tituloCorto: 'Términos',
    resumen: 'Qué es Inspector, cómo funciona y qué se espera de ti.',
    icono: Icons.description_outlined,
    secciones: [
      SeccionLegal(
        '1. Qué es Inspector',
        'Inspector es una aplicación de Servialco que conecta a Clientes con '
            'Colaboradores. Un Cliente pide que un Colaborador vaya a un lugar '
            'de Bogotá y le entregue información (texto, imagen, audio o '
            'video). Inspector actúa solo como intermediario: cada '
            'Colaborador responde por la veracidad de lo que reporta.',
      ),
      SeccionLegal(
        '2. Registro y cuenta',
        'Debes ser mayor de 18 años y dar datos verdaderos. Cada persona '
            'puede tener una sola cuenta. Eres responsable de guardar tu '
            'contraseña y de todo lo que se haga con tu cuenta. Tu alias '
            '(por ejemplo, Inspector_ABC123) se asigna automáticamente y es '
            'el nombre con el que te ven los demás usuarios.',
      ),
      SeccionLegal(
        '3. Roles',
        'Puedes usar la app como Cliente o como Colaborador y cambiar de rol '
            'cuando quieras. No puedes tomar ni responder tus propias '
            'solicitudes.',
      ),
      SeccionLegal(
        '4. Cómo funciona una solicitud',
        'El Cliente elige el tipo de servicio, lo que necesita recibir, lo '
            'que debe hacer el Colaborador, el lugar exacto en el mapa y la '
            'urgencia. Luego realiza el pago y la solicitud queda disponible. '
            'El primer Colaborador que la acepta se encarga de ella y debe '
            'responder con todo el contenido pedido. El Cliente ve la '
            'respuesta una sola vez y después se elimina de nuestros '
            'servidores.',
      ),
      SeccionLegal(
        '5. Pagos y valores',
        'En esta versión de la aplicación los pagos y las ganancias son '
            'simulados: los valores son de referencia y no se cobra ni se '
            'transfiere dinero real. Si en el futuro se habilitan pagos '
            'reales, se informará antes y se pedirá tu aceptación.',
      ),
      SeccionLegal(
        '6. Cancelaciones',
        'El Cliente puede cancelar mientras nadie haya aceptado su '
            'solicitud. Si un Colaborador cancela una solicitud que ya '
            'aceptó, la solicitud vuelve a quedar disponible y su cuenta se '
            'bloquea por 5 minutos.',
      ),
      SeccionLegal(
        '7. Responsabilidades',
        'El Colaborador debe respetar la ley y las normas del lugar, no '
            'ingresar a sitios privados o restringidos sin autorización y '
            'entregar información real. El Cliente debe pedir solo cosas '
            'lícitas y usar la información recibida de forma responsable. '
            'Servialco no responde por información inexacta reportada por un '
            'Colaborador ni por interrupciones del servicio, en la medida '
            'que la ley lo permita.',
      ),
      SeccionLegal(
        '8. Suspensión de cuentas',
        'Podemos suspender o cerrar cuentas que incumplan estos términos o '
            'las Políticas de uso, y cancelar solicitudes que las infrinjan.',
      ),
      SeccionLegal(
        '9. Cambios y ley aplicable',
        'Podemos actualizar estos documentos; los cambios se avisarán en la '
            'app y, si sigues usándola, se entiende que los aceptas. Estos '
            'términos se rigen por las leyes de la República de Colombia.',
      ),
    ],
  ),
  DocumentoLegal(
    titulo: 'Políticas de uso',
    tituloCorto: 'Uso',
    resumen: 'Lo que está permitido y lo que no en la aplicación.',
    icono: Icons.rule_folder_outlined,
    secciones: [
      SeccionLegal(
        'Contenido prohibido',
        'No se permite pedir, enviar ni publicar contenido sexual o '
            'pornográfico, ni de explotación o abuso de menores, ni '
            'relacionado con violación, incesto o trata de personas. Estas '
            'solicitudes se bloquean automáticamente y pueden ser reportadas '
            'a las autoridades.',
      ),
      SeccionLegal(
        'Respeto a la intimidad',
        'No uses Inspector para acosar, perseguir o vigilar personas. No '
            'fotografíes ni grabes a personas identificables sin su '
            'consentimiento: las solicitudes son sobre lugares, no sobre '
            'individuos.',
      ),
      SeccionLegal(
        'Actividades ilícitas',
        'No pidas ni realices solicitudes para cometer o facilitar delitos, '
            'ni para ingresar a propiedad privada o zonas restringidas sin '
            'permiso.',
      ),
      SeccionLegal(
        'Información veraz',
        'Las fotos, audios y videos que envíes como Colaborador deben ser '
            'reales y tomados en el lugar pedido. La app analiza en tu '
            'celular si una foto parece generada por IA; si es sospechosa, '
            'debes confirmar que es real antes de enviarla.',
      ),
      SeccionLegal(
        'Cuenta y seguridad',
        'No crees cuentas falsas ni automatizadas, no suplantes a otras '
            'personas, no compartas tu contraseña y no intentes vulnerar la '
            'seguridad de la aplicación o de otros usuarios.',
      ),
      SeccionLegal(
        'Consecuencias',
        'Incumplir estas políticas puede llevar a la cancelación de '
            'solicitudes, la suspensión o el cierre de la cuenta y, cuando '
            'corresponda, el reporte a las autoridades competentes.',
      ),
    ],
  ),
  DocumentoLegal(
    titulo: 'Tratamiento de datos personales',
    tituloCorto: 'Datos',
    resumen: 'Qué datos guardamos, para qué y cuáles son tus derechos.',
    icono: Icons.privacy_tip_outlined,
    secciones: [
      SeccionLegal(
        'Responsable',
        'Servialco es responsable del tratamiento de tus datos personales. '
            'Contacto para consultas, reclamos y solicitudes: '
            '$kCorreoContactoLegal.',
      ),
      SeccionLegal(
        'Datos que recolectamos',
        'Cuenta: nombre, edad, correo, contraseña (se guarda cifrada, nunca '
            'en texto legible), alias, rol y tu aceptación de estas políticas.\n'
            'Colaboradores: ocupación, localidad de trabajo y datos de la '
            'cuenta bancaria que configures.\n'
            'Ubicación: el Colaborador comparte su ubicación mientras está '
            'disponible; se usa solo para mostrarlo en el mapa (de forma '
            'aproximada) y deja de compartirse al salir.\n'
            'Solicitudes: tipo de servicio, contenido pedido, opción elegida, '
            'localidad, punto en el mapa, foto de referencia opcional, '
            'urgencia, valor de referencia, estado y fechas.\n'
            'Respuestas: el texto, foto, audio o video que envía el '
            'Colaborador se guarda solo hasta que el Cliente lo ve una vez; '
            'luego se elimina.\n'
            'Pagos: como el pago es simulado, solo se guarda una referencia y '
            'el método mostrado.',
      ),
      SeccionLegal(
        'Para qué los usamos',
        'Crear y administrar tu cuenta, conectar Clientes con '
            'Colaboradores, enviarte códigos de verificación por correo, '
            'prevenir fraude y abusos, moderar contenido prohibido y mejorar '
            'el servicio. No vendemos tus datos.',
      ),
      SeccionLegal(
        'Autorización',
        'Al aceptar estos documentos autorizas el tratamiento de tus datos '
            'para las finalidades descritas. No se permite registrar '
            'menores de 18 años.',
      ),
      SeccionLegal(
        'Tus derechos',
        'Como titular puedes: conocer, actualizar y rectificar tus datos; '
            'pedir prueba de tu autorización; saber cómo se usan; revocar la '
            'autorización y pedir la supresión de tus datos; acceder a ellos '
            'gratis y presentar quejas ante la Superintendencia de Industria '
            'y Comercio (SIC).',
      ),
      SeccionLegal(
        'Cómo ejercerlos',
        'Escríbenos a $kCorreoContactoLegal. Las consultas se responden en '
            'máximo 10 días hábiles y los reclamos en máximo 15 días hábiles, '
            'según la ley.',
      ),
      SeccionLegal(
        'Seguridad y conservación',
        'Aplicamos medidas técnicas y administrativas razonables para '
            'proteger la información. Conservamos tus datos mientras tu '
            'cuenta esté activa y por el tiempo que la ley exija.',
      ),
    ],
  ),
  DocumentoLegal(
    titulo: 'Normatividad aplicable',
    tituloCorto: 'Normas',
    resumen: 'Las leyes colombianas que rigen el servicio.',
    icono: Icons.gavel_outlined,
    secciones: [
      SeccionLegal(
        'Datos personales',
        'Constitución Política, artículos 15 (intimidad y habeas data) y 20. '
            'Ley 1581 de 2012 y su reglamentación (Decreto 1377 de 2013, '
            'compilado en el Decreto 1074 de 2015): protección de datos '
            'personales. La autoridad de control es la Superintendencia de '
            'Industria y Comercio (SIC).',
      ),
      SeccionLegal(
        'Consumidores y comercio electrónico',
        'Ley 1480 de 2011 (Estatuto del Consumidor) y Ley 527 de 1999 '
            '(comercio electrónico y validez de los mensajes de datos).',
      ),
      SeccionLegal(
        'Delitos informáticos',
        'Ley 1273 de 2009: protege la información y los datos, y sanciona el '
            'acceso abusivo a sistemas, la suplantación de identidad y otros '
            'delitos informáticos.',
      ),
      SeccionLegal(
        'Protección de menores',
        'Ley 1098 de 2006 (Código de la Infancia y la Adolescencia) y Ley '
            '679 de 2001 (prevención de la explotación sexual de menores en '
            'medios electrónicos). Por eso el servicio es solo para mayores de '
            '18 años y bloquea contenido de este tipo.',
      ),
    ],
  ),
];
