import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../core/localization/app_language.dart';
import '../../data/mock_data.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 110),
        children: [
          Row(
            children: [
              Expanded(
                child: LText(
                  'Messages',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              IconButton.filled(
                onPressed: () {},
                icon: const Icon(Icons.edit_outlined),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr('Rechercher une conversation...'),
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Conversations'),
          ...MockData.conversations.map(
            (m) => Pressable(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => _Chat(m)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    PersonAvatar(
                      initials: m.initials,
                      color: m.color,
                      size: 55,
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: LText(
                                  m.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              LText(
                                m.time,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: m.unread > 0
                                      ? AppColors.blue
                                      : AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          LText(
                            m.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: m.unread > 0
                                  ? AppColors.ink
                                  : AppColors.muted,
                              fontWeight: m.unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (m.unread > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 9),
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: LText(
                          '${m.unread}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Chat extends StatefulWidget {
  const _Chat(this.conversation);
  final Conversation conversation;
  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final input = TextEditingController();
  final messages = <String>[
    'Bonjour Sophie ! Lucas a été très concentré aujourd’hui.',
    'Son coup droit progresse vraiment bien 🎾',
    'Merci David ! Il était très fier de sa séance.',
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          PersonAvatar(
            initials: widget.conversation.initials,
            color: widget.conversation.color,
            size: 38,
          ),
          const SizedBox(width: 10),
          LText(
            widget.conversation.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(18),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final mine = i % 3 == 2;
                return Align(
                  alignment: mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    constraints: const BoxConstraints(maxWidth: 280),
                    decoration: BoxDecoration(
                      color: mine ? AppColors.ink : AppColors.cloud,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: LText(
                      messages[i],
                      style: TextStyle(
                        color: mine ? Colors.white : AppColors.ink,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    decoration: InputDecoration(
                      hintText: tr('Écrire un message...'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () {
                    if (input.text.trim().isNotEmpty) {
                      setState(() {
                        messages.add(input.text);
                        input.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.send_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
