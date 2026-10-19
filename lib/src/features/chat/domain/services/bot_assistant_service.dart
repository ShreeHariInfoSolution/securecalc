import 'dart:async';
import '../entities/chat_conversation.dart';
import '../entities/chat_message.dart';
import 'local_chat_storage.dart';

class BotQuestion {
  final String id;
  final String question;
  final String shortChipText;
  final String answer;

  const BotQuestion({
    required this.id,
    required this.question,
    required this.shortChipText,
    required this.answer,
  });
}

class BotAssistantService {
  BotAssistantService._();
  static final BotAssistantService instance = BotAssistantService._();

  static const String botId = 'bot_calnox_assistant';
  static const String botName = 'Calnox AI Assistant';

  static const List<BotQuestion> suggestedQuestions = [
    BotQuestion(
      id: 'e2ee',
      question: 'Is my chat data end-to-end encrypted?',
      shortChipText: '🔐 End-to-End Encryption',
      answer:
          '🔐 *End-to-End Encryption (E2EE)*\n\nAll your chat messages, media files, and voice notes are protected using zero-knowledge AES-256 and Curve25519 encryption.\n\nMessages are encrypted directly on your device before sending and can only be decrypted by the recipient. Nobody else—not even network providers or server admins—can read your chats!',
    ),
    BotQuestion(
      id: 'calc_vault',
      question: 'How does the Calculator Secret Vault work?',
      shortChipText: '🧮 Calculator Vault',
      answer:
          '🧮 *Calculator Secret Vault*\n\nCalnox functions as a real, fully working calculator on your home screen.\n\nTo open your hidden vault:\n1. Type your secret master PIN.\n2. Tap the "=" button (or long-press the top header).\n3. Your secret chats, private folder, and media instantly unlock!',
    ),
    BotQuestion(
      id: 'shake_panic',
      question: 'What happens when I shake my device?',
      shortChipText: '📱 Shake Panic Protection',
      answer:
          '📱 *Shake Panic Protection*\n\nIf you ever need to hide your vault instantly:\n• Simply shake your phone or flip it screen-down.\n• The app instantly locks itself, clears active memory, and takes you back to the calculator screen or home screen.',
    ),
    BotQuestion(
      id: 'disappearing',
      question: 'How do Disappearing Messages work?',
      shortChipText: '⏳ Disappearing Messages',
      answer:
          '⏳ *Disappearing Messages*\n\nYou can set a auto-delete timer in any chat settings (e.g., 10s, 1m, 1h, or 24h).\n\nOnce the recipient reads your message, the countdown begins. When time expires, the message is permanently wiped from memory and local storage on both devices.',
    ),
    BotQuestion(
      id: 'master_pin',
      question: 'How do I change my Vault PIN?',
      shortChipText: '🔑 Change Vault PIN',
      answer:
          '🔑 *Changing Your Master PIN*\n\nTo update your secret passcode:\n1. Open Vault Settings ⚙️ -> Security.\n2. Tap "Change Master PIN".\n3. Enter your current PIN, then set and confirm your new 4-8 digit passcode.',
    ),
    BotQuestion(
      id: 'duress_mode',
      question: 'What is Duress / Decoy Vault Mode?',
      shortChipText: '🚨 Duress Decoy Mode',
      answer:
          '🚨 *Duress Decoy Vault*\n\nIf someone forces you to unlock your phone, enter your secret Duress PIN!\n\nIt opens a completely clean, dummy vault with false data while keeping your actual private chats and photos completely hidden.',
    ),
    BotQuestion(
      id: 'media_storage',
      question: 'Are my private files backed up on the cloud?',
      shortChipText: '📁 Local Storage Safety',
      answer:
          '📁 *Private File Storage*\n\nAll your hidden photos, videos, and documents are stored locally inside an encrypted vault database on your device.\n\nThey are never uploaded to unencrypted cloud servers, ensuring 100% data ownership and privacy.',
    ),
  ];

  /// Ensures the Calnox AI Assistant conversation exists in LocalChatStorage.
  Future<ChatConversation> ensureBotConversationExists() async {
    final existing = LocalChatStorage.instance.getConversationSync(botId);
    if (existing != null) return existing;

    final initialMessages = [
      ChatMessage(
        id: 'bot_welcome_1',
        senderId: botId,
        content:
            '👋 Hello! I am your Calnox AI Assistant.\n\nHow can I help you today? Tap any of the suggested questions below or type your query!',
        timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
        isRead: true,
        isDelivered: true,
      ),
    ];

    final botConv = ChatConversation(
      id: botId,
      name: botName,
      avatarUrl: '',
      lastMessage: 'Tap to ask questions & learn how Calnox Vault works',
      lastMessageTime: 'Online',
      lastActivityAt: DateTime.now(),
      unreadCount: 0,
      isOnline: true,
      isPinned: true,
      messages: initialMessages,
    );

    final currentConvs =
        await LocalChatStorage.instance.loadConversations();
    if (currentConvs.indexWhere((c) => c.id == botId) < 0) {
      currentConvs.insert(0, botConv);
      await LocalChatStorage.instance.replaceConversations(currentConvs);
      await LocalChatStorage.instance.cacheMessages(botId, initialMessages);
    }

    return botConv;
  }

  /// Evaluates user query and returns matching bot response.
  String getBotResponse(String input) {
    final clean = input.trim().toLowerCase();

    // Check exact question matches
    for (final q in suggestedQuestions) {
      if (clean == q.question.toLowerCase() ||
          clean == q.shortChipText.toLowerCase()) {
        return q.answer;
      }
    }

    // Keyword matching
    if (clean.contains('encrypt') ||
        clean.contains('e2ee') ||
        clean.contains('security') ||
        clean.contains('safe') ||
        clean.contains('private')) {
      return suggestedQuestions[0].answer;
    }

    if (clean.contains('calc') ||
        clean.contains('vault') ||
        clean.contains('unlock') ||
        clean.contains('equal') ||
        clean.contains('code') ||
        clean.contains('open')) {
      return suggestedQuestions[1].answer;
    }

    if (clean.contains('shake') ||
        clean.contains('panic') ||
        clean.contains('motion') ||
        clean.contains('emergency')) {
      return suggestedQuestions[2].answer;
    }

    if (clean.contains('disappear') ||
        clean.contains('timer') ||
        clean.contains('destruct') ||
        clean.contains('auto delete') ||
        clean.contains('expire')) {
      return suggestedQuestions[3].answer;
    }

    if (clean.contains('pin') ||
        clean.contains('passcode') ||
        clean.contains('change pin') ||
        clean.contains('reset') ||
        clean.contains('password')) {
      return suggestedQuestions[4].answer;
    }

    if (clean.contains('duress') ||
        clean.contains('decoy') ||
        clean.contains('fake') ||
        clean.contains('force')) {
      return suggestedQuestions[5].answer;
    }

    if (clean.contains('media') ||
        clean.contains('photo') ||
        clean.contains('video') ||
        clean.contains('cloud') ||
        clean.contains('storage') ||
        clean.contains('backup')) {
      return suggestedQuestions[6].answer;
    }

    if (clean.contains('hi') ||
        clean.contains('hello') ||
        clean.contains('hey') ||
        clean.contains('start')) {
      return '👋 Hello! I am Calnox AI Assistant.\n\nI can help answer questions about End-to-End Encryption, Calculator Vault PINs, Shake Panic Lock, and Disappearing Messages. Tap any suggested question chip below!';
    }

    // Default polite response with topic list
    return '🤖 Thanks for your message!\n\nI am Calnox AI Assistant. Here are some key topics I can help you with:\n\n• 🔐 End-to-End Encryption\n• 🧮 Calculator Vault Access\n• 📱 Shake Panic Lock\n• ⏳ Disappearing Messages\n• 🔑 Master PIN Changes\n• 🚨 Duress / Decoy Mode\n\nTap any suggested question below!';
  }
}
