// lib/models/models.dart

class Officer {
  final String matricula;
  final String nomeGuerra;
  final String postoGraduacao;
  final String? telefone;
  final String role;

  Officer({
    required this.matricula,
    required this.nomeGuerra,
    required this.postoGraduacao,
    this.telefone,
    required this.role,
  });

  factory Officer.fromJson(Map<String, dynamic> json) {
    return Officer(
      matricula: json['matricula'] ?? '',
      nomeGuerra: json['nome_guerra'] ?? '',
      postoGraduacao: json['posto_graduacao'] ?? '',
      telefone: json['telefone_funcional'],
      role: json['role'] ?? 'motorista',
    );
  }

  String get displayName => '$postoGraduacao $nomeGuerra';
}

class Vehicle {
  final String prefixo;
  final String modelo;
  final String placa;
  final int kmAtual;
  final String nivelCombustivel;
  final String status;

  Vehicle({
    required this.prefixo,
    required this.modelo,
    required this.placa,
    required this.kmAtual,
    required this.nivelCombustivel,
    required this.status,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      prefixo: json['prefixo'] ?? '',
      modelo: json['modelo'] ?? '',
      placa: json['placa'] ?? '',
      kmAtual: json['km_atual'] ?? 0,
      nivelCombustivel: json['nivel_combustivel_atual'] ?? '3/4',
      status: json['status_operacional'] ?? 'ativa',
    );
  }
}

class VehicleNotice {
  final String id;
  final String prefixoVtr;
  final String titulo;
  final String mensagem;
  final String severidade;

  VehicleNotice({
    required this.id,
    required this.prefixoVtr,
    required this.titulo,
    required this.mensagem,
    required this.severidade,
  });

  factory VehicleNotice.fromJson(Map<String, dynamic> json) {
    return VehicleNotice(
      id: json['id'] ?? '',
      prefixoVtr: json['prefixo_vtr'] ?? '',
      titulo: json['titulo'] ?? '',
      mensagem: json['mensagem'] ?? '',
      severidade: json['severidade'] ?? 'info',
    );
  }
}

class ChecklistItemConfig {
  final String id;
  final String categoria;
  final String titulo;
  final String? descricao;
  final bool obrigatorio;
  final bool exigeFotoSeAlterado;
  final bool ativo;

  ChecklistItemConfig({
    required this.id,
    required this.categoria,
    required this.titulo,
    this.descricao,
    required this.obrigatorio,
    required this.exigeFotoSeAlterado,
    required this.ativo,
  });

  factory ChecklistItemConfig.fromJson(Map<String, dynamic> json) {
    return ChecklistItemConfig(
      id: json['id'] ?? '',
      categoria: json['categoria'] ?? 'Geral',
      titulo: json['titulo'] ?? '',
      descricao: json['descricao'],
      obrigatorio: json['obrigatorio'] ?? true,
      exigeFotoSeAlterado: json['exige_foto_se_alterado'] ?? true,
      ativo: json['ativo'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'categoria': categoria,
      'titulo': titulo,
      'descricao': descricao,
      'obrigatorio': obrigatorio,
      'exige_foto_se_alterado': exigeFotoSeAlterado,
      'ativo': ativo,
    };
  }
}

class ChecklistAnswer {
  final String itemId;
  String status; // 'OK' | 'ALTERACAO' | 'NA'
  String? descricao;
  String? localPhotoPath;
  String? uploadedPhotoUrl;

  ChecklistAnswer({
    required this.itemId,
    this.status = 'OK',
    this.descricao,
    this.localPhotoPath,
    this.uploadedPhotoUrl,
  });
}

class PreviousInspectionSummary {
  final String? id;
  final String driverRankAndName;
  final String driverBadge;
  final String driverPhone;
  final int kmOdometro;
  final String dataHoraFormatada;
  final List<String> itemsWithAlteration;

  PreviousInspectionSummary({
    this.id,
    required this.driverRankAndName,
    required this.driverBadge,
    required this.driverPhone,
    required this.kmOdometro,
    required this.dataHoraFormatada,
    required this.itemsWithAlteration,
  });
}
