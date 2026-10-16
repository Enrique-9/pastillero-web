import 'package:flutter/material.dart';

import '../horario_medicamento.dart';

class NuevoMedicamentoPage extends StatefulWidget {
  final Map<String, dynamic>? medicamentoInicial;

  const NuevoMedicamentoPage({
    super.key,
    this.medicamentoInicial,
  });

  @override
  State<NuevoMedicamentoPage> createState() =>
      _NuevoMedicamentoPageState();
}

class _NuevoMedicamentoPageState extends State<NuevoMedicamentoPage> {
  final formularioKey = GlobalKey<FormState>();
  final nombreController = TextEditingController();
  final dosisController = TextEditingController();

  String tipoHorario = 'fijo';
  TimeOfDay horaInicio = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay horaFin = const TimeOfDay(hour: 22, minute: 0);
  int intervaloHoras = 8;
  bool incluirMadrugada = true;
  final Set<String> diasSeleccionados = {};
  bool activo = true;

  bool get editando => widget.medicamentoInicial != null;

  @override
  void initState() {
    super.initState();

    final medicamento = widget.medicamentoInicial;
    if (medicamento == null) return;

    nombreController.text = medicamento['nombre']?.toString() ?? '';
    dosisController.text = medicamento['dosis']?.toString() ?? '';
    activo = medicamento['activo'] != false;
    tipoHorario = medicamento['tipoHorario']?.toString() == 'intervalo'
        ? 'intervalo'
        : 'fijo';

    horaInicio = _leerHora(
      medicamento['horaInicio'] ?? medicamento['hora'],
      horaInicio,
    );
    horaFin = _leerHora(medicamento['horaFin'], horaFin);

    final intervaloGuardado = medicamento['intervaloHoras'];
    final intervalo = intervaloGuardado is num
        ? intervaloGuardado.toInt()
        : int.tryParse(intervaloGuardado?.toString() ?? '');

    if ([4, 6, 8, 12, 24].contains(intervalo)) {
      intervaloHoras = intervalo!;
    }

    incluirMadrugada = medicamento['incluirMadrugada'] != false;
    diasSeleccionados.addAll(
      obtenerDiasMedicamento(medicamento['dias']),
    );
  }

  @override
  void dispose() {
    nombreController.dispose();
    dosisController.dispose();
    super.dispose();
  }

  TimeOfDay _leerHora(dynamic valor, TimeOfDay respaldo) {
    final minutos = minutosDeHora(valor?.toString() ?? '');

    if (minutos < 0) return respaldo;
    return TimeOfDay(hour: minutos ~/ 60, minute: minutos % 60);
  }

  String _hora24(TimeOfDay hora) {
    return '${hora.hour.toString().padLeft(2, '0')}:'
        '${hora.minute.toString().padLeft(2, '0')}';
  }

  int _minutos(TimeOfDay hora) => (hora.hour * 60) + hora.minute;

  Future<void> _seleccionarHoraInicio() async {
    final seleccionada = await showTimePicker(
      context: context,
      initialTime: horaInicio,
      helpText: tipoHorario == 'intervalo'
          ? 'HORA DE LA PRIMERA TOMA'
          : 'HORA DE LA TOMA',
    );

    if (seleccionada != null) {
      setState(() {
        horaInicio = seleccionada;
      });
    }
  }

  Future<void> _seleccionarHoraFin() async {
    final seleccionada = await showTimePicker(
      context: context,
      initialTime: horaFin,
      helpText: 'ÚLTIMA HORA PERMITIDA',
    );

    if (seleccionada != null) {
      setState(() {
        horaFin = seleccionada;
      });
    }
  }

  List<int> _minutosVistaPrevia() {
    final medicamentoTemporal = <String, dynamic>{
      'tipoHorario': tipoHorario,
      'hora': _hora24(horaInicio),
      'horaInicio': _hora24(horaInicio),
      'intervaloHoras': intervaloHoras,
      'incluirMadrugada': incluirMadrugada,
      'horaFin': _hora24(horaFin),
    };

    return minutosProgramados(medicamentoTemporal);
  }

  void _guardarMedicamento() {
    FocusScope.of(context).unfocus();

    if (!formularioKey.currentState!.validate()) return;

    if (diasSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un día'),
        ),
      );
      return;
    }

    if (tipoHorario == 'intervalo' &&
        !incluirMadrugada &&
        _minutos(horaFin) <= _minutos(horaInicio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La hora límite debe ser posterior a la primera toma',
          ),
        ),
      );
      return;
    }

    final horaBase = _hora24(horaInicio);
    final diasOrdenados = diasMedicamento
        .where(diasSeleccionados.contains)
        .toList();

    final medicamento = <String, dynamic>{
      'nombre': nombreController.text.trim(),
      'dosis': dosisController.text.trim(),
      'tipoHorario': tipoHorario,
      // Se conserva "hora" para que los medicamentos anteriores y las
      // versiones previas del pastillero sigan siendo compatibles.
      'hora': horaBase,
      'horaInicio': horaBase,
      'intervaloHoras': tipoHorario == 'intervalo' ? intervaloHoras : 0,
      'incluirMadrugada':
          tipoHorario == 'intervalo' ? incluirMadrugada : false,
      'horaFin': _hora24(horaFin),
      'dias': diasOrdenados,
      'activo': activo,
    };

    Navigator.pop(context, medicamento);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F6),
      appBar: AppBar(
        title: Text(
          editando ? 'Editar medicamento' : 'Nuevo medicamento',
        ),
        backgroundColor: const Color(0xFFF3F7F6),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: formularioKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const CircleAvatar(
                  radius: 38,
                  backgroundColor: Color(0xFFDDF5EE),
                  child: Icon(
                    Icons.medication,
                    color: Color(0xFF168C80),
                    size: 38,
                  ),
                ),
                const SizedBox(height: 25),
                TextFormField(
                  controller: nombreController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del medicamento',
                    hintText: 'Ejemplo: Paracetamol',
                    prefixIcon: Icon(Icons.medication_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Escribe el nombre del medicamento';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: dosisController,
                  decoration: const InputDecoration(
                    labelText: 'Dosis',
                    hintText: 'Ejemplo: 500 mg o 1 tableta',
                    prefixIcon: Icon(Icons.science_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (valor) {
                    if (valor == null || valor.trim().isEmpty) {
                      return 'Escribe la dosis';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Tipo de horario',
                  style: TextStyle(
                    color: Color(0xFF17324D),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'fijo',
                      icon: Icon(Icons.schedule),
                      label: Text('Hora fija'),
                    ),
                    ButtonSegment(
                      value: 'intervalo',
                      icon: Icon(Icons.repeat),
                      label: Text('Cada ciertas horas'),
                    ),
                  ],
                  selected: {tipoHorario},
                  onSelectionChanged: (seleccion) {
                    setState(() {
                      tipoHorario = seleccion.first;
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (tipoHorario == 'fijo')
                  _tarjetaHora(
                    icono: Icons.access_time,
                    titulo: 'Hora de la toma',
                    hora: horaInicio,
                    onTap: _seleccionarHoraInicio,
                  )
                else
                  _configuracionIntervalo(),
                const SizedBox(height: 24),
                const Text(
                  'Días de la semana',
                  style: TextStyle(
                    color: Color(0xFF17324D),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: diasMedicamento.map((dia) {
                    final seleccionado = diasSeleccionados.contains(dia);

                    return FilterChip(
                      label: Text(dia),
                      selected: seleccionado,
                      onSelected: (valor) {
                        setState(() {
                          if (valor) {
                            diasSeleccionados.add(dia);
                          } else {
                            diasSeleccionados.remove(dia);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 22),
                SwitchListTile(
                  value: activo,
                  onChanged: (valor) {
                    setState(() {
                      activo = valor;
                    });
                  },
                  title: const Text('Alarma activa'),
                  subtitle: const Text(
                    'El pastillero avisará según este horario',
                  ),
                  secondary: const Icon(Icons.notifications_active),
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _guardarMedicamento,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.save),
                  label: Text(
                    editando
                        ? 'Guardar cambios'
                        : 'Guardar medicamento',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _configuracionIntervalo() {
    final horas = _minutosVistaPrevia();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: intervaloHoras,
          decoration: const InputDecoration(
            labelText: 'Frecuencia',
            prefixIcon: Icon(Icons.repeat),
            border: OutlineInputBorder(),
          ),
          items: const [4, 6, 8, 12, 24]
              .map(
                (horas) => DropdownMenuItem(
                  value: horas,
                  child: Text('Cada $horas horas'),
                ),
              )
              .toList(),
          onChanged: (valor) {
            if (valor != null) {
              setState(() {
                intervaloHoras = valor;
              });
            }
          },
        ),
        const SizedBox(height: 14),
        _tarjetaHora(
          icono: Icons.play_circle_outline,
          titulo: 'Primera toma',
          hora: horaInicio,
          onTap: _seleccionarHoraInicio,
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          value: incluirMadrugada,
          onChanged: (valor) {
            setState(() {
              incluirMadrugada = valor;
            });
          },
          title: const Text('Continuar durante 24 horas'),
          subtitle: const Text(
            'Incluye las tomas que caigan durante la madrugada',
          ),
          secondary: const Icon(Icons.nights_stay_outlined),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        if (!incluirMadrugada) ...[
          const SizedBox(height: 10),
          _tarjetaHora(
            icono: Icons.stop_circle_outlined,
            titulo: 'Hora límite del día',
            hora: horaFin,
            onTap: _seleccionarHoraFin,
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4F3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.preview_outlined,
                    color: Color(0xFF168C80),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Vista previa de las tomas',
                    style: TextStyle(
                      color: Color(0xFF17324D),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (horas.isEmpty)
                const Text(
                  'La hora límite debe ser posterior a la primera toma.',
                  style: TextStyle(color: Color(0xFFB3261E)),
                )
              else
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: horas.map((minuto) {
                    final texto = formatearTomaProgramada(
                      context,
                      minuto,
                    );

                    return Chip(
                      avatar: const Icon(Icons.alarm, size: 16),
                      label: Text(texto),
                      backgroundColor: Colors.white,
                    );
                  }).toList(),
                ),
              const SizedBox(height: 10),
              const Text(
                'Configura este horario únicamente como fue indicado por el médico.',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tarjetaHora({
    required IconData icono,
    required String titulo,
    required TimeOfDay hora,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icono, color: const Color(0xFF168C80)),
        title: Text(titulo),
        subtitle: Text(hora.format(context)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
