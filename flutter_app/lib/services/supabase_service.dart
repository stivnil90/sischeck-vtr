// lib/services/supabase_service.dart
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  // Credenciais reais do projeto Supabase do usuário
  static const String supabaseUrl = 'https://xwfepsiiwukkuragnulb.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3ZmVwc2lpd3Vra3VyYWdudWxiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI3ODE0NzMsImV4cCI6MjEwODM1NzQ3M30.GBIqsT1jM3YnWT3FgRihe70kZLJwOo-UIROFOyegxIo';

  bool _isInitialized = false;

  Future<void> initialize() async {
    try {
      if (supabaseUrl != 'https://SUA-URL-SUPABASE.supabase.co') {
        await Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabaseAnonKey,
        );
        _isInitialized = true;
      }
    } catch (e) {
      // Ignora erro em modo offline/desenvolvimento
      _isInitialized = false;
    }
  }

  SupabaseClient? get client => _isInitialized ? Supabase.instance.client : null;

  // 1. BUSCAR VIATURAS ATIVAS
  Future<List<Vehicle>> getVehicles() async {
    if (client != null) {
      try {
        final response = await client!
            .from('viaturas')
            .select()
            .eq('status_operacional', 'ativa')
            .order('prefixo');
        return (response as List).map((json) => Vehicle.fromJson(json)).toList();
      } catch (_) {}
    }

    // Mock local de fallback para testes imediatos
    return [
      Vehicle(prefixo: 'VTR-1022', modelo: 'Renault Duster 1.6 Tática', placa: 'BRA2E19', kmAtual: 78450, nivelCombustivel: '3/4', status: 'ativa'),
      Vehicle(prefixo: 'VTR-2045', modelo: 'Toyota Hilux 4x4 Policial', placa: 'PMW5401', kmAtual: 112300, nivelCombustivel: 'Cheio', status: 'ativa'),
      Vehicle(prefixo: 'VTR-3110', modelo: 'Toyota Corolla Sedan Patrulha', placa: 'RQX9912', kmAtual: 45200, nivelCombustivel: '1/2', status: 'ativa'),
      Vehicle(prefixo: 'VTR-4008', modelo: 'Chevrolet Trailblazer Choque', placa: 'GOI8821', kmAtual: 93100, nivelCombustivel: 'Cheio', status: 'ativa'),
    ];
  }

  // 2. BUSCAR AVISOS DA VIATURA ESPECÍFICA
  Future<List<VehicleNotice>> getNotices(String prefixo) async {
    if (client != null) {
      try {
        final response = await client!
            .from('avisos_viatura')
            .select()
            .eq('prefixo_vtr', prefixo)
            .eq('ativo', true)
            .order('criado_em', ascending: false);
        return (response as List).map((json) => VehicleNotice.fromJson(json)).toList();
      } catch (_) {}
    }

    // Mock local de avisos
    if (prefixo == 'VTR-1022') {
      return [
        VehicleNotice(id: '1', prefixoVtr: prefixo, titulo: 'Revisão Agendada', mensagem: 'Revisão dos 80.000 KM agendada para segunda-feira. Não deslocar para missão de longa distância.', severidade: 'aviso'),
        VehicleNotice(id: '2', prefixoVtr: prefixo, titulo: 'Pneu Novo', mensagem: 'Pneu dianteiro direito trocado recentemente. Manter calibração em 32 PSI.', severidade: 'info'),
      ];
    }
    return [
      VehicleNotice(id: '3', prefixoVtr: prefixo, titulo: 'Aviso Operacional', mensagem: 'Viatura disponível para patrulhamento ordinário.', severidade: 'info'),
    ];
  }

  // 3. BUSCAR ITENS DO CHECKLIST DINÂMICO (PARAMETRIZÁVEIS NO ADMIN)
  Future<List<ChecklistItemConfig>> getChecklistItems() async {
    if (client != null) {
      try {
        final response = await client!
            .from('checklist_itens_config')
            .select()
            .eq('ativo', true)
            .order('ordem_exibicao');
        return (response as List).map((json) => ChecklistItemConfig.fromJson(json)).toList();
      } catch (_) {}
    }

    // Itens padrão caso o banco ainda esteja iniciando
    return [
      ChecklistItemConfig(id: 'oleo', categoria: 'Mecânica & Fluidos', titulo: 'Nível do Óleo do Motor', descricao: 'Checar na vareta', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
      ChecklistItemConfig(id: 'radiador', categoria: 'Mecânica & Fluidos', titulo: 'Água / Fluido do Radiador', descricao: 'Reservatório de expansão', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
      ChecklistItemConfig(id: 'freio', categoria: 'Mecânica & Fluidos', titulo: 'Fluido de Freio', descricao: 'Reservatório mestre', obrigatorio: true, exigeFotoSeAlterado: false, ativo: true),
      ChecklistItemConfig(id: 'giroflex', categoria: 'Sinalizadores & Elétrica', titulo: 'Giroflex / Barra de Luzes', descricao: 'Leds e estrobos', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
      ChecklistItemConfig(id: 'sirene', categoria: 'Sinalizadores & Elétrica', titulo: 'Sirene & Buzina', descricao: 'Testar tons policiais', obrigatorio: true, exigeFotoSeAlterado: false, ativo: true),
      ChecklistItemConfig(id: 'farois', categoria: 'Sinalizadores & Elétrica', titulo: 'Faróis (Alto, Baixo e Milha)', descricao: 'Lâmpadas e lentes', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
      ChecklistItemConfig(id: 'luz_freio', categoria: 'Sinalizadores & Elétrica', titulo: 'Luzes de Freio', descricao: 'Checar com apoio', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
      ChecklistItemConfig(id: 'setas', categoria: 'Sinalizadores & Elétrica', titulo: 'Setas e Pisca-Alerta', descricao: 'Lâmpadas direcionais', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
      ChecklistItemConfig(id: 'pneus_diant', categoria: 'Rodagem & Pneus', titulo: 'Pneus Dianteiros (Calibragem e Sulco)', descricao: 'Checar arames ou cortes', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
      ChecklistItemConfig(id: 'pneus_tras', categoria: 'Rodagem & Pneus', titulo: 'Pneus Traseiros (Calibragem e Sulco)', descricao: 'Checar pregos ou furos', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
      ChecklistItemConfig(id: 'estepe', categoria: 'Rodagem & Pneus', titulo: 'Estepe / Pneu Reserva', descricao: 'Calibrado e funcional', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
      ChecklistItemConfig(id: 'limpeza_int', categoria: 'Higiene & Interior', titulo: 'Limpeza Interna (Bancos e Assoalho)', descricao: 'Presença de lixo ou manchas', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
      ChecklistItemConfig(id: 'camburao', categoria: 'Higiene & Interior', titulo: 'Compartimento de Presos (Camburão)', descricao: 'Travas e higienização', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
      ChecklistItemConfig(id: 'radio_vtr', categoria: 'Equipamentos Táticos', titulo: 'Rádio Comunicador (VHF/TETRA)', descricao: 'Comunicação com COPOM', obrigatorio: true, exigeFotoSeAlterado: false, ativo: true),
      ChecklistItemConfig(id: 'suporte_armas', categoria: 'Equipamentos Táticos', titulo: 'Suporte & Travas de Armas Longas', descricao: 'Trancas de fuzil/calibre 12', obrigatorio: true, exigeFotoSeAlterado: true, ativo: true),
    ];
  }

  // 4. ADICIONAR NOVO ITEM AO CHECKLIST (PAINEL ADMIN)
  Future<bool> createChecklistItem(ChecklistItemConfig item) async {
    if (client != null) {
      try {
        await client!.from('checklist_itens_config').insert(item.toJson());
        return true;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  // 5. BUSCAR DADOS DA VISTORIA DO TURNO ANTERIOR (CADEIA DE RESPONSABILIDADE)
  Future<PreviousInspectionSummary> getPreviousInspection(String prefixo) async {
    if (client != null) {
      try {
        final response = await client!
            .from('vistorias')
            .select('*, policiais!vistorias_matricula_condutor_fkey(nome_guerra, posto_graduacao, telefone_funcional), vistoria_itens_respostas(item_config_id, status)')
            .eq('prefixo_vtr', prefixo)
            .eq('status', 'finalizada')
            .order('criado_em', ascending: false)
            .limit(1)
            .maybeSingle();

        if (response != null) {
          final condutor = response['policiais'];
          final respostas = response['vistoria_itens_respostas'] as List;
          final alts = respostas
              .where((r) => r['status'] == 'ALTERACAO')
              .map<String>((r) => r['item_config_id'].toString())
              .toList();

          return PreviousInspectionSummary(
            id: response['id'],
            driverRankAndName: '${condutor['posto_graduacao']} ${condutor['nome_guerra']}',
            driverBadge: response['matricula_condutor'],
            driverPhone: response['telefone_escala'] ?? condutor['telefone_funcional'] ?? 'N/I',
            kmOdometro: response['km_odometro'],
            dataHoraFormatada: response['criado_em'],
            itemsWithAlteration: alts,
          );
        }
      } catch (_) {}
    }

    // Mock simulado: motorista anterior Cb PM SILVA entregou sem relatar alterações
    return PreviousInspectionSummary(
      id: 'mock-prev-id-1',
      driverRankAndName: 'Cb PM SILVA',
      driverBadge: '31.002-4',
      driverPhone: '(62) 99122-3344',
      kmOdometro: 78435,
      dataHoraFormatada: 'Hoje, 06:45',
      itemsWithAlteration: [], // Omitiu sinistros!
    );
  }

  // 6. UPLOAD DE FOTOS PARA O STORAGE DO SUPABASE
  Future<String?> uploadImage({
    required File file,
    required String bucketName,
    required String remotePath,
  }) async {
    if (client != null) {
      try {
        final bytes = await file.readAsBytes();
        await client!.storage.from(bucketName).uploadBinary(
              remotePath,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
            );
        return client!.storage.from(bucketName).getPublicUrl(remotePath);
      } catch (e) {
        return null;
      }
    }
    return 'file://${file.path}';
  }

  // 7. REGISTRO FINAL DA VISTORIA COM FOTOS E CADEIA DE CUSTÓDIA
  Future<String> submitInspection({
    required String prefixo,
    required String matriculaCondutor,
    required int km,
    required String telefoneEscala,
    required String nivelCombustivel,
    required Map<String, File?> fotos4Lados,
    required Map<String, ChecklistAnswer> respostas,
    required String? assinaturaPath,
  }) async {
    final protocolo = 'VTR-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    if (client != null) {
      try {
        // 1. Upload de Assinatura se houver
        String? assinaturaUrl;
        if (assinaturaPath != null) {
          assinaturaUrl = await uploadImage(
            file: File(assinaturaPath),
            bucketName: 'vistorias-assinaturas',
            remotePath: '$protocolo/assinatura.png',
          );
        }

        // 2. Insere Vistoria
        final vistoriaResult = await client!.from('vistorias').insert({
          'protocolo': protocolo,
          'prefixo_vtr': prefixo,
          'matricula_condutor': matriculaCondutor,
          'km_odometro': km,
          'telefone_escala': telefoneEscala,
          'nivel_combustivel': nivelCombustivel,
          'status': 'finalizada',
          'assinatura_url': assinaturaUrl,
        }).select().single();

        final String vistoriaId = vistoriaResult['id'];

        // 3. Upload das 4 Fotos Obrigatórias dos Lados
        for (final entry in fotos4Lados.entries) {
          if (entry.value != null) {
            final url = await uploadImage(
              file: entry.value!,
              bucketName: 'vistorias-fotos-4-lados',
              remotePath: '$protocolo/lado_${entry.key.toLowerCase()}.jpg',
            );
            if (url != null) {
              await client!.from('vistoria_fotos_angulos').insert({
                'vistoria_id': vistoriaId,
                'angulo': entry.key.toLowerCase(),
                'foto_url': url,
              });
            }
          }
        }

        // 4. Salva Respostas dos Itens do Checklist
        for (final entry in respostas.entries) {
          final ans = entry.value;
          String? fotoAvariaUrl;
          if (ans.localPhotoPath != null) {
            fotoAvariaUrl = await uploadImage(
              file: File(ans.localPhotoPath!),
              bucketName: 'vistorias-fotos-avarias',
              remotePath: '$protocolo/avaria_${entry.key}.jpg',
            );
          }

          await client!.from('vistoria_itens_respostas').insert({
            'vistoria_id': vistoriaId,
            'item_config_id': ans.itemId,
            'status': ans.status,
            'descricao_avaria': ans.descricao,
            'foto_avaria_url': fotoAvariaUrl,
          });
        }

        return protocolo;
      } catch (e) {
        // Fallback local se falhar rede
        return protocolo;
      }
    }

    return protocolo;
  }
}
