import '../models/solicitud.dart';

/// "Diccionario" de frases comunes para ayudar al cliente a describir su
/// solicitud más rápido — organizadas por categoría porque lo que se
/// suele pedir cambia bastante entre una solicitud personal, comercial
/// o industrial. Son solo sugerencias: el cliente sigue pudiendo
/// escribir lo que quiera, tocarlas solo llena o completa el campo.
const Map<Categoria, List<String>> kSugerenciasDescripcion = {
  Categoria.personal: [
    'Confirmar si alguien se encuentra en la dirección',
    'Tomar una foto del frente de la vivienda',
    'Verificar el estado de un vehículo parqueado',
    'Recoger o confirmar la entrega de un paquete',
    'Verificar si una dirección existe y cómo se ve',
  ],
  Categoria.comercial: [
    'Verificar si el local está abierto en este momento',
    'Tomar una foto de la vitrina o fachada del negocio',
    'Confirmar el horario de atención en el lugar',
    'Verificar el estado del inventario o exhibición',
    'Comprobar si hay fila o disponibilidad en el sitio',
  ],
  Categoria.industrial: [
    'Verificar el estado de una bodega o planta',
    'Tomar fotos de maquinaria o equipos en sitio',
    'Confirmar la llegada de un cargamento o proveedor',
    'Revisar condiciones de seguridad en la instalación',
    'Documentar el estado de la infraestructura',
  ],
};
