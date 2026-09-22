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
  static const comentario = LucideIcons.messageSquare;
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

  // Navegacion y objetos
  static const inicio = LucideIcons.house;
  static const arbol = LucideIcons.listTree;
  static const caja = LucideIcons.package;
  static const carpeta = LucideIcons.folder;
  static const nuevaCarpeta = LucideIcons.folderPlus;
  static const subnivel = LucideIcons.cornerDownRight;
  static const mover = LucideIcons.folderInput;
  static const inventarios = LucideIcons.clipboardList;
  static const lista = LucideIcons.list;
  static const cuadricula = LucideIcons.layoutGrid;
  static const escuela = LucideIcons.graduationCap;
  static const maestro = LucideIcons.presentation;
  static const expediente = LucideIcons.contact;
  static const credencial = LucideIcons.idCard;
  static const acta = LucideIcons.receiptText;
  static const oficio = LucideIcons.fileText;
  static const nota = LucideIcons.stickyNote;

  // Acciones
  static const agregarFoto = LucideIcons.imagePlus;
  static const galeria = LucideIcons.images;
  static const enlazar = LucideIcons.link;
  static const articuloNuevo = LucideIcons.packagePlus;
  static const agregarALista = LucideIcons.listPlus;
  static const apartar = LucideIcons.bookmarkPlus;
  static const quitar = LucideIcons.trash;
  static const quitarUno = LucideIcons.minus;
  static const quitarCirculo = LucideIcons.circleMinus;
  static const desactivar = LucideIcons.ban;
  static const reactivar = LucideIcons.archiveRestore;
  static const desarchivar = LucideIcons.archiveRestore;
  static const reparar = LucideIcons.hammer;
  static const revisar = LucideIcons.clipboardCheck;
  static const aprobar = LucideIcons.userCheck;
  static const aprobado = LucideIcons.thumbsUp;
  static const entrega = LucideIcons.handshake;
  static const enviar = LucideIcons.send;
  static const entrar = LucideIcons.logIn;
  static const salir = LucideIcons.logOut;
  static const listo = LucideIcons.check;
  static const todoListo = LucideIcons.checkCheck;
  static const reiniciar = LucideIcons.rotateCcw;
  static const ver = LucideIcons.eye;
  static const ocultar = LucideIcons.eyeOff;
  static const avanzarFlecha = LucideIcons.arrowRight;
  static const plegar = LucideIcons.chevronsLeft;
  static const desplegar = LucideIcons.chevronsRight;
  static const linterna = LucideIcons.flashlight;
  static const enEsteAparato = LucideIcons.smartphone;
  static const agregarPersona = LucideIcons.userPlus;
  static const buscarPersona = LucideIcons.userSearch;
  static const cambiarFecha = LucideIcons.calendarCog;

  // Estados, conteos y avisos
  static const conteo = LucideIcons.hash;
  static const pin = LucideIcons.squareAsterisk;
  static const contrasena = LucideIcons.keyRound;
  static const conContrasena = LucideIcons.shieldCheck;
  static const categoria = LucideIcons.tag;
  static const energia = LucideIcons.zap;
  static const alarma = LucideIcons.alarmClock;
  static const fecha = LucideIcons.calendar;
  static const periodo = LucideIcons.calendarRange;
  static const vence = LucideIcons.calendarX;
  static const enEspera = LucideIcons.hourglass;
  static const enCurso = LucideIcons.listTodo;
  static const sinMarcar = LucideIcons.circle;
  static const bloqueado = LucideIcons.ban;
  static const abierto = LucideIcons.lockOpen;
  static const perdida = LucideIcons.packageX;
  static const noDisponible = LucideIcons.circleMinus;
  static const imagenRota = LucideIcons.imageOff;
  static const sinUbicacion = LucideIcons.mapPinOff;
  static const personaInactiva = LucideIcons.userX;
  static const sinCoincidencias = LucideIcons.searchX;
  static const correo = LucideIcons.mail;
  static const correoLeido = LucideIcons.mailCheck;
  static const correoSinLeer = LucideIcons.mailOpen;
  static const avisoActivo = LucideIcons.bellRing;
  static const problemaSincronia = LucideIcons.refreshCwOff;
  static const carrito = LucideIcons.shoppingBasket;
  static const historial = LucideIcons.history;

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
