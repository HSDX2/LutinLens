import 'package:flutter/material.dart';
import 'package:librecamera/src/utils/preferences.dart';
import '../../l10n/app_localizations.dart';

class TimerButton extends StatefulWidget {
  const TimerButton({
    Key? key,
    required this.enabled,
  }) : super(key: key);

  final bool enabled;

  @override
  State<TimerButton> createState() => _TimerButtonState();
}

class _TimerButtonState extends State<TimerButton> {
  List<Duration> durations = [
    const Duration(seconds: 1),
    const Duration(seconds: 2),
    const Duration(seconds: 3),
    const Duration(seconds: 5),
    const Duration(seconds: 10),
    const Duration(seconds: 15),
    const Duration(seconds: 30),
    const Duration(minutes: 1),
    const Duration(minutes: 2),
    const Duration(minutes: 5),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
      ),
      child: DropdownButton<Duration>(
        isDense: true,
        menuMaxHeight: 384.0,
        icon: const Icon(Icons.av_timer_outlined),
        underline: Container(),
        borderRadius: BorderRadius.circular(12),
        value: Duration(seconds: Preferences.getTimerDuration()),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 14,
        ),
        selectedItemBuilder: (context) {
          return durations.map(
            (duration) {
              final name = duration.inSeconds < 60
                  ? '${duration.inSeconds}s'
                  : '${duration.inMinutes}m';

              return DropdownMenuItem(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.av_timer_outlined,
                        size: 18,
                        color: widget.enabled 
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        name,
                        style: TextStyle(
                          color: widget.enabled 
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ).toList()
            ..insert(
              0,
              DropdownMenuItem<Duration>(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.av_timer_outlined,
                        size: 18,
                        color: widget.enabled 
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '––',
                        style: TextStyle(
                          color: widget.enabled 
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
        },
        items: durations.map(
          (duration) {
            final name = duration.inSeconds < 60
                ? '${duration.inSeconds}s'
                : '${duration.inMinutes}m';

            return DropdownMenuItem(
              value: duration,
              onTap: () {
                setState(() {
                  Preferences.setTimerDuration(duration.inSeconds);
                });
              },
              child: Text(
                name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            );
          },
        ).toList()
          ..insert(
            0,
            DropdownMenuItem<Duration>(
              value: const Duration(),
              onTap: () {
                setState(() {
                  Preferences.setTimerDuration(0);
                });
              },
              child: Text(
                AppLocalizations.of(context)!.off,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        onChanged: widget.enabled ? (_) {} : null,
      ),
    );
  }
}
