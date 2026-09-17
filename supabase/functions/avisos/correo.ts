// Correo por API HTTP (Supabase no deja abrir SMTP en los puertos habituales).
// Resend exige un dominio verificado para escribirle a cualquiera; Brevo permite verificar
// solo una dirección remitente. Se usa el que tenga llave.

const RESEND = Deno.env.get("RESEND_API_KEY");
const BREVO = Deno.env.get("BREVO_API_KEY");
const REMITENTE = Deno.env.get("CORREO_REMITENTE") ?? "Laboratorio Maker <onboarding@resend.dev>";

export const hayCorreo = () => Boolean(RESEND || BREVO);

function escapar(t: string): string {
  return t.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

// El texto viene armado en la base; aquí solo se le da formato y se vuelven clicables los enlaces.
function html(texto: string): string {
  const cuerpo = escapar(texto)
    .replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" style="color:#00695c;font-weight:600">$1</a>')
    .replaceAll("\n", "<br>");
  return `<div style="font-family:Arial,sans-serif;font-size:15px;line-height:1.5;color:#1b1b1b;max-width:560px">${cuerpo}</div>`;
}

function separarRemitente(r: string): { name?: string; email: string } {
  const m = r.match(/^\s*(.*?)\s*<([^>]+)>\s*$/);
  return m ? { name: m[1] || undefined, email: m[2] } : { email: r.trim() };
}

export async function enviarCorreo(destino: string, asunto: string, texto: string): Promise<void> {
  if (RESEND) {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${RESEND}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: REMITENTE, to: [destino], subject: asunto, text: texto, html: html(texto) }),
    });
    if (!r.ok) throw new Error(`Resend ${r.status}: ${(await r.text()).slice(0, 300)}`);
    return;
  }
  if (BREVO) {
    const r = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": BREVO, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        sender: separarRemitente(REMITENTE),
        to: [{ email: destino }],
        subject: asunto,
        textContent: texto,
        htmlContent: html(texto),
      }),
    });
    if (!r.ok) throw new Error(`Brevo ${r.status}: ${(await r.text()).slice(0, 300)}`);
    return;
  }
  throw new Error("No hay servicio de correo configurado");
}
