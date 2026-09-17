// Avisos al celular con Firebase Cloud Messaging (API v1).
// La cuenta de servicio firma un token de Google; se guarda en memoria mientras dura (1 hora).

interface CuentaServicio {
  project_id: string;
  client_email: string;
  private_key: string;
}

export interface ResultadoPush {
  ok: boolean;
  tokenInvalido: boolean;
  error?: string;
}

const CRUDO = Deno.env.get("FIREBASE_CUENTA_SERVICIO");
let cuenta: CuentaServicio | null = null;
try {
  // scripts/desplegar.py la guarda en base64; también se acepta el JSON tal cual.
  cuenta = CRUDO ? (JSON.parse(CRUDO.trim().startsWith("{") ? CRUDO : atob(CRUDO)) as CuentaServicio) : null;
} catch {
  console.error("FIREBASE_CUENTA_SERVICIO no es un JSON válido");
}

export const hayPush = () => cuenta !== null;

let tokenGoogle: { valor: string; vence: number } | null = null;

const base64url = (datos: ArrayBuffer | Uint8Array | string): string => {
  const bytes = typeof datos === "string" ? new TextEncoder().encode(datos) : new Uint8Array(datos);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
};

async function accesoGoogle(c: CuentaServicio): Promise<string> {
  const ahora = Math.floor(Date.now() / 1000);
  if (tokenGoogle && tokenGoogle.vence > ahora + 60) return tokenGoogle.valor;

  const pem = c.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (ch) => ch.charCodeAt(0));
  const llave = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const encabezado = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const reclamos = base64url(JSON.stringify({
    iss: c.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: ahora,
    exp: ahora + 3600,
  }));
  const firma = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", llave, new TextEncoder().encode(`${encabezado}.${reclamos}`));
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${encabezado}.${reclamos}.${base64url(firma)}`,
    }),
  });
  if (!r.ok) throw new Error(`Google ${r.status}: ${(await r.text()).slice(0, 300)}`);
  const j = await r.json();
  tokenGoogle = { valor: j.access_token, vence: ahora + (j.expires_in ?? 3600) };
  return tokenGoogle.valor;
}

export async function enviarPush(token: string, titulo: string, cuerpo: string, datos: Record<string, unknown>): Promise<ResultadoPush> {
  if (!cuenta) return { ok: false, tokenInvalido: false, error: "Firebase no configurado" };
  const acceso = await accesoGoogle(cuenta);
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${cuenta.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${acceso}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token,
        notification: { title: titulo, body: cuerpo },
        data: Object.fromEntries(Object.entries(datos ?? {}).map(([k, v]) => [k, String(v ?? "")])),
        // Canal de importancia alta que crea la app (MainActivity.kt): el aviso aparece arriba y suena.
        // Visible también en la pantalla bloqueada: los avisos nunca llevan nombres de alumnos.
        android: { priority: "high", notification: { channel_id: "avisos", visibility: "PUBLIC", default_sound: true } },
      },
    }),
  });
  if (r.ok) return { ok: true, tokenInvalido: false };
  const texto = await r.text();
  // El celular desinstaló la app o renovó su identificador.
  const invalido = r.status === 404 || texto.includes("UNREGISTERED") || texto.includes("registration token");
  return { ok: false, tokenInvalido: invalido, error: `FCM ${r.status}: ${texto.slice(0, 300)}` };
}
