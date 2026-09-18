import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../modelos/catalogos.dart';

/// Una sola familia de iconos en toda la app: Lucide, de contorno.
/// Tamaños: 16 en insignias, 20 en la interfaz, 24 en la barra inferior, 32+ en estados vacíos.
abstract final class Ico {
  // Navegación
  static const tablero = LucideIcons.layoutDashboard;
  static const inventario = LucideIcons.boxes;
  static const herramientas = LucideIcons.wrench;
  static const prestamos = LucideIcons.arrowLeftRight;
  static const solicitudes = LucideIcons.inbox;
  static const pendientes = LucideIcons.listChecks;
  static const contenedores = LucideIcons.warehouse;
  static const kits = LucideIcons.blocks;
  static const reportes = LucideIcons.chartColumn;
  static const adeudos = LucideIcons.userRound;
  static const cuentas = LucideIcons.users;
  static const ajustes = LucideIcons.settings;
  static const bitacora = LucideIcons.history;
  static const menu = LucideIcons.menu;
  static const mas = LucideIcons.ellipsisVertical;
  static const diseno = LucideIcons.palette;

  /// El hexágono de la marca en la barra lateral.
  static const marca = LucideIcons.hexagon;

  // Acciones
  static const escanear = LucideIcons.scanLine;
  static const prestar = LucideIcons.arrowLeftRight;
  static const devolver = LucideIcons.undo2;
  static const reportar = LucideIcons.flag;
  static const contar = LucideIcons.listChecks;
  static const editar = LucideIcons.pencil;
  static const nuevo = LucideIcons.plus;
  static const guardar = LucideIcons.circleCheck;
  static const baja = LucideIcons.trash2;
  static const imprimir = LucideIcons.printer;
  static const buscar = LucideIcons.search;
  static const filtros = LucideIcons.slidersHorizontal;
  static const descargar = LucideIcons.download;
  static const excel = LucideIcons.fileSpreadsheet;
  static const pdf = LucideIcons.fileText;
  static const foto = LucideIcons.camera;
  static const qr = LucideIcons.qrCode;
  static const cerrar = LucideIcons.x;
  static const reintentar = LucideIcons.refreshCw;
  static const avanzar = LucideIcons.chevronRight;
  static const regresar = LucideIcons.chevronLeft;

  // Estados y avisos
  static const ok = LucideIcons.circleCheck;
  static const aviso = LucideIcons.triangleAlert;
  static const error = LucideIcons.circleX;
  static const info = LucideIcons.info;
  static const alerta = LucideIcons.circleAlert;
  static const reloj = LucideIcons.clock;
  static const campana = LucideIcons.bell;
  static const verificado = LucideIcons.badgeCheck;
  static const porVerificar = LucideIcons.eye;
  static const noSePresta = LucideIcons.lock;
  static const sinFoto = LucideIcons.image;
  static const ubicacion = LucideIcons.mapPin;
  static const persona = LucideIcons.user;
  static const sinConexion = LucideIcons.cloudOff;
  static const enLinea = LucideIcons.cloudCheck;
  static const porEnviar = LucideIcons.cloudUpload;
  static const vacio = LucideIcons.packageOpen;
  static const sinResultados = LucideIcons.search;
  static const sinSenal = LucideIcons.wifiOff;

  /// El icono de cada categoría (el nombre siempre se escribe junto).
  static IconData deCategoria(Categoria c) => switch (c) {
        Categoria.vex => LucideIcons.hexagon,
        Categoria.ftc => LucideIcons.cog,
        Categoria.herramientas => LucideIcons.wrench,
        Categoria.herramientasElectricas => LucideIcons.plugZap,
        Categoria.consumibles => LucideIcons.layers,
        Categoria.comun => LucideIcons.package,
        Categoria.sinClasificar => LucideIcons.circleHelp,
      };

  /// Subcategorías (estructura, movimiento, sensores…): icono neutro, sin color propio.
  static IconData deSubcategoria(String? sub) => switch ((sub ?? '').toLowerCase()) {
        final s when s.contains('estructura') => LucideIcons.brickWall,
        final s when s.contains('movimiento') => LucideIcons.disc3,
        final s when s.contains('electrón') || s.contains('electron') => LucideIcons.cpu,
        final s when s.contains('sensor') => LucideIcons.radar,
        final s when s.contains('control') => LucideIcons.gamepad2,
        final s when s.contains('tornill') => LucideIcons.hash,
        final s when s.contains('energ') || s.contains('bater') => LucideIcons.battery,
        final s when s.contains('medici') => LucideIcons.gauge,
        final s when s.contains('soldad') => LucideIcons.flame,
        final s when s.contains('impresi') => LucideIcons.printer,
        final s when s.contains('corte') => LucideIcons.scissors,
        final s when s.contains('segurid') => LucideIcons.shieldCheck,
        final s when s.contains('fabricaci') => LucideIcons.construction,
        final s when s.contains('kit') => LucideIcons.boxes,
        final s when s.contains('manual') || s.contains('mano') => LucideIcons.wrench,
        _ => LucideIcons.tag,
      };

  /// Tipo de movimiento en historial y bitácora.
  static IconData deMovimiento(String tipo) => switch (tipo) {
        'PRESTAMO' => LucideIcons.arrowLeftRight,
        'DEVOLUCION' => LucideIcons.undo2,
        'CONSUMO' => LucideIcons.layers,
        'PERDIDA' => LucideIcons.circleX,
        'DANO' || 'DAÑO' => LucideIcons.triangleAlert,
        'REPARACION' => LucideIcons.wrench,
        'ALTA' => LucideIcons.plus,
        'BAJA' => LucideIcons.trash2,
        'AJUSTE_CONTEO' => LucideIcons.clipboardCheck,
        'EXTENSION' => LucideIcons.calendarClock,
        _ => LucideIcons.history,
      };
}
