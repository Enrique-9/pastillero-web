import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class HistorialPage extends StatefulWidget {
  final String? medicamentoId;
  final String? nombreMedicamento;

  const HistorialPage({
    super.key,
    this.medicamentoId,
    this.nombreMedicamento,
  });

  @override
  State<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends State<HistorialPage> {
  late final DatabaseReference historialRef;

  bool get muestraUnMedicamento =>
      widget.medicamentoId != null && widget.medicamentoId!.isNotEmpty;

  @override
  void initState() {
    super.initState();

    final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://pastillero-digital-8ad62-default-rtdb.firebaseio.com',
    );

    historialRef = database.ref('historial');
  }

  List<Map<String, dynamic>> obtenerRegistros(
    DataSnapshot snapshot,
  ) {
    final valor = snapshot.value;

    if (valor is! Map) {
      return [];
    }

    final registros = <Map<String, dynamic>>[];

    for (final entrada in valor.entries) {
      if (entrada.value is Map) {
        final registro = Map<String, dynamic>.from(
          entrada.value as Map,
        );

        registro['id'] = entrada.key.toString();

        if (_perteneceAlMedicamento(registro)) {
          registros.add(registro);
        }
      }
    }

    registros.sort((a, b) {
      final fechaA = obtenerMarcaDeTiempo(a);
      final fechaB = obtenerMarcaDeTiempo(b);
      return fechaB.compareTo(fechaA);
    });

    return registros;
  }

  bool _perteneceAlMedicamento(Map<String, dynamic> registro) {
    if (!muestraUnMedicamento) return true;

    final idRegistro = registro['medicamentoId']?.toString() ?? '';

    if (idRegistro.isNotEmpty) {
      return idRegistro == widget.medicamentoId;
    }

    // Compatibilidad con registros creados antes de guardar medicamentoId.
    final nombreRegistro =
        registro['nombre']?.toString().trim().toLowerCase() ?? '';
    final nombreSeleccionado =
        widget.nombreMedicamento?.trim().toLowerCase() ?? '';

    return nombreSeleccionado.isNotEmpty &&
        nombreRegistro == nombreSeleccionado;
  }

  int obtenerMarcaDeTiempo(Map<String, dynamic> registro) {
    final valor = registro['registradoEn'];

    if (valor is int) return valor;
    if (valor is num) return valor.toInt();

    return 0;
  }

  String formatearFecha(Map<String, dynamic> registro) {
    final milisegundos = obtenerMarcaDeTiempo(registro);

    if (milisegundos > 0) {
      final fecha = DateTime.fromMillisecondsSinceEpoch(
        milisegundos,
      ).toLocal();

      final dia = fecha.day.toString().padLeft(2, '0');
      final mes = fecha.month.toString().padLeft(2, '0');
      final anio = fecha.year.toString();

      return '$dia/$mes/$anio';
    }

    final fechaRtc = registro['fechaRtc']?.toString() ?? '';

    if (fechaRtc.length >= 10) {
      return fechaRtc.substring(0, 10);
    }

    return 'Fecha no disponible';
  }

  String formatearHora(Map<String, dynamic> registro) {
    final milisegundos = obtenerMarcaDeTiempo(registro);

    if (milisegundos > 0) {
      final fecha = DateTime.fromMillisecondsSinceEpoch(
        milisegundos,
      ).toLocal();

      final periodo = fecha.hour >= 12 ? 'PM' : 'AM';
      final hora12 = fecha.hour % 12 == 0 ? 12 : fecha.hour % 12;
      final minutos = fecha.minute.toString().padLeft(2, '0');

      return '$hora12:$minutos $periodo';
    }

    final fechaRtc = registro['fechaRtc']?.toString() ?? '';

    if (fechaRtc.length >= 16) {
      return fechaRtc.substring(11, 16);
    }

    return registro['horaProgramada']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.nombreMedicamento ?? 'medicamento';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F6),
      appBar: AppBar(
        title: Text(
          muestraUnMedicamento
              ? 'Historial de $nombre'
              : 'Historial de tomas',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFFF3F7F6),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: StreamBuilder<DatabaseEvent>(
              stream: historialRef.onValue,
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return const _MensajeVacio(
                    icono: Icons.cloud_off,
                    titulo: 'No se pudo cargar el historial',
                    descripcion:
                        'Verifica la conexión e inténtalo nuevamente.',
                  );
                }

                final registros = snapshot.hasData
                    ? obtenerRegistros(snapshot.data!.snapshot)
                    : <Map<String, dynamic>>[];

                if (registros.isEmpty) {
                  return _MensajeVacio(
                    icono: Icons.history,
                    titulo: muestraUnMedicamento
                        ? 'Todavía no hay tomas de $nombre'
                        : 'Todavía no hay tomas registradas',
                    descripcion: muestraUnMedicamento
                        ? 'Las tomas confirmadas u omitidas de $nombre aparecerán aquí.'
                        : 'Las confirmaciones realizadas en el pastillero aparecerán aquí.',
                  );
                }

                final confirmadas = registros
                    .where((registro) =>
                        registro['estado']?.toString() == 'confirmada')
                    .length;
                final omitidas = registros.length - confirmadas;

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _ResumenHistorial(
                      total: registros.length,
                      confirmadas: confirmadas,
                      omitidas: omitidas,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      muestraUnMedicamento
                          ? 'Tomas de $nombre'
                          : 'Registros recientes',
                      style: const TextStyle(
                        color: Color(0xFF17324D),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...registros.map(_tarjetaRegistro),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _tarjetaRegistro(Map<String, dynamic> registro) {
    final estado = registro['estado']?.toString() ?? 'omitida';
    final confirmada = estado == 'confirmada';
    final nombre = registro['nombre']?.toString() ?? 'Medicamento';
    final dosis = registro['dosis']?.toString() ?? 'Sin dosis';
    final horaProgramada =
        registro['horaProgramada']?.toString() ?? 'Sin horario';

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: confirmada
                  ? const Color(0xFFDDF5EE)
                  : const Color(0xFFFFE9CC),
              child: Icon(
                confirmada ? Icons.check : Icons.warning_amber,
                color: confirmada
                    ? const Color(0xFF168C80)
                    : const Color(0xFFE28A20),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: const TextStyle(
                      color: Color(0xFF17324D),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('$dosis · Programada: $horaProgramada'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: confirmada
                          ? const Color(0xFFDDF5EE)
                          : const Color(0xFFFFE9CC),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      confirmada ? 'Confirmada' : 'Omitida',
                      style: TextStyle(
                        color: confirmada
                            ? const Color(0xFF137052)
                            : const Color(0xFFB96700),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatearHora(registro),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  formatearFecha(registro),
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumenHistorial extends StatelessWidget {
  final int total;
  final int confirmadas;
  final int omitidas;

  const _ResumenHistorial({
    required this.total,
    required this.confirmadas,
    required this.omitidas,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17324D), Color(0xFF168C80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen de tomas',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _datoResumen('Total', total, Colors.white),
              _datoResumen(
                'Confirmadas',
                confirmadas,
                const Color(0xFFBFF5DD),
              ),
              _datoResumen(
                'Omitidas',
                omitidas,
                const Color(0xFFFFD39B),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _datoResumen(String texto, int cantidad, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            cantidad.toString(),
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            texto,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MensajeVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;

  const _MensajeVacio({
    required this.icono,
    required this.titulo,
    required this.descripcion,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icono,
              size: 60,
              color: Colors.black26,
            ),
            const SizedBox(height: 18),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF17324D),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              descripcion,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
