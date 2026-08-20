import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../state/trip_controller.dart';
import '../history/history_screen.dart';
import '../marketplace/feed_screen.dart';
import '../profile/profile_screen.dart';
import '../trips/trips_screen.dart';

/// Корневая оболочка с нижней навигацией.
///
/// Вкладки живут в [IndexedStack]: возвращаясь к ленте, водитель попадает на
/// то же место списка, а не в начало.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Приложение открывается на «Рейсах»: водитель заходит сюда за своей
  /// текущей работой, а на биржу — только когда свободен.
  int _index = _tripsTab;

  static const _tripsTab = 1;

  void _select(int index) {
    if (index == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    // Активный рейс подсвечивает вкладку «Рейсы» — водитель не должен его терять.
    final hasLiveTrip = context.select<TripController, bool>(
      (t) => t.active?.status.isLive ?? false,
    );

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          FeedScreen(),
          TripsScreen(),
          HistoryScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        index: _index,
        onSelect: _select,
        tripBadge: hasLiveTrip,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.index,
    required this.onSelect,
    required this.tripBadge,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final bool tripBadge;

  @override
  Widget build(BuildContext context) {
    final items = <({IconData active, IconData inactive, String label})>[
      (
        active: PhosphorIcons.package(PhosphorIconsStyle.fill),
        inactive: PhosphorIcons.package(),
        label: 'Заявки',
      ),
      (
        active: PhosphorIcons.truck(PhosphorIconsStyle.fill),
        inactive: PhosphorIcons.truck(),
        label: 'Рейсы',
      ),
      (
        active: PhosphorIcons.clockCounterClockwise(PhosphorIconsStyle.fill),
        inactive: PhosphorIcons.clockCounterClockwise(),
        label: 'История',
      ),
      (
        active: PhosphorIcons.user(PhosphorIconsStyle.fill),
        inactive: PhosphorIcons.user(),
        label: 'Я',
      ),
    ];

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.bgBase,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.sm, 6, Gap.sm, 0),
          child: Row(
            children: [
              for (final (itemIndex, item) in items.indexed)
                Expanded(
                  child: _NavItem(
                    icon: itemIndex == index ? item.active : item.inactive,
                    label: item.label,
                    selected: itemIndex == index,
                    badge: itemIndex == 1 && tripBadge,
                    onTap: () => onSelect(itemIndex),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;

  /// Янтарная точка — рейс в работе.
  final bool badge;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textTertiary;

    return Semantics(
      selected: selected,
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: SizedBox(
          height: Touch.min,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 24, color: color),
                  if (badge)
                    Positioned(
                      right: -3,
                      top: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.bgBase, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Gap.xs),
              Text(
                label,
                style: AppText.tab.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
