import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';

/// Protocolo del firmware incluido: JSON UTF-8 por lineas, fragmentos de 20 B.
/// Una solicitud en vuelo. Un timeout desconecta para descartar tramas parciales.
class PastilleroBle extends ChangeNotifier {
  static const servicio = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const entrada = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const salida = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  final dispositivos = <String, BleDevice>{};
  final _bytes = <int>[];
  StreamSubscription<BleDevice>? _escaneo;
  StreamSubscription<bool>? _conexion;
  StreamSubscription<Uint8List>? _valores;
  Timer? _finEscaneo;
  Completer<Map<String, dynamic>>? _respuesta;
  int _numero = 0;
  int _solicitudActual = 0;
  bool _cerrado = false;
  bool conectado = false;
  bool buscando = false;
  String? dispositivoId;
  String nombre = '';
  Map<String, dynamic> estado = {};

  bool get ocupado => _respuesta != null;

  void _avisar() {
    if (!_cerrado) notifyListeners();
  }

  Future<void> buscar() async {
    if (conectado || buscando) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final info = await DeviceInfoPlugin().androidInfo;
      final permisos = info.version.sdkInt >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.locationWhenInUse];
      final resultado = await permisos.request();
      if (resultado.values.any((p) => !p.isGranted)) {
        throw StateError('Autoriza los permisos de Bluetooth para buscar.');
      }
    }
    dispositivos.clear();
    final escaneoAnterior = _escaneo;
    if (escaneoAnterior != null) {
      // En web, el selector BLE debe abrirse durante el gesto del botón.
      // Esperar una cancelación antes de startScan puede perder ese gesto.
      if (kIsWeb) {
        unawaited(escaneoAnterior.cancel());
      } else {
        await escaneoAnterior.cancel();
      }
    }
    _escaneo = UniversalBle.scanStream.listen((d) {
      dispositivos[d.deviceId] = d;
      _avisar();
    });
    buscando = true;
    _avisar();
    try {
      // En Chrome abre el selector de dispositivos desde este gesto del usuario.
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: [servicio]),
      );
      _finEscaneo?.cancel();
      _finEscaneo = Timer(const Duration(seconds: 20), () {
        detenerBusqueda().catchError((Object _) {});
      });
    } catch (_) {
      buscando = false;
      _avisar();
      rethrow;
    }
  }

  Future<void> detenerBusqueda() async {
    _finEscaneo?.cancel();
    if (buscando) {
      buscando = false;
      await UniversalBle.stopScan();
      _avisar();
    }
  }

  Future<void> conectar(BleDevice d, String pin) async {
    await detenerBusqueda();
    await desconectar();
    dispositivoId = d.deviceId;
    nombre = d.name ?? 'Pastillero';
    _conexion = UniversalBle.connectionStream(d.deviceId).listen((valor) {
      if (!valor) {
        conectado = false;
        _bytes.clear();
        if (_respuesta != null && !_respuesta!.isCompleted) {
          _respuesta!.completeError(StateError('El pastillero se desconectó.'));
        }
        _avisar();
      }
    });
    try {
      await UniversalBle.connect(d.deviceId);
      final servicios = await UniversalBle.discoverServices(d.deviceId);
      final existe = servicios.any((s) => s.uuid.toLowerCase() == servicio);
      if (!existe)
        throw StateError('Este dispositivo no tiene el firmware BLE.');
      _valores = UniversalBle.characteristicValueStream(
        d.deviceId,
        salida,
      ).listen(_recibir);
      await UniversalBle.subscribeNotifications(d.deviceId, servicio, salida);
      conectado = true;
      estado = await comando('hello', {'pin': pin});
      _avisar();
    } catch (_) {
      await desconectar();
      rethrow;
    }
  }

  void _recibir(Uint8List valor) {
    for (final byte in valor) {
      if (byte == 10) {
        final trama = List<int>.from(_bytes);
        _bytes.clear();
        try {
          final mensaje = Map<String, dynamic>.from(
            jsonDecode(utf8.decode(trama)) as Map,
          );
          if (mensaje['request'] == _solicitudActual &&
              _respuesta != null &&
              !_respuesta!.isCompleted) {
            _respuesta!.complete(mensaje);
          }
        } catch (_) {
          // Una trama incompleta nunca se interpreta como un acuse de guardado.
        }
      } else {
        _bytes.add(byte);
        if (_bytes.length > 32768) _bytes.clear();
      }
    }
  }

  Future<Map<String, dynamic>> comando(
    String cmd, [
    Map<String, dynamic> datos = const {},
  ]) async {
    final id = dispositivoId;
    if (!conectado || id == null)
      throw StateError('Conecta primero el pastillero.');
    if (ocupado) throw StateError('Espera a que termine la operación actual.');
    _solicitudActual = ++_numero;
    final pendiente = Completer<Map<String, dynamic>>();
    _respuesta = pendiente;
    // Instala el timeout antes de enviar para manejar una desconexion durante TX.
    final espera = pendiente.future.timeout(const Duration(seconds: 90));
    // Evita errores asincronos sin consumidor si falla una escritura antes de await.
    unawaited(espera.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    final bytes = utf8.encode(
      jsonEncode({...datos, 'cmd': cmd, 'request': _solicitudActual}) + '\n',
    );
    var transferenciaCompleta = false;
    try {
      if (bytes.length > 16384)
        throw StateError('La lista excede el tamaño permitido.');
      for (var inicio = 0; inicio < bytes.length; inicio += 20) {
        final fin = (inicio + 20 < bytes.length) ? inicio + 20 : bytes.length;
        await UniversalBle.write(
          id,
          servicio,
          entrada,
          Uint8List.fromList(bytes.sublist(inicio, fin)),
          withoutResponse: false,
        );
      }
      transferenciaCompleta = true;
      final respuesta = await espera;
      if (respuesta['ok'] != true) {
        throw StateError(
          respuesta['error']?.toString() ??
              'El pastillero rechazó la operación.',
        );
      }
      return respuesta;
    } on TimeoutException {
      await desconectar();
      throw StateError(
        'No llegó el acuse. Vuelve a conectar y lee los horarios antes de reintentar.',
      );
    } catch (_) {
      // Una escritura fallida puede dejar media linea en el ESP32. Reiniciar
      // la conexion evita concatenarla accidentalmente con la siguiente orden.
      if (!transferenciaCompleta) await desconectar();
      rethrow;
    } finally {
      if (!pendiente.isCompleted) {
        pendiente.completeError(StateError('La transferencia se interrumpió.'));
      }
      if (identical(_respuesta, pendiente)) _respuesta = null;
    }
  }

  Future<void> actualizarEstado() async {
    estado = await comando('status');
    _avisar();
  }

  Future<void> desconectar() async {
    final id = dispositivoId;
    conectado = false;
    if (_respuesta != null && !_respuesta!.isCompleted) {
      _respuesta!.completeError(StateError('El pastillero se desconectó.'));
    }
    await _valores?.cancel();
    await _conexion?.cancel();
    _valores = null;
    _conexion = null;
    _bytes.clear();
    if (id != null) {
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
    dispositivoId = null;
    _avisar();
  }

  @override
  void dispose() {
    _cerrado = true;
    _finEscaneo?.cancel();
    unawaited(_escaneo?.cancel());
    unawaited(detenerBusqueda().catchError((Object _) {}));
    unawaited(desconectar());
    super.dispose();
  }
}


