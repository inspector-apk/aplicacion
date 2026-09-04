enum TipoSolicitud { texto, imagen, audio, video }

extension TipoSolicitudX on TipoSolicitud {
  String get valor => name;

  String get etiqueta {
    switch (this) {
      case TipoSolicitud.texto:
        return 'Texto';
      case TipoSolicitud.imagen:
        return 'Imagen';
      case TipoSolicitud.audio:
        return 'Audio';
      case TipoSolicitud.video:
        return 'Video';
    }
  }

  static TipoSolicitud fromValor(String valor) {
    return TipoSolicitud.values.firstWhere((t) => t.valor == valor);
  }
}

/// Categoría de la solicitud: cambia el valor (ficticio) que se muestra
/// por cada tipo de contenido pedido.
enum Categoria { personal, comercial, industrial }

extension CategoriaX on Categoria {
  String get valor => name;

  String get etiqueta {
    switch (this) {
      case Categoria.personal:
        return 'Personal';
      case Categoria.comercial:
        return 'Comercial';
      case Categoria.industrial:
        return 'Industrial';
    }
  }

  static Categoria fromValor(String valor) {
    return Categoria.values.firstWhere((c) => c.valor == valor);
  }
}

/// Qué tan rápido necesita el cliente la información: entre más
/// urgente, más caro (ver `lib/core/precios.dart`).
enum Urgencia { unaHora, cincoHoras, dosDias }

extension UrgenciaX on Urgencia {
  String get valor => name;

  String get etiqueta {
    switch (this) {
      case Urgencia.unaHora:
        return 'En 1 hora';
      case Urgencia.cincoHoras:
        return 'En 5 horas';
      case Urgencia.dosDias:
        return 'En 2 días';
    }
  }

  static Urgencia fromValor(String valor) {
    return Urgencia.values.firstWhere((u) => u.valor == valor);
  }
}

enum EstadoSolicitud { pendiente, aceptada, completada, cancelada }

extension EstadoSolicitudX on EstadoSolicitud {
  String get valor => name;

  String get etiqueta {
    switch (this) {
      case EstadoSolicitud.pendiente:
        return 'Buscando colaborador';
      case EstadoSolicitud.aceptada:
        return 'Colaborador en camino';
      case EstadoSolicitud.completada:
        return 'Completada';
      case EstadoSolicitud.cancelada:
        return 'Cancelada';
    }
  }

  static EstadoSolicitud fromValor(String valor) {
    return EstadoSolicitud.values.firstWhere((e) => e.valor == valor);
  }
}

/// Una solicitud vive en el backend compartido (no en SQLite local),
/// porque tiene que poder verla un Colaborador en un dispositivo
/// distinto al del Cliente que la creó. Por eso se identifica a las
/// personas por su `alias` (único, generado al registrarse) en vez de
/// un id local de base de datos, que no tendría sentido fuera del
/// dispositivo donde se creó.
class Solicitud {
  final int? id;
  final String clienteAlias;
  final String? colaboradorAlias;

  /// Uno o más tipos de contenido pedidos (ej. texto + imagen).
  final List<TipoSolicitud> tipos;
  final Categoria categoria;

  /// Qué tan rápido necesita el cliente la información.
  final Urgencia urgencia;

  /// Valor ficticio (no es un cobro real) calculado a partir de la
  /// categoría, los tipos pedidos y la urgencia — ver
  /// `lib/core/precios.dart`.
  final int valorTotal;

  /// Datos de la pasarela de pago FICTICIA (ver
  /// `lib/screens/pago_ficticio_screen.dart`): no hay ningún cobro real,
  /// ni tarjeta ni dinero de por medio. Solo se guarda una referencia y
  /// una descripción del "método" simulado para mostrar en el historial.
  final String referenciaPago;
  final String metodoPago;

  final String descripcion;
  final String localidad;

  /// Dirección exacta (texto libre) escrita por el cliente, dentro de
  /// la localidad elegida — para que el colaborador sepa a dónde ir.
  final String direccion;

  /// Imagen de referencia OPCIONAL que el cliente adjunta al crear la
  /// solicitud (ej. para mostrar exactamente qué lugar o ángulo
  /// necesita). A diferencia del contenido de la respuesta, esta no es
  /// de una sola vista: la ve el colaborador mientras atiende la
  /// solicitud, y sigue visible después (no se borra al verla).
  final String? imagenReferenciaBase64;

  final double latitud;
  final double longitud;
  final EstadoSolicitud estado;
  final String fechaCreacion;
  final String fechaActualizacion;

  /// Metadatos de la respuesta del colaborador — NUNCA el contenido en
  /// sí (ese solo se obtiene, una única vez, con
  /// `SolicitudService.verRespuesta`).
  final String? respuestaFecha;
  final bool respuestaVista;

  const Solicitud({
    this.id,
    required this.clienteAlias,
    this.colaboradorAlias,
    required this.tipos,
    required this.categoria,
    this.urgencia = Urgencia.dosDias,
    required this.valorTotal,
    this.referenciaPago = '',
    this.metodoPago = '',
    required this.descripcion,
    required this.localidad,
    this.direccion = '',
    this.imagenReferenciaBase64,
    required this.latitud,
    required this.longitud,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
    this.respuestaFecha,
    this.respuestaVista = false,
  });

  /// true si hay una respuesta esperando a que el cliente la vea.
  bool get tieneRespuestaSinVer =>
      estado == EstadoSolicitud.completada && !respuestaVista;

  String get tiposEtiqueta => tipos.map((t) => t.etiqueta).join(' + ');

  Map<String, Object?> toJson() {
    return {
      'clienteAlias': clienteAlias,
      'tipos': tipos.map((t) => t.valor).toList(),
      'categoria': categoria.valor,
      'urgencia': urgencia.valor,
      'valorTotal': valorTotal,
      'referenciaPago': referenciaPago,
      'metodoPago': metodoPago,
      'descripcion': descripcion,
      'localidad': localidad,
      'direccion': direccion,
      if (imagenReferenciaBase64 != null)
        'imagenReferenciaBase64': imagenReferenciaBase64,
      'latitud': latitud,
      'longitud': longitud,
    };
  }

  factory Solicitud.fromJson(Map<String, dynamic> json) {
    final tiposRaw = json['tipos'];
    final tipos = tiposRaw is List
        ? tiposRaw.map((t) => TipoSolicitudX.fromValor(t as String)).toList()
        : [TipoSolicitudX.fromValor(json['tipo'] as String)]; // compatibilidad

    return Solicitud(
      id: json['id'] as int?,
      clienteAlias: json['cliente_alias'] as String,
      colaboradorAlias: json['colaborador_alias'] as String?,
      tipos: tipos,
      categoria: json['categoria'] != null
          ? CategoriaX.fromValor(json['categoria'] as String)
          : Categoria.personal,
      urgencia: json['urgencia'] != null
          ? UrgenciaX.fromValor(json['urgencia'] as String)
          : Urgencia.dosDias,
      valorTotal: (json['valor_total'] as num?)?.toInt() ?? 0,
      referenciaPago: json['referencia_pago'] as String? ?? '',
      metodoPago: json['metodo_pago'] as String? ?? '',
      descripcion: json['descripcion'] as String,
      direccion: json['direccion'] as String? ?? '',
      imagenReferenciaBase64: json['imagen_referencia_base64'] as String?,
      localidad: json['localidad'] as String,
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      estado: EstadoSolicitudX.fromValor(json['estado'] as String),
      fechaCreacion: json['fecha_creacion'] as String,
      fechaActualizacion: json['fecha_actualizacion'] as String,
      respuestaFecha: json['respuesta_fecha'] as String?,
      respuestaVista: ((json['respuesta_vista'] as num?)?.toInt() ?? 0) == 1,
    );
  }
}
