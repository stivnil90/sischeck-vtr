// lib/screens/admin_screen.dart
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';

class AdminScreen extends StatefulWidget {
  final VoidCallback onBackToDriver;

  const AdminScreen({super.key, required this.onBackToDriver});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ChecklistItemConfig> _items = [];
  bool _isLoading = true;

  // Controladores para novo item
  final _titleController = TextEditingController();
  String _selectedCategory = 'Mecânica & Fluidos';
  bool _requirePhoto = true;

  final List<String> _categories = [
    'Mecânica & Fluidos',
    'Sinalizadores & Elétrica',
    'Rodagem & Pneus',
    'Higiene & Interior',
    'Equipamentos Táticos',
    'Outros'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadItems();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    final items = await SupabaseService.instance.getChecklistItems();
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _addItem() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final newItem = ChecklistItemConfig(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      categoria: _selectedCategory,
      titulo: title,
      obrigatorio: true,
      exigeFotoSeAlterado: _requirePhoto,
      ativo: true,
    );

    await SupabaseService.instance.createChecklistItem(newItem);
    _titleController.clear();
    await _loadItems();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Item "$title" adicionado com sucesso!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1329),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBackToDriver,
        ),
        title: const Text(
          'Painel Administrativo',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFF59E0B),
          labelColor: const Color(0xFFF59E0B),
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(text: 'Itens do Checklist'),
            Tab(text: 'Auditoria de Sinistros'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildChecklistManagementTab(),
                _buildAuditTab(),
              ],
            ),
    );
  }

  Widget _buildChecklistManagementTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card de Cadastro de Novo Item
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
                    Icon(Icons.add_circle, color: Color(0xFFF59E0B), size: 18),
                    SizedBox(width: 6),
                    Text(
                      'ACRESCENTAR NOVO ITEM DE VISTORIA',
                      style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Como surgem novas alterações na rotina, cadastre aqui para sincronizar com os celulares dos policiais imediatamente.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 12),

                // Campo Nome do Item
                TextField(
                  controller: _titleController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Ex: Câmera Corporal, Suporte Fuzil, Luz de Ré...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),

                // Categoria e Switch Foto
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          isExpanded: true,
                          underline: const SizedBox(),
                          dropdownColor: const Color(0xFF1E293B),
                          items: _categories.map((c) {
                            return DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(color: Colors.white, fontSize: 11)));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedCategory = val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Checkbox(
                      value: _requirePhoto,
                      activeColor: const Color(0xFFF59E0B),
                      onChanged: (v) => setState(() => _requirePhoto = v ?? true),
                    ),
                    const Expanded(
                      child: Text(
                        'Exigir foto quando o motorista marcar "Alteração"',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                ElevatedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Salvar no Checklist Dinâmico', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: const Color(0xFF0F172A),
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Lista de Itens Existentes
          Text(
            'ITENS ATIVOS NO APLICATIVO (${_items.length})',
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          ..._items.map((it) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.titulo, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          Text('${it.categoria} • ${it.exigeFotoSeAlterado ? 'Exige foto' : 'Sem foto'}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                    ),
                    const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildAuditTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF450A0A).withOpacity(0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEF4444)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.gavel, color: Color(0xFFEF4444), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'SINISTRO NÃO NOTIFICADO DETECTADO',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'Viatura: VTR-1022 | Data: Hoje, 07:15',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Text(
                'Motorista Anterior (Não Informou): Cb PM SILVA (Mat. 31.002-4)',
                style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11),
              ),
              Text(
                'Motorista Atual (Apontou Sinistro): Cb PM ALMEIDA (Mat. 39.412-8)',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Divider(color: Color(0xFFEF4444), height: 16),
              Text(
                'Avaria: Luz de Freio & Lanterna Traseira Direita Danificada',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
              SizedBox(height: 8),
              Text(
                'Status: Notificação enviada ao Oficial de Dia para Sindicância Administrativa.',
                style: TextStyle(color: Colors.white54, fontSize: 10, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
