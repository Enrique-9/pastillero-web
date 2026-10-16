import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../horario_medicamento.dart';
import 'historial_page.dart';
import 'nuevo_medicamento_page.dart';

class MedicinasPage extends StatefulWidget {
  const MedicinasPage({super.key});

  @override
  State<MedicinasPage> createState() => _MedicinasPageState();
}

class _MedicinasPageState extends State<MedicinasPage> {
  late final DatabaseReference _medicamentosRef;

  @override
  void initState() {
    super.initState();

    final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://pastillero-digital-8ad62-default-rtdb.firebaseio.com',
    );

    _medicamentosRef = database.ref('medicamentos');
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje)),
    );
  }

  Future<void> _agregarMedicamento() async {
    final medicamento = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => const NuevoMedicamentoPage(),
      ),
    );

    if (!mounted || medicamento == null) return;

    try {
      final referencia = _medicamentosRef.push();

      await referencia.set({
        ...medicamento,
        'id': referencia.key,
        'creadoEn': ServerValue.timestamp,
      });

      if (!mounted) return;
      _mostrarMensaje('${medicamento['nombre']} guardado correctamente');
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje('No se pudo guardar el medicamento: $error');
    }
  }

  Future<void> _editarMedicamento(
    Map<String, dynamic> medicamento,
  ) async {
    final id = medicamento['id']?.toString();

    if (id == null || id.isEmpty) {
      _mostrarMensaje('No se encontró el identificador del medicamento');
      return;
    }

    final cambios = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => NuevoMedicamentoPage(
          medicamentoInicial: medicamento,
        ),
      ),
    );

    if (!mounted || cambios == null) return;

    try {
      await _medicamentosRef.child(id).update({
        ...cambios,
        'actualizadoEn': ServerValue.timestamp,
      });

      if (!mounted) return;
      _mostrarMensaje('${cambios['nombre']} actualizado correctamente');
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje('No se pudo actualizar el medicamento: $error');
    }
  }

  Future<void> _abrirHistorialMedicamento(
    Map<String, dynamic> medicamento,
  ) async {
    final id = medicamento['id']?.toString();
    final nombre = medicamento['nombre']?.toString() ?? 'Medicamento';

    if (id == null || id.isEmpty) {
      _mostrarMensaje('No se encontró el identificador del medicamento');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistorialPage(
          medicamentoId: id,
          nombreMedicamento: nombre,
        ),
      ),
    );
  }

  Future<void> _cambiarEstado(
    Map<String, dynamic> medicamento,
    bool nuevoEstado,
  ) async {
    final id = medicamento['id']?.toString();

    if (id == null || id.isEmpty) {
      _mostrarMensaje('No se encontró el identificador del medicamento');
      return;
    }

    try {
      await _medicamentosRef.child(id).update({
        'activo': nuevoEstado,
        'actualizadoEn': ServerValue.timestamp,
      });

      if (!mounted) return;
      _mostrarMensaje(
        nuevoEstado ? 'Alarma activada' : 'Alarma pausada',
      );
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje('No se pudo cambiar el estado: $error');
    }
  }

  Future<void> _eliminarMedicamento(
    Map<String, dynamic> medicamento,
  ) async {
    final id = medicamento['id']?.toString();
    final nombre = medicamento['nombre']?.toString() ?? 'este medicamento';

    if (id == null || id.isEmpty) {
      _mostrarMensaje('No se encontró el identificador del medicamento');
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar medicamento'),
        content: Text(
          '¿Seguro que deseas eliminar $nombre? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (!mounted || confirmar != true) return;

    try {
      await _medicamentosRef.child(id).remove();

      if (!mounted) return;
      _mostrarMensaje('$nombre eliminado');
    } catch (error) {
      if (!mounted) return;
      _mostrarMensaje('No se pudo eliminar el medicamento: $error');
    }
  }

  List<Map<String, dynamic>> _obtenerMedicamentos(
    DataSnapshot snapshot,
  ) {
    final valor = snapshot.value;
    if (valor is! Map) return [];

    final medicamentos = <Map<String, dynamic>>[];

    for (final entrada in valor.entries) {
      if (entrada.value is Map) {
        final medicamento = Map<String, dynamic>.from(
          entrada.value as Map,
        );
        medicamento['id'] ??= entrada.key.toString();
        medicamentos.add(medicamento);
      }
    }

    medicamentos.sort((a, b) {
      final activoA = a['activo'] != false;
      final activoB = b['activo'] != false;

      if (activoA != activoB) return activoA ? -1 : 1;

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
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F6),
      appBar: AppBar(
        title: const Text('Medicinas'),
        backgroundColor: const Color(0xFFF3F7F6),
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _medicamentosRef.onValue,
        builder: (context, snapshot) {
          final medicamentos = snapshot.hasData
              ? _obtenerMedicamentos(snapshot.data!.snapshot)
              : <Map<String, dynamic>>[];
          final activos = medicamentos
              .where((medicamento) => medicamento['activo'] != false)
              .length;

          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  children: [
                    const Text(
                      'Administra los medicamentos',
                      style: TextStyle(
                        color: Color(0xFF17324D),
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Puedes usar una hora fija o programar tomas cada ciertas horas.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    _resumen(
                      total: medicamentos.length,
                      activos: activos,
                      pausados: medicamentos.length - activos,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Tus medicamentos',
                            style: TextStyle(
                              color: Color(0xFF17324D),
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _agregarMedicamento,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (snapshot.connectionState ==
                        ConnectionState.waiting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (snapshot.hasError)
                      _mensajeError()
                    else if (medicamentos.isEmpty)
                      _estadoVacio()
                    else
                      ...medicamentos.map(_tarjetaMedicamento),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregarMedicamento,
        icon: const Icon(Icons.add),
        label: const Text('Nueva medicina'),
      ),
    );
  }

  Widget _resumen({
    required int total,
    required int activos,
    required int pausados,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17324D), Color(0xFF168C80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          _datoResumen('$total', 'Total'),
          _separadorResumen(),
          _datoResumen('$activos', 'Activas'),
          _separadorResumen(),
          _datoResumen('$pausados', 'Pausadas'),
        ],
      ),
    );
  }

  Widget _datoResumen(String cantidad, String etiqueta) {
    return Expanded(
      child: Column(
        children: [
          Text(
            cantidad,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            etiqueta,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _separadorResumen() {
    return Container(width: 1, height: 38, color: Colors.white24);
  }

  Widget _tarjetaMedicamento(Map<String, dynamic> medicamento) {
    final nombre = medicamento['nombre']?.toString() ?? 'Sin nombre';
    final dosis = medicamento['dosis']?.toString() ?? 'Sin dosis';
    final activo = medicamento['activo'] != false;
    final horas = horasFormateadas(context, medicamento);

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: activo
                  ? const Color(0xFFDDF5EE)
                  : const Color(0xFFECEFF1),
              child: Icon(
                activo ? Icons.medication : Icons.pause,
                color: activo ? const Color(0xFF168C80) : Colors.grey,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: const TextStyle(
                      color: Color(0xFF17324D),
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(dosis, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 8),
                  Text(
                    descripcionHorario(context, medicamento),
                    style: const TextStyle(
                      color: Color(0xFF17324D),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  _etiqueta(
                    Icons.calendar_today_outlined,
                    textoDiasMedicamento(medicamento['dias']),
                  ),
                  if (horas.length > 1) ...[
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: horas
                          .map(
                            (hora) => Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                hora,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 7),
                  Text(
                    activo ? 'Alarma activa' : 'Alarma pausada',
                    style: TextStyle(
                      color: activo
                          ? const Color(0xFF137052)
                          : Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Switch(
                  value: activo,
                  onChanged: (valor) => _cambiarEstado(
                    medicamento,
                    valor,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  onSelected: (accion) {
                    if (accion == 'historial') {
                      _abrirHistorialMedicamento(medicamento);
                    } else if (accion == 'editar') {
                      _editarMedicamento(medicamento);
                    } else if (accion == 'eliminar') {
                      _eliminarMedicamento(medicamento);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'historial',
                      child: Row(
                        children: [
                          Icon(Icons.history),
                          SizedBox(width: 10),
                          Text('Ver historial'),
                        ],
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'editar',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined),
                          SizedBox(width: 10),
                          Text('Editar'),
                        ],
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'eliminar',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: Color(0xFFB3261E),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Eliminar',
                            style: TextStyle(color: Color(0xFFB3261E)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _etiqueta(IconData icono, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5F4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: const Color(0xFF47615E)),
          const SizedBox(width: 5),
          Text(
            texto,
            style: const TextStyle(
              color: Color(0xFF47615E),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _estadoVacio() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.medication_outlined,
            size: 48,
            color: Colors.black38,
          ),
          const SizedBox(height: 12),
          const Text(
            'Aún no hay medicamentos',
            style: TextStyle(
              color: Color(0xFF17324D),
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Agrega el primero para programar una alarma.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _agregarMedicamento,
            icon: const Icon(Icons.add),
            label: const Text('Agregar medicamento'),
          ),
        ],
      ),
    );
  }

  Widget _mensajeError() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9E9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.error_outline, color: Color(0xFFB3261E)),
          SizedBox(width: 10),
          Expanded(
            child: Text('No se pudieron cargar los medicamentos.'),
          ),
        ],
      ),
    );
  }
}
