-- =============================================================================
-- SisCheck-VTR — funções (RPC) e Storage
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Storage: bucket privado para fotos e assinaturas
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vistorias', 'vistorias', false, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Motorista (anon) pode ENVIAR arquivo novo na pasta "envios/"; não lê, não troca, não apaga.
drop policy if exists "vistorias_upload" on storage.objects;
create policy "vistorias_upload" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'vistorias' and (storage.foldername(name))[1] = 'envios');

-- Só o Chefe lê (URLs assinadas)
drop policy if exists "vistorias_admin_read" on storage.objects;
create policy "vistorias_admin_read" on storage.objects for select to authenticated
  using (bucket_id = 'vistorias' and (select public.is_admin()));

-- ---------------------------------------------------------------------------
-- Dados da passagem de serviço (último condutor) — leitura pública restrita
-- ---------------------------------------------------------------------------
create or replace function public.passagem_viatura(p_viatura_id uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select coalesce((
    select jsonb_build_object(
      'condutor', v.condutor_posto || ' ' || v.condutor_nome_guerra,
      'matricula', v.condutor_matricula,
      'km', v.km_odometro,
      'em', v.created_at,
      'alteracoes', coalesce((
        select jsonb_agg(jsonb_build_object('item_id', i.item_id, 'titulo', i.item_titulo, 'obs', i.observacao)
                         order by i.item_titulo)
          from public.vistoria_itens i
         where i.vistoria_id = v.id and i.status = 'ALTERACAO'), '[]'::jsonb)
    )
    from public.vistorias v
   where v.viatura_id = p_viatura_id
   order by v.created_at desc
   limit 1), 'null'::jsonb);
$$;

-- ---------------------------------------------------------------------------
-- Finaliza a vistoria: valida tudo no servidor e grava de forma atômica
-- ---------------------------------------------------------------------------
create or replace function public.finalizar_vistoria(p jsonb)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_vtr        public.viaturas;
  v_ant        public.vistorias;
  v_id         uuid;
  v_protocolo  text;
  v_km         integer;
  v_nome       text;
  v_mat        text;
  v_item       record;
  v_resp       jsonb;
  v_status     text;
  v_obs        text;
  v_foto       text;
  v_omitidos   integer := 0;
  v_path       text;
begin
  -- Viatura (trava a linha para evitar duas vistorias simultâneas bagunçando o KM)
  select * into v_vtr from public.viaturas where id = (p->>'viatura_id')::uuid for update;
  if not found then raise exception 'Viatura não encontrada.'; end if;
  if v_vtr.status_operacional = 'baixada' then raise exception 'Viatura baixada não pode ser vistoriada.'; end if;

  -- Identificação
  v_nome := upper(btrim(coalesce(p->>'nome_guerra','')));
  v_mat  := btrim(coalesce(p->>'matricula',''));
  if char_length(v_nome) < 2 then raise exception 'Informe o nome de guerra.'; end if;
  if v_mat !~ '^[0-9][0-9.\-/ ]{2,19}$' then raise exception 'Matrícula inválida.'; end if;
  if char_length(btrim(coalesce(p->>'posto',''))) < 2 then raise exception 'Informe o posto/graduação.'; end if;
  if char_length(regexp_replace(coalesce(p->>'telefone',''), '\D', '', 'g')) not between 10 and 11 then
    raise exception 'Telefone da escala inválido (use DDD + número).';
  end if;

  -- KM
  v_km := (p->>'km')::integer;
  if v_km is null then raise exception 'Informe o KM.'; end if;
  if v_km < v_vtr.km_atual then
    raise exception 'KM informado (%) é menor que o último registrado (%).', v_km, v_vtr.km_atual;
  end if;
  if v_km > v_vtr.km_atual + 5000 then
    raise exception 'KM informado (%) passa de 5.000 km acima do último registro (%). Confira o odômetro.', v_km, v_vtr.km_atual;
  end if;

  -- Fotos obrigatórias e assinatura: precisam existir no Storage
  foreach v_path in array array[p->>'foto_frente', p->>'foto_traseira', p->>'foto_esquerda', p->>'foto_direita', p->>'assinatura_path'] loop
    if v_path is null or not exists (select 1 from storage.objects o where o.bucket_id = 'vistorias' and o.name = v_path) then
      raise exception 'Fotos dos 4 lados e assinatura são obrigatórias (arquivo não encontrado na nuvem).';
    end if;
  end loop;

  -- Vistoria anterior desta viatura
  select * into v_ant from public.vistorias
   where viatura_id = v_vtr.id order by created_at desc limit 1;

  v_protocolo := 'VST-' || to_char(now() at time zone 'America/Sao_Paulo', 'YYYY') || '-'
                 || lpad(nextval('public.vistorias_protocolo_seq')::text, 6, '0');

  insert into public.vistorias (
    protocolo, viatura_id, vistoria_anterior_id, condutor_posto, condutor_nome_guerra,
    condutor_matricula, telefone_escala, km_odometro, km_anterior, nivel_combustivel,
    foto_frente, foto_traseira, foto_esquerda, foto_direita, assinatura_path, dispositivo)
  values (
    v_protocolo, v_vtr.id, v_ant.id, btrim(p->>'posto'), v_nome, v_mat, btrim(p->>'telefone'),
    v_km, v_vtr.km_atual, p->>'combustivel',
    p->>'foto_frente', p->>'foto_traseira', p->>'foto_esquerda', p->>'foto_direita',
    p->>'assinatura_path', left(p->>'dispositivo', 300))
  returning id into v_id;

  -- Cada item ativo do checklist precisa de resposta
  for v_item in select * from public.checklist_itens where ativo order by ordem, titulo loop
    v_resp := null;
    select e into v_resp from jsonb_array_elements(coalesce(p->'itens','[]'::jsonb)) e
     where e->>'item_id' = v_item.id::text limit 1;
    v_status := coalesce(v_resp->>'status', 'OK');
    if v_status not in ('OK','ALTERACAO') then raise exception 'Status inválido no item %.', v_item.titulo; end if;
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
    values (v_id, v_item.id, v_item.titulo, v_status, v_obs, v_foto);

    -- Avaria não comunicada: alterada agora e NÃO apontada na vistoria anterior
    if v_status = 'ALTERACAO' and v_ant.id is not null and not exists (
         select 1 from public.vistoria_itens a
          where a.vistoria_id = v_ant.id and a.item_id = v_item.id and a.status = 'ALTERACAO') then
      insert into public.sinistros (
        viatura_id, vistoria_detectora_id, vistoria_anterior_id, item_id, item_titulo, observacao, foto_path,
        responsavel_nome, responsavel_matricula, comunicante_nome, comunicante_matricula)
      values (
        v_vtr.id, v_id, v_ant.id, v_item.id, v_item.titulo, v_obs, v_foto,
        v_ant.condutor_posto || ' ' || v_ant.condutor_nome_guerra, v_ant.condutor_matricula,
        btrim(p->>'posto') || ' ' || v_nome, v_mat);
      v_omitidos := v_omitidos + 1;
    end if;
  end loop;

  update public.viaturas set km_atual = v_km where id = v_vtr.id;

  return jsonb_build_object(
    'id', v_id,
    'protocolo', v_protocolo,
    'registrado_em', now(),
    'avarias_nao_comunicadas', v_omitidos);
end $$;

revoke all on function public.finalizar_vistoria(jsonb) from public;
revoke all on function public.passagem_viatura(uuid) from public;
grant execute on function public.finalizar_vistoria(jsonb) to anon, authenticated;
grant execute on function public.passagem_viatura(uuid) to anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;
