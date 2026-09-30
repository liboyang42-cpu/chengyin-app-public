import 'package:flutter/material.dart';

import '../../core/theme/cy_tokens.dart';

class AppSensorChallengePlaceholder extends StatelessWidget {
  const AppSensorChallengePlaceholder({super.key, this.stillnessReady = false});

  final bool stillnessReady;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: CyTokens.space2),
      padding: const EdgeInsets.all(CyTokens.space2_5),
      decoration: BoxDecoration(
        color: CyTokens.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
        border: Border.all(color: CyTokens.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            stillnessReady
                ? Icons.sensors_outlined
                : Icons.sensors_off_outlined,
            size: 18,
            color: CyTokens.textSecondary,
          ),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'App 专属挑战',
                  style: TextStyle(
                    color: CyTokens.textPrimary,
                    fontSize: CyTokens.typeLabel,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  stillnessReady ? '点击开始静止挑战' : '该传感器玩法暂未开放',
                  style: TextStyle(
                    color: CyTokens.textSecondary,
                    fontSize: CyTokens.typeCaption,
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
