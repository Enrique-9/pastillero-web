import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/pastillero_ble.dart';

class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key});

  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  static const _azul = Color(0xFF17324D);
  static const _verde = Color(0xFF168C80);
  static const _fondo = Color(0xFFF3F7F6);
  final ble = PastilleroBle();
  final pin = TextEditingController();
  Map<String, dynamic> lista = {};
  Map<String, dynamic> eventos = {};
  int revision = 0;
  bool trabajando = false;
  String mensaje = 'Busca tu pastillero y escribe el PIN de su pantalla.';
  Timer? temporizador;
  late final Future<void> historialInicial;
  static const _claveHistorial = 'pastillero_historial_ble_v1';

  FirebaseDatabase get database => FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://pastillero-digital-8ad62-default-rtdb.firebaseio.com',
  );

  @override
  void initState() {
    super.initState();
    ble.addListener(_cambio);
    historialInicial = _cargarHistorial();
    temporizador = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (trabajando || ble.ocupado || !ble.conectado) return;
      try {
        await ble.actualizarEstado();
      } catch (_) {}
    });
  }

  void _cambio() {
    if (mounted) setState(() {});
  }

  Future<void> _cargarHistorial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardado = prefs.getString(_claveHistorial);
      if (guardado != null)
        eventos = Map<String, dynamic>.from(jsonDecode(guardado) as Map);
    } catch (_) {
      mensaje =
          'No se pudo leer el historial del teléfono; se conserva en el pastillero.';
    }
    _cambio();
  }

  Future<void> _guardarHistorial() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_claveHistorial, jsonEncode(eventos))) {
      throw StateError('No se pudo respaldar el historial en este teléfono.');
    }
  }

  Future<void> _operar(Future<void> Function() accion) async {
    if (trabajando) return;
    setState(() => trabajando = true);
    try {
      await historialInicial;
      final limite = DateTime.now().add(const Duration(seconds: 95));
      while (ble.ocupado) {
        if (DateTime.now().isAfter(limite)) {
          throw StateError('La conexión está ocupada. Vuelve a conectar.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await accion();
    } catch (e) {
      mensaje = e.toString().replaceFirst('Bad state: ', '');
    } finally {
      if (mounted) setState(() => trabajando = false);
    }
  }

  void _buscarPastillero() {
    if (!kIsWeb) {
      _operar(ble.buscar);
      return;
    }
    // Web Bluetooth necesita abrir el selector desde el toque del usuario.
    // _operar espera el historial antes de buscar y puede perder ese gesto.
    ble.buscar().catchError((Object error) {
      if (mounted) {
        setState(() => mensaje = error.toString().replaceFirst('Bad state: ', ''));
      }
    });
  }

  Future<void> _leerLista() async {
    final respuesta = await ble.comando('get_meds');
    lista = Map<String, dynamic>.from(respuesta['lista'] as Map);
    revision = (respuesta['revision'] as num).toInt();
    await ble.actualizarEstado();
    _cambio();
  }

  Future<void> _guardarCambio(String id, Map<String, dynamic>? valor) async {
    await ble.comando('patch', {
      'revision': revision,
      'cambios': {id: valor},
    });
    await _leerLista();
    mensaje =
        'Aplicado y guardado en el pastillero. Puede funcionar sin conexión.';
  }

  Future<void> _editar([String? id, Map<String, dynamic>? anterior]) async {
    final nuevo = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditorMedicamento(anterior: anterior),
    );
    if (nuevo == null || !mounted) return;
    final clave =
        id ??
        'ble_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0xffffff)}';
    await _operar(() => _guardarCambio(clave, {...nuevo, 'id': clave}));
  }

  Future<bool> _confirmar(String titulo, String contenido) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(titulo),
          content: Text(contenido),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ) ??
      false;

  void _requiereSesion() {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError(
        'Para sincronizar con Firebase, vuelve e inicia sesión. Bluetooth funciona sin iniciar sesión.',
      );
    }
  }

  Future<void> _importarFirebase() async {
    _requiereSesion();
    final valor =
        (await database
                .ref('medicamentos')
                .get()
                .timeout(const Duration(seconds: 12)))
            .value;
    final nube = valor is Map
        ? Map<String, dynamic>.from(valor)
        : <String, dynamic>{};
    if (nube.length > 12)
      throw StateError('El pastillero admite hasta 12 medicamentos.');
    if (!mounted) return;
    if (!await _confirmar(
      'Copiar horarios de Firebase',
      'Sustituirá los ${lista.length} horarios del pastillero por los ${nube.length} de Firebase. '
          'Los cambios locales de horarios se reemplazarán; el historial se conserva.',
    ))
      return;
    final cambios = <String, dynamic>{
      for (final id in lista.keys)
        if (!nube.containsKey(id)) id: null,
      ...nube,
    };
    final resultado = await ble.comando('patch', {
      'revision': revision,
      'cambios': cambios,
    });
    // Es la copia que acabamos de leer de la nube, no una edicion local nueva.
    await ble.comando('cloud_ack', {'revision': resultado['revision']});
    await _leerLista();
    mensaje = 'Horarios de Firebase aplicados y guardados en el pastillero.';
  }

  Future<void> _recibirHistorial() async {
    var despues = '';
    var recibidos = 0;
    while (ble.conectado && recibidos < 250) {
      final respuesta = await ble.comando('next_event', {'after': despues});
      final valor = respuesta['evento'];
      if (valor == null) break;
      final evento = Map<String, dynamic>.from(valor as Map);
      final id = evento['idEvento'].toString();
      final anterior = eventos[id];
      eventos[id] = {
        ...evento,
        '_subido': anterior is Map && anterior['_subido'] == true,
      };
      // Guardar el respaldo antes de avanzar. No borrar todavia del ESP32.
      await _guardarHistorial();
      despues = id;
      recibidos++;
    }
    mensaje =
        '$recibidos registros recibidos. Se conservan en el pastillero hasta llegar a Firebase.';
    await ble.actualizarEstado();
  }

  Future<void> _sincronizarFirebase() async {
    _requiereSesion();
    // Actualizar la revision evita publicar un borrador de una lista anterior.
    final horarios = await ble.comando('get_meds');
    if (horarios['subiendoCambios'] == true) {
      throw StateError(
        'El ESP32 está sincronizando horarios por Wi-Fi. Espera unos segundos y reintenta.',
      );
    }
    final cambios = Map<String, dynamic>.from(horarios['cambios'] as Map);
    if (cambios.isNotEmpty) {
      // PATCH por ID: conserva los medicamentos de la nube que no editamos.
      await database
          .ref('medicamentos')
          .update(cambios)
          .timeout(const Duration(seconds: 12));
      await ble.comando('cloud_ack', {'revision': horarios['revision']});
    }
    await _recibirHistorial();
    var subidos = 0;
    for (final entrada in eventos.entries.toList()) {
      final evento = Map<String, dynamic>.from(entrada.value as Map);
      if (evento['_subido'] != true) {
        final datos = Map<String, dynamic>.from(evento)..remove('_subido');
        datos['sincronizadoEn'] = ServerValue.timestamp;
        // set sobre la misma ID: los reintentos no crean duplicados.
        await database
            .ref('historial/${entrada.key}')
            .set(datos)
            .timeout(const Duration(seconds: 12));
        evento['_subido'] = true;
        eventos[entrada.key] = evento;
        await _guardarHistorial();
        subidos++;
      }
      // Solo se envía este acuse DESPUES de la confirmacion de Firebase.
      await ble.comando('ack_event', {'id': entrada.key});
    }
    await _leerLista();
    mensaje =
        'Sincronizado con Firebase: $subidos registros nuevos. '
        'Pendientes en el pastillero: ${ble.estado['historialPendiente'] ?? '?'}.';
  }

  Future<void> _ajustarHora() async {
    await ble.comando('set_time', {
      'utc': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    });
    await ble.actualizarEstado();
    mensaje = 'Hora ajustada a Monterrey (UTC−6).';
  }

  Future<void> _confirmarToma() async {
    await ble.comando('confirm', {'clave': ble.estado['claveAlarma']});
    await ble.actualizarEstado();
    mensaje = 'Toma confirmada en el pastillero.';
  }

  @override
  void dispose() {
    temporizador?.cancel();
    ble.removeListener(_cambio);
    ble.dispose();
    pin.dispose();
    super.dispose();
  }

  Widget _seccion(String titulo, {Widget? accion}) => Row(
    children: [
      Expanded(
        child: Text(
          titulo,
          style: const TextStyle(
            color: _azul,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      if (accion != null) accion,
    ],
  );

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE4ECEB)),
    ),
    child: child,
  );

  Widget _etiqueta(IconData icono, String texto) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0x22FFFFFF),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, color: Colors.white, size: 15),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    ),
  );

  Widget _encabezado() {
    final conectado = ble.conectado;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _azul,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0x22FFFFFF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  conectado ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conectado ? 'Pastillero conectado' : 'Conecta tu pastillero',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      conectado
                          ? ble.nombre
                          : 'Envía horarios y consulta tus tomas por Bluetooth.',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (conectado) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _etiqueta(Icons.bluetooth, 'Bluetooth activo'),
                _etiqueta(
                  ble.estado['wifi'] == true ? Icons.wifi : Icons.wifi_off,
                  ble.estado['wifi'] == true ? 'Wi-Fi conectado' : 'Modo local',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _aviso() => _panel(
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: _verde, size: 21),
        const SizedBox(width: 11),
        Expanded(child: Text(mensaje, style: const TextStyle(color: _azul))),
      ],
    ),
  );

  Widget _conexion() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Vincular dispositivo',
          style: TextStyle(color: _azul, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        const SizedBox(height: 6),
        const Text(
          'Escribe el PIN de seis dígitos que aparece en la pantalla del pastillero.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: pin,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'PIN del pastillero',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 4),
        FilledButton.icon(
          onPressed: trabajando || ble.buscando ? null : _buscarPastillero,
          icon: const Icon(Icons.bluetooth_searching),
          label: Text(ble.buscando ? 'Buscando…' : 'Buscar pastillero'),
        ),
        if (ble.dispositivos.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('DISPOSITIVOS CERCANOS',
              style: TextStyle(color: Colors.black54, fontSize: 12,
                  fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          for (final dispositivo in ble.dispositivos.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFDDF5EE),
                child: Icon(Icons.bluetooth, color: _verde),
              ),
              title: Text(dispositivo.name ?? 'Pastillero'),
              trailing: const Icon(Icons.chevron_right),
              onTap: trabajando ? null : () => _operar(() async {
                if (!RegExp(r'^\d{6}$').hasMatch(pin.text.trim())) {
                  throw StateError('Escribe los seis números del PIN.');
                }
                await ble.conectar(dispositivo, pin.text.trim());
                pin.clear();
                await _leerLista();
                mensaje = 'Conectado. Revisa tus horarios y la hora del pastillero.';
              }),
            ),
        ],
      ],
    ),
  );

  Widget _medicamento(String id, Map<String, dynamic> m, bool habilitado) {
    final activo = m['activo'] != false;
    final hora = m['horaInicio'] ?? m['hora'] ?? '--:--';
    final frecuencia = m['tipoHorario'] == 'intervalo'
        ? 'Cada ${m['intervaloHoras']} h desde $hora'
        : 'A las $hora';
    final dias = (m['dias'] as List?)?.join(', ') ?? 'Sin días';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _panel(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: activo
                  ? const Color(0xFFDDF5EE) : const Color(0xFFECEFF1),
              child: Icon(activo ? Icons.medication : Icons.pause,
                  color: activo ? _verde : Colors.grey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m['nombre']?.toString() ?? 'Sin nombre',
                      style: const TextStyle(color: _azul, fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(m['dosis']?.toString() ?? 'Sin dosis',
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 9),
                  Text(frecuencia,
                      style: const TextStyle(color: _azul,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('$dias · ${activo ? 'Activo' : 'Pausado'}',
                      style: const TextStyle(color: Colors.black54,
                          fontSize: 12)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Opciones del medicamento',
              enabled: habilitado,
              onSelected: (accion) async {
                if (accion == 'editar') await _editar(id, m);
                if (accion == 'pausar') {
                  await _operar(() => _guardarCambio(id, {
                    ...m, 'activo': !activo,
                  }));
                }
                if (accion == 'borrar' &&
                    await _confirmar('Eliminar medicamento',
                      'Se eliminará ${m['nombre']} del pastillero. El cambio quedará pendiente de sincronizar.')) {
                  await _operar(() => _guardarCambio(id, null));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'editar', child: Text('Editar')),
                PopupMenuItem(value: 'pausar',
                    child: Text(activo ? 'Pausar' : 'Activar')),
                const PopupMenuItem(value: 'borrar', child: Text('Eliminar')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _herramientas(bool habilitado, String reloj) => _panel(
    ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      leading: const Icon(Icons.tune, color: _verde),
      title: const Text('Herramientas del pastillero'),
      subtitle: const Text('Hora, lectura manual y opciones de sincronización'),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: const Text('Hora del pastillero'),
          subtitle: Text(reloj),
          trailing: TextButton(
            onPressed: habilitado ? () => _operar(_ajustarHora) : null,
            child: const Text('Ajustar'),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.refresh),
          title: const Text('Actualizar horarios'),
          onTap: habilitado ? () => _operar(_leerLista) : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.download_outlined),
          title: const Text('Recibir historial por Bluetooth'),
          onTap: habilitado ? () => _operar(_recibirHistorial) : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_download_outlined),
          title: const Text('Copiar horarios desde Firebase'),
          subtitle: const Text('Reemplaza los horarios locales; pide confirmación'),
          onTap: habilitado && FirebaseAuth.instance.currentUser != null
              ? () => _operar(_importarFirebase) : null,
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bluetooth_disabled),
          title: const Text('Desconectar Bluetooth'),
          onTap: habilitado ? () => _operar(ble.desconectar) : null,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final habilitado = ble.conectado && !trabajando && !ble.ocupado;
    final conSesion = FirebaseAuth.instance.currentUser != null;
    final historial = eventos.values.whereType<Map>().toList()
      ..sort((a, b) => ((b['registradoEn'] as num?) ?? 0)
          .compareTo((a['registradoEn'] as num?) ?? 0));
    final utc = ble.estado['rtcUtc'];
    final reloj = utc is num
        ? DateTime.fromMillisecondsSinceEpoch(utc.toInt() * 1000, isUtc: true)
            .subtract(const Duration(hours: 6)).toString().substring(0, 19)
        : 'Aún no se ha consultado';
    final cambios = ble.estado['cambiosPendientes'] ?? 0;
    final pendientes = ble.estado['historialPendiente'] ?? 0;

    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(title: const Text('Mi pastillero'), backgroundColor: _fondo),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
              children: [
                _encabezado(),
                if (trabajando) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (mensaje != 'Busca tu pastillero y escribe el PIN de su pantalla.') ...[
                  const SizedBox(height: 14),
                  _aviso(),
                ],
                const SizedBox(height: 18),
                if (!ble.conectado) ...[
                  _conexion(),
                  const SizedBox(height: 12),
                  const Text('Los horarios guardados siguen funcionando aunque el celular se desconecte.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 12)),
                ] else ...[
                  if (ble.estado['alarma'] == true) ...[
                    _panel(Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Es hora de una toma',
                            style: TextStyle(color: _azul, fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: habilitado ? () => _operar(_confirmarToma) : null,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Confirmar toma actual'),
                        ),
                      ],
                    )),
                    const SizedBox(height: 18),
                  ],
                  if (ble.estado['almacenamiento'] != true ||
                      ble.estado['errorHistorial'] == true) ...[
                    _panel(const Row(children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
                      SizedBox(width: 10),
                      Expanded(child: Text('Revisa el almacenamiento del pastillero antes de apagarlo.')),
                    ])),
                    const SizedBox(height: 18),
                  ],
                  _seccion('Medicamentos',
                    accion: Text('${lista.length}/12',
                        style: const TextStyle(color: Colors.black54))),
                  const SizedBox(height: 10),
                  if (lista.isEmpty)
                    _panel(const Column(children: [
                      Icon(Icons.medication_outlined, size: 34, color: _verde),
                      SizedBox(height: 9),
                      Text('Aún no hay horarios en el pastillero',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _azul, fontWeight: FontWeight.bold)),
                      SizedBox(height: 5),
                      Text('Agrega un medicamento para empezar.',
                          style: TextStyle(color: Colors.black54)),
                    ]))
                  else
                    for (final entrada in lista.entries)
                      _medicamento(entrada.key,
                          Map<String, dynamic>.from(entrada.value as Map), habilitado),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: habilitado && lista.length < 12 ? _editar : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar medicamento'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _seccion('Sincronización'),
                  const SizedBox(height: 10),
                  _panel(Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Los horarios y las tomas se guardan en el pastillero. La nube muestra los datos de la última sincronización.',
                          style: TextStyle(color: Colors.black54)),
                      if (cambios != 0 || pendientes != 0) ...[
                        const SizedBox(height: 10),
                        Text('$cambios cambio(s) de horarios · $pendientes toma(s) pendientes',
                            style: const TextStyle(color: _azul,
                                fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: habilitado && conSesion
                            ? () => _operar(_sincronizarFirebase) : null,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sincronizar ahora'),
                      ),
                      if (!conSesion) ...[
                        const SizedBox(height: 6),
                        const Text('Inicia sesión para enviar datos a Firebase. Bluetooth funciona sin sesión.',
                            style: TextStyle(color: Colors.black54, fontSize: 12)),
                      ],
                    ],
                  )),
                  const SizedBox(height: 14),
                  _herramientas(habilitado, reloj),
                  if (historial.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _panel(ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('Tomas recibidas (${historial.length})'),
                      leading: const Icon(Icons.history, color: _verde),
                      children: [
                        for (final evento in historial.take(50))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${evento['nombre']} · ${evento['estado']}'),
                            subtitle: Text('${evento['fechaRtc']} · ${evento['dosis']}'),
                            trailing: Icon(evento['_subido'] == true
                                ? Icons.cloud_done : Icons.cloud_upload_outlined),
                          ),
                      ],
                    )),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _EditorMedicamento extends StatefulWidget {
  const _EditorMedicamento({this.anterior});
  final Map<String, dynamic>? anterior;

  @override
  State<_EditorMedicamento> createState() => _EditorMedicamentoState();
}

class _EditorMedicamentoState extends State<_EditorMedicamento> {
  final formulario = GlobalKey<FormState>();
  late TextEditingController nombre;
  late TextEditingController dosis;
  late TimeOfDay hora;
  late TimeOfDay fin;
  late int intervalo;
  late bool madrugada;
  late Set<String> dias;
  static const diasOrden = ['L', 'M', 'Mi', 'J', 'V', 'S', 'D'];

  TimeOfDay _hora(String valor, int defecto) {
    final partes = valor.split(':');
    return TimeOfDay(
      hour: int.tryParse(partes.first) ?? defecto,
      minute: partes.length > 1 ? int.tryParse(partes[1]) ?? 0 : 0,
    );
  }

  @override
  void initState() {
    super.initState();
    final m = widget.anterior ?? {};
    nombre = TextEditingController(text: m['nombre']?.toString() ?? '');
    dosis = TextEditingController(text: m['dosis']?.toString() ?? '');
    hora = _hora((m['horaInicio'] ?? m['hora'] ?? '08:00').toString(), 8);
    fin = _hora((m['horaFin'] ?? '22:00').toString(), 22);
    intervalo = m['tipoHorario'] == 'intervalo'
        ? (m['intervaloHoras'] as num).toInt()
        : 0;
    madrugada = m['incluirMadrugada'] != false;
    dias = ((m['dias'] as List?) ?? diasOrden).map((d) => d.toString()).toSet();
  }

  String _textoHora(TimeOfDay h) =>
      '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    nombre.dispose();
    dosis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.anterior == null ? 'Nuevo medicamento' : 'Editar medicamento',
    ),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Form(
          key: formulario,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nombre,
                maxLength: 50,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Escribe el nombre' : null,
              ),
              TextFormField(
                controller: dosis,
                maxLength: 50,
                decoration: const InputDecoration(labelText: 'Dosis'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Escribe la dosis' : null,
              ),
              DropdownButtonFormField<int>(
                value: intervalo,
                decoration: const InputDecoration(labelText: 'Frecuencia'),
                items: [0, 4, 6, 8, 12, 24]
                    .map(
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(i == 0 ? 'Una hora fija' : 'Cada $i horas'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => intervalo = v ?? 0),
              ),
              ListTile(
                title: Text('Hora inicial: ${hora.format(context)}'),
                trailing: const Icon(Icons.schedule),
                onTap: () async {
                  final elegida = await showTimePicker(
                    context: context,
                    initialTime: hora,
                  );
                  if (elegida != null && mounted)
                    setState(() => hora = elegida);
                },
              ),
              if (intervalo > 0) ...[
                CheckboxListTile(
                  title: const Text('Incluir tomas durante la madrugada'),
                  value: madrugada,
                  onChanged: (v) => setState(() => madrugada = v ?? true),
                ),
                if (!madrugada)
                  ListTile(
                    title: Text('Última hora del día: ${fin.format(context)}'),
                    onTap: () async {
                      final elegida = await showTimePicker(
                        context: context,
                        initialTime: fin,
                      );
                      if (elegida != null && mounted)
                        setState(() => fin = elegida);
                    },
                  ),
              ],
              const Text('Días del horario'),
              Wrap(
                spacing: 5,
                children: diasOrden
                    .map(
                      (d) => FilterChip(
                        label: Text(d),
                        selected: dias.contains(d),
                        onSelected: (activo) => setState(() {
                          if (activo)
                            dias.add(d);
                          else
                            dias.remove(d);
                        }),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!formulario.currentState!.validate() || dias.isEmpty) {
            if (dias.isEmpty)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selecciona al menos un día.')),
              );
            return;
          }
          Navigator.pop(context, <String, dynamic>{
            ...?widget.anterior,
            'nombre': nombre.text.trim(),
            'dosis': dosis.text.trim(),
            'hora': _textoHora(hora),
            'horaInicio': _textoHora(hora),
            'tipoHorario': intervalo == 0 ? 'fijo' : 'intervalo',
            'intervaloHoras': intervalo,
            'incluirMadrugada': madrugada,
            'horaFin': _textoHora(fin),
            'dias': diasOrden.where(dias.contains).toList(),
            'activo': widget.anterior?['activo'] ?? true,
            'actualizadoEn': DateTime.now().toUtc().millisecondsSinceEpoch,
          });
        },
        child: const Text('Enviar al pastillero'),
      ),
    ],
  );
}
