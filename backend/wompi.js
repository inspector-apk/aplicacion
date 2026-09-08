const crypto = require('crypto');

// Wompi (Bancolombia) — pasarela real para cobrar por PSE. Modo sandbox
// por defecto (dinero simulado, ningún cargo real) hasta que se pongan
// las llaves de producción en el .env. Las llaves se sacan gratis
// creando una cuenta en https://comercios.wompi.co (el modo "Sandbox"
// del panel no requiere ningún trámite ni verificación de negocio, solo
// registrarte) — ver backend/README.md para el paso a paso.
const BASE_URL = process.env.WOMPI_BASE_URL || 'https://sandbox.wompi.co/v1';
const LLAVE_PUBLICA = process.env.WOMPI_PUBLIC_KEY;
const LLAVE_PRIVADA = process.env.WOMPI_PRIVATE_KEY;
const SECRETO_EVENTOS = process.env.WOMPI_EVENTS_SECRET;

class ErrorWompi extends Error {}

function configurado() {
  return Boolean(LLAVE_PUBLICA && LLAVE_PRIVADA);
}

async function llamar(ruta, { metodo = 'GET', body, llave = LLAVE_PRIVADA } = {}) {
  if (!llave) {
    throw new ErrorWompi('El backend no tiene configuradas las llaves de Wompi (WOMPI_PUBLIC_KEY/WOMPI_PRIVATE_KEY en el .env)');
  }
  const resp = await fetch(`${BASE_URL}${ruta}`, {
    method: metodo,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${llave}`,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const cuerpo = await resp.json().catch(() => null);
  if (!resp.ok) {
    const mensaje = cuerpo?.error?.messages
      ? JSON.stringify(cuerpo.error.messages)
      : cuerpo?.error?.reason || `Wompi respondió ${resp.status}`;
    throw new ErrorWompi(mensaje);
  }
  return cuerpo;
}

/**
 * Los tokens de aceptación (términos y condiciones + autorización de
 * datos personales) son obligatorios en cada transacción nueva; Wompi
 * los genera al vuelo por comercio, así que se piden frescos cada vez
 * en vez de guardarlos (el volumen de transacciones de esta app es bajo).
 */
async function obtenerTokensAceptacion() {
  const cuerpo = await llamar(`/merchants/${LLAVE_PUBLICA}`, { llave: LLAVE_PUBLICA });
  const datos = cuerpo?.data;
  const tokenTerminos = datos?.presigned_acceptance?.acceptance_token;
  const tokenDatosPersonales = datos?.presigned_personal_data_auth?.acceptance_token;
  if (!tokenTerminos) {
    throw new ErrorWompi('No se pudieron obtener los tokens de aceptación de Wompi');
  }
  return { tokenTerminos, tokenDatosPersonales };
}

/** Lista de bancos habilitados para PSE (código + nombre), para el selector en la app. */
async function listarBancosPSE() {
  const cuerpo = await llamar('/pse/financial_institutions');
  return (cuerpo?.data || []).map((b) => ({
    codigo: b.financial_institution_code,
    nombre: b.financial_institution_name,
  }));
}

/**
 * Crea una transacción PSE. `montoCentavos` es el valor en centavos de
 * peso (ej. $50.000 = 5000000). Devuelve el id de la transacción en
 * Wompi, su estado inicial y la URL a la que hay que mandar al cliente
 * para que autentique el pago con su banco.
 */
async function crearTransaccionPSE({
  referencia, montoCentavos, correo, codigoBanco, tipoPersona,
  tipoDocumento, numeroDocumento, redirectUrl, descripcion,
}) {
  const { tokenTerminos, tokenDatosPersonales } = await obtenerTokensAceptacion();

  const cuerpo = await llamar('/transactions', {
    metodo: 'POST',
    body: {
      amount_in_cents: montoCentavos,
      currency: 'COP',
      customer_email: correo,
      reference: referencia,
      acceptance_token: tokenTerminos,
      accept_personal_auth: tokenDatosPersonales,
      payment_method: {
        type: 'PSE',
        user_type: tipoPersona === 'juridica' ? 1 : 0,
        user_legal_id_type: tipoDocumento,
        user_legal_id: numeroDocumento,
        financial_institution_code: codigoBanco,
        payment_description: descripcion || 'Pago Inspector',
      },
      redirect_url: redirectUrl,
    },
  });

  const datos = cuerpo?.data;
  const urlBanco = datos?.payment_method?.extra?.async_payment_url;
  if (!datos?.id || !urlBanco) {
    throw new ErrorWompi('Wompi no devolvió una URL de redirección para PSE');
  }
  return { wompiId: datos.id, estado: datos.status, urlBanco };
}

async function obtenerTransaccion(wompiId) {
  const cuerpo = await llamar(`/transactions/${wompiId}`, { llave: LLAVE_PUBLICA });
  return cuerpo?.data || null;
}

/**
 * Verifica la firma de un evento de webhook (ver README para cómo
 * configurar la URL del webhook en el panel de Wompi). El cálculo es:
 * sha256( valores_de_las_propiedades_firmadas + timestamp + secreto ).
 */
function verificarFirmaWebhook({ data, signature, timestamp }) {
  if (!SECRETO_EVENTOS || !signature?.checksum || !Array.isArray(signature?.properties)) {
    return false;
  }
  const valores = signature.properties
    .map((ruta) => ruta.split('.').reduce((obj, clave) => obj?.[clave], data))
    .join('');
  const cadena = `${valores}${timestamp}${SECRETO_EVENTOS}`;
  const checksumCalculado = crypto.createHash('sha256').update(cadena).digest('hex').toUpperCase();
  return checksumCalculado === String(signature.checksum).toUpperCase();
}

module.exports = {
  ErrorWompi,
  configurado,
  listarBancosPSE,
  crearTransaccionPSE,
  obtenerTransaccion,
  verificarFirmaWebhook,
};
