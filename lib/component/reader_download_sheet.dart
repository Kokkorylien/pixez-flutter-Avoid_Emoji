import 'package:material_ui/material_ui.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/models/illust.dart';

Future<void> showReaderDownloadSheet(
  BuildContext context,
  Illusts illust,
  int index,
  void Function(List<bool>) onDownload,
) async {
  final multi = await showModalBottomSheet<bool>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: Text(
              '${I18n.of(context).save} · ${index + 1}/${illust.pageCount}',
            ),
            onTap: () => Navigator.pop(sheetContext, false),
          ),
          if (illust.pageCount > 1)
            ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(I18n.of(context).muti_choice_save),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
          ListTile(
            leading: const Icon(Icons.close),
            title: Text(I18n.of(context).cancel),
            onTap: () => Navigator.pop(sheetContext),
          ),
        ],
      ),
    ),
  );
  if (multi == null || !context.mounted) return;
  final selected = List<bool>.generate(illust.pageCount, (i) => i == index);
  if (!multi) {
    onDownload(selected);
    return;
  }
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(illust.title),
              ),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                  ),
                  itemCount: selected.length,
                  itemBuilder: (context, i) => Semantics(
                    label: '${i + 1}',
                    selected: selected[i],
                    button: true,
                    child: InkWell(
                      onTap: () => update(() => selected[i] = !selected[i]),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: PixivImage(
                              illust.metaPages[i].imageUrls!.squareMedium,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: CircleAvatar(
                              radius: 14,
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          if (selected[i])
                            const Positioned(
                              bottom: 8,
                              right: 8,
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              CheckboxListTile(
                title: Text(I18n.of(context).all),
                value: selected.every((value) => value),
                onChanged: (value) => update(
                  () => selected.fillRange(0, selected.length, value ?? false),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: Text(
                  '${I18n.of(context).save} (${selected.where((v) => v).length})',
                ),
                enabled: selected.any((v) => v),
                onTap: () => Navigator.pop(sheetContext, true),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (confirmed == true && context.mounted) onDownload(selected);
}
