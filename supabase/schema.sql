-- =============================================================================
-- SisCheck-VTR — esquema do banco (Supabase / Postgres)
-- Modelo de acesso:
--   * Motorista (anon, sem conta): lê viaturas, checklist e avisos ativos;
--     envia fotos para o Storage e grava a vistoria SOMENTE via RPC
--     public.finalizar_vistoria (validada no servidor).
--   * Chefe de Transporte (usuário autenticado presente em public.admins):
--     gerencia tudo.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Administradores (Chefes de Transporte)
-- ---------------------------------------------------------------------------
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  nome       text,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.admins a where a.user_id = auth.uid());
$$;

create or replace function public.tg_set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Viaturas
-- ---------------------------------------------------------------------------
create table if not exists public.viaturas (
  id                          uuid primary key default gen_random_uuid(),
  prefixo                     text not null unique
                              check (prefixo = upper(btrim(prefixo)) and char_length(prefixo) between 2 and 20),
  placa                       text not null unique
                              check (placa ~ '^[A-Z]{3}-?[0-9][A-Z0-9][0-9]{2}$'),
  modelo                      text not null check (char_length(btrim(modelo)) between 2 and 80),
  km_atual                    integer not null check (km_atual >= 0),
  status_operacional          text not null default 'ativa'
                              check (status_operacional in ('ativa','manutencao','reserva','baixada')),
  km_ultima_troca_oleo        integer not null check (km_ultima_troca_oleo >= 0),
  data_ultima_troca_oleo      date not null,
  intervalo_troca_oleo_km     integer not null default 10000 check (intervalo_troca_oleo_km > 0),
  intervalo_troca_oleo_dias   integer not null default 180   check (intervalo_troca_oleo_dias > 0),
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  constraint oleo_km_coerente check (km_ultima_troca_oleo <= km_atual)
);

drop trigger if exists trg_viaturas_updated on public.viaturas;
create trigger trg_viaturas_updated before update on public.viaturas
  for each row execute function public.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- Itens do checklist (desativação lógica para preservar histórico)
-- ---------------------------------------------------------------------------
create table if not exists public.checklist_itens (
  id          uuid primary key default gen_random_uuid(),
  titulo      text not null check (char_length(btrim(titulo)) between 2 and 120),
  categoria   text not null check (categoria in (
                'Mecânica & Fluidos','Sinalizadores & Elétrica','Rodagem & Pneus',
                'Higiene & Interior','Equipamentos Táticos','Outros')),
  exige_foto  boolean not null default true,
  ativo       boolean not null default true,
  ordem       integer not null default 100,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Mural de avisos por viatura
-- ---------------------------------------------------------------------------
create table if not exists public.avisos (
  id          uuid primary key default gen_random_uuid(),
  viatura_id  uuid not null references public.viaturas(id) on delete cascade,
  mensagem    text not null check (char_length(btrim(mensagem)) between 2 and 500),
  ativo       boolean not null default true,
  criado_por  uuid references auth.users(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now()
);
create index if not exists avisos_viatura_idx on public.avisos(viatura_id) where ativo;

-- ---------------------------------------------------------------------------
-- Vistorias (gravadas somente pela RPC finalizar_vistoria)
-- ---------------------------------------------------------------------------
create sequence if not exists public.vistorias_protocolo_seq;

create table if not exists public.vistorias (
  id                    uuid primary key default gen_random_uuid(),
  protocolo             text not null unique,
  viatura_id            uuid not null references public.viaturas(id) on delete restrict,
  vistoria_anterior_id  uuid references public.vistorias(id) on delete set null,
  condutor_posto        text not null,
  condutor_nome_guerra  text not null,
  condutor_matricula    text not null,
  telefone_escala       text not null,
  km_odometro           integer not null,
  km_anterior           integer not null,
  nivel_combustivel     text not null check (nivel_combustivel in ('Reserva','1/4','1/2','3/4','Cheio')),
  foto_frente           text not null,
  foto_traseira         text not null,
  foto_esquerda         text not null,
  foto_direita          text not null,
  assinatura_path       text not null,
  dispositivo           text,
  created_at            timestamptz not null default now()
);
create index if not exists vistorias_viatura_idx on public.vistorias(viatura_id, created_at desc);

create table if not exists public.vistoria_itens (
  vistoria_id   uuid not null references public.vistorias(id) on delete cascade,
  item_id       uuid not null references public.checklist_itens(id) on delete restrict,
  item_titulo   text not null,          -- cópia do título no momento da vistoria
  status        text not null check (status in ('OK','ALTERACAO')),
  observacao    text,
  foto_path     text,
  primary key (vistoria_id, item_id)
);

-- ---------------------------------------------------------------------------
-- Sinistros / avarias não comunicadas pelo condutor anterior
-- ---------------------------------------------------------------------------
create table if not exists public.sinistros (
  id                      uuid primary key default gen_random_uuid(),
  viatura_id              uuid not null references public.viaturas(id) on delete restrict,
  vistoria_detectora_id   uuid not null references public.vistorias(id) on delete restrict,
  vistoria_anterior_id    uuid not null references public.vistorias(id) on delete restrict,
  item_id                 uuid not null references public.checklist_itens(id) on delete restrict,
  item_titulo             text not null,
  observacao              text,
  foto_path               text,
  responsavel_nome        text not null,
  responsavel_matricula   text not null,
  comunicante_nome        text not null,
  comunicante_matricula   text not null,
  status                  text not null default 'aguardando_despacho'
                          check (status in ('aguardando_despacho','em_apuracao','procedente','arquivado')),
  despacho                text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create index if not exists sinistros_status_idx on public.sinistros(status, created_at desc);

drop trigger if exists trg_sinistros_updated on public.sinistros;
create trigger trg_sinistros_updated before update on public.sinistros
  for each row execute function public.tg_set_updated_at();

-- ---------------------------------------------------------------------------
-- Histórico de trocas de óleo (atualiza a viatura via trigger)
-- ---------------------------------------------------------------------------
create table if not exists public.trocas_oleo (
  id           uuid primary key default gen_random_uuid(),
  viatura_id   uuid not null references public.viaturas(id) on delete cascade,
  km           integer not null check (km >= 0),
  data         date not null check (data <= (now() at time zone 'America/Sao_Paulo')::date),
  registrado_por uuid references auth.users(id) on delete set null default auth.uid(),
  created_at   timestamptz not null default now()
);

create or replace function public.tg_aplicar_troca_oleo()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v public.viaturas;
begin
  select * into v from public.viaturas where id = new.viatura_id for update;
  if new.km > v.km_atual then
    raise exception 'KM da troca (%) maior que o KM atual da viatura (%)', new.km, v.km_atual;
  end if;
  update public.viaturas
     set km_ultima_troca_oleo = new.km,
         data_ultima_troca_oleo = new.data
   where id = new.viatura_id;
  return new;
end $$;

drop trigger if exists trg_trocas_oleo_aplicar on public.trocas_oleo;
create trigger trg_trocas_oleo_aplicar after insert on public.trocas_oleo
  for each row execute function public.tg_aplicar_troca_oleo();

-- =============================================================================
-- RLS
-- =============================================================================
alter table public.admins          enable row level security;
alter table public.viaturas        enable row level security;
alter table public.checklist_itens enable row level security;
alter table public.avisos          enable row level security;
alter table public.vistorias       enable row level security;
alter table public.vistoria_itens  enable row level security;
alter table public.sinistros       enable row level security;
alter table public.trocas_oleo     enable row level security;

-- admins: cada admin vê a si mesmo
drop policy if exists admins_self on public.admins;
create policy admins_self on public.admins for select to authenticated
  using (user_id = (select auth.uid()));

-- viaturas: leitura pública; escrita só admin
drop policy if exists viaturas_read on public.viaturas;
create policy viaturas_read on public.viaturas for select to anon, authenticated using (true);
drop policy if exists viaturas_admin_ins on public.viaturas;
create policy viaturas_admin_ins on public.viaturas for insert to authenticated with check ((select public.is_admin()));
drop policy if exists viaturas_admin_upd on public.viaturas;
create policy viaturas_admin_upd on public.viaturas for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- checklist: motorista vê ativos; admin vê e edita tudo
drop policy if exists checklist_read on public.checklist_itens;
create policy checklist_read on public.checklist_itens for select to anon, authenticated
  using (ativo or (select public.is_admin()));
drop policy if exists checklist_admin_ins on public.checklist_itens;
create policy checklist_admin_ins on public.checklist_itens for insert to authenticated with check ((select public.is_admin()));
drop policy if exists checklist_admin_upd on public.checklist_itens;
create policy checklist_admin_upd on public.checklist_itens for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- avisos
drop policy if exists avisos_read on public.avisos;
create policy avisos_read on public.avisos for select to anon, authenticated
  using (ativo or (select public.is_admin()));
drop policy if exists avisos_admin_ins on public.avisos;
create policy avisos_admin_ins on public.avisos for insert to authenticated with check ((select public.is_admin()));
drop policy if exists avisos_admin_upd on public.avisos;
create policy avisos_admin_upd on public.avisos for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- vistorias / itens: só admin lê; ninguém grava direto (só pela RPC)
drop policy if exists vistorias_admin_read on public.vistorias;
create policy vistorias_admin_read on public.vistorias for select to authenticated using ((select public.is_admin()));
drop policy if exists vistoria_itens_admin_read on public.vistoria_itens;
create policy vistoria_itens_admin_read on public.vistoria_itens for select to authenticated using ((select public.is_admin()));

-- sinistros: admin lê e despacha
drop policy if exists sinistros_admin_read on public.sinistros;
create policy sinistros_admin_read on public.sinistros for select to authenticated using ((select public.is_admin()));
drop policy if exists sinistros_admin_upd on public.sinistros;
create policy sinistros_admin_upd on public.sinistros for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- trocas de óleo: admin
drop policy if exists trocas_admin_read on public.trocas_oleo;
create policy trocas_admin_read on public.trocas_oleo for select to authenticated using ((select public.is_admin()));
drop policy if exists trocas_admin_ins on public.trocas_oleo;
create policy trocas_admin_ins on public.trocas_oleo for insert to authenticated with check ((select public.is_admin()));

-- Grants explícitos (RLS continua decidindo o que cada um vê)
grant usage on schema public to anon, authenticated;
grant select on public.viaturas, public.checklist_itens, public.avisos to anon;
grant select, insert, update on public.viaturas, public.checklist_itens, public.avisos,
  public.sinistros to authenticated;
grant select on public.vistorias, public.vistoria_itens, public.admins to authenticated;
grant select, insert on public.trocas_oleo to authenticated;
revoke insert, update, delete on public.vistorias, public.vistoria_itens from anon, authenticated;
revoke insert, delete on public.sinistros from anon, authenticated;
