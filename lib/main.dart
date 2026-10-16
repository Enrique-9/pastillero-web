import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'horario_medicamento.dart';
import 'screens/ajustes_page.dart';
import 'screens/bluetooth_page.dart';
import 'screens/auth_page.dart';
import 'screens/historial_page.dart';
import 'screens/medicinas_page.dart';
import 'screens/nuevo_medicamento_page.dart';
import 'screens/vincular_pastillero_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const PastilleroApp());
}

class PastilleroApp extends StatelessWidget {
  const PastilleroApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mi Pastillero',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF168C80)),
        scaffoldBackgroundColor: const Color(0xFFF3F7F6),
      ),
      home: const _PuertaDeAcceso(),
    );
  }
}

class _PuertaDeAcceso extends StatelessWidget {
  const _PuertaDeAcceso();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BluetoothPage()),
                    ),
                    icon: const Icon(Icons.bluetooth),
                    label: const Text('Usar por Bluetooth'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Sin sesión disponible. Puedes usar Bluetooth.'),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BluetoothPage()),
                    ),
                    icon: const Icon(Icons.bluetooth),
                    label: const Text('Usar por Bluetooth'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.data == null) {
          return Stack(
            children: [
              const AuthPage(),
              Positioned(
                right: 16,
                bottom: 24,
                child: FloatingActionButton.extended(
                  heroTag: 'bluetooth_sin_sesion',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BluetoothPage()),
                  ),
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Usar por Bluetooth'),
                ),
              ),
            ],
          );
        }
        final user = snapshot.data!;
        final database = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: 'https://pastillero-digital-8ad62-default-rtdb.firebaseio.com',
        );
        return StreamBuilder<DatabaseEvent>(
          stream: database.ref('config/ownerUid').onValue,
          builder: (context, vinculo) {
            if (vinculo.hasError) {
              return const Scaffold(body: Center(child: Text(
                'No se pudo comprobar la vinculacion. Revisa Internet y las reglas de Firebase.',
              )));
            }
            if (!vinculo.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final owner = vinculo.data!.snapshot.value?.toString();
            if (owner == user.uid) return const InicioPage();
            return VincularPastilleroPage(
              usuarioUid: user.uid,
              yaVinculado: owner != null,
            );
          },
        );
      },
    );
  }
}

class InicioPage extends StatefulWidget {
  const InicioPage({super.key});
  @override
  State<InicioPage> createState() => _InicioPageState();
}

class _InicioPageState extends State<InicioPage> {
  int paginaSeleccionada = 0;
  late final DatabaseReference medicamentosRef;
  late final DatabaseReference dispositivoRef;
  Timer? temporizadorEstado;
  @override
  void initState() {
    super.initState();
    final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://pastillero-digital-8ad62-default-rtdb.firebaseio.com',
    );
    medicamentosRef = database.ref('medicamentos');
    dispositivoRef = database.ref('dispositivo');
    temporizadorEstado = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    temporizadorEstado?.cancel();
    super.dispose();
  }

  void mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> abrirMedicinas() async {
    setState(() {
      paginaSeleccionada = 1;
    });
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MedicinasPage()),
    );
    if (mounted) {
      setState(() {
        paginaSeleccionada = 0;
      });
    }
  }

  Future<void> abrirHistorial() async {
    setState(() {
      paginaSeleccionada = 2;
    });
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HistorialPage()),
    );
    if (mounted) {
      setState(() {
        paginaSeleccionada = 0;
      });
    }
  }

  Future<void> abrirAjustes() async {
    setState(() {
      paginaSeleccionada = 3;
    });
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AjustesPage()),
    );
    if (mounted) {
      setState(() {
        paginaSeleccionada = 0;
      });
    }
  }

  Future<void> abrirNuevoMedicamento() async {
    final medicamento = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const NuevoMedicamentoPage()),
    );
    if (!mounted || medicamento == null) return;
    try {
      final referencia = medicamentosRef.push();
      await referencia.set({
        ...medicamento,
        'id': referencia.key,
        'creadoEn': ServerValue.timestamp,
      });
      if (!mounted) return;
      mostrarMensaje('${medicamento['nombre']} guardado correctamente');
    } catch (error) {
      if (!mounted) return;
      mostrarMensaje('No se pudo guardar el medicamento: $error');
    }
  }

  List<Map<String, dynamic>> _obtenerMedicamentos(DataSnapshot snapshot) {
    final valor = snapshot.value;
    if (valor is! Map) return [];
    final medicamentos = <Map<String, dynamic>>[];
    for (final entrada in valor.entries) {
      if (entrada.value is Map) {
        final medicamento = Map<String, dynamic>.from(entrada.value as Map);
        medicamento['id'] ??= entrada.key.toString();
        medicamentos.add(medicamento);
      }
    }
    medicamentos.sort((a, b) {
      final horasA = minutosProgramados(a);
      final horasB = minutosProgramados(b);
      final primeraA = horasA.isEmpty ? 1440 : horasA.first;
      final primeraB = horasB.isEmpty ? 1440 : horasB.first;
      return primeraA.compareTo(primeraB);
    });
    return medicamentos;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: medicamentosRef.onValue,
      builder: (context, snapshot) {
        final medicamentos = snapshot.hasData
            ? _obtenerMedicamentos(snapshot.data!.snapshot)
            : <Map<String, dynamic>>[];
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _encabezado(),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BluetoothPage(),
                        ),
                      ),
                      icon: const Icon(Icons.bluetooth),
                      label: const Text('Conectar pastillero por Bluetooth'),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Próxima toma',
                      style: TextStyle(
                        color: Color(0xFF17324D),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _tarjetaProximaToma(medicamentos),
                    const SizedBox(height: 26),
                    _accionesRapidas(),
                    const SizedBox(height: 28),
                    const Text(
                      'Resumen de medicamentos',
                      style: TextStyle(
                        color: Color(0xFF17324D),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (snapshot.hasError)
                      _mensajeError('No se pudieron cargar los medicamentos')
                    else ...[
                      ..._tarjetasMedicamentos(medicamentos.take(3).toList()),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: abrirMedicinas,
                        icon: const Icon(Icons.medication_outlined),
                        label: const Text('Administrar medicinas'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: NavigationBar(
                selectedIndex: paginaSeleccionada,
                onDestinationSelected: (indice) {
                  if (indice == 0) return;
                  if (indice == 1) abrirMedicinas();
                  if (indice == 2) abrirHistorial();
                  if (indice == 3) abrirAjustes();
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Inicio',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.medication_outlined),
                    selectedIcon: Icon(Icons.medication),
                    label: 'Medicinas',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history),
                    label: 'Historial',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Ajustes',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _encabezado() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 25,
          backgroundColor: Color(0xFF168C80),
          child: Icon(Icons.medication_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mi Pastillero',
                style: TextStyle(
                  color: Color(0xFF17324D),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Control de medicamentos',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
        _indicadorConexion(),
      ],
    );
  }

  Widget _indicadorConexion() {
    return StreamBuilder<DatabaseEvent>(
      stream: dispositivoRef.onValue,
      builder: (context, snapshot) {
        var texto = 'Verificando';
        var colorTexto = const Color(0xFF607D8B);
        var colorFondo = const Color(0xFFECEFF1);
        final valor = snapshot.data?.snapshot.value;
        if (snapshot.hasError) {
          texto = 'Sin conexión';
          colorTexto = const Color(0xFFB3261E);
          colorFondo = const Color(0xFFFDE8E7);
        } else if (valor is Map) {
          final ultimaConexionValor = valor['ultimaConexion'];
          final reportadoComoConectado = valor['conectado'] == true;
          final ultimaConexion = ultimaConexionValor is num
              ? ultimaConexionValor.toInt()
              : 0;
          final diferencia =
              DateTime.now().millisecondsSinceEpoch - ultimaConexion;
          final conectado =
              reportadoComoConectado &&
              ultimaConexion > 0 &&
              diferencia >= -5000 &&
              diferencia <= 90000;
          if (conectado) {
            texto = 'En línea';
            colorTexto = const Color(0xFF137052);
            colorFondo = const Color(0xFFDDF5EE);
          } else {
            texto = 'Desconectado';
            colorTexto = const Color(0xFFB3261E);
            colorFondo = const Color(0xFFFDE8E7);
          }
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorFondo,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, color: colorTexto, size: 10),
              const SizedBox(width: 6),
              Text(
                texto,
                style: TextStyle(
                  color: colorTexto,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tarjetaProximaToma(List<Map<String, dynamic>> medicamentos) {
    final proximas = buscarProximasTomas(medicamentos);
    if (proximas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF17324D), Color(0xFF168C80)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.event_available, color: Colors.white70),
            SizedBox(height: 16),
            Text(
              'Sin tomas programadas',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Agrega un medicamento para comenzar',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    final proxima = proximas.first;
    final medicamento = proxima.medicamento;
    final nombre = medicamento['nombre']?.toString() ?? 'Sin nombre';
    final dosis = medicamento['dosis']?.toString() ?? 'Sin dosis';
    final hora = TimeOfDay.fromDateTime(proxima.fecha).format(context);
    final hayVarias = proximas.length > 1;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17324D), Color(0xFF168C80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3317324D),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alarm, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                etiquetaDiaToma(context, proxima.fecha),
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const Spacer(),
              Text(
                tiempoRestante(proxima),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            hora,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          if (!hayVarias) ...[
            Text(
              '$nombre · $dosis',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              resumenHorario(context, medicamento),
              style: const TextStyle(color: Colors.white70),
            ),
          ] else ...[
            Text(
              '${proximas.length} medicamentos a esta hora',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...proximas.map((toma) {
              final item = toma.medicamento;
              final itemNombre = item['nombre']?.toString() ?? 'Sin nombre';
              final itemDosis = item['dosis']?.toString() ?? 'Sin dosis';
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.medication_outlined,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '$itemNombre · $itemDosis',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              mostrarMensaje(
                hayVarias
                    ? 'Las ${proximas.length} tomas se confirmarán juntas desde el pastillero'
                    : 'Esta toma se confirmará desde el pastillero',
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF17324D),
            ),
            icon: const Icon(Icons.info_outline),
            label: Text(hayVarias ? 'Ver medicamentos' : 'Ver detalles'),
          ),
        ],
      ),
    );
  }

  Widget _accionesRapidas() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: abrirNuevoMedicamento,
            icon: const Icon(Icons.add),
            label: const Text('Agregar'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: abrirHistorial,
            icon: const Icon(Icons.history),
            label: const Text('Historial'),
          ),
        ),
      ],
    );
  }

  List<Widget> _tarjetasMedicamentos(List<Map<String, dynamic>> medicamentos) {
    if (medicamentos.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            children: [
              Icon(Icons.medication_outlined, size: 42, color: Colors.black38),
              SizedBox(height: 10),
              Text(
                'Todavía no hay medicamentos guardados',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ];
    }
    return medicamentos.map((medicamento) {
      final activo = medicamento['activo'] != false;
      return Card(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: CircleAvatar(
            backgroundColor: activo
                ? const Color(0xFFDDF5EE)
                : const Color(0xFFECEFF1),
            child: Icon(
              activo ? Icons.schedule : Icons.pause,
              color: activo ? const Color(0xFF168C80) : Colors.grey,
            ),
          ),
          title: Text(
            medicamento['nombre']?.toString() ?? 'Sin nombre',
            style: const TextStyle(
              color: Color(0xFF17324D),
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            '${medicamento['dosis'] ?? 'Sin dosis'} · '
            '${resumenHorario(context, medicamento)}',
          ),
          trailing: Text(
            activo ? 'Activa' : 'Pausada',
            style: TextStyle(
              color: activo ? const Color(0xFF137052) : Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: abrirMedicinas,
        ),
      );
    }).toList();
  }

  Widget _mensajeError(String mensaje) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9E9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje)),
        ],
      ),
    );
  }
}
