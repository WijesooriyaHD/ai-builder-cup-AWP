import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'she_stacks_common.dart';

class NegotiationLabModal extends StatefulWidget {
  final VoidCallback onComplete;
  const NegotiationLabModal({super.key, required this.onComplete});

  @override
  State<NegotiationLabModal> createState() => _NegotiationLabModalState();
}

class _NegotiationLabModalState extends State<NegotiationLabModal> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _chatController = TextEditingController();
  int _step = 0;
  double _confidence = 0.5;
  bool _isTyping = false;
  bool _isAiMode = false;
  
  final List<Map<String, dynamic>> _chatHistory = [
    {
      "isRecruiter": true,
      "text": "We're excited about your profile! What are your salary expectations for this Director role?",
    }
  ];

  final List<List<Map<String, dynamic>>> _script = [
    // Step 0: The Anchor
    [
      {
        "text": "Based on my research for this role in San Francisco, the range is \$175k-\$195k. I'm looking for \$185k.",
        "confidence": 0.2,
        "strategy": "ANCHORING: You set the baseline high using market data. This controls the range from the start.",
        "recruiter_reply": "That's at the high end. What specific value do you bring to justify \$185k?"
      },
      {
        "text": "I'm open to seeing what you typically offer someone with my background.",
        "confidence": -0.1,
        "strategy": "PASSIVITY: By not naming a number, you give the recruiter total control to low-ball you.",
        "recruiter_reply": "We typically start around \$145k. Does that work for you?"
      }
    ],
    // Step 1: The ROI Link
    [
      {
        "text": "In my last role, I built a team that increased revenue by 20%. I'll apply that same scaling logic here.",
        "confidence": 0.3,
        "strategy": "ROI LINK: You've turned your salary from a 'cost' into an 'investment' with proven returns.",
        "recruiter_reply": "Impressive stats. We can do \$170k, but the board has a hard cap on base salary at that level."
      },
      {
        "text": "I'm just really passionate about the product and want to help the mission grow.",
        "confidence": -0.1,
        "strategy": "EMOTION vs VALUE: Passion is great for the interview, but hard data is what moves the needle in negotiation.",
        "recruiter_reply": "We love the passion! \$150k is our standard for this level. Shall we proceed?"
      }
    ],
    // Step 2: The Final Pivot
    [
      {
        "text": "I respect the base limit. Can we bridge the gap with an additional 0.5% equity or a sign-on bonus?",
        "confidence": 0.2,
        "strategy": "TOTAL COMP PIVOT: When the base is fixed, move to 'soft' benefits like equity, bonuses, or extra PTO.",
        "recruiter_reply": "I'll check with the team... Okay, we can add a \$15k sign-on bonus. Welcome aboard!"
      },
      {
        "text": "Okay, \$170k works for me. I'm happy to join!",
        "confidence": 0.0,
        "strategy": "LEAVING MONEY ON TABLE: You accepted the first 'hard' limit. Always try at least one pivot to soft benefits.",
        "recruiter_reply": "Wonderful! We'll send the offer over shortly. Welcome to the team!"
      }
    ]
  ];

  void _handleChoice(Map<String, dynamic> choice) {
    if (_isTyping) return;

    setState(() {
      _chatHistory.add({
        "isRecruiter": false,
        "text": choice['text'],
        "strategy": choice['strategy'],
      });
      _confidence = (_confidence + choice['confidence']).clamp(0.0, 1.0);
      _isTyping = true;
    });
    
    HapticFeedback.lightImpact();
    _scrollToBottom();

    // Recruiter Response Simulation
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _chatHistory.add({
          "isRecruiter": true,
          "text": choice['recruiter_reply'],
        });
        if (_step < _script.length - 1) {
          _step++;
        } else {
          _step = 99; // Completion
        }
      });
      _scrollToBottom();
    });
  }

  Future<void> _sendAiMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isTyping) return;

    setState(() {
      _chatHistory.add({"isRecruiter": false, "text": text});
      _chatController.clear();
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      debugPrint("DEBUG: Sending AI Request. User: ${FirebaseAuth.instance.currentUser?.uid}");

      final callable = FirebaseFunctions.instance.httpsCallable('negotiationCoach');
      final response = await callable.call({
        'messages': _chatHistory.map((m) => {
          'role': m['isRecruiter'] ? 'assistant' : 'user',
          'content': m['text'],
        }).toList(),
      });

      final data = response.data as Map<String, dynamic>;
      String reply = data['reply'] ?? "I'm having trouble responding right now.";
      String? tip;

      // Extract Tip if present in [Tip: ...] format
      final tipMatch = RegExp(r'\[Tip: (.*?)\]').firstMatch(reply);
      if (tipMatch != null) {
        tip = tipMatch.group(1);
        reply = reply.replaceFirst(tipMatch.group(0)!, '').trim();
      }

      setState(() {
        _isTyping = false;
        _chatHistory.add({
          "isRecruiter": true,
          "text": reply,
          "strategy": tip,
        });
      });
    } catch (e) {
      debugPrint("AI CHAT ERROR: $e");
      setState(() {
        _isTyping = false;
        _chatHistory.add({
          "isRecruiter": true,
          "text": "Error: $e", // Show actual error to user for debugging
        });
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101316) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text("Negotiation Lab", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        actions: [
            IconButton(
              icon: Icon(Icons.help_outline_rounded, color: primaryColor),
              onPressed: () => SheStacksCommon.showFinanceExplainer(context, "Negotiation Rules", "1. Anchor First: Name a range based on data.\n2. ROI Link: Prove your worth in \$.\n3. Pivot: If salary is capped, ask for equity/bonuses."),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // AI Mode Switch Row
              Center(
                child: Container(
                  width: 200,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Stack(
                    children: [
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        alignment: _isAiMode ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: 100,
                          height: 36,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isAiMode = false),
                              behavior: HitTestBehavior.opaque,
                              child: Center(
                                child: Text(
                                  "Guided Script",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: !_isAiMode ? FontWeight.bold : FontWeight.w500,
                                    color: !_isAiMode 
                                        ? Colors.black 
                                        : (isDark ? Colors.white54 : Colors.grey),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _isAiMode = true),
                              behavior: HitTestBehavior.opaque,
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.auto_awesome, 
                                      size: 14, 
                                      color: _isAiMode 
                                          ? (primaryColor) // Active & Light Mode -> Primary
                                          : (isDark ? Colors.white54 : Colors.grey)
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "AI Coach",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: _isAiMode ? FontWeight.bold : FontWeight.w500,
                                        color: _isAiMode 
                                            ? Colors.black
                                            : (isDark ? Colors.white54 : Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildConfidenceMeter(primaryColor, isDark),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: _chatHistory.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _chatHistory.length && _isTyping) {
                      return _buildTypingIndicator(isDark);
                    }
                    final chat = _chatHistory[index];
                    return _buildChatBubble(chat, isDark, primaryColor);
                  },
                ),
              ),
              const SizedBox(height: 16),
              if (_step != 99) 
                _isAiMode ? _buildAiInput(isDark, primaryColor) : _buildOptions(isDark, primaryColor)
              else 
                _buildCompletionButton(primaryColor),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiInput(bool isDark, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              onSubmitted: (_) => _sendAiMessage(),
              decoration: const InputDecoration(
                hintText: "Type your response...",
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          IconButton(
            onPressed: _sendAiMessage,
            icon: Icon(Icons.send_rounded, color: primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceMeter(Color primaryColor, bool isDark) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Your Leverage", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
            Text("${(_confidence * 100).toInt()}%", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: primaryColor)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: _confidence,
            minHeight: 6,
            backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
            color: primaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> chat, bool isDark, Color primaryColor) {
    final isRecruiter = chat['isRecruiter'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: isRecruiter ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isRecruiter 
                  ? (isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100)
                  : primaryColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isRecruiter ? 4 : 20),
                bottomRight: Radius.circular(isRecruiter ? 20 : 4),
              ),
            ),
            child: Text(
              chat['text'],
              style: TextStyle(
                color: isRecruiter ? (isDark ? Colors.white : Colors.black87) : Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
          if (chat['strategy'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 20, right: 4),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, color: Colors.amber, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        chat['strategy'],
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms),
            ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
              borderRadius: const BorderRadius.all(Radius.circular(20)),
            ),
            child: const Text("Typing...", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
          ),
        ],
      ).animate().fadeIn().shimmer(),
    );
  }

  Widget _buildOptions(bool isDark, Color primaryColor) {
    return Column(
      children: _script[_step].map((opt) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(18),
                backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                side: BorderSide(color: primaryColor.withOpacity(0.2)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => _handleChoice(opt),
              child: Text(
                opt['text'],
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCompletionButton(Color primaryColor) {
    return Column(
      children: [
        const Text("Negotiation Complete!", style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(20),
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () {
              widget.onComplete();
              Navigator.pop(context);
            },
            child: const Text("SEE MY TOTAL COMP", style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    ).animate().scale();
  }
}
