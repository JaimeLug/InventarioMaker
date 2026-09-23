// Administración de cuentas: crear, desactivar, reactivar y restablecer contraseña.
//
// Primero la base autoriza con el token de quien opera (public.cuenta_autorizar: rol, contraseña
// reconfirmada, el responsable solo administra docentes). Solo entonces se usa la llave secreta
// para tocar Supabase Auth.
import { clienteAdmin, clienteDeUsuario, CORS, rechazo, respuesta } from "../_compartido/comun.ts";

type Accion = "CREAR" | "DESACTIVAR" | "REACTIVAR" | "CONTRASENA";
const ROLES = ["DOCENTE", "RESPONSABLE", "SUBADMIN", "SELECCION"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CORREO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SIEMPRE = "876000h"; // "desactivada" en Supabase Auth: bloqueo por 100 años

interface Solicitud {
  accion?: Accion;
  nombre?: string;
  correo?: string;
  rol?: string;
  contrasena?: string;
  usuario_id?: string;
  matricula?: string;
  nombre_alumno?: string;
  grupo?: string;
}

function validar(s: Solicitud): string | null {
  switch (s.accion) {
    case "CREAR":
      if (!s.nombre || s.nombre.trim().length < 3) return "Escribe el nombre completo.";
      if (!s.rol || !ROLES.includes(s.rol)) return "Elige el rol de la cuenta.";
      if (s.correo && !CORREO.test(s.correo.trim())) return "El correo no parece válido.";
      if (s.contrasena && s.contrasena.length < 8) return "La contraseña debe tener al menos 8 caracteres.";
      if (s.rol === "SELECCION" && (!s.matricula || s.matricula.trim().length === 0)) {
        return "Escribe la matrícula del alumno de la selección.";
      }
      return null;
    case "CONTRASENA":
      if (!s.contrasena || s.contrasena.length < 8) return "La contraseña debe tener al menos 8 caracteres.";
      return s.usuario_id && UUID.test(s.usuario_id) ? null : "Falta la cuenta.";
    case "DESACTIVAR":
    case "REACTIVAR":
      return s.usuario_id && UUID.test(s.usuario_id) ? null : "Falta la cuenta.";
    default:
      return "Acción desconocida.";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return respuesta({ ok: false, mensaje: "Método no permitido" }, 405);

  const autorizacion = req.headers.get("Authorization") ?? "";
  if (!autorizacion.startsWith("Bearer ")) {
    return rechazo("Identifícate para continuar.", { codigo: "PT401", detalle: "SIN_SESION" });
  }

  let s: Solicitud;
  try {
    s = await req.json();
  } catch {
    return respuesta({ ok: false, mensaje: "Solicitud inválida" }, 400);
  }
  // Se valida antes de autorizar, para no gastar la reconfirmación de contraseña en un dato mal escrito.
  const invalido = validar(s);
  if (invalido) return rechazo(invalido);

  const { data: autorizadoPor, error: e1 } = await clienteDeUsuario(autorizacion).rpc("cuenta_autorizar", {
    p_accion: s.accion,
    p_rol: s.rol ?? null,
    p_usuario: s.usuario_id ?? null,
  });
  if (e1) return rechazo(e1.message, { codigo: e1.code, detalle: e1.details });

  const admin = clienteAdmin();
  switch (s.accion) {
    case "CREAR": {
      const correoReal = s.correo?.trim().toLowerCase() || null;
      // Sin correo, la cuenta solo entra con PIN; Supabase Auth igual necesita un correo interno.
      const correoAuth = correoReal ?? `sin-correo-${crypto.randomUUID()}@sin-correo.invalid`;
      const { data: creado, error: e2 } = await admin.auth.admin.createUser({
        email: correoAuth,
        password: s.contrasena || `${crypto.randomUUID()}${crypto.randomUUID()}`,
        email_confirm: true,
        user_metadata: { nombre: s.nombre!.trim() },
      });
      if (e2 || !creado.user) {
        console.error("createUser", e2);
        const repetido = e2?.message?.toLowerCase().includes("already");
        return rechazo(repetido ? "Ya existe una cuenta con ese correo." : "No se pudo crear la cuenta.");
      }
      const { error: e3 } = await admin.rpc("cuenta_registrar", {
        p_id: creado.user.id,
        p_nombre: s.nombre,
        p_rol: s.rol,
        p_correo: correoReal,
        p_creada_por: autorizadoPor,
        p_matricula: s.matricula?.trim() || null,
        p_nombre_alumno: s.nombre_alumno?.trim() || null,
        p_grupo: s.grupo?.trim() || null,
      });
      if (e3) {
        console.error("cuenta_registrar", e3);
        await admin.auth.admin.deleteUser(creado.user.id);
        return rechazo("No se pudo registrar la cuenta.");
      }
      return respuesta({ ok: true, id: creado.user.id });
    }

    case "DESACTIVAR":
    case "REACTIVAR": {
      const activar = s.accion === "REACTIVAR";
      const { error: e2 } = await admin.auth.admin.updateUserById(s.usuario_id!, { ban_duration: activar ? "none" : SIEMPRE });
      if (e2) {
        console.error("updateUserById", e2);
        return rechazo("No se pudo cambiar el estado de la cuenta.");
      }
      const { error: e3 } = await admin.rpc("cuenta_cambiar_estado", {
        p_id: s.usuario_id,
        p_activo: activar,
        p_por: autorizadoPor,
      });
      if (e3) return rechazo(e3.message);
      return respuesta({ ok: true });
    }

    case "CONTRASENA": {
      const { error: e2 } = await admin.auth.admin.updateUserById(s.usuario_id!, { password: s.contrasena });
      if (e2) {
        console.error("updateUserById", e2);
        return rechazo("No se pudo cambiar la contraseña.");
      }
      return respuesta({ ok: true });
    }
  }
  return rechazo("Acción desconocida.");
});
