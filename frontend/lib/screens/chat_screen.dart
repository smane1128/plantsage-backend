import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/plant.dart';
import '../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final Plant plant;
  final Map<String, dynamic> plantRaw;

  const ChatScreen({super.key, required this.plant, required this.plantRaw});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Message> _messages = [];
  bool _isThinking = false;

  static const _quickQuestions = [
    '🌏 Can this grow in Malaysia?',
    '🐾 Is it safe for pets?',
    '🌱 What plants grow well with it?',
    '🐛 How do I fix common problems?',
  ];

  @override
  void initState() {
    super.initState();
    final name = widget.plant.identification.plantName;
    _messages.add(_Message(
      role: 'assistant',
      text: 'Hi! I\'m your AI plant expert for **$name**. Ask me anything about this plant — care tips, compatibility, problems, or anything else!',
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _isThinking) return;
    _controller.clear();

    setState(() {
      _messages.add(_Message(role: 'user', text: msg));
      _isThinking = true;
    });
    _scrollToBottom();

    try {
      // Build history excluding the initial greeting
      final history = _messages
          .skip(1) // skip the initial assistant greeting
          .where((m) => m.role != 'thinking')
          .map((m) => {'role': m.role, 'content': m.text})
          .toList();
      // Remove the last user message (it's sent separately as `message`)
      if (history.isNotEmpty && history.last['role'] == 'user') {
        history.removeLast();
      }

      final reply = await ApiService.chatWithExpert(
        plantData: widget.plantRaw,
        message: msg,
        history: history,
      );

      if (!mounted) return;
      setState(() {
        _isThinking = false;
        _messages.add(_Message(role: 'assistant', text: reply));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isThinking = false;
        _messages.add(_Message(role: 'assistant', text: 'Sorry, I encountered an error: ${e.toString().replaceAll("Exception: ", "")}'));
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.plant.identification.plantName;
    final score = widget.plant.purchaseDecision.suitabilityScore;
    final rec = widget.plant.purchaseDecision.recommendation;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text('AI Plant Expert', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Plant summary banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFE8F5E9),
            child: Row(
              children: [
                const Text('🌿', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B5E20))),
                      Text(widget.plant.identification.scientificName,
                          style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$score/100', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_isThinking ? 1 : 0),
              itemBuilder: (context, i) {
                if (_isThinking && i == _messages.length) {
                  return const _ThinkingBubble();
                }
                return _ChatBubble(message: _messages[i]);
              },
            ),
          ),

          // Quick question chips (only when no user messages yet)
          if (_messages.length == 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Quick questions:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _quickQuestions.map((q) => ActionChip(
                          label: Text(q, style: const TextStyle(fontSize: 12)),
                          backgroundColor: const Color(0xFFE8F5E9),
                          side: const BorderSide(color: Color(0xFFA5D6A7)),
                          onPressed: () => _send(q),
                        )).toList(),
                  ),
                ],
              ),
            ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, -2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: InputDecoration(
                      hintText: 'Ask about this plant...',
                      filled: true,
                      fillColor: const Color(0xFFF1F8F1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFF2E7D32),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: () => _send(_controller.text),
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

class _Message {
  final String role;
  final String text;
  _Message({required this.role, required this.text});
}

class _ChatBubble extends StatelessWidget {
  final _Message message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              backgroundColor: Color(0xFF2E7D32),
              radius: 16,
              child: Text('🌿', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF2E7D32) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Text(
                message.text,
                style: TextStyle(fontSize: 14, color: isUser ? Colors.white : Colors.black87, height: 1.4),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFF2E7D32),
            radius: 16,
            child: Text('🌿', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  child: LinearProgressIndicator(
                    color: Color(0xFF2E7D32),
                    backgroundColor: Color(0xFFE8F5E9),
                  ),
                ),
                SizedBox(width: 8),
                Text('Thinking...', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
