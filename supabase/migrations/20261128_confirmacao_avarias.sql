-- =============================================================================
-- SisCheck-VTR — Confirmação de avarias já registradas
-- O motorista vê as avarias em aberto da VTR (local, descrição, data, miniatura)
-- e marca "Confirmo, ainda presente" em vez de registrar de novo.
-- A confirmação fica gravada junto com a vistoria (identificação, hora do
-- servidor, assinatura) e serve de prova de que ele constatou e comunicou.
-- Mudanças aditivas: o front antigo continua funcionando.
-- =============================================================================

-- Miniatura sem carimbo (o carimbo da foto original traz o nome de quem apontou)
alter table public.avarias add column if not exists foto_mini_path text;

create table if not exists public.avaria_confirmacoes (
  id          uuid primary key default gen_random_uuid(),
  avaria_id   uuid not null references public.avarias(id) on delete cascade,
  vistoria_id uuid not null references public.vistorias(id) on delete cascade,
  condutor    text not null,
  matricula   text not null,
  created_at  timestamptz not null default now(),
  unique (avaria_id, vistoria_id)
);
create index if not exists avaria_confirmacoes_avaria_idx on public.avaria_confirmacoes (avaria_id, created_at desc);
create index if not exists avaria_confirmacoes_vistoria_idx on public.avaria_confirmacoes (vistoria_id);

alter table public.avaria_confirmacoes enable row level security;
revoke all on public.avaria_confirmacoes from anon;
drop policy if exists avaria_confirmacoes_admin_read on public.avaria_confirmacoes;
create policy avaria_confirmacoes_admin_read on public.avaria_confirmacoes
  for select to authenticated using ((select public.is_admin()));
-- Sem insert/update/delete por cliente: só a RPC finalizar_vistoria grava.

-- ---------------------------------------------------------------------------
-- Storage: anônimo lê SÓ miniaturas de avarias em aberto
-- ---------------------------------------------------------------------------
create or replace function public.miniatura_publica(p_name text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.avarias a where a.foto_mini_path = p_name and a.status = 'aberta');
$$;
revoke all on function public.miniatura_publica(text) from public;
grant execute on function public.miniatura_publica(text) to anon, authenticated;

drop policy if exists sischeck_mini_read on storage.objects;
create policy sischeck_mini_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'vistorias' and (select public.miniatura_publica(name)));

-- ---------------------------------------------------------------------------
-- Passagem de serviço: avarias em aberto com id, miniatura e nº de confirmações
-- (sem nomes/matrículas de quem apontou ou confirmou)
-- ---------------------------------------------------------------------------
create or replace function public.passagem_viatura(p_viatura_id uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'ultima', (
      select jsonb_build_object(
        'condutor', v.condutor_posto || ' ' || v.condutor_nome_guerra,
        'matricula', v.condutor_matricula,
        'km', v.km_odometro,
        'em', v.created_at,
        'alteracoes', coalesce((
          select jsonb_agg(jsonb_build_object('item_id', i.item_id, 'titulo', i.item_titulo, 'obs', i.observacao)
                           order by i.item_titulo)
            from public.vistoria_itens i
           where i.vistoria_id = v.id and i.status = 'ALTERACAO'), '[]'::jsonb))
      from public.vistorias v
     where v.viatura_id = p_viatura_id
     order by v.created_at desc, v.protocolo desc
     limit 1),
    'avarias_abertas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'local', a.local, 'descricao', a.descricao, 'em', a.created_at,
               'foto_mini', a.foto_mini_path,
               'confirmacoes', (select count(*) from public.avaria_confirmacoes c where c.avaria_id = a.id),
               'ultima_confirmacao', (select max(c.created_at) from public.avaria_confirmacoes c where c.avaria_id = a.id))
             order by a.created_at)
        from public.avarias a
       where a.viatura_id = p_viatura_id and a.status = 'aberta'), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------------
-- Finalizar vistoria: aceita avarias_confirmadas [uuid] e foto_mini_path
-- ---------------------------------------------------------------------------
create or replace function public.finalizar_vistoria(p jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $function$
declare
  v_vtr public.viaturas; v_ant public.vistorias; v_id uuid; v_protocolo text; v_km integer;
  v_nome text; v_mat text; v_posto text; v_item record; v_resp jsonb; v_status text;
  v_obs text; v_foto text; v_mini text; v_omitidos integer := 0; v_path text; v_av jsonb; v_av_id uuid; v_local text;
  v_confirmadas integer := 0;
begin
  select * into v_vtr from public.viaturas where id = (p->>'viatura_id')::uuid for update;
  if not found then raise exception 'Viatura não encontrada.'; end if;
  if v_vtr.status_operacional = 'baixada' then raise exception 'Viatura baixada não pode ser vistoriada.'; end if;

  v_posto := btrim(coalesce(p->>'posto',''));
  v_nome  := upper(btrim(coalesce(p->>'nome_guerra','')));
  v_mat   := btrim(coalesce(p->>'matricula',''));
  if char_length(v_posto) < 2 then raise exception 'Informe o posto/graduação.'; end if;
  if char_length(v_nome) < 2 or char_length(v_nome) > 40 then raise exception 'Informe o nome de guerra.'; end if;
  if v_mat !~ '^[0-9][0-9.\-/ ]{2,19}$' then raise exception 'Matrícula inválida.'; end if;
  if char_length(regexp_replace(coalesce(p->>'telefone',''), '\D', '', 'g')) not between 10 and 11 then
    raise exception 'Telefone da escala inválido (use DDD + número).';
  end if;
  if coalesce(p->>'combustivel','') not in ('Reserva','1/4','1/2','3/4','Cheio') then
    raise exception 'Informe o nível de combustível.';
  end if;

  begin
    v_km := (p->>'km')::integer;
  exception when others then raise exception 'KM inválido.';
  end;
  if v_km is null then raise exception 'Informe o KM.'; end if;
  if v_km < v_vtr.km_atual then
    raise exception 'KM informado (%) é menor que o último registrado (%).', v_km, v_vtr.km_atual;
  end if;
  if v_vtr.km_atual > 0 and v_km > v_vtr.km_atual + 5000 then
    raise exception 'KM informado (%) passa de 5.000 km acima do último registro (%). Confira o odômetro.', v_km, v_vtr.km_atual;
  end if;

  foreach v_path in array array[p->>'foto_frente', p->>'foto_traseira', p->>'foto_esquerda', p->>'foto_direita', p->>'assinatura_path'] loop
    if v_path is null or not exists (select 1 from storage.objects o where o.bucket_id = 'vistorias' and o.name = v_path) then
      raise exception 'Fotos dos 4 lados e assinatura são obrigatórias (arquivo não encontrado na nuvem).';
    end if;
  end loop;

  if jsonb_array_length(coalesce(p->'avarias_novas','[]'::jsonb)) > 20 then
    raise exception 'Máximo de 20 avarias novas por vistoria.';
  end if;
  if jsonb_typeof(coalesce(p->'avarias_confirmadas','[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p->'avarias_confirmadas','[]'::jsonb)) > 100 then
    raise exception 'Lista de avarias confirmadas inválida.';
  end if;

  select * into v_ant from public.vistorias where viatura_id = v_vtr.id order by created_at desc, protocolo desc limit 1;

  v_protocolo := 'VST-' || to_char(now() at time zone 'America/Sao_Paulo', 'YYYY') || '-'
                 || lpad(nextval('public.vistorias_protocolo_seq')::text, 6, '0');

  insert into public.vistorias (
    protocolo, viatura_id, vistoria_anterior_id, condutor_posto, condutor_nome_guerra,
    condutor_matricula, telefone_escala, km_odometro, km_anterior, nivel_combustivel,
    foto_frente, foto_traseira, foto_esquerda, foto_direita, assinatura_path, dispositivo)
  values (
    v_protocolo, v_vtr.id, v_ant.id, v_posto, v_nome, v_mat, btrim(p->>'telefone'),
    v_km, v_vtr.km_atual, p->>'combustivel',
    p->>'foto_frente', p->>'foto_traseira', p->>'foto_esquerda', p->>'foto_direita',
    p->>'assinatura_path', left(p->>'dispositivo', 300))
  returning id into v_id;

  for v_item in select * from public.checklist_itens where ativo order by ordem, titulo loop
    v_resp := null;
    select e into v_resp from jsonb_array_elements(coalesce(p->'itens','[]'::jsonb)) e
     where e->>'item_id' = v_item.id::text limit 1;
    if v_resp is null then raise exception 'Item sem resposta: %', v_item.titulo; end if;
    v_status := v_resp->>'status';
    if v_status is null or v_status not in ('OK','ALTERACAO') then
      raise exception 'Item sem resposta: %', v_item.titulo;
    end if;
    v_obs  := nullif(btrim(coalesce(v_resp->>'observacao','')), '');
    v_foto := nullif(v_resp->>'foto_path', '');

    if v_status = 'ALTERACAO' then
      if v_obs is null then raise exception 'Descreva a alteração em: %', v_item.titulo; end if;
      if v_item.exige_foto and v_foto is null then raise exception 'Foto obrigatória da alteração em: %', v_item.titulo; end if;
      if v_foto is not null and not exists (select 1 from storage.objects o where o.bucket_id='vistorias' and o.name = v_foto) then
        raise exception 'Foto da alteração em % não encontrada na nuvem.', v_item.titulo;
      end if;
    else
      v_obs := null; v_foto := null;
    end if;

    insert into public.vistoria_itens (vistoria_id, item_id, item_titulo, status, observacao, foto_path)
    values (v_id, v_item.id, v_item.titulo, v_status, left(v_obs, 500), v_foto);

    if v_status = 'ALTERACAO' and v_ant.id is not null and not exists (
         select 1 from public.vistoria_itens a
          where a.vistoria_id = v_ant.id and a.item_id = v_item.id and a.status = 'ALTERACAO') then
      insert into public.sinistros (
        viatura_id, vistoria_detectora_id, vistoria_anterior_id, item_id, item_titulo, observacao, foto_path,
        responsavel_nome, responsavel_matricula, comunicante_nome, comunicante_matricula)
      values (
        v_vtr.id, v_id, v_ant.id, v_item.id, v_item.titulo, left(v_obs, 500), v_foto,
        v_ant.condutor_posto || ' ' || v_ant.condutor_nome_guerra, v_ant.condutor_matricula,
        v_posto || ' ' || v_nome, v_mat);
      v_omitidos := v_omitidos + 1;
    end if;
  end loop;

  -- Avarias já registradas que o motorista confirmou (sem nova foto, sem apuração)
  insert into public.avaria_confirmacoes (avaria_id, vistoria_id, condutor, matricula)
  select a.id, v_id, v_posto || ' ' || v_nome, v_mat
    from public.avarias a
   where a.viatura_id = v_vtr.id and a.status = 'aberta'
     and a.id::text in (select jsonb_array_elements_text(coalesce(p->'avarias_confirmadas','[]'::jsonb)))
  on conflict do nothing;
  get diagnostics v_confirmadas = row_count;

  -- Avarias fora do checklist (lataria, vidros etc.): entram no registro da VTR
  for v_av in select * from jsonb_array_elements(coalesce(p->'avarias_novas','[]'::jsonb)) loop
    v_local := v_av->>'local';
    v_obs   := nullif(btrim(coalesce(v_av->>'descricao','')), '');
    v_foto  := nullif(v_av->>'foto_path', '');
    v_mini  := nullif(v_av->>'foto_mini_path', '');
    if v_local is null or v_local not in ('Frente','Traseira','Lateral esquerda','Lateral direita','Teto','Vidros','Rodas/pneus','Interior','Outro') then
      raise exception 'Informe o local da avaria.';
    end if;
    if v_obs is null or char_length(v_obs) < 3 then raise exception 'Descreva a avaria (%).', v_local; end if;
    if v_foto is null or not exists (select 1 from storage.objects o where o.bucket_id='vistorias' and o.name = v_foto) then
      raise exception 'Foto obrigatória da avaria (%).', v_local;
    end if;
    if v_mini is not null and not exists (select 1 from storage.objects o where o.bucket_id='vistorias' and o.name = v_mini) then
      v_mini := null;
    end if;

    insert into public.avarias (viatura_id, local, descricao, foto_path, foto_mini_path, vistoria_origem_id, apontada_por)
    values (v_vtr.id, v_local, left(v_obs, 300), v_foto, v_mini, v_id, v_posto || ' ' || v_nome || ' (' || v_mat || ')')
    returning id into v_av_id;

    if v_ant.id is not null then
      insert into public.sinistros (
        viatura_id, vistoria_detectora_id, vistoria_anterior_id, avaria_id, item_titulo, observacao, foto_path,
        responsavel_nome, responsavel_matricula, comunicante_nome, comunicante_matricula)
      values (
        v_vtr.id, v_id, v_ant.id, v_av_id, 'Avaria: ' || v_local, left(v_obs, 300), v_foto,
        v_ant.condutor_posto || ' ' || v_ant.condutor_nome_guerra, v_ant.condutor_matricula,
        v_posto || ' ' || v_nome, v_mat);
      v_omitidos := v_omitidos + 1;
    end if;
  end loop;

  update public.viaturas set km_atual = v_km where id = v_vtr.id;

  return jsonb_build_object('id', v_id, 'protocolo', v_protocolo, 'registrado_em', now(),
                            'avarias_nao_comunicadas', v_omitidos, 'avarias_confirmadas', v_confirmadas);
end $function$;
