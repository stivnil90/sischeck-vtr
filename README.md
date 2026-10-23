# SisCheck-VTR | Sistema de Gestão de Viaturas, Vistoria Operacional & Cadeia de Custódia

Sistema integrado para gestão de frota policial, vistoria in loco (mobile), controle preventivo de manutenção e responsabilização formal de condutores por avarias não comunicadas.

---

## 🚔 Principais Módulos do Sistema

### 1. Vistoria In Loco (Motorista do Dia)
- **Wizard Mobile Tático:** Interface otimizada para uso com uma mão em celulares durante a passagem de serviço.
- **Registro Fotográfico Obrigatório dos 4 Lados:** Frente, Traseira, Lateral Esquerda e Lateral Direita com carimbo tático d'água (Prefixo, Data/Hora, KM e Condutor).
- **Checklist Dinâmico:** Checagem de óleo, água, freios, luzes, giroflex, sirene, pneus, compartimento de presos e armamento.
- **Evidências de Avarias:** Campo dedicado para fotografar e descrever avarias pontuais.
- **Assinatura Digital:** Assinatura na tela do celular com protocolo imutável.

### 2. Cadeia de Custódia & Responsabilidade
- O sistema cruza automaticamente os dados da vistoria atual com o último checklist entregue pelo motorista anterior.
- Se uma avaria for detectada e **não constava** na vistoria anterior, o sistema identifica o policial anterior como responsável e abre uma notificação de sindicância/averiguação disciplinar.

### 3. Controle Inteligente de Troca de Óleo & Revisões
- **Regra Híbrida (KM e/ou Tempo):** Controla a vida útil do óleo a cada **10.000 KM ou 6 meses (180 dias)**, o que vencer primeiro.
- **Alertas Automáticos:**
  - 🟢 **Em dia:** Manutenção regular.
  - 🟡 **Próximo:** Menos de 1.000 KM ou menos de 20 dias restantes.
  - 🔴 **Vencido / Urgente:** KM ou prazo expirados com bloqueio de missões de longa distância.

### 4. Dashboard do Chefe de Transporte
- Visão panorâmica dos indicadores (KPIs) da frota.
- Tabela com barra de vida útil de óleo por viatura e botão para registrar a execução de trocas.
- Cadastro de novas viaturas.
- Gestor dinâmico de novos itens de checklist (permite criar novos itens sem alterar código).
- Mural de avisos por prefixo de viatura.

---

## 📁 Estrutura do Repositório

```text
sischeck-vtr/
├── web/
│   └── index.html                # Aplicativo Web PWA pronto para execução direta
├── flutter_app/
│   ├── pubspec.yaml              # Dependências do app nativo Flutter
│   ├── lib/
│   │   ├── main.dart             # Entrada do app tático
│   │   ├── models/               # Modelos de dados
│   │   ├── screens/              # Telas de vistoria e admin
│   │   ├── services/             # Integração Supabase
│   │   └── widgets/              # Widgets especializados (câmera, assinatura, banners)
│   └── android/                  # Configuração nativa Android (permissões de câmera)
├── database/
│   └── supabase_schema.sql       # Script SQL completo com tabelas, RLS e gatilhos
└── docs/
    └── arquitetura_viaturacheck.md # Especificação técnica completa
```

---

## ☁️ Conexão Supabase

O projeto está configurado para o Supabase:
- **Tabelas:** `viaturas`, `policiais`, `avisos_viatura`, `checklist_itens_config`, `vistorias`, `vistoria_fotos_angulos`, `vistoria_itens_respostas`, `sinistros_nao_notificados`.
- **Gatilho:** `trg_auditoria_vistoria` (processa automaticamente a auditoria de sinistros omitidos a cada vistoria finalizada).
- **Storage:** Buckets para fotos dos 4 lados, fotos das avarias e assinaturas.
