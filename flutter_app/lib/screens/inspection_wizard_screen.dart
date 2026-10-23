// lib/screens/inspection_wizard_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../widgets/camera_angle_card.dart';
import '../widgets/checklist_item_card.dart';
import '../widgets/audit_alert_banner.dart';

class InspectionWizardScreen extends StatefulWidget {
  final VoidCallback onOpenAdmin;

  const InspectionWizardScreen({super.key, required this.onOpenAdmin});

  @override
  State<InspectionWizardScreen> createState() => _InspectionWizardScreenState();
}

class _InspectionWizardScreenState extends State<InspectionWizardScreen> {
  int _currentStep = 0;
  bool _isLoading = true;
  bool _isSaving = false;

  // Controladores de Texto
  final _rankController = TextEditingController(text: 'Cb PM');
  final _warNameController = TextEditingController(text: 'ALMEIDA');
  final _badgeController = TextEditingController(text: '39.412-8');
  final _kmController = TextEditingController(text: '78450');
  final _phoneController = TextEditingController(text: '(62) 99341-8899');
  String _selectedFuel = '3/4';

  // Dados carregados do serviço
  List<Vehicle> _vehicles = [];
  String _selectedPrefix = 'VTR-1022';
  List<VehicleNotice> _notices = [];
  List<ChecklistItemConfig> _checklistConfigs = [];
  PreviousInspectionSummary? _previousSummary;

  // Fotos dos 4 Lados
  final Map<String, File?> _photos4Sides = {
    'Frente': null,
    'Traseira': null,
    'Esquerda': null,
    'Direita': null,
  };

  // Respostas do Checklist
  final Map<String, ChecklistAnswer> _answers = {};

  // Assinatura Digital
  late SignatureController _sigController;

  @override
  void initState() {
    super.initState();
    _sigController = SignatureController(
      penStrokeWidth: 3,
      penColor: const Color(0xFFF59E0B),
      exportBackgroundColor: Colors.transparent,
    );
    _loadInitialData();
  }

  @override
  void dispose() {
    _sigController.dispose();
    _kmController.dispose();
    _phoneController.dispose();
    _warNameController.dispose();
    _badgeController.dispose();
    _rankController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final svc = SupabaseService.instance;

    final vehicles = await svc.getVehicles();
    final configs = await svc.getChecklistItems();

    _vehicles = vehicles;
    _checklistConfigs = configs;

    // Inicializa respostas com 'OK'
    for (final cfg in configs) {
      _answers[cfg.id] = ChecklistAnswer(itemId: cfg.id, status: 'OK');
    }

    if (vehicles.isNotEmpty) {
      _selectedPrefix = vehicles.first.prefixo;
      await _onVehicleChanged(_selectedPrefix);
    }

    setState(() => _isLoading = false);
  }

  Future<void> _onVehicleChanged(String prefix) async {
    setState(() => _selectedPrefix = prefix);
    final svc = SupabaseService.instance;

    final notices = await svc.getNotices(prefix);
    final prev = await svc.getPreviousInspection(prefix);

    // Ajusta o KM com base no odômetro da viatura
    final vtr = _vehicles.firstWhere((v) => v.prefixo == prefix, orElse: () => _vehicles.first);
    _kmController.text = vtr.kmAtual.toString();

    setState(() {
      _notices = notices;
      _previousSummary = prev;
    });
  }

  void _markAllAsOk() {
    setState(() {
      for (final cfg in _checklistConfigs) {
        _answers[cfg.id] = ChecklistAnswer(itemId: cfg.id, status: 'OK');
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Todos os itens foram marcados como CONFORME (OK).'),
        backgroundColor: Color(0xFF10B981),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _submitInspection() async {
    if (_sigController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, assine no campo digital para autenticar o checklist.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final svc = SupabaseService.instance;
      final km = int.tryParse(_kmController.text) ?? 0;

      final protocolo = await svc.submitInspection(
        prefixo: _selectedPrefix,
        matriculaCondutor: _badgeController.text,
        km: km,
        telefoneEscala: _phoneController.text,
        nivelCombustivel: _selectedFuel,
        fotos4Lados: _photos4Sides,
        respostas: _answers,
        assinaturaPath: null,
      );

      setState(() => _isSaving = false);

      if (mounted) {
        _showSuccessDialog(protocolo);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  void _showSuccessDialog(String protocolo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 28),
            SizedBox(width: 8),
            Text(
              'Vistoria Finalizada!',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Protocolo de Cautela: $protocolo',
              style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Viatura: $_selectedPrefix | KM: ${_kmController.text}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Motorista: ${_rankController.text} ${_warNameController.text}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              'Telefone Escala: ${_phoneController.text}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              'Os dados foram registrados com carimbo de tempo imutável. Em caso de divergência de avarias com o turno anterior, a sindicância foi notificada.',
              style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.3),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _currentStep = 0;
                _sigController.clear();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Nova Vistoria', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B1329),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B1329),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SisCheck-VTR',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.black, letterSpacing: 1),
            ),
            Text(
              'Vistoria In Loco & Custódia',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: widget.onOpenAdmin,
            icon: const Icon(Icons.tune, color: Color(0xFFF59E0B)),
            tooltip: 'Painel Admin',
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de Progresso
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF0F172A),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _getStepTitle(_currentStep),
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${((_currentStep + 1) / 4 * 100).toInt()}%',
                      style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (_currentStep + 1) / 4,
                  backgroundColor: const Color(0xFF1E293B),
                  color: const Color(0xFFF59E0B),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),

          // Conteúdo do Wizard
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildCurrentStepContent(),
            ),
          ),

          // Barra Inferior de Navegação
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _currentStep--),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Voltar', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () {
                            if (_currentStep < 3) {
                              setState(() => _currentStep++);
                            } else {
                              _submitInspection();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Color(0xFF0F172A), strokeWidth: 2),
                          )
                        : Text(
                            _currentStep == 3 ? 'Finalizar & Travar Vistoria' : 'Avançar',
                            style: const TextStyle(fontWeight: FontWeight.black, fontSize: 12, letterSpacing: 0.5),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStepTitle(int step) {
    switch (step) {
      case 0:
        return 'Passo 1: Viatura & Telefone Cautela';
      case 1:
        return 'Passo 2: Fotos dos 4 Lados';
      case 2:
        return 'Passo 3: Checklist Dinâmico';
      case 3:
        return 'Passo 4: Auditoria & Assinatura';
      default:
        return '';
    }
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1VehicleAndOfficer();
      case 1:
        return _buildStep2Photos();
      case 2:
        return _buildStep3Checklist();
      case 3:
        return _buildStep4ReviewAndSign();
      default:
        return const SizedBox();
    }
  }

  // PASSO 1: DADOS INICIAIS
  Widget _buildStep1VehicleAndOfficer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Identificação do Motorista
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.badge_outlined, color: Color(0xFFF59E0B), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'MOTORISTA DO DIA',
                    style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: _buildTextField(label: 'Graduação', controller: _rankController),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: _buildTextField(label: 'Nome de Guerra', controller: _warNameController),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildTextField(label: 'Matrícula / RE', controller: _badgeController),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Viatura, KM e Telefone Cautelado
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.directions_car, color: Color(0xFF3B82F6), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'VIATURA & ESCALA',
                    style: TextStyle(color: Color(0xFF3B82F6), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Dropdown de Viatura
              const Text('Prefixo da Viatura', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _selectedPrefix,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E293B),
                  underline: const SizedBox(),
                  items: _vehicles.map((v) {
                    return DropdownMenuItem(
                      value: v.prefixo,
                      child: Text('${v.prefixo} (${v.modelo})', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) _onVehicleChanged(val);
                  },
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'KM Odômetro',
                      controller: _kmController,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTextField(
                      label: 'Telefone Cautela (Escala)',
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Combustível
              const Text('Nível de Combustível', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: ['Reserva', '1/2', '3/4', 'Cheio'].map((f) {
                  final isSel = _selectedFuel == f;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ChoiceChip(
                        label: Text(f, style: TextStyle(fontSize: 10, color: isSel ? const Color(0xFF0F172A) : Colors.white70, fontWeight: FontWeight.bold)),
                        selected: isSel,
                        selectedColor: const Color(0xFF10B981),
                        backgroundColor: const Color(0xFF1E293B),
                        onSelected: (val) {
                          if (val) setState(() => _selectedFuel = f);
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Mural de Avisos da Viatura
        if (_notices.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign, color: Color(0xFFF59E0B), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'AVISOS DA VIATURA ($_selectedPrefix)',
                      style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._notices.map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_right, color: Color(0xFFF59E0B), size: 16),
                          Expanded(
                            child: Text(
                              n.mensagem,
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
      ],
    );
  }

  // PASSO 2: FOTOS DOS 4 LADOS
  Widget _buildStep2Photos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: const Text(
            'Fotografe os 4 lados da viatura in loco. As fotos recebem carimbo automático de autenticidade.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
        const SizedBox(height: 14),

        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.95,
          children: [
            CameraAngleCard(
              title: 'Frente',
              subtitle: 'Faróis e Placa',
              icon: Icons.arrow_upward,
              photoFile: _photos4Sides['Frente'],
              onPhotoCaptured: (f) => setState(() => _photos4Sides['Frente'] = f),
            ),
            CameraAngleCard(
              title: 'Traseira',
              subtitle: 'Lanternas e Presos',
              icon: Icons.arrow_downward,
              photoFile: _photos4Sides['Traseira'],
              onPhotoCaptured: (f) => setState(() => _photos4Sides['Traseira'] = f),
            ),
            CameraAngleCard(
              title: 'Lat. Esquerda',
              subtitle: 'Portas e Rodas',
              icon: Icons.arrow_back,
              photoFile: _photos4Sides['Esquerda'],
              onPhotoCaptured: (f) => setState(() => _photos4Sides['Esquerda'] = f),
            ),
            CameraAngleCard(
              title: 'Lat. Direita',
              subtitle: 'Portas e Tanque',
              icon: Icons.arrow_forward,
              photoFile: _photos4Sides['Direita'],
              onPhotoCaptured: (f) => setState(() => _photos4Sides['Direita'] = f),
            ),
          ],
        ),
      ],
    );
  }

  // PASSO 3: CHECKLIST DINÂMICO
  Widget _buildStep3Checklist() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ITENS DE VERIFICAÇÃO',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _markAllAsOk,
              icon: const Icon(Icons.done_all, color: Color(0xFF10B981), size: 16),
              label: const Text('Marcar Todos OK', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ..._checklistConfigs.map((cfg) {
          final ans = _answers[cfg.id] ?? ChecklistAnswer(itemId: cfg.id);
          return ChecklistItemCard(
            config: cfg,
            answer: ans,
            onStatusChanged: (st) {
              setState(() {
                ans.status = st;
                _answers[cfg.id] = ans;
              });
            },
            onDescriptionChanged: (desc) {
              ans.descricao = desc;
              _answers[cfg.id] = ans;
            },
            onPhotoCaptured: (file) {
              setState(() {
                ans.localPhotoPath = file.path;
                _answers[cfg.id] = ans;
              });
            },
          );
        }),
      ],
    );
  }

  // PASSO 4: AUDITORIA & ASSINATURA
  Widget _buildStep4ReviewAndSign() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // BANNER DE AUDITORIA DE SINISTRO OMITIDO
        if (_previousSummary != null)
          AuditAlertBanner(
            previousSummary: _previousSummary!,
            allConfigs: _checklistConfigs,
            currentAnswers: _answers,
          ),

        // Resumo dos Dados
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Vistoria:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  Text(_selectedPrefix, style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Condutor:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  Text('${_rankController.text} ${_warNameController.text} (Mat. ${_badgeController.text})', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Telefone Escala:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  Text(_phoneController.text, style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Pad de Assinatura com o Dedo
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ASSINATURA DIGITAL DO MOTORISTA',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () => _sigController.clear(),
                    child: const Text('Limpar', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF070B19),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Signature(
                  controller: _sigController,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFF1E293B),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}
