import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/journal_entry.dart';
import '../providers/app_state.dart';
import '../services/ai_service.dart';
import '../utils/wellnesspal_snackbar.dart';

class JournalAiDiscussionScreen extends StatefulWidget {
  final JournalEntry entry;

  const JournalAiDiscussionScreen({super.key, required this.entry});

  @override
  State<JournalAiDiscussionScreen> createState() => _JournalAiDiscussionScreenState();
}

class _JournalAiDiscussionScreenState extends State<JournalAiDiscussionScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Start with an initial grounding message from the AI.
    final title = widget.entry.title.trim();
    final opener = title.isNotEmpty
        ? "I've read your entry \u201C$title\u201D. What feels most alive for you in it right now, and how are you doing with it?"
        : "I've read your journal entry. What feels most alive for you in it right now, and how are you doing with it?";
    _messages.add(ChatMessage(text: opener, isAi: true));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isAi: false));
      _messageController.clear();
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      // Build the prior conversation (everything except the message we just
      // added) so the AI can respond in context.
      final history = _messages
          .take(_messages.length - 1)
          .map((m) => {'role': m.isAi ? 'ai' : 'user', 'text': m.text})
          .toList();

      final reply = await AIService().discussJournalEntry(
        entryTitle: widget.entry.title,
        entryContent: widget.entry.content,
        history: history,
        userMessage: text,
      );

      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(
          text: reply ??
              "I'm having trouble responding right now. Could you try rephrasing, or check your connection?",
          isAi: true,
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      WellnessPalSnackBar.show(context,
          message: "Error connecting to AI: $e", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.title.isNotEmpty ? widget.entry.title : "Discussion", style: const TextStyle(fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _ChatBubble(message: message, sourceEntryId: widget.entry.id);
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))
        ]
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: "Type your thoughts...",
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white.withOpacity(0.05) 
                    : Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.purple,
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isAi;
  bool isSaved;

  ChatMessage({required this.text, required this.isAi, this.isSaved = false});
}

class _ChatBubble extends StatefulWidget {
  final ChatMessage message;
  final String sourceEntryId;

  const _ChatBubble({required this.message, required this.sourceEntryId});

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final message = widget.message;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: message.isAi ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: message.isAi 
                  ? (isDark ? Colors.grey.shade900 : Colors.white)
                  : Colors.purple.withOpacity(0.1),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(message.isAi ? 4 : 20),
                bottomRight: Radius.circular(message.isAi ? 20 : 4),
              ),
              border: message.isAi ? Border.all(color: Colors.grey.withOpacity(0.2)) : null,
              boxShadow: message.isAi ? [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
              ] : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkdownBody(
                  data: message.text,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                ),
                if (message.isAi) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: message.isSaved ? null : () => _saveToJournal(context, message.text),
                        icon: Icon(
                          message.isSaved ? Icons.check_circle_rounded : Icons.bookmark_add_outlined, 
                          size: 16, 
                          color: message.isSaved ? Colors.blue : Colors.purple
                        ),
                        label: Text(
                          message.isSaved ? "Saved" : "Save as Insight", 
                          style: TextStyle(
                            fontSize: 12, 
                            color: message.isSaved ? Colors.blue : Colors.purple,
                            fontWeight: message.isSaved ? FontWeight.bold : FontWeight.normal,
                          )
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _saveToJournal(BuildContext context, String text) {
    final appState = Provider.of<AppState>(context, listen: false);
    final newEntry = JournalEntry(
      title: "AI Insight: ${DateTime.now().month}/${DateTime.now().day}",
      content: text,
      type: JournalEntryType.note,
      color: Colors.purple.shade50.value,
      isSaved: true,
      tags: ["AI Discussion"],
      sourceEntryId: widget.sourceEntryId,
    );
    appState.addJournalEntry(newEntry);
    
    setState(() {
      widget.message.isSaved = true;
    });
    
    WellnessPalSnackBar.show(context, message: "Saved to Journal", icon: Icons.check_circle_rounded);
  }
}
