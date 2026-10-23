-- ==============================================================================
-- SISCHECK-VTR: SCHEMA POSTGRESQL PARA SUPABASE
-- Sistema de Gestão de Viaturas, Checklist Dinâmico e Cadeia de Responsabilidade
-- ==============================================================================

-- 1. EXTENSÕES
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. TABELA DE POLICIAIS / USUÁRIOS DO SISTEMA
CREATE TABLE IF NOT EXISTS public.policiais (
    matricula VARCHAR(20) PRIMARY KEY,
    nome_guerra VARCHAR(100) NOT NULL,
    posto_graduacao VARCHAR(50) NOT NULL, -- Ex: 'Sd PM', 'Cb PM', '3º Sgt PM', 'Oficial'
    telefone_funcional VARCHAR(30),
    role VARCHAR(20) DEFAULT 'motorista' CHECK (role IN ('motorista', 'admin', 'fiscal_frota')),
    ativo BOOLEAN DEFAULT TRUE,
    criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- 3. TABELA DE VIATURAS
CREATE TABLE IF NOT EXISTS public.viaturas (
    prefixo VARCHAR(20) PRIMARY KEY, -- Ex: 'VTR-1022'
    modelo VARCHAR(100) NOT NULL,   -- Ex: 'Renault Duster 1.6'
    placa VARCHAR(10) NOT NULL,
    km_atual INTEGER NOT NULL DEFAULT 0,
    nivel_combustivel_atual VARCHAR(20) DEFAULT '3/4',
    status_operacional VARCHAR(30) DEFAULT 'ativa' CHECK (status_operacional IN ('ativa', 'manutencao', 'baixada', 'reserva')),
    
    -- Controle Preventivo de Troca de Óleo e Revisões (Tempo e/ou KM)
    km_ultima_troca_oleo INTEGER NOT NULL DEFAULT 0,
    data_ultima_troca_oleo DATE DEFAULT CURRENT_DATE,
    intervalo_troca_oleo_km INTEGER NOT NULL DEFAULT 10000, -- Ex: a cada 10.000 KM
    intervalo_troca_oleo_dias INTEGER NOT NULL DEFAULT 180,  -- Ex: a cada 6 meses (180 dias)
    proxima_revisao_geral_km INTEGER DEFAULT 80000,
    
    criado_em TIMESTAMPTZ DEFAULT NOW(),
    atualizado_em TIMESTAMPTZ DEFAULT NOW()
);

-- 4. TABELA DE AVISOS E INFORMATIVOS POR VIATURA (Cadastrado pelo Admin)
CREATE TABLE IF NOT EXISTS public.avisos_viatura (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    prefixo_vtr VARCHAR(20) NOT NULL REFERENCES public.viaturas(prefixo) ON DELETE CASCADE,
    titulo VARCHAR(150) NOT NULL,
    mensagem TEXT NOT NULL,
    severidade VARCHAR(20) DEFAULT 'info' CHECK (severidade IN ('info', 'aviso', 'urgente')),
    ativo BOOLEAN DEFAULT TRUE,
    criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- 5. TABELA DE DEFINIÇÃO DOS ITENS DO CHECKLIST (DINÂMICO)
-- Permite que o Painel Admin acrescente novas alterações sem alterar o código do app!
CREATE TABLE IF NOT EXISTS public.checklist_itens_config (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    categoria VARCHAR(50) NOT NULL, -- 'Mecânica & Fluidos', 'Sinalizadores & Elétrica', 'Rodagem & Pneus', etc.
    titulo VARCHAR(150) NOT NULL,   -- 'Luz de Freio', 'Nível do Óleo', 'Sujeira Interna'
    descricao TEXT,
    obrigatorio BOOLEAN DEFAULT TRUE,
    exige_foto_se_alterado BOOLEAN DEFAULT TRUE,
    ordem_exibicao INTEGER DEFAULT 0,
    ativo BOOLEAN DEFAULT TRUE,
    criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- 6. TABELA MESTRE DE VISTORIAS / PASSAGEM DE SERVIÇO
CREATE TABLE IF NOT EXISTS public.vistorias (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    protocolo VARCHAR(50) UNIQUE NOT NULL, -- Ex: 'VTR-20261023-8941'
    prefixo_vtr VARCHAR(20) NOT NULL REFERENCES public.viaturas(prefixo),
    matricula_condutor VARCHAR(20) NOT NULL REFERENCES public.policiais(matricula),
    km_odometro INTEGER NOT NULL,
    telefone_escala VARCHAR(30) NOT NULL, -- Telefone cautelado para a escala de serviço
    nivel_combustivel VARCHAR(20) NOT NULL, -- 'Reserva', '1/4', '1/2', '3/4', 'Cheio'
    data_hora_abertura TIMESTAMPTZ DEFAULT NOW(),
    data_hora_fechamento TIMESTAMPTZ,
    status VARCHAR(20) DEFAULT 'finalizada' CHECK (status IN ('em_andamento', 'finalizada', 'cancelada')),
    
    -- Dados da vistoria anterior para rastreabilidade
    vistoria_anterior_id UUID REFERENCES public.vistorias(id),
    matricula_condutor_anterior VARCHAR(20) REFERENCES public.policiais(matricula),
    
    -- Assinatura e integridade
    assinatura_url TEXT,
    hash_autenticidade VARCHAR(128),
    criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- 7. TABELA DE FOTOS DOS 4 LADOS OBRIGATÓRIOS DA VIATURA
CREATE TABLE IF NOT EXISTS public.vistoria_fotos_angulos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vistoria_id UUID NOT NULL REFERENCES public.vistorias(id) ON DELETE CASCADE,
    angulo VARCHAR(30) NOT NULL CHECK (angulo IN ('frente', 'traseira', 'lateral_esquerda', 'lateral_direita')),
    foto_url TEXT NOT NULL,
    criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- 8. TABELA DE RESPOSTAS DOS ITENS DE CHECKLIST
CREATE TABLE IF NOT EXISTS public.vistoria_itens_respostas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vistoria_id UUID NOT NULL REFERENCES public.vistorias(id) ON DELETE CASCADE,
    item_config_id UUID NOT NULL REFERENCES public.checklist_itens_config(id),
    status VARCHAR(20) NOT NULL CHECK (status IN ('OK', 'ALTERACAO', 'NA')),
    descricao_avaria TEXT,
    foto_avaria_url TEXT,
    criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- 9. TABELA DE AUDITORIA E CADEIA DE CUSTÓDIA: SINISTROS NÃO NOTIFICADOS
-- Caso uma alteração seja detectada pelo motorista atual que o anterior omitiu!
CREATE TABLE IF NOT EXISTS public.sinistros_nao_notificados (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vistoria_atual_id UUID NOT NULL REFERENCES public.vistorias(id) ON DELETE CASCADE,
    vistoria_anterior_id UUID REFERENCES public.vistorias(id),
    prefixo_vtr VARCHAR(20) NOT NULL,
    item_config_id UUID NOT NULL REFERENCES public.checklist_itens_config(id),
    matricula_responsavel_anterior VARCHAR(20) NOT NULL REFERENCES public.policiais(matricula),
    matricula_comunicante_atual VARCHAR(20) NOT NULL REFERENCES public.policiais(matricula),
    descricao_avaria TEXT NOT NULL,
    foto_avaria_url TEXT,
    status_apuracao VARCHAR(30) DEFAULT 'pendente' CHECK (status_apuracao IN ('pendente', 'em_apuracao', 'justificado', 'sindicancia_aberta', 'concluido')),
    despacho_oficial TEXT,
    criado_em TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 10. TRIGGER AUTOMÁTICO DE RESPONSABILIDADE (CRUZAMENTO DE TURNOS)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.fn_processar_auditoria_vistoria()
RETURNS TRIGGER AS $$
DECLARE
    v_vistoria_antiga RECORD;
    v_item RECORD;
    v_existia_anteriormente BOOLEAN;
BEGIN
    -- Busca a última vistoria finalizada para a mesma viatura (anterior a esta)
    SELECT id, matricula_condutor INTO v_vistoria_antiga
    FROM public.vistorias
    WHERE prefixo_vtr = NEW.prefixo_vtr 
      AND id != NEW.id 
      AND status = 'finalizada'
    ORDER BY criado_em DESC
    LIMIT 1;

    -- Se existe vistoria anterior, vincula e verifica avarias omitidas
    IF v_vistoria_antiga.id IS NOT NULL THEN
        UPDATE public.vistorias 
        SET vistoria_anterior_id = v_vistoria_antiga.id,
            matricula_condutor_anterior = v_vistoria_antiga.matricula_condutor
        WHERE id = NEW.id;

        -- Varre todos os itens com 'ALTERACAO' apontados na vistoria atual
        FOR v_item IN 
            SELECT r.item_config_id, r.descricao_avaria, r.foto_avaria_url
            FROM public.vistoria_itens_respostas r
            WHERE r.vistoria_id = NEW.id AND r.status = 'ALTERACAO'
        LOOP
            -- Checa se o motorista anterior já havia apontado essa mesma alteração
            SELECT EXISTS (
                SELECT 1 FROM public.vistoria_itens_respostas ant
                WHERE ant.vistoria_id = v_vistoria_antiga.id 
                  AND ant.item_config_id = v_item.item_config_id 
                  AND ant.status = 'ALTERACAO'
            ) INTO v_existia_anteriormente;

            -- SE NÃO EXISTIA NA ANTERIOR: O motorista anterior omitiu o sinistro!
            IF NOT v_existia_anteriormente THEN
                INSERT INTO public.sinistros_nao_notificados (
                    vistoria_atual_id,
                    vistoria_anterior_id,
                    prefixo_vtr,
                    item_config_id,
                    matricula_responsavel_anterior,
                    matricula_comunicante_atual,
                    descricao_avaria,
                    foto_avaria_url
                ) VALUES (
                    NEW.id,
                    v_vistoria_antiga.id,
                    NEW.prefixo_vtr,
                    v_item.item_config_id,
                    v_vistoria_antiga.matricula_condutor,
                    NEW.matricula_condutor,
                    COALESCE(v_item.descricao_avaria, 'Avaria omitida na passagem anterior'),
                    v_item.foto_avaria_url
                );
            END IF;
        END LOOP;
    END IF;

    -- Atualiza o KM da viatura na tabela mestre
    UPDATE public.viaturas 
    SET km_atual = NEW.km_odometro,
        nivel_combustivel_atual = NEW.nivel_combustivel,
        atualizado_em = NOW()
    WHERE prefixo = NEW.prefixo_vtr;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Disparador após finalizar a vistoria
DROP TRIGGER IF EXISTS trg_auditoria_vistoria ON public.vistorias;
CREATE TRIGGER trg_auditoria_vistoria
AFTER INSERT OR UPDATE OF status ON public.vistorias
FOR EACH ROW
WHEN (NEW.status = 'finalizada')
EXECUTE FUNCTION public.fn_processar_auditoria_vistoria();

-- ==============================================================================
-- 11. BUCKETS DE STORAGE (FOTOS & ASSINATURAS)
-- ==============================================================================
-- No Supabase Dashboard -> Storage, criar os seguintes buckets públicos ou autenticados:
-- 1. 'vistorias-fotos-4-lados'
-- 2. 'vistorias-fotos-avarias'
-- 3. 'vistorias-assinaturas'

-- ==============================================================================
-- 12. DADOS INICIAIS (SEED DATA)
-- ==============================================================================

-- Viaturas com controle de óleo inicial
INSERT INTO public.viaturas (prefixo, modelo, placa, km_atual, nivel_combustivel_atual, km_ultima_troca_oleo, data_ultima_troca_oleo, intervalo_troca_oleo_km, intervalo_troca_oleo_dias) VALUES
('VTR-1022', 'Renault Duster 1.6 Tática', 'BRA2E19', 78450, '3/4', 70000, CURRENT_DATE - INTERVAL '120 days', 10000, 180),
('VTR-2045', 'Toyota Hilux 4x4 Policial', 'PMW5401', 112340, 'Cheio', 103000, CURRENT_DATE - INTERVAL '70 days', 10000, 180),
('VTR-3110', 'Toyota Corolla Sedan Patrulha', 'RQX9912', 49800, '1/2', 40000, CURRENT_DATE - INTERVAL '190 days', 10000, 180),
('VTR-4008', 'Chevrolet Trailblazer Choque', 'GOI8821', 93100, 'Cheio', 82000, CURRENT_DATE - INTERVAL '90 days', 10000, 180)
ON CONFLICT (prefixo) DO NOTHING;

-- Policiais de exemplo
INSERT INTO public.policiais (matricula, nome_guerra, posto_graduacao, telefone_funcional, role) VALUES
('31.002-4', 'SILVA', 'Cb PM', '(62) 99122-3344', 'motorista'),
('39.412-8', 'ALMEIDA', 'Cb PM', '(62) 99341-8899', 'motorista'),
('28.115-9', 'RODRIGUES', '3º Sgt PM', '(62) 99222-1100', 'motorista'),
('14.880-1', 'MAJOR COSTA', 'Major PM', '(62) 98888-0001', 'admin')
ON CONFLICT (matricula) DO NOTHING;

-- Avisos de viatura
INSERT INTO public.avisos_viatura (prefixo_vtr, titulo, mensagem, severidade) VALUES
('VTR-1022', 'Revisão Agendada', 'Revisão dos 80.000 KM agendada para segunda-feira. Não realizar deslocamentos de longa distância.', 'aviso'),
('VTR-1022', 'Pneu Novo', 'Pneu dianteiro direito trocado recentemente. Manter calibração em 32 PSI.', 'info'),
('VTR-2045', 'Tração 4x4', 'Acionar a tração 4x4 somente com o veículo totalmente imobilizado.', 'urgente');

-- Itens dinâmicos padrão do checklist
INSERT INTO public.checklist_itens_config (categoria, titulo, descricao, obrigatorio, exige_foto_se_alterado, ordem_exibicao) VALUES
-- Mecânica & Fluidos
('Mecânica & Fluidos', 'Nível do Óleo do Motor', 'Verificar na vareta antes de ligar o motor', TRUE, TRUE, 1),
('Mecânica & Fluidos', 'Água / Fluido do Radiador', 'Verificar nível no reservatório de expansão', TRUE, TRUE, 2),
('Mecânica & Fluidos', 'Fluido de Freio', 'Verificar nível do reservatório do cilindro mestre', TRUE, FALSE, 3),

-- Sinalizadores & Elétrica
('Sinalizadores & Elétrica', 'Giroflex / Barra de Luzes', 'Verificar todos os estrobos e leds vermelhos/azuis', TRUE, TRUE, 4),
('Sinalizadores & Elétrica', 'Sirene & Buzina', 'Testar tons wail, yelp e buzina a ar', TRUE, FALSE, 5),
('Sinalizadores & Elétrica', 'Faróis (Alto, Baixo e Milha)', 'Verificar lâmpadas queimadas ou lentes trincadas', TRUE, TRUE, 6),
('Sinalizadores & Elétrica', 'Luzes de Freio', 'Pedir apoio ao patrulheiro para pisar no pedal', TRUE, TRUE, 7),
('Sinalizadores & Elétrica', 'Setas e Pisca-Alerta', 'Testar setas dianteiras, traseiras e laterais', TRUE, TRUE, 8),

-- Rodagem & Pneus
('Rodagem & Pneus', 'Pneus Dianteiros (Calibragem e Desgaste)', 'Checar se há deformações, arames ou baixa pressão', TRUE, TRUE, 9),
('Rodagem & Pneus', 'Pneus Traseiros (Calibragem e Desgaste)', 'Checar se há pregos, cortes ou baixa pressão', TRUE, TRUE, 10),
('Rodagem & Pneus', 'Estepe / Pneu Reserva', 'Verificar se está calibrado e sem avarias', TRUE, TRUE, 11),
('Rodagem & Pneus', 'Macaco, Chave de Roda e Triângulo', 'Conferir presença no compartimento de ferramentas', TRUE, FALSE, 12),

-- Higiene & Interior
('Higiene & Interior', 'Limpeza Interna (Bancos e Assoalho)', 'Verificar presença de lixo, terra excessiva ou manchas', TRUE, TRUE, 13),
('Higiene & Interior', 'Compartimento de Presos (Camburão)', 'Conferir trincos, travas de segurança e higienização', TRUE, TRUE, 14),

-- Equipamentos Táticos
('Equipamentos Táticos', 'Rádio Comunicador (VHF/TETRA)', 'Testar transmissão e recepção com o COPOM/Central', TRUE, FALSE, 15),
('Equipamentos Táticos', 'Suporte & Travas de Armas Longas', 'Conferir trancamento de fuzil/calibre 12', TRUE, TRUE, 16);
