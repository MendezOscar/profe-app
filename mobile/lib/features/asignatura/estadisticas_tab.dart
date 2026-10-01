import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/planes/estadisticas.dart';
import '../../core/planes/modelos.dart';
import '../../core/providers.dart';
import '../../ui/estado_vacio.dart';
import '../../ui/shell.dart';
import '../../theme/tokens.dart';

/// Cómo va el grupo en el parcial: promedio, quién está en riesgo, qué rubro cuesta más,
/// quién no entrega y quién falta. Abajo, la evolución de parcial a parcial.
class EstadisticasTab extends ConsumerWidget {
  const EstadisticasTab({super.key, required this.plan});

  final PlanParcial plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = calcularEstadisticas(plan);
    final evol = ref.watch(evolucionProvider(plan.claseId)).valueOrNull ?? const <PuntoEvolucion>[];

    if (e.conNota.isEmpty && e.sesiones == 0) {
      return const EstadoVacio(
        icono: Icons.insights_outlined,
        titulo: 'Todavía no hay datos',
        mensaje: 'Las estadísticas aparecen cuando califiques la primera actividad o pases lista.',
      );
    }

    final secciones = <Widget>[
      _Resumen(e: e, cerrado: plan.cerrado),
      if (e.conNota.isNotEmpty) _Distribucion(e: e),
      if (e.enRiesgo.isNotEmpty) _EnRiesgo(e: e),
      if (e.rubros.any((r) => r.porcentaje != null)) _PorRubro(e: e),
      if (e.entregas.any((x) => x.noEntregadas > 0 || x.sinNota > 0)) _Entregas(e: e, alumnos: plan.alumnos.length),
      if (e.sesiones > 0) _Asistencia(e: e),
      if (evol.length > 1) _Evolucion(puntos: evol, alumnos: plan.alumnos),
    ];

    return ContenidoCentrado(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, Espacio.bajoBotonFlotante),
        itemCount: secciones.length,
        separatorBuilder: (_, _) => const SizedBox(height: Espacio.l),
        itemBuilder: (_, i) => secciones[i],
      ),
    );
  }
}

String _pct(double v) => '${v.round()} %';

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, this.ayuda, required this.child});

  final String titulo;
  final String? ayuda;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo, style: text.titleMedium),
            if (ayuda != null) ...[
              const SizedBox(height: Espacio.xxs),
              Text(ayuda!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: Espacio.m),
            child,
          ],
        ),
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.e, required this.cerrado});

  final Estadisticas e;
  final bool cerrado;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final promedio = e.promedio;
    return _Seccion(
      titulo: cerrado ? 'Resultado del parcial' : 'Cómo va el parcial',
      ayuda: cerrado ? null : 'En curso: cada nota es el porcentaje de lo que ya calificaste, no de los 100 puntos.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _Cifra(
            valor: promedio == null ? '—' : promedio.toStringAsFixed(1),
            etiqueta: cerrado ? 'Promedio' : 'Promedio (%)',
            color: promedio != null && promedio < notaMinima ? scheme.error : null,
          ),
          _Cifra(valor: '${e.aprobados}', etiqueta: 'Aprueban ($notaMinima o más)'),
          _Cifra(valor: '${e.reprobados}', etiqueta: 'Bajo $notaMinima', color: e.reprobados > 0 ? scheme.error : null),
          _Cifra(valor: e.asistencia == null ? '—' : _pct(e.asistencia!), etiqueta: 'Asistencia'),
        ],
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.valor, required this.etiqueta, this.color});

  final String valor;
  final String etiqueta;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(Espacio.m),
      color: scheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: color ?? scheme.primary)),
          Text(etiqueta, style: text.labelMedium),
        ],
      ),
    );
  }
}

/// Barra horizontal simple, 0 a [maximo].
class _Barra extends StatelessWidget {
  const _Barra({required this.etiqueta, required this.valor, required this.maximo, required this.texto, this.color});

  final String etiqueta;
  final double valor;
  final double maximo;
  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$etiqueta: $texto',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Espacio.xs),
        child: Row(
          children: [
            SizedBox(width: 120, child: Text(etiqueta, style: text.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Expanded(
              child: LinearProgressIndicator(
                value: maximo <= 0 ? 0 : (valor / maximo).clamp(0.0, 1.0),
                minHeight: 14,
                borderRadius: BorderRadius.zero,
                backgroundColor: scheme.primaryContainer,
                color: color ?? scheme.primary,
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(texto, textAlign: TextAlign.end, style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Distribucion extends StatelessWidget {
  const _Distribucion({required this.e});

  final Estadisticas e;

  @override
  Widget build(BuildContext context) {
    final tramos = e.distribucion;
    final maximo = tramos.fold(0, (m, t) => t.alumnos > m ? t.alumnos : m).toDouble();
    final error = Theme.of(context).colorScheme.error;
    return _Seccion(
      titulo: 'Distribución de notas',
      child: Column(
        children: [
          for (final (i, t) in tramos.indexed)
            _Barra(
              etiqueta: t.etiqueta,
              valor: t.alumnos.toDouble(),
              maximo: maximo,
              texto: '${t.alumnos}',
              color: i < 2 ? error : null,
            ),
        ],
      ),
    );
  }
}

class _EnRiesgo extends StatelessWidget {
  const _EnRiesgo({required this.e});

  final Estadisticas e;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return _Seccion(
      titulo: 'Alumnos en riesgo · ${e.enRiesgo.length}',
      ayuda: 'Bajo $notaMinima, o con 3 faltas o más (al menos el 15 % de las clases).',
      child: Column(
        children: [
          for (final a in e.enRiesgo)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(a.alumno.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text([
                if (a.inasistencias > 0) '${a.inasistencias} ${a.inasistencias == 1 ? 'falta' : 'faltas'}',
                if (a.noEntregadas > 0) '${a.noEntregadas} sin entregar',
              ].join(' · ')),
              trailing: Text(
                a.nota?.toString() ?? '—',
                style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, color: a.enRiesgo ? scheme.error : scheme.onSurface),
              ),
            ),
        ],
      ),
    );
  }
}

class _PorRubro extends StatelessWidget {
  const _PorRubro({required this.e});

  final Estadisticas e;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return _Seccion(
      titulo: 'Rendimiento por rubro',
      ayuda: 'Qué porcentaje de los puntos calificados obtuvo el grupo en cada rubro.',
      child: Column(
        children: [
          for (final r in e.rubros)
            if (r.porcentaje case final p?)
              _Barra(
                etiqueta: r.rubro.nombre,
                valor: p,
                maximo: 100,
                texto: _pct(p),
                color: p < notaMinima ? error : null,
              ),
        ],
      ),
    );
  }
}

class _Entregas extends StatelessWidget {
  const _Entregas({required this.e, required this.alumnos});

  final Estadisticas e;
  final int alumnos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final conProblema = [for (final x in e.entregas) if (x.noEntregadas > 0 || x.sinNota > 0) x];
    final quienes = [for (final a in e.alumnos) if (a.noEntregadas > 0) a]
      ..sort((a, b) => b.noEntregadas.compareTo(a.noEntregadas));
    return _Seccion(
      titulo: 'Entregas',
      ayuda: '“Sin entregar” es una nota de 0; “sin nota”, lo que falta calificar.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final x in conProblema)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(x.actividad.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(DateFormat("d 'de' MMMM", 'es').format(x.actividad.fecha)),
              trailing: Text(
                [
                  if (x.noEntregadas > 0) '${x.noEntregadas} sin entregar',
                  if (x.sinNota > 0) '${x.sinNota} de $alumnos sin nota',
                ].join(' · '),
                style: text.labelMedium?.copyWith(color: x.sinNota > 0 ? scheme.primary : scheme.error),
              ),
            ),
          if (quienes.isNotEmpty) ...[
            const Divider(),
            Text('Quiénes no entregan', style: text.labelLarge),
            const SizedBox(height: Espacio.xs),
            for (final a in quienes.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Espacio.xxs),
                child: Text('${a.alumno.nombre} · ${a.noEntregadas}', style: text.bodyMedium),
              ),
          ],
        ],
      ),
    );
  }
}

class _Asistencia extends StatelessWidget {
  const _Asistencia({required this.e});

  final Estadisticas e;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final faltistas = [for (final a in e.alumnos) if (a.inasistencias > 0) a]
      ..sort((a, b) => b.inasistencias.compareTo(a.inasistencias));
    final fecha = DateFormat("EEEE d 'de' MMMM", 'es');
    return _Seccion(
      titulo: 'Asistencia',
      ayuda: '${e.sesiones} listas en el parcial. Sólo las ausencias cuentan como inasistencias.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (faltistas.isEmpty)
            Text('Nadie ha faltado en este parcial.', style: text.bodyMedium)
          else ...[
            Text('Con más faltas', style: text.labelLarge),
            const SizedBox(height: Espacio.xs),
            for (final a in faltistas.take(5))
              _Barra(
                etiqueta: a.alumno.nombre.split(' ').take(2).join(' '),
                valor: a.inasistencias.toDouble(),
                maximo: faltistas.first.inasistencias.toDouble(),
                texto: '${a.inasistencias}',
                color: e.muchasFaltas(a) ? Theme.of(context).colorScheme.error : null,
              ),
          ],
          if (e.diasConMasFaltas.isNotEmpty) ...[
            const SizedBox(height: Espacio.m),
            Text('Días con más ausencias', style: text.labelLarge),
            const SizedBox(height: Espacio.xs),
            for (final d in e.diasConMasFaltas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Espacio.xxs),
                child: Text('${fecha.format(d.fecha)} · ${d.ausentes} ${d.ausentes == 1 ? 'ausente' : 'ausentes'}',
                    style: text.bodyMedium),
              ),
          ],
        ],
      ),
    );
  }
}

/// Promedio por parcial y, por alumno, sus notas con la tendencia del último cambio.
class _Evolucion extends StatelessWidget {
  const _Evolucion({required this.puntos, required this.alumnos});

  final List<PuntoEvolucion> puntos;
  final List<AlumnoPlan> alumnos;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget celda(int? nota, {bool negrita = false}) => SizedBox(
          width: 56,
          child: Text(
            nota?.toString() ?? '—',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              fontWeight: negrita ? FontWeight.w800 : null,
              color: nota != null && nota < notaMinima ? scheme.error : null,
            ),
          ),
        );

    Widget tendencia(String alumnoId) {
      final notas = [for (final p in puntos) p.porAlumno[alumnoId]].whereType<int>().toList();
      if (notas.length < 2) return const SizedBox(width: Espacio.xxl);
      final cambio = notas.last - notas[notas.length - 2];
      final (icono, color) = cambio >= 5
          ? (Icons.trending_up, scheme.primary)
          : cambio <= -5
              ? (Icons.trending_down, scheme.error)
              : (Icons.trending_flat, scheme.onSurfaceVariant);
      return SizedBox(
        width: 32,
        child: Tooltip(message: '${cambio > 0 ? '+' : ''}$cambio', child: Icon(icono, size: 20, color: color)),
      );
    }

    return _Seccion(
      titulo: 'Evolución por parcial',
      ayuda: 'Los parciales en curso muestran el porcentaje de lo calificado. La flecha compara los dos últimos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in puntos)
            _Barra(
              etiqueta: p.cerrado ? p.parcial.titulo : '${p.parcial.titulo} (en curso)',
              valor: p.promedio ?? 0,
              maximo: 100,
              texto: p.promedio?.toStringAsFixed(1) ?? '—',
              color: (p.promedio ?? 100) < notaMinima ? scheme.error : null,
            ),
          const SizedBox(height: Espacio.m),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(width: 220, child: Text('ALUMNO', style: text.labelSmall)),
                    for (final p in puntos)
                      SizedBox(
                        width: 56,
                        child: Text(p.parcial.titulo.replaceFirst('PARCIAL ', 'P. '),
                            textAlign: TextAlign.center, style: text.labelSmall),
                      ),
                    const SizedBox(width: Espacio.xxl),
                  ],
                ),
                const Divider(),
                for (final a in alumnos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Espacio.xs),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 220,
                          child: Text(a.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                        ),
                        for (final p in puntos) celda(p.porAlumno[a.id], negrita: p == puntos.last),
                        tendencia(a.id),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
