const nodemailer = require('nodemailer');

const transportador = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.GMAIL_USER,
    pass: process.env.GMAIL_APP_PASSWORD,
  },
});

async function enviarCorreoCodigo(destinatario, codigo) {
  await transportador.sendMail({
    from: `Inspector <${process.env.GMAIL_USER}>`,
    to: destinatario,
    subject: 'Tu código de verificación de Inspector',
    text: `Tu código de verificación es: ${codigo}\n\nExpira en 10 minutos. Si no solicitaste este código, ignora este mensaje.`,
    html: `
      <div style="font-family: sans-serif; background:#000000; color:#F5F5F5; padding:24px;">
        <h2 style="color:#FFD700; margin-top:0;">Inspector</h2>
        <p>Tu código de verificación es:</p>
        <p style="font-size:28px; font-weight:bold; letter-spacing:6px; color:#FFD700;">${codigo}</p>
        <p style="color:#A0A0A3; font-size:13px;">Expira en 10 minutos. Si no solicitaste este código, ignora este mensaje.</p>
      </div>
    `,
  });
}

module.exports = { enviarCorreoCodigo };
