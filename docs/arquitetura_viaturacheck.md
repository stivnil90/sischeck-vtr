# Especificação e Arquitetura do Sistema: SisCheck-VTR
## Sistema Integrado de Vistoria, Cautela e Cadeia de Responsabilidade de Viaturas

---

### 1. Visão Geral e Objetivo Operacional
O **SisCheck-VTR** é uma solução voltada para a rotina operacional das forças de segurança pública e policiamento, resolvendo um dos maiores gargalos da gestão de frotas policiais: **a atribuição clara e tempestiva de responsabilidade sobre danos, avarias e falta de manutenção**.

A verificação ocorre **in loco** no momento da passagem e assunção do serviço policial (cautela da viatura). O motorista que assume o plantão tem total interesse e respaldo para apontar qualquer sinistro preexistente, resguardando sua equipe e responsabilizando formalmente o condutor do turno anterior que omitiu a avaria.

---

### 2. Fluxo Operacional de Assunção de Serviço (Passo a Passo)

```mermaid
flowchart TD
    A["Policial Motorista abre o App no Celular"] --> B["Identificação: Matrícula, Nome de Guerra e Prefixo da Viatura"]
    B --> C["Registro Inicial: KM Atual, Nível de Combustível, Celular da Escala"]
    C --> D["Mural de Avisos da Viatura (Pendências registradas, avisos da manutenção)"]
    D --> E["Captura dos 4 Lados Obrigatórios (Frente, Traseira, Lat. Esquerda, Lat. Direita)"]
    E --> F["Checklist Dinâmico de Itens Operacionais (Óleo, Água, Freio, Pneus, Sinais, etc.)"]
    F --> G{"Detectou Alteração / Avaria Nova?"}
    G -- Sim --> H["Tica 'Com Alteração' + Foto da Avaria + Descrição Detalhada"]
    H --> I["Cruza com Vistoria do Turno Anterior"]
    I --> J["Gera Alerta Automático de Sinistro Omitido pelo Condutor Anterior"]
    G -- Não --> K["Tica 'Conforme / OK'"]
    J --> L["Revisão Final e Assinatura Digital do Condutor"]
    K --> L
    L --> M["Armazenamento em Nuvem / Local + Geração do Termo de Vistoria Imutável"]
```

---

### 3. Pilares Fundamentais do Aplicativo

#### A. Registro Fotográfico dos 4 Lados (Obrigatório)
No ato da inspeção, a interface guia o motorista com silhuetas/instruções para fotografar:
1. **Frente:** Placa, grade frontal, faróis, capô e para-brisa.
2. **Traseira:** Placa traseira, lanternas, tampa do porta-malas / compartimento de presos e para-choque.
3. **Lateral Esquerda:** Portas, retrovisor, pneus/rodas, vidros e adesivagem tática.
4. **Lateral Direita:** Portas, retrovisor, pneus/rodas, tampa do tanque de combustível.

> [!NOTE]
> As fotos recebem carimbo digital (Watermark) automático contendo: Prefixo da Viatura, Data/Hora sincronizada com servidor, KM informado e Matrícula do condutor.

#### B. Checklist Dinâmico e Customizável (Painel Administrativo)
Como novas avarias e necessidades surgem com frequência, o administrador pode criar ou editar itens sem necessidade de atualizar o aplicativo:
* **Mecânica & Fluidos:** Nível de óleo do motor, água do radiador, fluido de freio, bateria.
* **Sinalizadores & Elétrica:** Giroflex/barra de luzes, sirene policial e comandos de áudio, estrobos, faróis altos/baixos, luzes de freio, setas e pisca-alerta.
* **Rodagem & Acessórios:** Pressão dos pneus, estepe, macaco hidráulico, chave de roda, triângulo.
* **Compartimento e Higiene:** Limpeza interna (bancos/assoalho), compartimento de contenção de presos (cubículo/camburão), travas e cintos.
* **Comunicação & Armamento:** Rádio transceptor fixo (VHF/TETRA), suporte/trava de armas longas (fuzil/espingarda), lanterna tática acoplada.

Para cada item com alteração, o policial clica em **"Adicionar Foto da Alteração"** e detalha o ocorrido.

#### C. Cadeia de Custódia e Cruzamento de Responsabilidade
Quando um condutor finaliza o checklist com uma nova avaria:
1. O sistema busca automaticamente o **último checklist fechado para aquele prefixo**.
2. Compara se o item já havia sido apontado pelo motorista anterior.
3. Se **NÃO** constava no checklist anterior:
   - O sistema gera uma **Notificação de Avaria Não Informada**.
   - Vincula imediatamente:
     - Motorista anterior (Matrícula, Nome, Telefone da escala anterior, Data/Hora da devolução).
     - Motorista atual que identificou o sinistro.
     - Registro fotográfico do antes vs depois.
   - Fornece subsídio probatório pronto para o Encarregado de Transporte ou Corregedoria.

---

### 4. Modelo de Entidades e Banco de Dados (ERD)

```mermaid
erDiagram
    VIATURA ||--o{ VISTORIA : possui
    POLICIAL ||--o{ VISTORIA : realiza
    VISTORIA ||--|{ VISTORIA_ITEM : contem
    CHECKLIST_TEMPLATE ||--|{ CHECKLIST_ITEM_DEF : define
    CHECKLIST_ITEM_DEF ||--o{ VISTORIA_ITEM : referencia
    VISTORIA ||--o{ FOTO_VIATURA : registra
    VISTORIA ||--o{ ALERTA_SINISTRO : pode_gerar

    VIATURA {
        string prefixo PK
        string modelo
        string placa
        int km_atual
        string status_operacional
        string avisos_ativos
    }

    POLICIAL {
        string matricula PK
        string nome_de_guerra
        string posto_graduacao
        string telefone_contato
        string funcao
    }

    VISTORIA {
        uuid id PK
        string prefixo_vtr FK
        string matricula_condutor FK
        int km_inicial
        string telefone_cautelado
        string nivel_combustivel
        datetime data_hora
        string status_inspecao
        string assinatura_base64
        string hash_comprovante
    }

    VISTORIA_ITEM {
        uuid id PK
        uuid vistoria_id FK
        string item_def_id FK
        string status "OK / ALTERACAO / NA"
        string observacao
        string foto_avaria_url
    }

    CHECKLIST_ITEM_DEF {
        string id PK
        string categoria
        string titulo
        string descricao
        boolean obrigatorio
        boolean ativo
    }

    FOTO_VIATURA {
        uuid id PK
        uuid vistoria_id FK
        string posicao "FRENTE / TRASEIRA / ESQUERDA / DIREITA"
        string foto_url
        datetime data_captura
    }

    ALERTA_SINISTRO {
        uuid id PK
        uuid vistoria_atual_id FK
        uuid vistoria_anterior_id FK
        string item_afetado
        string matricula_responsavel_anterior
        datetime data_deteccao
        string status "PENDENTE / EM_ANALISE / JUSTIFICADO"
    }
```

---

### 5. Requisitos de Interface Mobile (In Loco)
* **Design Tático e Rápido:** Interface de alto contraste, tipografia legível sob luz solar direta, botões táteis largos (para uso até mesmo com luvas táticas).
* **Captura de Câmera Fluida:** Compactação de imagens localmente no dispositivo para não travar a memória nem onerar dados 4G/5G.
* **Modo Offline Resiliente:** Operação em áreas sem sinal de internet (batalhões remotos ou zonas rurais); sincronização automática assim que houver rede.
* **Assinatura na Tela:** O policial assina com o dedo diretamente no celular antes de submeter o checklist.
