import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixez/main.dart';

class AiVisibilityButton extends StatelessWidget {
  const AiVisibilityButton({super.key});

  @override
  Widget build(BuildContext context) => Observer(
    builder: (_) {
      final hidden = muteStore.banAIIllust;
      return IconButton(
        tooltip: hidden ? 'AI 作品已隐藏，点按显示' : 'AI 作品已显示，点按隐藏',
        isSelected: hidden,
        icon: const Text('AI', style: TextStyle(fontWeight: FontWeight.bold)),
        selectedIcon: const Icon(Icons.hide_image_outlined),
        onPressed: () => muteStore.changeBanAI(!hidden),
      );
    },
  );
}
