// lib/widgets/audit_alert_banner.dart
import 'package:flutter/material.dart';
import '../models/models.dart';

class AuditAlertBanner extends StatelessWidget {
  final PreviousInspectionSummary previousSummary;
  final List<ChecklistItemConfig> allConfigs;
  final Map<String, ChecklistAnswer> currentAnswers;

  const AuditAlertBanner({
    super.key,
    required this.previousSummary,
    required this.allConfigs,
    required this.currentAnswers,
  });

  @override
  Widget build(BuildContext context) {
    // Localiza alterações apontadas no turno atual que NÃO estavam no anterior
    final omittedItems = <ChecklistItemConfig>[];

    for (final entry in currentAnswers.entries) {
      if (entry.value.status == 'ALTERACAO') {
        final itemId = entry.key;
        // Se a vistoria anterior não tinha essa alteração
        if (!previousSummary.itemsWithAlteration.contains(itemId)) {
          final cfg = allConfigs.firstWhere(
            (c) => c.id == itemId,
            orElse: () => ChecklistItemConfig(
              id: itemId,
              categoria: 'Geral',
              titulo: 'Item $itemId',
              obrigatorio: true,
              exigeFotoSeAlterado: true,
              ativo: true,
            ),
          );
          omittedItems.add(cfg);
        }
      }
    }

    final hasDiscrepancy = omittedItems.isNotEmpty;

    if (hasDiscrepancy) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF450A0A).withOpacity(0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.report_problem, color: Color(0xFFEF4444), size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AVARIA OMITIDA PELO MOTORISTA ANTERIOR!',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Motorista Anterior:',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      Text(
                        previousSummary.driverRankAndName,
                        style: const TextStyle(
                          color: Color(0xFFF59E0B),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Matrícula / Telefone:',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      Text(
                        'Mat. ${previousSummary.driverBadge} • ${previousSummary.driverPhone}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFF334155), height: 12),
                  const Text(
                    'Avarias Detectadas que Não Constavam:',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  ...omittedItems.map(
                    (it) => Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_right, color: Color(0xFFEF4444), size: 16),
                          Expanded(
                            child: Text(
                              it.titulo,
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield, color: Color(0xFFF59E0B), size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Este registro resguarda o seu turno e notifica formalmente o oficial de dia para apuração disciplinar/sindicância de trânsito.',
                    style: TextStyle(color: Colors.white70, fontSize: 10, height: 1.3),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Caso de conformidade 100%
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF064E3B).withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Em conformidade com a vistoria entregue por ${previousSummary.driverRankAndName}.',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
