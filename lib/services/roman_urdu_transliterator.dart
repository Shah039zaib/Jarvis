/// Lightweight Roman-Urdu → Urdu-script transliterator (no dependencies).
///
/// Why this exists: the app's replies are Roman Urdu written in Latin
/// script, but Edge-TTS `ur-PK` voices are trained on Urdu script. Feeding
/// Latin-script Roman Urdu to the Urdu voice pronounces it wrong, so the
/// voice path transliterates the reply to Urdu script before synthesis.
///
/// Scope: VOICE ONLY. Chat text, saved messages and the SOUL.md language
/// rule are untouched — chat stays in Roman Urdu (Latin script). The
/// transliterator is idempotent: text already in Urdu script, digits,
/// punctuation, URLs and [keepAsIs] words pass through unchanged, so
/// applying it twice is safe.
///
/// Method: word-by-word. Whole-word [wordOverrides] cover the common words
/// the letter rules get wrong; everything else falls back to a
/// character/phoneme mapping (digraphs first, then single letters). It is
/// not perfect — Roman Urdu spelling is ambiguous ('gh' can be گھ or غ,
/// 't' can be ت or ٹ, 'e' can be a dropped zabar or ی) — but it is clearly
/// better than feeding Latin text to the Urdu voice.
class RomanUrduTransliterator {
  /// English technical terms that must stay in Latin script, in both the
  /// chat text and the text sent to the Urdu voice. The Urdu voice reads
  /// them as English loanwords, which is natural — and it matches the
  /// SOUL.md language rule (English technical words used naturally inside
  /// Roman Urdu).
  ///
  /// Matching is case-insensitive and the original casing is preserved.
  /// To keep more words as-is, add them here — this is the single place
  /// the keep-list lives.
  static const Set<String> keepAsIs = {
    // --- technical terms (user's list) ---
    'model', 'models', 'settings', 'wi-fi', 'wifi', 'install', 'uninstall',
    'update', 'upgrade', 'app', 'apps', 'api', 'key', 'keys', 'phone',
    'battery', 'permission', 'permissions', 'password', 'username', 'email',
    'link', 'file', 'files', 'download', 'upload', 'login', 'logout',
    'sign-in', 'sign in', 'account', 'device', 'screen', 'notification',
    'notifications', 'bluetooth', 'data', 'network', 'internet', 'browser',
    'chrome', 'google', 'play', 'store', 'github', 'ollama', 'openrouter',
    'gemini', 'telegram', 'whatsapp', 'jarvis', 'abuzar', 'ai', 'vpn', 'sim',
    'usb', 'pdf', 'image', 'video', 'audio', 'voice', 'volume', 'brightness',
    'flashlight', 'torch', 'widget', 'cache', 'version', 'error', 'code',
    'web', 'website', 'server', 'cloud', 'online', 'offline', 'ram', 'cpu',
    'storage', 'memory', 'sensor', 'gps', 'location', 'camera', 'mic',
    'microphone', 'speaker', 'headphone', 'charger', 'cable', 'qr', 'otp',
    'pin', 'nfc', 'lte', '5g', '4g', 'sms', 'call', 'chat', 'group',
    'channel', 'bot', 'plugin', 'addon', 'theme', 'font', 'apk', 'ios',
    'android', 'flutter', 'dart', 'python', 'java', 'sql', 'html', 'css',
    'json', 'url', 'http', 'https', 'ip', 'dns', 'proxy', 'token',
    'license', 'premium', 'free', 'pro', 'plus', 'beta', 'alpha', 'stable',
    'debug', 'test', 'testing', 'build', 'release', 'deploy', 'render',
    'mongodb', 'firebase', 'openai', 'claude', 'deepseek', 'llama', 'qwen',
    'nemotron', 'nvidia', 'meta', 'microsoft', 'samsung', 'tecno', 'vivo',
    'xiaomi', 'oppo', 'huawei', 'iphone', 'windows', 'linux',
    'macos', 'edge', 'tts', 'stt', 'whisper', 'groq', 'huggingface',
    'system', 'systems', 'low', 'high', 'full', 'empty', 'boring',
    // --- common English words that appear inside mixed replies ---
    'i', 'you', 'he', 'she', 'we', 'they', 'it', 'is', 'am', 'are', 'was',
    'were', 'the', 'a', 'an', 'and', 'or', 'but', 'if', 'then', 'so', 'of',
    'to', 'in', 'on', 'for', 'with', 'can', 'could', 'will', 'would',
    'should', 'may', 'might', 'must', 'have', 'has', 'had', 'do', 'does',
    'did', 'not', 'this', 'that', 'what', 'when', 'where', 'who', 'why',
    'how', 'ok', 'okay', 'hi', 'hello', 'hey', 'bye', 'please', 'thanks',
    'thank', 'yes', 'no', 'good', 'morning', 'night', 'happy', 'birthday',
    'love', 'sir', 'set', 'let', 'long', 'new', 'old', 'big', 'small',
    'fast', 'slow', 'open', 'close', 'start', 'stop', 'pause',
    'next', 'back', 'home', 'search', 'find', 'help', 'info', 'about',
    'gpt', 'tax',
  };

  /// Whole-word overrides for common Roman Urdu words the letter rules
  /// get wrong (ambiguous letters: gh/ghar vs ghalat, t/teek vs theek,
  /// final 'ai' which is ے in 'hai' but ائی in 'bhai', etc.).
  static const Map<String, String> wordOverrides = {
    'aankh': 'آنکھ',
    'aankhen': 'آنکھیں',
    'aap': 'آپ',
    'aapka': 'آپکا',
    'aapki': 'آپکی',
    'aapko': 'آپکو',
    'aapne': 'آپنے',
    'acha': 'اچھا',
    'achha': 'اچھا',
    'ache': 'اچھے',
    'achi': 'اچھی',
    'achay': 'اچھے',
    'aai': 'آئی',
    'aaiye': 'آئیے',
    'aain': 'آئیں',
    'aao': 'آؤ',
    'aayega': 'آئے گا',
    'aayegi': 'آئے گی',
    'aayenge': 'آئیں گے',
    'aaye': 'آئے',
    'aayen': 'آئیں',
    'batao': 'بتاؤ',
    'bataen': 'بتائیں',
    'behen': 'بہن',
    'behan': 'بہن',
    'bhai': 'بھائی',
    'bhaiya': 'بھیا',
    'bohat': 'بہت',
    'bahut': 'بہت',
    'bulao': 'بلاؤ',
    'chai': 'چائے',
    'chahiye': 'چاہیے',
    'chahye': 'چاہیے',
    'chhota': 'چھوٹا',
    'chhoti': 'چھوٹی',
    'dar': 'ڈر',
    'darna': 'ڈرنا',
    'dara': 'ڈرا',
    'darr': 'ڈر',
    'daro': 'ڈرو',
    'dekho': 'دیکھو',
    'dekh': 'دیکھ',
    'dekha': 'دیکھا',
    'dekhen': 'دیکھیں',
    'eh': 'اے',
    'gai': 'گئی',
    'ghalat': 'غلط',
    'ghaib': 'غائب',
    'gham': 'غم',
    'ghussa': 'غصہ',
    'gharoor': 'غرور',
    'maghrib': 'مغرب',
    'ghaur': 'غور',
    'haan': 'ہاں',
    'jai': 'جائے',
    'jahan': 'جہاں',
    'jao': 'جاؤ',
    'jayen': 'جائیں',
    'jaye': 'جائے',
    'kai': 'کئی',
    'kaun': 'کون',
    'kahan': 'کہاں',
    'kehna': 'کہنا',
    'kehta': 'کہتا',
    'kha': 'کھا',
    'khaana': 'کھانا',
    'khana': 'کھانا',
    'khao': 'کھاؤ',
    'khaya': 'کھایا',
    'khayen': 'کھائیں',
    'khel': 'کھیل',
    'kher': 'خیر',
    'kheriyat': 'خیریت',
    'khoon': 'خون',
    'kurta': 'کرتا',
    'kurti': 'کرتی',
    'kursi': 'کرسی',
    'kuch': 'کچھ',
    'kyun': 'کیوں',
    'kyoon': 'کیوں',
    'kyon': 'کیوں',
    'kyu': 'کیوں',
    'kyunke': 'کیونکہ',
    'kyunki': 'کیونکہ',
    'lagao': 'لگاؤ',
    'lagana': 'لگانا',
    'lai': 'لائے',
    'larna': 'لڑنا',
    'lara': 'لڑا',
    'laro': 'لڑو',
    'likh': 'لکھ',
    'likha': 'لکھا',
    'likhen': 'لکھیں',
    'hoon': 'ہوں',
    'honge': 'ہوں گے',
    'hongi': 'ہوں گی',
    'inhe': 'انہیں',
    'inhen': 'انہیں',
    'mere': 'میرے',
    'mera': 'میرا',
    'meri': 'میری',
    'mohabbat': 'محبت',
    'murghi': 'مرغی',
    'murga': 'مرغا',
    'nahin': 'نہیں',
    'nahi': 'نہیں',
    'pehle': 'پہلے',
    'pehla': 'پہلا',
    'pet': 'پیٹ',
    'rai': 'رائے',
    'purana': 'پرانا',
    'purani': 'پرانی',
    'rakh': 'رکھ',
    'rakha': 'رکھا',
    'rehna': 'رہنا',
    'seekh': 'سیکھ',
    'seekha': 'سیکھا',
    'sunao': 'سناؤ',
    'suraj': 'سورج',
    'sai': 'سائے',
    'salam': 'سلام',
    'sarak': 'سڑک',
    'sher': 'شیر',
    'shukriya': 'شکریہ',
    'shukria': 'شکریہ',
    'tayyar': 'تیار',
    'tayar': 'تیار',
    'tera': 'تیرا',
    'tere': 'تیرے',
    'teri': 'تیری',
    'theek': 'ٹھیک',
    'thora': 'تھوڑا',
    'thori': 'تھوڑی',
    'tumhe': 'تمہیں',
    'tumhen': 'تمہیں',
    'tor': 'توڑ',
    'torna': 'توڑنا',
    'toro': 'توڑو',
    'tut': 'ٹوٹ',
    'udna': 'اڑنا',
    'ud': 'اڑ',
    'udo': 'اڑو',
    'ujala': 'اجالا',
    'umar': 'عمر',
    'unhe': 'انہیں',
    'unhein': 'انہیں',
    'unhen': 'انہیں',
    'uper': 'اوپر',
    'upar': 'اوپر',
    'wahan': 'وہاں',
    'wo': 'وہ',
    'woh': 'وہ',
    'yahan': 'یہاں',
    'ye': 'یہ',
    'zaroor': 'ضرور',
    'zaroori': 'ضروری',
    'zaroorat': 'ضرورت',
    'zyada': 'زیادہ',
  };

  /// Transliterates a full reply from Roman Urdu (Latin script) to Urdu
  /// script. Non-Latin text, digits, punctuation and keep-as-is words are
  /// returned unchanged.
  static String transliterate(String text) {
    if (text.isEmpty) return text;
    final buffer = StringBuffer();
    // Latin word tokens (letters plus internal hyphens/apostrophes, so
    // "wi-fi" and "don't" stay one token), numbers, and everything else.
    final tokenPattern =
        RegExp(r"[A-Za-z]+(?:['\-][A-Za-z]+)*|[0-9]+|[^\sA-Za-z0-9]+|\s+");
    for (final m in tokenPattern.allMatches(text)) {
      final token = m.group(0)!;
      final first = token.codeUnitAt(0);
      final isLatinLetter =
          (first >= 65 && first <= 90) || (first >= 97 && first <= 122);
      if (isLatinLetter) {
        buffer.write(_transliterateToken(token));
      } else {
        buffer.write(token);
      }
    }
    return buffer.toString();
  }

  static String _transliterateToken(String token) {
    // Single letters are initials/abbreviations — leave them alone.
    if (token.length <= 1) return token;
    final lower = token.toLowerCase();
    // English technical terms stay in Latin script (keep-list).
    if (keepAsIs.contains(lower)) return token;
    // English contractions ("don't", "I'm") stay as-is.
    if (token.contains("'")) return token;
    final override = wordOverrides[lower];
    if (override != null) return override;
    return _transliterateWord(lower);
  }

  /// Final 'n' is the nasal noon-ghunna (ں) only after the diphthongs
  /// ai/ay/ei, or in words ending "...ahan" (kahan, wahan, jahan).
  /// Everywhere else it is plain noon (ن): jaan, maan, kaan, khoon, kaun.
  static bool _isNasalN(String word, int i) {
    if (i < 2) return false;
    final prev2 = word.substring(i - 2, i);
    if (prev2 == 'ai' || prev2 == 'ay' || prev2 == 'ei') return true;
    if (i >= 3 && word.substring(i - 3, i + 1) == 'ahan') return true;
    return false;
  }

  /// Letter-by-letter fallback for words with no whole-word override.
  /// Digraphs are checked before single letters; short vowels a/e/i/u in
  /// the middle of a word are unwritten in Urdu script (zabar/zair/pesh).
  /// A medial 'a' is never written by the letter rules — words whose
  /// medial 'a' is long (salam, mohabbat, kahan) live in wordOverrides.
  static String _transliterateWord(String word) {
    final out = StringBuffer();
    final n = word.length;
    var i = 0;
    while (i < n) {
      // Three-letter digraph first: chh (چھ).
      if (i + 3 <= n && word.substring(i, i + 3) == 'chh') {
        out.write('چھ');
        i += 3;
        continue;
      }
      // Two-letter digraphs.
      if (i + 2 <= n) {
        final di = word.substring(i, i + 2);
        switch (di) {
          case 'aa':
            // Word-initial aa is alef-madda (aaj → آج); medial aa is a
            // plain alef (chaar → چار, salaam → سلام).
            out.write(i == 0 ? 'آ' : 'ا');
            i += 2;
            continue;
          case 'ao':
            out.write('او');
            i += 2;
            continue;
          case 'ai':
          case 'ay':
            // Word-initial: ای (aaina → آئینہ starts with آ + ی).
            // Word-final: ے (hai → ہے). Medial: ی (kaisa → کیسا).
            if (i == 0) {
              out.write('ای');
            } else if (i + 2 == n) {
              out.write('ے');
            } else {
              out.write('ی');
            }
            i += 2;
            continue;
          case 'au':
          case 'ou':
            out.write('او');
            i += 2;
            continue;
          case 'ee':
            out.write('ی');
            i += 2;
            continue;
          case 'oo':
            // Word-initial oo is alef + wao (ooncha → اونچا); medial oo
            // is wao alone (zaroor → ضرور).
            out.write(i == 0 ? 'او' : 'و');
            i += 2;
            continue;
          case 'ei':
            out.write('ی');
            i += 2;
            continue;
          case 'kh':
            out.write('خ');
            i += 2;
            continue;
          case 'gh':
            // 'gh' is گھ here (ghar, ghoomna); غ words are in overrides.
            out.write('گھ');
            i += 2;
            continue;
          case 'ch':
            out.write('چ');
            i += 2;
            continue;
          case 'sh':
            out.write('ش');
            i += 2;
            continue;
          case 'th':
            out.write('تھ');
            i += 2;
            continue;
          case 'ph':
            out.write('پھ');
            i += 2;
            continue;
          case 'bh':
            out.write('بھ');
            i += 2;
            continue;
          case 'dh':
            out.write('دھ');
            i += 2;
            continue;
          case 'jh':
            out.write('جھ');
            i += 2;
            continue;
          case 'rh':
            out.write('ڑھ');
            i += 2;
            continue;
          case 'zh':
            out.write('ژ');
            i += 2;
            continue;
          case 'ng':
            out.write(i + 2 == n ? 'ں' : 'نگ');
            i += 2;
            continue;
        }
      }
      final c = word[i];
      final isFirst = i == 0;
      final isLast = i == n - 1;
      switch (c) {
        case 'a':
          if (isFirst || isLast) {
            out.write('ا');
          }
          // Medial short 'a' is an unwritten zabar — skip. (Words whose
          // medial 'a' IS written long — salam, mohabbat, kahan, wahan —
          // are in wordOverrides; a general "final syllable" rule fired
          // wrongly on short-a words like ghar, kal, kar, kidhar.)
          break;
        case 'e':
          if (isLast) {
            out.write('ے'); // de → دے, se → سے, mere → میرے (via override).
          } else if (isFirst) {
            out.write('ای'); // ek → ایک.
          } else {
            // Medial 'e': ی before l/b/t/s/d/k/f/g/j/z/v (khel → کھیل,
            // seb → سیب, ret → ریت, bes → بیس); dropped before n/m/h/r
            // (hen → ہن, kem → کم, keh → کہ, per → پر).
            final next = word[i + 1];
            if ('lbtsdkfgjzv'.contains(next)) {
              out.write('ی');
            }
          }
          break;
        case 'i':
          if (isFirst) {
            out.write('ا'); // is → اس, in → ان, itna → اتنا.
          } else if (isLast) {
            out.write('ی'); // bhi → بھی, ki → کی, ji → جی.
          }
          // Medial short 'i' is an unwritten zair — skip.
          break;
        case 'o':
          out.write('و'); // jo → جو, do → دو, ko → کو.
          break;
        case 'u':
          if (isFirst) {
            out.write('ا'); // us → اس, usko → اسکو.
          } else if (isLast) {
            out.write('و'); // aalu → آلو, babu → بابو.
          } else if ((word[i + 1] == 'r' && n <= 4) ||
              word[i + 1] == 'd' ||
              (i + 2 < n && word.substring(i + 1, i + 3) == 'sh')) {
            // Medial 'u' is wao in short words (dur → دور, pur → پور,
            // pura → پورا), before 'd' (khud → خود) and before 'sh'
            // (khushi → خوشی); otherwise it is an unwritten pesh
            // (tum → تم, kuch → کچھ, kurta/kursi/murghi → overrides).
            out.write('و');
          }
          // Otherwise the medial short 'u' is an unwritten pesh — skip.
          break;
        case 'b':
          out.write('ب');
          break;
        case 'c':
          out.write('ک');
          break;
        case 'd':
          out.write('د');
          break;
        case 'f':
          out.write('ف');
          break;
        case 'g':
          out.write('گ');
          break;
        case 'h':
          out.write('ہ');
          break;
        case 'j':
          out.write('ج');
          break;
        case 'k':
          out.write('ک');
          break;
        case 'l':
          out.write('ل');
          break;
        case 'm':
          out.write('م');
          break;
        case 'n':
          out.write(isLast && _isNasalN(word, i) ? 'ں' : 'ن');
          break;
        case 'p':
          out.write('پ');
          break;
        case 'q':
          out.write('ق');
          break;
        case 'r':
          out.write('ر');
          break;
        case 's':
          out.write('س');
          break;
        case 't':
          out.write('ت');
          break;
        case 'v':
          out.write('و');
          break;
        case 'w':
          out.write('و');
          break;
        case 'x':
          out.write('کس');
          break;
        case 'y':
          out.write('ی');
          break;
        case 'z':
          out.write('ز');
          break;
        default:
          out.write(c);
          break;
      }
      i++;
    }
    return out.toString();
  }
}
