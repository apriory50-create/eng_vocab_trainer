import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../data/remote/ai_client.dart';
import '../../main.dart';
import 'leeches_screen.dart';

const _secureStorage = FlutterSecureStorage();
const _apiKeyStorageKey = 'ai_api_key';

Future<AiClient> loadAiClient(WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final provider = await db.getSetting('ai_provider', 'anthropic');
  final baseUrl = await db.getSetting('ai_base_url', 'https://api.anthropic.com/v1/messages');
  final model = await db.getSetting('ai_model', 'claude-sonnet-4-20250514');
  final apiKey = await _secureStorage.read(key: _apiKeyStorageKey) ?? '';

  return AiClient(AiConfig(
    provider: provider,
    apiKey: apiKey,
    baseUrl: baseUrl,
    model: model,
  ));
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _apiKeyCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _newLimitCtrl = TextEditingController();
  final _reviewLimitCtrl = TextEditingController();
  String _provider = 'anthropic';
  double _retention = 0.9;
  bool _loading = true;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    _newLimitCtrl.dispose();
    _reviewLimitCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final key = await _secureStorage.read(key: _apiKeyStorageKey) ?? '';
    final provider = await db.getSetting('ai_provider', 'anthropic');
    final baseUrl = await db.getSetting('ai_base_url', 'https://api.anthropic.com/v1/messages');
    final model = await db.getSetting('ai_model', 'claude-sonnet-4-20250514');
    final newLim = await db.getSetting('daily_new_limit', '15');
    final revLim = await db.getSetting('daily_review_limit', '100');
    final ret = double.tryParse(await db.getSetting('desired_retention', '0.9')) ?? 0.9;

    if (!mounted) return;
    setState(() {
      _apiKeyCtrl.text = key;
      _provider = provider;
      _baseUrlCtrl.text = baseUrl;
      _modelCtrl.text = model;
      _newLimitCtrl.text = newLim;
      _reviewLimitCtrl.text = revLim;
      _retention = ret.clamp(0.85, 0.95);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    await _secureStorage.write(key: _apiKeyStorageKey, value: _apiKeyCtrl.text.trim());
    await db.setSetting('ai_provider', _provider);
    await db.setSetting('ai_base_url', _baseUrlCtrl.text.trim());
    await db.setSetting('ai_model', _modelCtrl.text.trim());
    await db.setSetting('daily_new_limit', _newLimitCtrl.text.trim());
    await db.setSetting('daily_review_limit', _reviewLimitCtrl.text.trim());
    await db.setSetting('desired_retention', _retention.toStringAsFixed(2));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Настройки сохранены')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            title: const Text('Трудные карточки («Пиявки»)'),
            subtitle: const Text('Карточки с 4+ ошибками — подбор новых мнемоник'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LeechesScreen()),
            ),
          ),
          const Divider(height: 28),
          const Text('ИИ-помощник', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _provider,
            decoration: const InputDecoration(
              labelText: 'Формат API',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'anthropic', child: Text('Anthropic (Claude)')),
              DropdownMenuItem(value: 'openai', child: Text('OpenAI-совместимый (прокси / OpenRouter)')),
            ],
            onChanged: (val) {
              if (val == null) return;
              setState(() {
                _provider = val;
                if (val == 'anthropic' && _baseUrlCtrl.text.contains('openai')) {
                  _baseUrlCtrl.text = 'https://api.anthropic.com/v1/messages';
                } else if (val == 'openai' && _baseUrlCtrl.text.contains('anthropic')) {
                  _baseUrlCtrl.text = 'https://api.openai.com/v1/chat/completions';
                }
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              labelText: 'Модель',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'API-ключ (хранится защищённо)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const Divider(height: 32),
          const Text('Повторения (FSRS)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newLimitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Новых в день',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _reviewLimitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Лимит повторений',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Целевое удержание (desired_retention): ${(_retention * 100).round()}%'),
          Slider(
            value: _retention,
            min: 0.85,
            max: 0.95,
            divisions: 10,
            label: '${(_retention * 100).round()}%',
            onChanged: (v) => setState(() => _retention = v),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Сохранить настройки'),
          ),
        ],
      ),
    );
  }
}
