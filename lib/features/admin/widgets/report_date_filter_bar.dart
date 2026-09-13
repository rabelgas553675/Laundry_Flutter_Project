import 'package:flutter/material.dart';

import '../../../services/report_service.dart';

/// PART 19A — the "Today / This Week / This Month / Custom Range"
/// filter shared by [SalesReportScreen] and [OrderReportScreen].
///
/// Purely presentational, same split every other widget in this
/// project follows: it never calls [ReportService] itself and never
/// decides what the resolved date range actually is. It only reports
/// *selections* back to the screen that owns the state
/// ([onPresetSelected], [onPickStart], [onPickEnd]) — the screen is
/// what calls `ReportService.resolveRange` and re-fetches its report
/// data.
class ReportDateFilterBar extends StatelessWidget {
  const ReportDateFilterBar({
    super.key,
    required this.selected,
    required this.onPresetSelected,
    this.customStart,
    this.customEnd,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final ReportRangePreset selected;
  final ValueChanged<ReportRangePreset> onPresetSelected;

  /// Only meaningful (and only shown) when [selected] is
  /// [ReportRangePreset.custom].
  final DateTime? customStart;
  final DateTime? customEnd;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ReportRangePreset.values.map((preset) {
              final isSelected = preset == selected;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(preset.label),
                  selected: isSelected,
                  onSelected: (_) => onPresetSelected(preset),
                ),
              );
            }).toList(),
          ),
        ),
        if (selected == ReportRangePreset.custom) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickStart,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    customStart == null
                        ? 'Start date'
                        : 'From: ${ReportService.formatDate(customStart!)}',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickEnd,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    customEnd == null
                        ? 'End date'
                        : 'To: ${ReportService.formatDate(customEnd!)}',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}