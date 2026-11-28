// =============================================================================
// SisCheck-VTR — aplicação (motorista + chefe de transporte)
// =============================================================================
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY, BUCKET } from './config.js';

const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ---------------------------------------------------------------------------
// Utilitários
// ---------------------------------------------------------------------------
const $ = (id) => document.getElementById(id);
const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ESC[c]);
const icons = () => window.lucide && window.lucide.createIcons();
const fmtKm = (n) => Number(n || 0).toLocaleString('pt-BR');
const fmtDT = (iso) => new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', dateStyle: 'short', timeStyle: 'short' });
const todayStr = () => new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Sao_Paulo' }); // YYYY-MM-DD
const parseLocalDate = (s) => { const [y, m, d] = String(s).split('-').map(Number); return new Date(y, m - 1, d); };
const fmtDate = (s) => parseLocalDate(s).toLocaleDateString('pt-BR');
const digits = (s) => String(s || '').replace(/\D/g, '');
const PLATE_RE = /^[A-Z]{3}-?[0-9][A-Z0-9][0-9]{2}$/;
const BADGE_RE = /^[0-9][0-9.\-/ ]{2,19}$/;
const STATUS_VTR = { ativa: 'Ativa', manutencao: 'Manutenção', reserva: 'Reserva', baixada: 'Baixada' };
const STATUS_SIN = { aguardando_despacho: 'Aguardando despacho', em_apuracao: 'Em apuração', procedente: 'Procedente', arquivado: 'Arquivado' };
const LOCAIS_AVARIA = ['Frente', 'Traseira', 'Lateral esquerda', 'Lateral direita', 'Teto', 'Vidros', 'Rodas/pneus', 'Interior', 'Outro'];
const SIDES = [
  { key: 'Frente', icon: 'arrow-up-circle', label: 'FRENTE', field: 'foto_frente' },
  { key: 'Traseira', icon: 'arrow-down-circle', label: 'TRASEIRA', field: 'foto_traseira' },
  { key: 'Esquerda', icon: 'arrow-left-circle', label: 'LAT. ESQUERDA', field: 'foto_esquerda' },
  { key: 'Direita', icon: 'arrow-right-circle', label: 'LAT. DIREITA', field: 'foto_direita' }
];

let toastTimer;
function toast(msg, type = 'info', ms = 4500) {
  const el = $('toast');
  const cls = { info: 'bg-slate-800 border border-slate-600 text-white', ok: 'bg-emerald-600 text-white', err: 'bg-red-600 text-white' };
  el.className = `fixed left-1/2 -translate-x-1/2 bottom-20 z-[60] max-w-sm w-[92%] px-4 py-3 rounded-xl text-xs font-bold shadow-2xl ${cls[type] || cls.info}`;
  el.textContent = msg;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.add('hidden'), ms);
}

function friendlyError(error) {
  const m = error?.message || String(error);
  if (/Failed to fetch|NetworkError|Load failed/i.test(m)) return 'Sem conexão com a internet. Tente novamente quando o sinal voltar.';
  if (error?.code === '23505') return 'Já existe um registro com esse prefixo ou placa.';
  if (/row-level security/i.test(m)) return 'Sem permissão para esta ação.';
  return m;
}

function setNet(ok, text) {
  $('netDot').className = `w-2 h-2 rounded-full ${ok ? 'bg-emerald-400' : 'bg-red-500'}`;
  $('netText').textContent = text;
}

function markInvalid(ids) {
  document.querySelectorAll('.inp-error').forEach((e) => e.classList.remove('inp-error'));
  ids.forEach((id) => $(id)?.classList.add('inp-error'));
  if (ids[0]) $(ids[0])?.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

// ---------------------------------------------------------------------------
// Cálculo do óleo (KM ou tempo, o que vencer primeiro)
// ---------------------------------------------------------------------------
function oilStatus(v, km) {
  if (v.km_ultima_troca_oleo == null || !v.data_ultima_troca_oleo) {
    // Sem troca registrada: orientação pela próxima marca de intervalo do odômetro (ex.: 10.000, 20.000…)
    const iv = v.intervalo_troca_oleo_km || 10000;
    if (!km) return { status: 'SEM_DADOS', estimated: true, reason: 'Aguardando o KM da primeira vistoria', health: 0, nextKm: null, nextDate: '—' };
    const nextKm = (Math.floor(km / iv) + 1) * iv;
    const rem = nextKm - km;
    return {
      status: rem <= 1000 ? 'ALERTA' : 'OK', estimated: true,
      reason: `Orientação: faltam ${fmtKm(rem)} km para a troca dos ${fmtKm(nextKm)} km`,
      health: Math.round(rem / iv * 100), nextKm, nextDate: '—'
    };
  }
  const kmUsed = km - v.km_ultima_troca_oleo;
  const kmRem = v.intervalo_troca_oleo_km - kmUsed;
  const last = parseLocalDate(v.data_ultima_troca_oleo);
  const today = parseLocalDate(todayStr());
  const daysPassed = Math.round((today - last) / 864e5);
  const daysRem = v.intervalo_troca_oleo_dias - daysPassed;
  const worst = Math.max(kmUsed / v.intervalo_troca_oleo_km, daysPassed / v.intervalo_troca_oleo_dias) * 100;
  const health = Math.max(0, Math.min(100, Math.round(100 - worst)));
  const next = new Date(last); next.setDate(next.getDate() + v.intervalo_troca_oleo_dias);

  let status = 'OK', reason;
  if (kmRem <= 0 || daysRem <= 0) {
    status = 'VENCIDO';
    const parts = [];
    if (kmRem <= 0) parts.push(`por KM (${fmtKm(-kmRem)} km além do limite)`);
    if (daysRem <= 0) parts.push(`por tempo (${-daysRem} dias além do prazo de ${v.intervalo_troca_oleo_dias})`);
    reason = 'Vencido ' + parts.join(' e ');
  } else if (kmRem <= 1000 || daysRem <= 20) {
    status = 'ALERTA';
    reason = `Próximo da troca: restam ${fmtKm(kmRem)} km ou ${daysRem} dias`;
  } else {
    reason = `Em dia: restam ${fmtKm(kmRem)} km ou ${daysRem} dias`;
  }
  return { status, reason, health, nextKm: v.km_ultima_troca_oleo + v.intervalo_troca_oleo_km, nextDate: next.toLocaleDateString('pt-BR') };
}

// Miniatura sem carimbo (o carimbo tem o nome de quem apontou; a miniatura é vista por outros motoristas)
async function makeThumb(file) {
  const img = await loadImage(file);
  const max = 360;
  const r = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
  const c = document.createElement('canvas');
  c.width = Math.round(img.naturalWidth * r); c.height = Math.round(img.naturalHeight * r);
  c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
  return new Promise((res) => c.toBlob(res, 'image/jpeg', 0.7));
}

// ---------------------------------------------------------------------------
// Imagem: redimensiona + carimbo
// ---------------------------------------------------------------------------
function loadImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('Não foi possível ler a imagem.')); };
    img.src = url;
  });
}

async function stampPhoto(file, line1, line2) {
  const img = await loadImage(file);
  const maxDim = 1280;
  let w = img.naturalWidth, h = img.naturalHeight;
  if (w > maxDim || h > maxDim) {
    if (w >= h) { h = Math.round(h * maxDim / w); w = maxDim; } else { w = Math.round(w * maxDim / h); h = maxDim; }
  }
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const ctx = c.getContext('2d');
  ctx.drawImage(img, 0, 0, w, h);
  const fs = Math.max(13, Math.round(w / 52));
  const bar = fs * 3.4;
  ctx.fillStyle = 'rgba(6,10,23,0.85)';
  ctx.fillRect(0, h - bar, w, bar);
  ctx.fillStyle = '#f59e0b';
  ctx.font = `bold ${fs}px monospace`;
  ctx.fillText(line1, fs, h - bar + fs * 1.35);
  ctx.fillStyle = '#ffffff';
  ctx.font = `${Math.round(fs * 0.85)}px sans-serif`;
  ctx.fillText(line2, fs, h - bar + fs * 2.75);
  const blob = await new Promise((r) => c.toBlob(r, 'image/jpeg', 0.8));
  return { blob, url: URL.createObjectURL(blob) };
}

// =============================================================================
// ESTADO
// =============================================================================
const S = {
  viaturas: [], itens: [], avisos: [], passagem: null, avariasAbertas: [], avariasNovas: [],
  confirmadas: new Set(), miniUrls: {},
  step: 1, answers: {}, photos: {}, sigHas: false, sending: false,
  isAdmin: false, admin: { viaturas: [], itens: [], avisos: [], sinistros: [], avarias: [], confirmacoes: [] },
  oilVtr: null
};
const currentVtr = () => S.viaturas.find((v) => v.id === $('vehiclePrefixSelect').value);

// =============================================================================
// MOTORISTA
// =============================================================================
async function loadDriverData() {
  const [v, i, a] = await Promise.all([
    sb.from('viaturas').select('*').neq('status_operacional', 'baixada').order('prefixo'),
    sb.from('checklist_itens').select('*').eq('ativo', true).order('ordem').order('titulo'),
    sb.from('avisos').select('id, viatura_id, mensagem, created_at').eq('ativo', true).order('created_at', { ascending: false })
  ]);
  const err = v.error || i.error || a.error;
  if (err) { setNet(false, 'Sem conexão com a nuvem'); toast(friendlyError(err), 'err'); return false; }
  setNet(true, 'Nuvem conectada');
  S.viaturas = v.data; S.itens = i.data; S.avisos = a.data;

  const sel = $('vehiclePrefixSelect');
  const prev = sel.value;
  sel.innerHTML = S.viaturas.length
    ? '<option value="">Selecione a VTR…</option>' + S.viaturas.map((x) => `<option value="${esc(x.id)}">${esc(x.prefixo)} (${esc(x.modelo)})</option>`).join('')
    : '<option value="">Nenhuma viatura cadastrada</option>';
  if (prev && S.viaturas.some((x) => x.id === prev)) sel.value = prev;
  // remove respostas de itens que deixaram de existir
  Object.keys(S.answers).forEach((k) => { if (!S.itens.some((it) => it.id === k)) delete S.answers[k]; });
  await onVehicleChange(false);
  renderChecklist();
  return true;
}

async function onVehicleChange(resetPhotos = true) {
  const vtr = currentVtr();
  if (resetPhotos) { S.photos = {}; renderPhotoGrid(); }
  $('vtrNoticePrefixLabel').textContent = vtr ? vtr.prefixo : '---';
  $('kmHint').textContent = !vtr ? '' : vtr.km_atual > 0 ? `Último registrado: ${fmtKm(vtr.km_atual)} km` : 'Primeiro registro: digite o KM do painel';
  $('vehicleKmInput').placeholder = vtr && vtr.km_atual > 0 ? `≥ ${vtr.km_atual}` : 'KM do painel';

  const notices = vtr ? S.avisos.filter((a) => a.viatura_id === vtr.id) : [];
  $('vtrNoticesContainer').innerHTML = notices.length
    ? notices.map((n) => `<div class="flex items-start gap-2 bg-slate-900/60 p-2.5 rounded-lg border border-amber-500/20"><i data-lucide="info" class="w-3.5 h-3.5 text-amber-400 shrink-0 mt-0.5"></i><span>${esc(n.mensagem)}</span></div>`).join('')
    : `<p class="text-amber-200/60">${vtr ? 'Nenhum aviso ativo para esta viatura.' : 'Selecione a viatura.'}</p>`;

  S.passagem = null; S.avariasAbertas = []; S.confirmadas = new Set(); S.miniUrls = {};
  renderPrevShift();
  renderOilCard();
  renderAvarias();
  if (vtr) {
    const { data, error } = await sb.rpc('passagem_viatura', { p_viatura_id: vtr.id });
    if (!error && currentVtr()?.id === vtr.id) {
      S.passagem = data?.ultima || null;
      S.avariasAbertas = data?.avarias_abertas || [];
      renderPrevShift(); renderAvarias();
      loadMiniaturas(vtr.id);
    }
  }
  icons();
}

// Miniaturas das avarias em aberto (o servidor só libera as de avarias abertas)
async function loadMiniaturas(vid) {
  const paths = S.avariasAbertas.map((a) => a.foto_mini).filter(Boolean);
  if (!paths.length) return;
  const { data } = await sb.storage.from(BUCKET).createSignedUrls(paths, 900);
  if (currentVtr()?.id !== vid || !data) return;
  S.miniUrls = Object.fromEntries(data.filter((d) => d.signedUrl).map((d) => [d.path, d.signedUrl]));
  renderAvarias();
}

function renderPrevShift() {
  const el = $('prevShiftCard');
  const vtr = currentVtr();
  if (!vtr) { el.innerHTML = '<p class="text-slate-500 text-[11px]">Selecione a viatura para ver a passagem de serviço.</p>'; return; }
  const p = S.passagem;
  if (!p) {
    el.innerHTML = `<div class="flex items-center gap-1.5 text-slate-400 text-[11px] font-bold"><i data-lucide="history" class="w-3.5 h-3.5 text-tactical-accent"></i>Passagem de serviço</div>
      <p class="text-[11px] text-slate-400">Nenhuma vistoria anterior registrada para esta VTR. Esta será a primeira.</p>`;
    icons(); return;
  }
  const alts = p.alteracoes || [];
  el.innerHTML = `
    <div class="flex items-center justify-between text-slate-300 font-bold border-b border-slate-800 pb-1.5">
      <span class="flex items-center gap-1.5 text-slate-400 text-[11px]"><i data-lucide="history" class="w-3.5 h-3.5 text-tactical-accent"></i>Último condutor:</span>
      <span class="text-tactical-gold font-bold text-[11px]">${esc(p.condutor)} (Mat. ${esc(p.matricula)})</span>
    </div>
    <div class="flex justify-between text-[11px] text-slate-400">
      <span>Em: <b class="text-white">${esc(fmtDT(p.em))}</b></span>
      <span>KM: <b class="text-white font-mono">${fmtKm(p.km)}</b></span>
    </div>
    <div class="p-2 rounded-lg bg-slate-800/80 text-[11px] text-slate-300 border border-slate-700/60">
      <span class="text-amber-400 font-bold">Alterações que ele apontou:</span>
      ${alts.length ? `<ul class="list-disc pl-4 mt-1">${alts.map((a) => `<li><b>${esc(a.titulo)}</b>${a.obs ? ': ' + esc(a.obs) : ''}</li>`).join('')}</ul>` : ' Nenhuma. Viatura entregue sem alterações.'}
    </div>
    ${S.avariasAbertas.length ? `<div class="text-[11px] text-red-300">${S.avariasAbertas.length} avaria(s) de lataria/outras já registrada(s) nesta VTR. No passo 3, confirme as que ainda estão lá em vez de registrar de novo.</div>` : ''}`;
  icons();
}

function renderOilCard() {
  const card = $('oilStatusCard');
  const vtr = currentVtr();
  if (!vtr) { card.className = 'hidden'; return; }
  const km = parseInt($('vehicleKmInput').value, 10);
  const oil = oilStatus(vtr, Number.isFinite(km) && km >= vtr.km_atual ? km : vtr.km_atual);
  if (oil.status === 'SEM_DADOS') {
    card.className = 'bg-slate-900 border border-slate-700 rounded-2xl p-3.5 space-y-1';
    card.innerHTML = `<div class="flex items-center gap-1.5 text-xs font-black uppercase text-slate-300"><i data-lucide="droplet" class="w-4 h-4 text-slate-400"></i>Óleo do motor</div>
      <p class="text-[11px] text-slate-400">Digite o KM do painel para ver quanto falta até a próxima troca (a cada ${fmtKm(vtr.intervalo_troca_oleo_km)} km).</p>`;
  } else if (oil.status === 'VENCIDO') {
    card.className = 'bg-red-500/15 border-2 border-red-500 rounded-2xl p-3.5 shadow-lg space-y-2';
    card.innerHTML = `<div class="flex items-center justify-between text-xs font-black uppercase text-red-400"><span class="flex items-center gap-1.5"><i data-lucide="alert-triangle" class="w-4 h-4 text-red-500"></i>Óleo do motor vencido</span><span class="text-[10px] bg-red-500 text-white px-2 py-0.5 rounded font-mono">0%</span></div>
      <p class="text-xs text-red-200">${esc(oil.reason)}</p>
      <div class="text-[10px] text-red-300 bg-red-950/60 p-2 rounded-lg border border-red-500/30">Troca prevista para <b>${fmtKm(oil.nextKm)} km</b> ou <b>${oil.nextDate}</b>. Avise o Chefe de Transporte antes de missões longas.</div>`;
  } else if (oil.status === 'ALERTA') {
    card.className = 'bg-amber-500/15 border border-amber-500 rounded-2xl p-3.5 shadow-md space-y-2';
    card.innerHTML = `<div class="flex items-center justify-between text-xs font-black uppercase text-amber-400"><span class="flex items-center gap-1.5"><i data-lucide="droplet" class="w-4 h-4"></i>Óleo próximo da troca</span><span class="text-[10px] bg-amber-500 text-slate-950 px-2 py-0.5 rounded font-mono font-bold">${oil.health}%</span></div>
      <p class="text-xs text-amber-200">${esc(oil.reason)}</p>
      <div class="w-full bg-slate-800 h-1.5 rounded-full overflow-hidden"><div class="bg-amber-500 h-full" style="width:${oil.health}%"></div></div>`;
  } else {
    card.className = 'bg-emerald-500/10 border border-emerald-500/30 rounded-2xl p-3.5 shadow-sm space-y-1.5';
    card.innerHTML = `<div class="flex items-center justify-between text-xs font-black uppercase text-emerald-400"><span class="flex items-center gap-1.5"><i data-lucide="check-circle" class="w-4 h-4"></i>${oil.estimated ? 'Próxima troca de óleo' : 'Óleo do motor em dia'}</span><span class="text-[10px] font-mono font-bold">${oil.health}% vida útil</span></div>
      <p class="text-[11px] text-slate-300">${esc(oil.reason)}</p>`;
  }
  icons();
}

// ----- Passo 2: fotos -----
function renderPhotoGrid() {
  $('photoGrid').innerHTML = SIDES.map((s) => {
    const p = S.photos[s.key];
    return `<div class="bg-slate-900 border ${p ? 'border-emerald-500/50' : 'border-slate-800'} rounded-2xl p-2.5 flex flex-col items-center text-center">
      <div class="w-full aspect-video bg-slate-800/80 rounded-xl border-2 border-dashed border-slate-700 flex flex-col items-center justify-center overflow-hidden mb-2">
        ${p ? `<img src="${p.url}" alt="${s.label}" class="w-full h-full object-cover">` : `<i data-lucide="${s.icon}" class="w-5 h-5 mb-1 text-tactical-gold"></i><span class="text-[10px] font-bold text-slate-400">${s.label}</span>`}
      </div>
      <label class="w-full bg-slate-800 hover:bg-slate-700 text-white text-[10px] font-black py-2 px-2 rounded-lg flex items-center justify-center gap-1.5 cursor-pointer border border-slate-700">
        <i data-lucide="camera" class="w-3.5 h-3.5 text-tactical-gold"></i>${p ? 'Refazer' : 'Capturar'}
        <input type="file" accept="image/*" capture="environment" class="sr-only" data-side="${s.key}">
      </label></div>`;
  }).join('');
  icons();
}

async function onSidePhoto(input) {
  const file = input.files?.[0]; if (!file) return;
  const side = input.dataset.side;
  const vtr = currentVtr();
  try {
    const nome = `${$('driverRank').value} ${$('driverWarName').value.trim().toUpperCase()}`;
    const res = await stampPhoto(file,
      `SISCHECK-VTR | ${vtr?.prefixo || '?'} | ${side.toUpperCase()} | KM ${$('vehicleKmInput').value}`,
      `CONDUTOR: ${nome} | CAPTURA: ${new Date().toLocaleString('pt-BR')}`);
    if (S.photos[side]) URL.revokeObjectURL(S.photos[side].url);
    S.photos[side] = res;
    renderPhotoGrid();
  } catch (e) { toast(friendlyError(e), 'err'); }
}

// ----- Passo 3: checklist -----
function renderChecklist() {
  const cats = {};
  S.itens.forEach((it) => { (cats[it.categoria] ||= []).push(it); });
  let html = '';
  for (const [cat, items] of Object.entries(cats)) {
    html += `<div class="space-y-2 pt-1"><div class="text-[10px] font-black uppercase text-tactical-accent tracking-wider flex items-center gap-1.5 px-1"><span class="w-1.5 h-1.5 rounded-full bg-tactical-accent"></span>${esc(cat)}</div>`;
    items.forEach((it) => {
      const a = S.answers[it.id] || {};
      const isOk = a.status === 'OK', isAlt = a.status === 'ALTERACAO';
      html += `<div id="item-${it.id}" class="bg-slate-900 border ${isAlt ? 'border-red-500/70' : (a.status ? 'border-slate-800' : 'border-slate-700 border-dashed')} rounded-2xl p-3 shadow-sm">
        <div class="flex items-center justify-between gap-2">
          <div class="flex-1 pr-2"><span class="text-xs font-bold text-white block leading-snug">${esc(it.titulo)}</span>
            ${it.exige_foto ? '<span class="text-[9px] text-amber-400 font-bold uppercase">Foto obrigatória se alterado</span>' : ''}</div>
          <div class="flex items-center gap-1.5 shrink-0">
            <button type="button" data-act="OK" data-id="${it.id}" class="px-3 py-1.5 rounded-lg text-xs font-bold border ${isOk ? 'bg-emerald-500 text-slate-950 border-emerald-400' : 'bg-slate-800 border-slate-700 text-slate-400'}">OK</button>
            <button type="button" data-act="ALTERACAO" data-id="${it.id}" class="px-2.5 py-1.5 rounded-lg text-xs font-bold border ${isAlt ? 'bg-red-500 text-white border-red-400' : 'bg-slate-800 border-slate-700 text-slate-400'}">Alteração</button>
          </div>
        </div>
        ${isAlt ? `<div class="mt-2.5 pt-2.5 border-t border-red-500/30 space-y-2">
          <input type="text" maxlength="500" data-obs="${it.id}" value="${esc(a.obs || '')}" placeholder="Descreva o defeito/avaria…" class="w-full bg-slate-950 border border-red-500/40 rounded-lg px-2.5 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-red-400">
          <div class="flex items-center gap-2">
            <label class="flex-1 bg-red-500/20 border border-red-500/50 rounded-lg py-2 px-3 text-[10px] font-bold text-red-200 flex items-center justify-center gap-1.5 cursor-pointer">
              <i data-lucide="camera" class="w-3.5 h-3.5 text-red-400"></i><span>${a.photo ? 'Trocar foto' : 'Adicionar foto da avaria'}</span>
              <input type="file" accept="image/*" capture="environment" class="sr-only" data-itemphoto="${it.id}">
            </label>
            ${a.photo ? `<div class="w-9 h-9 rounded-lg border border-red-400 overflow-hidden shrink-0"><img src="${a.photo.url}" alt="" class="w-full h-full object-cover"></div>` : ''}
          </div></div>` : ''}
      </div>`;
    });
    html += '</div>';
  }
  $('dynamicChecklistContainer').innerHTML = html || '<p class="text-xs text-slate-500">Nenhum item de checklist cadastrado.</p>';
  icons();
}

async function onItemPhoto(input) {
  const file = input.files?.[0]; if (!file) return;
  const id = input.dataset.itemphoto;
  const it = S.itens.find((x) => x.id === id);
  try {
    const res = await stampPhoto(file, `SISCHECK-VTR | ${currentVtr()?.prefixo || '?'} | AVARIA`, (it?.titulo || '').toUpperCase().slice(0, 70));
    const a = (S.answers[id] ||= { status: 'ALTERACAO' });
    if (a.photo) URL.revokeObjectURL(a.photo.url);
    a.photo = res;
    renderChecklist();
  } catch (e) { toast(friendlyError(e), 'err'); }
}

// ----- Avarias fora do checklist -----
function renderAvarias() {
  const ab = S.avariasAbertas;
  $('avariasAbertasList').innerHTML = ab.length
    ? `<div class="p-2.5 rounded-xl bg-sky-500/10 border border-sky-500/30 text-[11px] text-sky-100 space-y-0.5">
        <div class="font-black uppercase text-[10px] text-sky-300 flex items-center gap-1"><i data-lucide="shield-check" class="w-3.5 h-3.5"></i>Já registradas nesta VTR (${ab.length})</div>
        <div>Essas avarias já foram comunicadas e <b>não são sua responsabilidade</b>. Se ainda estiverem lá, toque em <b>Confirmo, ainda presente</b>. Não precisa fotografar nem registrar de novo: a confirmação fica gravada com seu nome e a hora do servidor.</div>
      </div>` +
      ab.map((a) => {
        const on = a.id && S.confirmadas.has(a.id);
        const mini = a.foto_mini && S.miniUrls[a.foto_mini];
        const n = Number(a.confirmacoes || 0);
        return `<div class="rounded-xl border ${on ? 'border-emerald-500/60 bg-emerald-500/10' : 'border-slate-700 bg-slate-800/70'} p-2 flex gap-2.5">
          <div class="w-16 h-16 rounded-lg overflow-hidden bg-slate-950 border border-slate-700 shrink-0 flex items-center justify-center">
            ${mini ? `<img src="${mini}" alt="" class="w-full h-full object-cover" data-avzoom="${esc(mini)}">` : '<i data-lucide="image-off" class="w-5 h-5 text-slate-600"></i>'}
          </div>
          <div class="flex-1 min-w-0 space-y-1">
            <div class="text-[11px]"><b class="text-amber-300">${esc(a.local)}</b>: ${esc(a.descricao)}</div>
            <div class="text-[10px] text-slate-500">Registrada em ${esc(fmtDT(a.em))}${n ? ` • confirmada ${n}x, última em ${esc(fmtDT(a.ultima_confirmacao))}` : ''}</div>
            ${a.id ? `<button type="button" data-avconf="${esc(a.id)}" class="text-[10px] font-black px-2.5 py-1 rounded-lg flex items-center gap-1 ${on ? 'bg-emerald-500 text-slate-950' : 'bg-slate-700 text-white border border-slate-600'}">
              <i data-lucide="${on ? 'check-circle' : 'circle'}" class="w-3.5 h-3.5"></i>${on ? 'Confirmado: ainda presente' : 'Confirmo, ainda presente'}</button>` : ''}
          </div>
        </div>`;
      }).join('')
    : `<p class="text-[11px] text-slate-500">${currentVtr() ? 'Nenhuma avaria registrada nesta VTR até agora.' : ''}</p>`;
  $('avariasNovasList').innerHTML = S.avariasNovas.map((a, i) => `
    <div class="bg-red-950/30 border border-red-500/50 rounded-xl p-2.5 space-y-2">
      <div class="flex items-center justify-between">
        <span class="text-[10px] font-black uppercase text-red-300">Nova avaria ${i + 1}</span>
        <button type="button" data-avrm="${i}" class="text-[10px] text-slate-400 underline">remover</button>
      </div>
      <select data-avlocal="${i}" class="inp">
        <option value="">Local da avaria…</option>
        ${LOCAIS_AVARIA.map((l) => `<option ${a.local === l ? 'selected' : ''}>${l}</option>`).join('')}
      </select>
      ${(() => { const iguais = S.avariasAbertas.filter((x) => x.local === a.local); return a.local && iguais.length ? `<div class="text-[10px] text-sky-200 bg-sky-500/10 border border-sky-500/30 rounded-lg px-2 py-1.5">Já existe ${iguais.length} avaria registrada em <b>${esc(a.local)}</b> (lista acima). Se for a mesma, use <b>Confirmo, ainda presente</b> e remova este registro.</div>` : ''; })()}
      <input type="text" maxlength="300" data-avdesc="${i}" value="${esc(a.desc || '')}" placeholder="Ex: arranhão de 20 cm na porta traseira" class="inp">
      <div class="flex items-center gap-2">
        <label class="flex-1 bg-red-500/20 border border-red-500/50 rounded-lg py-2 px-3 text-[10px] font-bold text-red-200 flex items-center justify-center gap-1.5 cursor-pointer">
          <i data-lucide="camera" class="w-3.5 h-3.5 text-red-400"></i><span>${a.photo ? 'Trocar foto' : 'Foto da avaria (obrigatória)'}</span>
          <input type="file" accept="image/*" capture="environment" class="sr-only" data-avphoto="${i}">
        </label>
        ${a.photo ? `<div class="w-12 h-12 rounded-lg border border-red-400 overflow-hidden shrink-0"><img src="${a.photo.url}" alt="" class="w-full h-full object-cover"></div>` : ''}
      </div>
    </div>`).join('');
  icons();
}

async function onAvariaPhoto(input) {
  const file = input.files?.[0]; if (!file) return;
  const i = Number(input.dataset.avphoto);
  const a = S.avariasNovas[i]; if (!a) return;
  try {
    const res = await stampPhoto(file, `SISCHECK-VTR | ${currentVtr()?.prefixo || '?'} | AVARIA ${(a.local || '').toUpperCase()}`,
      `APONTADA POR: ${driverName()} | CAPTURA: ${new Date().toLocaleString('pt-BR')}`);
    if (a.photo) URL.revokeObjectURL(a.photo.url);
    a.photo = res;
    a.mini = await makeThumb(file).catch(() => null);
    renderAvarias();
  } catch (e) { toast(friendlyError(e), 'err'); }
}

// ----- Validações por passo -----
function validateStep1() {
  const bad = [], msgs = [];
  const vtr = currentVtr();
  if (!$('driverRank').value) { bad.push('driverRank'); msgs.push('posto/graduação'); }
  if ($('driverWarName').value.trim().length < 2) { bad.push('driverWarName'); msgs.push('nome de guerra'); }
  if (!BADGE_RE.test($('driverBadge').value.trim())) { bad.push('driverBadge'); msgs.push('matrícula'); }
  if (!vtr) { bad.push('vehiclePrefixSelect'); msgs.push('viatura'); }
  const km = Number($('vehicleKmInput').value);
  if (vtr) {
    if (!$('vehicleKmInput').value || !Number.isInteger(km)) { bad.push('vehicleKmInput'); msgs.push('KM'); }
    else if (km < vtr.km_atual) { bad.push('vehicleKmInput'); msgs.push(`KM não pode ser menor que ${fmtKm(vtr.km_atual)}`); }
    else if (vtr.km_atual > 0 && km > vtr.km_atual + 5000) { bad.push('vehicleKmInput'); msgs.push('KM muito acima do último registro: confira o odômetro'); }
  }
  const tel = digits($('dutyPhoneInput').value);
  if (tel.length < 10 || tel.length > 11) { bad.push('dutyPhoneInput'); msgs.push('telefone com DDD'); }
  if (!document.querySelector('input[name="fuelLevel"]:checked')) { bad.push('fuelGroup'); msgs.push('combustível'); }
  markInvalid(bad);
  if (msgs.length) { toast('Confira: ' + msgs.join(', ') + '.', 'err'); return false; }
  return true;
}

function validateStep2() {
  const missing = SIDES.filter((s) => !S.photos[s.key]).map((s) => s.label.toLowerCase());
  if (missing.length) { toast('Faltam as fotos: ' + missing.join(', ') + '.', 'err'); return false; }
  return true;
}

function validateStep3() {
  for (const it of S.itens) {
    const a = S.answers[it.id];
    let msg = null;
    if (!a?.status) msg = `Responda o item "${it.titulo}".`;
    else if (a.status === 'ALTERACAO' && !(a.obs || '').trim()) msg = `Descreva a alteração em "${it.titulo}".`;
    else if (a.status === 'ALTERACAO' && it.exige_foto && !a.photo) msg = `Foto obrigatória da alteração em "${it.titulo}".`;
    if (msg) { $('item-' + it.id)?.scrollIntoView({ behavior: 'smooth', block: 'center' }); toast(msg, 'err'); return false; }
  }
  for (const [i, a] of S.avariasNovas.entries()) {
    let msg = null;
    if (!a.local) msg = `Informe o local da nova avaria ${i + 1}.`;
    else if ((a.desc || '').trim().length < 3) msg = `Descreva a nova avaria ${i + 1}.`;
    else if (!a.photo) msg = `Fotografe a nova avaria ${i + 1}.`;
    if (msg) { $('avariasSection').scrollIntoView({ behavior: 'smooth', block: 'center' }); toast(msg, 'err'); return false; }
  }
  return true;
}

// ----- Passo 4: revisão -----
function driverName() { return `${$('driverRank').value} ${$('driverWarName').value.trim().toUpperCase()}`; }

function renderReview() {
  const vtr = currentVtr();
  const alts = S.itens.filter((it) => S.answers[it.id]?.status === 'ALTERACAO');
  const prevIds = new Set((S.passagem?.alteracoes || []).map((a) => a.item_id));
  const omittedItens = S.passagem ? alts.filter((it) => !prevIds.has(it.id)) : [];
  const novas = S.avariasNovas.map((a) => ({ titulo: 'Avaria: ' + a.local, obs: a.desc.trim(), photo: a.photo }));
  const omitted = [...omittedItens.map((it) => ({ titulo: it.titulo, obs: S.answers[it.id].obs })), ...(S.passagem ? novas : [])];
  const banner = $('auditResponsibilityBanner');

  if (!S.passagem) {
    banner.className = 'bg-slate-900 border border-slate-700 rounded-2xl p-3.5 space-y-1';
    banner.innerHTML = `<div class="flex items-center gap-2 text-slate-300 font-bold text-xs uppercase"><i data-lucide="info" class="w-4 h-4"></i>Primeira vistoria desta VTR</div><p class="text-xs text-slate-400">Não há condutor anterior para comparar.</p>`;
  } else if (omitted.length) {
    banner.className = 'bg-red-500/15 border-2 border-red-500 rounded-2xl p-3.5 shadow-xl space-y-2';
    banner.innerHTML = `<div class="flex items-center gap-2 text-red-400 font-black text-xs uppercase"><i data-lucide="alert-octagon" class="w-5 h-5 text-red-500"></i>Alteração não apontada pelo condutor anterior</div>
      <div class="p-2.5 bg-red-950/70 rounded-xl border border-red-500/30 text-xs text-red-200 space-y-1.5">
        <div class="text-[11px]">Condutor anterior: <b class="text-tactical-gold">${esc(S.passagem.condutor)} (Mat. ${esc(S.passagem.matricula)})</b></div>
        <ul class="list-disc pl-4 space-y-0.5 text-[11px]">${omitted.map((o) => `<li><b>${esc(o.titulo)}</b>: ${esc(o.obs)}</li>`).join('')}</ul>
      </div>
      <p class="text-[10px] text-red-300 font-semibold">Ao finalizar, o registro resguarda o seu turno e é encaminhado ao Chefe de Transporte para apuração.</p>`;
  } else {
    banner.className = 'bg-emerald-500/10 border border-emerald-500/40 rounded-2xl p-3.5 space-y-1';
    banner.innerHTML = `<div class="flex items-center gap-2 text-emerald-400 font-bold text-xs uppercase"><i data-lucide="check-circle" class="w-4 h-4"></i>Conforme a passagem anterior</div><p class="text-xs text-slate-300">Nada novo em relação ao que foi entregue por <b>${esc(S.passagem.condutor)}</b>.</p>`;
  }

  $('reviewVtrPrefix').textContent = vtr?.prefixo || '---';
  const fuel = document.querySelector('input[name="fuelLevel"]:checked')?.value;
  $('reviewGrid').innerHTML = `
    <div>Motorista: <b class="text-white">${esc(driverName())}</b></div>
    <div>Matrícula: <b class="text-white font-mono">${esc($('driverBadge').value.trim())}</b></div>
    <div>KM: <b class="text-white font-mono">${fmtKm($('vehicleKmInput').value)}</b> <span class="text-slate-500">(+${fmtKm($('vehicleKmInput').value - (vtr?.km_atual || 0))})</span></div>
    <div>Combustível: <b class="text-white">${esc(fuel)}</b></div>
    <div class="col-span-2">Telefone da escala: <b class="text-white font-mono">${esc($('dutyPhoneInput').value)}</b></div>`;
  const todas = [...alts.map((it) => ({ titulo: it.titulo, obs: S.answers[it.id].obs, photo: S.answers[it.id].photo })), ...novas];
  $('reviewAlterationsList').innerHTML = todas.length
    ? todas.map((o) => `<li class="bg-slate-800/80 p-2 rounded-lg border border-red-500/30 flex items-start justify-between text-xs"><div><b class="text-red-400">${esc(o.titulo)}</b>: ${esc(o.obs)}</div>${o.photo ? '<span class="text-[9px] bg-red-500/20 text-red-300 px-1.5 py-0.5 rounded font-bold shrink-0 ml-1">Foto</span>' : ''}</li>`).join('')
    : '<li class="text-emerald-400 font-semibold">Sem alterações.</li>';
  const conf = confirmadasList();
  $('reviewConfirmadasBox').classList.toggle('hidden', !conf.length);
  $('reviewConfirmadasList').innerHTML = conf.map((a) => `<li class="bg-emerald-500/10 p-2 rounded-lg border border-emerald-500/30 text-xs"><b class="text-emerald-300">${esc(a.local)}</b>: ${esc(a.descricao)}</li>`).join('');
  icons();
}
function confirmadasList() { return S.avariasAbertas.filter((a) => a.id && S.confirmadas.has(a.id)); }

// ----- Assinatura -----
let sigCtx;
function initSignature() {
  const c = $('signatureCanvas');
  sigCtx = c.getContext('2d');
  sigCtx.strokeStyle = '#f59e0b'; sigCtx.lineWidth = 4; sigCtx.lineCap = 'round'; sigCtx.lineJoin = 'round';
  let drawing = false;
  const pos = (e) => { const r = c.getBoundingClientRect(); return { x: (e.clientX - r.left) * c.width / r.width, y: (e.clientY - r.top) * c.height / r.height }; };
  c.addEventListener('pointerdown', (e) => {
    e.preventDefault(); c.setPointerCapture(e.pointerId); drawing = true;
    const p = pos(e); sigCtx.beginPath(); sigCtx.moveTo(p.x, p.y);
    $('sigPlaceholder').classList.add('hidden');
  });
  c.addEventListener('pointermove', (e) => {
    if (!drawing) return;
    const p = pos(e); sigCtx.lineTo(p.x, p.y); sigCtx.stroke(); S.sigHas = true;
  });
  const stop = () => { drawing = false; };
  c.addEventListener('pointerup', stop); c.addEventListener('pointercancel', stop);
}
function clearSignature() {
  const c = $('signatureCanvas');
  sigCtx.clearRect(0, 0, c.width, c.height);
  S.sigHas = false;
  $('sigPlaceholder').classList.remove('hidden');
}

// ----- Navegação -----
const STEP_TITLES = ['Passo 1 de 4: Viatura & Escala', 'Passo 2 de 4: Fotos dos 4 Lados', 'Passo 3 de 4: Itens de Vistoria', 'Passo 4 de 4: Revisão & Assinatura'];
const NEXT_LABELS = ['Avançar para Fotos', 'Avançar para Vistoria', 'Revisar & Assinar', 'Finalizar & Enviar'];
function setStep(n) {
  S.step = n;
  [1, 2, 3, 4].forEach((i) => $('step' + i).classList.toggle('hidden', i !== n));
  $('btnPrevStep').classList.toggle('hidden', n === 1);
  $('stepTitle').textContent = STEP_TITLES[n - 1];
  $('stepPercent').textContent = n * 25 + '%';
  $('progressBar').style.width = n * 25 + '%';
  $('btnNextStepLabel').textContent = NEXT_LABELS[n - 1];
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

async function nextStep() {
  if (S.sending) return;
  if (S.step === 1 && validateStep1()) { localStorage.setItem('sischeck_tel', $('dutyPhoneInput').value.trim()); setStep(2); }
  else if (S.step === 2 && validateStep2()) setStep(3);
  else if (S.step === 3 && validateStep3()) { renderReview(); setStep(4); }
  else if (S.step === 4) await finalize();
}

// ----- Envio -----
function sending(on, text, pct) {
  $('modalSending').classList.toggle('hidden', !on);
  if (text) $('sendingText').textContent = text;
  if (pct != null) $('sendingBar').style.width = pct + '%';
}

async function finalize() {
  if (!S.sigHas) { toast('Assine no quadro antes de finalizar.', 'err'); return; }
  if (!navigator.onLine) { toast('Sem internet. Aguarde o sinal para enviar (nada foi perdido).', 'err'); return; }
  const vtr = currentVtr();
  S.sending = true; $('btnNextStep').disabled = true;
  try {
    const folder = `envios/${crypto.randomUUID()}`;
    const sigBlob = await new Promise((r) => $('signatureCanvas').toBlob(r, 'image/png'));
    const uploads = SIDES.map((s) => ({ path: `${folder}/${s.key.toLowerCase()}.jpg`, blob: S.photos[s.key].blob, type: 'image/jpeg', field: s.field }));
    uploads.push({ path: `${folder}/assinatura.png`, blob: sigBlob, type: 'image/png', field: 'assinatura_path' });
    S.itens.forEach((it) => {
      const a = S.answers[it.id];
      if (a?.status === 'ALTERACAO' && a.photo) uploads.push({ path: `${folder}/avaria-${it.id}.jpg`, blob: a.photo.blob, type: 'image/jpeg', itemId: it.id });
    });
    S.avariasNovas.forEach((a, i) => {
      uploads.push({ path: `${folder}/avaria-extra-${i + 1}.jpg`, blob: a.photo.blob, type: 'image/jpeg', extra: i });
      if (a.mini) uploads.push({ path: `${folder}/avaria-extra-${i + 1}-mini.jpg`, blob: a.mini, type: 'image/jpeg', mini: i });
    });

    let done = 0;
    sending(true, `Enviando fotos (0/${uploads.length})…`, 5);
    await Promise.all(uploads.map(async (u) => {
      const { error } = await sb.storage.from(BUCKET).upload(u.path, u.blob, { contentType: u.type, upsert: false });
      if (error) throw error;
      done++; sending(true, `Enviando fotos (${done}/${uploads.length})…`, 5 + Math.round(done / uploads.length * 80));
    }));

    sending(true, 'Registrando vistoria no servidor…', 92);
    const payload = {
      viatura_id: vtr.id,
      posto: $('driverRank').value,
      nome_guerra: $('driverWarName').value.trim(),
      matricula: $('driverBadge').value.trim(),
      telefone: $('dutyPhoneInput').value.trim(),
      km: Number($('vehicleKmInput').value),
      combustivel: document.querySelector('input[name="fuelLevel"]:checked').value,
      dispositivo: navigator.userAgent,
      itens: S.itens.map((it) => {
        const a = S.answers[it.id];
        const up = uploads.find((u) => u.itemId === it.id);
        return { item_id: it.id, status: a.status, observacao: a.status === 'ALTERACAO' ? a.obs : null, foto_path: up ? up.path : null };
      })
    };
    uploads.filter((u) => u.field).forEach((u) => { payload[u.field] = u.path; });
    payload.avarias_novas = S.avariasNovas.map((a, i) => ({
      local: a.local, descricao: a.desc.trim(),
      foto_path: uploads.find((u) => u.extra === i).path,
      foto_mini_path: uploads.find((u) => u.mini === i)?.path || null
    }));
    payload.avarias_confirmadas = confirmadasList().map((a) => a.id);

    const { data, error } = await sb.rpc('finalizar_vistoria', { p: payload });
    if (error) throw error;
    sending(false);
    showTermo(data, vtr);
  } catch (e) {
    sending(false);
    toast('Vistoria NÃO enviada: ' + friendlyError(e), 'err', 8000);
  } finally {
    S.sending = false; $('btnNextStep').disabled = false;
  }
}

function showTermo(res, vtr) {
  const fuel = document.querySelector('input[name="fuelLevel"]:checked')?.value;
  const alts = S.itens.filter((it) => S.answers[it.id]?.status === 'ALTERACAO');
  $('termoContentBody').innerHTML = `
    <div class="bg-slate-950 p-3 rounded-xl border border-slate-800 space-y-1.5 font-mono text-[11px]">
      <div class="flex justify-between text-tactical-gold font-bold"><span>PROTOCOLO: ${esc(res.protocolo)}</span><span>${esc(fmtDT(res.registrado_em))}</span></div>
      <div>VIATURA: <b>${esc(vtr.prefixo)}</b> (${esc(vtr.placa)}) | KM: <b>${fmtKm($('vehicleKmInput').value)}</b></div>
      <div>CONDUTOR: <b>${esc(driverName())}</b> (Mat. ${esc($('driverBadge').value.trim())})</div>
      <div>TEL. ESCALA: <b>${esc($('dutyPhoneInput').value)}</b> | COMB.: <b>${esc(fuel)}</b></div>
      <div>ALTERAÇÕES: <b>${alts.length ? esc(alts.map((a) => a.titulo).join('; ')) : 'nenhuma'}</b></div>
      ${confirmadasList().length ? `<div>AVARIAS JÁ REGISTRADAS, CONFIRMADAS POR VOCÊ: <b>${esc(confirmadasList().map((a) => `${a.local}: ${a.descricao}`).join('; '))}</b></div>` : ''}
      ${S.avariasNovas.length ? `<div>AVARIAS REGISTRADAS: <b>${esc(S.avariasNovas.map((a) => `${a.local}: ${a.desc.trim()}`).join('; '))}</b></div>` : ''}
    </div>
    <div class="p-3 bg-emerald-500/10 border border-emerald-500/30 rounded-xl text-emerald-300 text-xs font-semibold flex items-center gap-2">
      <i data-lucide="shield-check" class="w-5 h-5 text-emerald-400"></i><span>Vistoria registrada na nuvem. Data e hora gravadas pelo servidor.</span>
    </div>
    ${res.avarias_nao_comunicadas ? `<div class="p-3 bg-red-500/10 border border-red-500/30 rounded-xl text-red-300 text-xs font-semibold">${res.avarias_nao_comunicadas} alteração(ões)/avaria(s) não apontada(s) pelo condutor anterior foram encaminhadas ao Chefe de Transporte, registradas antes de você assumir a VTR.</div>` : ''}
    <div><span class="font-bold text-slate-300 block mb-1">Fotos enviadas:</span>
      <div class="grid grid-cols-4 gap-1.5">${SIDES.map((s) => `<div class="aspect-square bg-slate-800 rounded border border-slate-700 overflow-hidden"><img src="${S.photos[s.key].url}" alt="${s.label}" class="w-full h-full object-cover"></div>`).join('')}</div></div>
    <div><span class="font-bold text-slate-300 block mb-1">Assinatura:</span><div class="bg-slate-950 p-1 rounded-lg border border-slate-800"><img src="${$('signatureCanvas').toDataURL()}" alt="Assinatura" class="h-12 mx-auto"></div></div>`;
  $('modalTermoFinalizado').classList.remove('hidden');
  icons();
}

async function closeTermo() {
  $('modalTermoFinalizado').classList.add('hidden');
  resetDriver();
  await loadDriverData();
}

function resetDriver() {
  Object.values(S.photos).forEach((p) => URL.revokeObjectURL(p.url));
  Object.values(S.answers).forEach((a) => a.photo && URL.revokeObjectURL(a.photo.url));
  S.avariasNovas.forEach((a) => a.photo && URL.revokeObjectURL(a.photo.url));
  S.photos = {}; S.answers = {}; S.passagem = null; S.avariasNovas = []; S.avariasAbertas = []; S.confirmadas = new Set(); S.miniUrls = {};
  ['driverRank', 'driverWarName', 'driverBadge', 'vehicleKmInput', 'vehiclePrefixSelect'].forEach((id) => { $(id).value = ''; });
  document.querySelectorAll('input[name="fuelLevel"]').forEach((r) => { r.checked = false; });
  clearSignature();
  renderPhotoGrid(); renderChecklist(); renderAvarias();
  setStep(1);
}

// =============================================================================
// CHEFE DE TRANSPORTE
// =============================================================================
async function showAdmin() {
  const { data: { session } } = await sb.auth.getSession();
  if (session && await checkAdmin()) { $('adminLogin').classList.add('hidden'); $('adminPanel').classList.remove('hidden'); await loadAdmin(); }
  else { $('adminLogin').classList.remove('hidden'); $('adminPanel').classList.add('hidden'); }
  icons();
}

async function checkAdmin() {
  const { data, error } = await sb.rpc('is_admin');
  S.isAdmin = !error && data === true;
  return S.isAdmin;
}

async function onLogin(e) {
  e.preventDefault();
  const msg = $('loginMsg'); msg.classList.add('hidden');
  const { error } = await sb.auth.signInWithPassword({ email: $('loginEmail').value.trim(), password: $('loginPass').value });
  if (error) { msg.textContent = /Invalid login/i.test(error.message) ? 'E-mail ou senha incorretos.' : friendlyError(error); msg.classList.remove('hidden'); return; }
  if (!(await checkAdmin())) {
    await sb.auth.signOut();
    msg.textContent = 'Esta conta não tem permissão de Chefe de Transporte.'; msg.classList.remove('hidden'); return;
  }
  $('loginPass').value = '';
  await showAdmin();
}

async function onLogout() {
  await sb.auth.signOut();
  S.isAdmin = false;
  $('badgePendingAlerts').classList.add('hidden');
  await showAdmin();
}

async function loadAdmin() {
  const [v, i, a, s, av] = await Promise.all([
    sb.from('viaturas').select('*').order('prefixo'),
    sb.from('checklist_itens').select('*').order('ativo', { ascending: false }).order('ordem').order('titulo'),
    sb.from('avisos').select('id, viatura_id, mensagem, created_at').eq('ativo', true).order('created_at', { ascending: false }),
    sb.from('sinistros').select('*').order('created_at', { ascending: false }).limit(200),
    sb.from('avarias').select('*').eq('status', 'aberta').order('created_at', { ascending: false })
  ]);
  const err = v.error || i.error || a.error || s.error || av.error;
  if (err) { toast(friendlyError(err), 'err'); return; }
  // Confirmações das avarias em aberto (tabela pode não existir antes da migração: ignora erro)
  const ids = av.data.map((x) => x.id);
  const cf = ids.length ? await sb.from('avaria_confirmacoes').select('*').in('avaria_id', ids).order('created_at', { ascending: false }) : { data: [] };
  Object.assign(S.admin, { viaturas: v.data, itens: i.data, avisos: a.data, sinistros: s.data, avarias: av.data, confirmacoes: cf.data || [] });
  renderFleet(); renderAdminItems(); renderAdminNotices(); renderSinistros(); fillAdminSelects();
  if (!$('modalAvarias').classList.contains('hidden') && S.avariasVtr) openAvarias(S.avariasVtr);
  await loadInspections();
}

const vtrById = (id) => S.admin.viaturas.find((v) => v.id === id);

function fillAdminSelects() {
  const ativas = S.admin.viaturas.filter((v) => v.status_operacional !== 'baixada');
  $('adminNoticeTargetVtr').innerHTML = ativas.map((v) => `<option value="${v.id}">${esc(v.prefixo)} (${esc(v.modelo)})</option>`).join('');
  const f = $('inspFilterVtr'); const cur = f.value;
  f.innerHTML = '<option value="">Todas as VTRs</option>' + S.admin.viaturas.map((v) => `<option value="${v.id}">${esc(v.prefixo)}</option>`).join('');
  f.value = cur;
}

function switchTab(tab) {
  document.querySelectorAll('.admin-tab').forEach((el) => el.classList.add('hidden'));
  $('adminTab' + tab.charAt(0).toUpperCase() + tab.slice(1)).classList.remove('hidden');
  document.querySelectorAll('.tab-btn').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
}

// ----- Frota -----
function renderFleet() {
  const list = [...S.admin.viaturas].sort((a, b) => (a.status_operacional === 'baixada') - (b.status_operacional === 'baixada') || a.prefixo.localeCompare(b.prefixo));
  let total = 0, ready = 0, warn = 0, crit = 0;
  $('fleetVehiclesList').innerHTML = list.length ? list.map((v) => {
    const baixada = v.status_operacional === 'baixada';
    const oil = oilStatus(v, v.km_atual);
    if (!baixada) {
      total++;
      if (v.status_operacional === 'ativa' && oil.status !== 'VENCIDO') ready++;
      if (oil.status === 'ALERTA') warn++;
      if (oil.status === 'VENCIDO') crit++;
    }
    const semDados = oil.status === 'SEM_DADOS';
    const semTroca = v.km_ultima_troca_oleo == null;
    const tone = semDados ? ['bg-slate-700/60 text-slate-300 border-slate-600', 'bg-slate-600', 'text-slate-400', 'Óleo não informado']
      : oil.status === 'VENCIDO' ? ['bg-red-500/15 text-red-400 border-red-500/50', 'bg-red-500', 'text-red-400', 'Óleo vencido']
      : oil.status === 'ALERTA' ? ['bg-amber-500/10 text-amber-400 border-amber-500/40', 'bg-amber-500', 'text-amber-400', 'Troca próxima']
      : ['bg-emerald-500/10 text-emerald-400 border-emerald-500/30', 'bg-emerald-500', 'text-emerald-400', oil.estimated ? 'Óleo (orientação)' : 'Óleo em dia'];
    return `<div class="bg-slate-800/80 border border-slate-700/80 rounded-xl p-3.5 space-y-2.5 ${baixada ? 'opacity-50' : ''}">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-slate-700/50 pb-2">
        <div class="flex items-center gap-2 flex-wrap">
          <span class="text-sm font-black text-tactical-gold font-mono">${esc(v.prefixo)}</span>
          <span class="text-xs text-white font-bold">${esc(v.modelo)}</span>
          <span class="text-[10px] text-slate-400 font-mono">(${esc(v.placa)})</span>
          <span class="text-[9px] px-1.5 py-0.5 rounded bg-slate-700 text-slate-300 font-bold uppercase">${STATUS_VTR[v.status_operacional]}</span>
        </div>
        <div class="flex items-center gap-1.5">
          ${baixada ? '' : `<span class="text-[10px] px-2 py-0.5 rounded-full border font-bold uppercase ${tone[0]}">${tone[3]}</span>`}
          ${(() => { const n = S.admin.avarias.filter((x) => x.viatura_id === v.id).length; return `<button data-avarias="${v.id}" class="text-[10px] ${n ? 'bg-red-500/20 text-red-200 border border-red-500/40' : 'bg-slate-700 text-white'} font-bold px-2.5 py-1 rounded-lg flex items-center gap-1"><i data-lucide="car-front" class="w-3 h-3"></i>Avarias${n ? ` (${n})` : ''}</button>`; })()}
          <button data-edit="${v.id}" class="text-[10px] bg-slate-700 hover:bg-slate-600 text-white font-bold px-2.5 py-1 rounded-lg flex items-center gap-1"><i data-lucide="pencil" class="w-3 h-3"></i>Editar</button>
          ${baixada ? '' : `<button data-oil="${v.id}" class="text-[10px] bg-tactical-gold hover:bg-amber-500 text-slate-950 font-black px-2.5 py-1 rounded-lg flex items-center gap-1"><i data-lucide="wrench" class="w-3 h-3"></i>Troca</button>`}
        </div>
      </div>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 text-[11px] text-slate-300">
        <div>KM atual: <b class="text-white font-mono">${v.km_atual > 0 ? fmtKm(v.km_atual) : 'aguardando 1ª vistoria'}</b></div>
        ${semTroca ? `<div class="col-span-1 sm:col-span-3 text-slate-400">${oil.nextKm ? `Próxima troca (orientação): <b class="text-tactical-gold font-mono">${fmtKm(oil.nextKm)} km</b>. ` : ''}Sem troca registrada: use <b>Troca</b> quando fizer a próxima.</div>` : `
        <div>Última troca: <b class="text-white font-mono">${fmtKm(v.km_ultima_troca_oleo)}</b> <span class="text-slate-500">${fmtDate(v.data_ultima_troca_oleo)}</span></div>
        <div>Próxima: <b class="text-tactical-gold font-mono">${fmtKm(oil.nextKm)} km</b></div>
        <div>Prazo: <b class="text-white">${oil.nextDate}</b></div>`}
      </div>
      ${baixada || semDados ? '' : `<div class="space-y-1"><div class="flex justify-between text-[10px]"><span class="text-slate-400">${esc(oil.reason)}</span><span class="font-mono font-bold ${tone[2]}">${oil.health}%</span></div>
        <div class="w-full bg-slate-900 h-2 rounded-full overflow-hidden"><div class="h-full rounded-full ${tone[1]}" style="width:${oil.health}%"></div></div></div>`}
    </div>`;
  }).join('') : '<p class="text-xs text-slate-500 text-center py-4">Nenhuma viatura cadastrada. Use a aba "Cadastrar VTR".</p>';
  $('kpiTotalVehicles').textContent = total;
  $('kpiActiveVehicles').textContent = ready;
  $('kpiWarningOil').textContent = warn;
  $('kpiCriticalOil').textContent = crit;
  icons();
}

// ----- Cadastro / edição de VTR -----
function resetVtrForm() {
  $('formNewVehicle').reset();
  $('vtrEditId').value = '';
  $('newVtrLastOilDate').max = todayStr();
  $('vtrFormTitle').textContent = 'Cadastrar Nova Viatura';
  $('btnSaveVtrLabel').textContent = 'Cadastrar Viatura';
  $('tabNewVtrLabel').textContent = 'Cadastrar VTR';
  $('btnCancelEdit').classList.add('hidden');
  $('newVtrPrefix').disabled = false;
  $('vtrFormErrors').classList.add('hidden');
  markInvalid([]);
}

function editVtr(id) {
  const v = vtrById(id); if (!v) return;
  resetVtrForm();
  $('vtrEditId').value = v.id;
  $('newVtrPrefix').value = v.prefixo;
  $('newVtrPlate').value = v.placa;
  $('newVtrModel').value = v.modelo;
  $('newVtrKmAtual').value = v.km_atual;
  $('newVtrStatus').value = v.status_operacional;
  $('newVtrLastOilKm').value = v.km_ultima_troca_oleo;
  $('newVtrLastOilDate').value = v.data_ultima_troca_oleo;
  $('newVtrIntervalKm').value = v.intervalo_troca_oleo_km;
  $('newVtrIntervalDays').value = v.intervalo_troca_oleo_dias;
  $('vtrFormTitle').textContent = `Editar ${v.prefixo}`;
  $('btnSaveVtrLabel').textContent = 'Salvar Alterações';
  $('tabNewVtrLabel').textContent = 'Editar VTR';
  $('btnCancelEdit').classList.remove('hidden');
  switchTab('newVtr');
}

async function onSaveVtr(e) {
  e.preventDefault();
  const id = $('vtrEditId').value;
  const prefixo = $('newVtrPrefix').value.trim().toUpperCase().replace(/\s+/g, '-');
  const placa = $('newVtrPlate').value.trim().toUpperCase().replace(/\s+/g, '');
  const modelo = $('newVtrModel').value.trim();
  const km = Number($('newVtrKmAtual').value);
  const oilKm = Number($('newVtrLastOilKm').value);
  const oilDate = $('newVtrLastOilDate').value;
  const iKm = Number($('newVtrIntervalKm').value);
  const iDays = Number($('newVtrIntervalDays').value);

  const errs = [], bad = [];
  if (prefixo.length < 2 || prefixo.length > 20) { errs.push('Prefixo deve ter de 2 a 20 caracteres.'); bad.push('newVtrPrefix'); }
  if (!PLATE_RE.test(placa)) { errs.push('Placa inválida (ex.: ABC1234 ou BRA2E19).'); bad.push('newVtrPlate'); }
  if (modelo.length < 2) { errs.push('Informe o modelo.'); bad.push('newVtrModel'); }
  if ($('newVtrKmAtual').value === '' || !Number.isInteger(km) || km < 0) { errs.push('KM atual inválido.'); bad.push('newVtrKmAtual'); }
  const semOleo = $('newVtrLastOilKm').value === '' && !oilDate;
  if (!semOleo) {
    if ($('newVtrLastOilKm').value === '' || !Number.isInteger(oilKm) || oilKm < 0) { errs.push('KM da última troca inválido (ou deixe KM e data da troca em branco).'); bad.push('newVtrLastOilKm'); }
    else if (Number.isInteger(km) && oilKm > km) { errs.push('KM da última troca não pode ser maior que o KM atual.'); bad.push('newVtrLastOilKm'); }
    if (!oilDate) { errs.push('Informe a data da última troca (ou deixe KM e data da troca em branco).'); bad.push('newVtrLastOilDate'); }
    else if (oilDate > todayStr()) { errs.push('A data da última troca não pode estar no futuro.'); bad.push('newVtrLastOilDate'); }
  }
  if (!Number.isInteger(iKm) || iKm < 1000) { errs.push('Intervalo por KM deve ser de pelo menos 1.000.'); bad.push('newVtrIntervalKm'); }
  if (!Number.isInteger(iDays) || iDays < 30) { errs.push('Intervalo por tempo deve ser de pelo menos 30 dias.'); bad.push('newVtrIntervalDays'); }
  if (!id && S.admin.viaturas.some((v) => v.prefixo === prefixo)) { errs.push('Já existe viatura com este prefixo.'); bad.push('newVtrPrefix'); }
  if (S.admin.viaturas.some((v) => v.placa.replace('-', '') === placa.replace('-', '') && v.id !== id)) { errs.push('Já existe viatura com esta placa.'); bad.push('newVtrPlate'); }

  const box = $('vtrFormErrors');
  markInvalid(bad);
  if (errs.length) { box.innerHTML = errs.map(esc).join('<br>'); box.classList.remove('hidden'); return; }
  box.classList.add('hidden');

  const row = { placa, modelo, km_atual: km, status_operacional: $('newVtrStatus').value, km_ultima_troca_oleo: semOleo ? null : oilKm,
    data_ultima_troca_oleo: semOleo ? null : oilDate, intervalo_troca_oleo_km: iKm, intervalo_troca_oleo_dias: iDays };
  if (id) {
    const old = vtrById(id);
    if (km < old.km_atual && !confirm(`O KM informado (${fmtKm(km)}) é menor que o atual (${fmtKm(old.km_atual)}). Corrigir mesmo assim?`)) return;
  }
  $('btnSaveVtr').disabled = true;
  const { error } = id
    ? await sb.from('viaturas').update(row).eq('id', id)
    : await sb.from('viaturas').insert({ ...row, prefixo });
  $('btnSaveVtr').disabled = false;
  if (error) { box.textContent = friendlyError(error); box.classList.remove('hidden'); return; }
  toast(id ? `Viatura ${prefixo} atualizada.` : `Viatura ${prefixo} cadastrada.`, 'ok');
  resetVtrForm();
  await loadAdmin();
  switchTab('fleet');
}

// ----- Troca de óleo -----
function openOil(id) {
  const v = vtrById(id); if (!v) return;
  S.oilVtr = v;
  $('modalOilPrefix').textContent = `${v.prefixo} (${v.modelo})`;
  $('modalOilDoneKm').value = v.km_atual;
  $('modalOilDoneKm').max = v.km_atual;
  $('modalOilDoneDate').value = todayStr();
  $('modalOilDoneDate').max = todayStr();
  $('modalOilMaintenance').classList.remove('hidden');
}

async function confirmOil() {
  const v = S.oilVtr; if (!v) return;
  const km = Number($('modalOilDoneKm').value), data = $('modalOilDoneDate').value;
  if (!Number.isInteger(km) || km < 0 || km > v.km_atual) { toast(`KM da troca deve estar entre 0 e ${fmtKm(v.km_atual)}.`, 'err'); return; }
  if (!data || data > todayStr()) { toast('Data inválida.', 'err'); return; }
  const { error } = await sb.from('trocas_oleo').insert({ viatura_id: v.id, km, data });
  if (error) { toast(friendlyError(error), 'err'); return; }
  $('modalOilMaintenance').classList.add('hidden');
  toast(`Troca de óleo da ${v.prefixo} registrada.`, 'ok');
  await loadAdmin();
}

// ----- Vistorias -----
async function loadInspections() {
  let q = sb.from('vistorias')
    .select('id, protocolo, created_at, condutor_posto, condutor_nome_guerra, condutor_matricula, km_odometro, km_anterior, nivel_combustivel, viatura_id, vistoria_itens(status)')
    .order('created_at', { ascending: false }).limit(50);
  if ($('inspFilterVtr').value) q = q.eq('viatura_id', $('inspFilterVtr').value);
  const { data, error } = await q;
  if (error) { toast(friendlyError(error), 'err'); return; }
  $('inspectionsList').innerHTML = data.length ? data.map((v) => {
    const alts = (v.vistoria_itens || []).filter((i) => i.status === 'ALTERACAO').length;
    return `<div class="bg-slate-800/80 border border-slate-700/80 rounded-xl p-3 flex items-center justify-between gap-2 text-[11px]">
      <div class="min-w-0">
        <div class="font-bold text-white"><span class="text-tactical-gold font-mono">${esc(vtrById(v.viatura_id)?.prefixo || '?')}</span> • ${esc(v.condutor_posto)} ${esc(v.condutor_nome_guerra)} <span class="text-slate-400">(${esc(v.condutor_matricula)})</span></div>
        <div class="text-slate-400">${esc(fmtDT(v.created_at))} • KM ${fmtKm(v.km_odometro)} (+${fmtKm(v.km_odometro - v.km_anterior)}) • ${esc(v.protocolo)}</div>
      </div>
      <div class="flex items-center gap-1.5 shrink-0">
        ${alts ? `<span class="text-[9px] bg-red-500/20 text-red-300 px-1.5 py-0.5 rounded font-bold">${alts} alt.</span>` : '<span class="text-[9px] bg-emerald-500/15 text-emerald-300 px-1.5 py-0.5 rounded font-bold">OK</span>'}
        <button data-insp="${v.id}" class="text-[10px] bg-slate-700 hover:bg-slate-600 text-white font-bold px-2.5 py-1 rounded-lg">Ver</button>
      </div></div>`;
  }).join('') : '<p class="text-xs text-slate-500 text-center py-4">Nenhuma vistoria registrada ainda.</p>';
}

async function signed(paths) {
  const list = paths.filter(Boolean);
  if (!list.length) return {};
  const { data, error } = await sb.storage.from(BUCKET).createSignedUrls(list, 900);
  if (error) { toast(friendlyError(error), 'err'); return {}; }
  return Object.fromEntries(data.filter((d) => d.signedUrl).map((d) => [d.path, d.signedUrl]));
}

async function openInspection(id) {
  $('detailTitle').textContent = 'Carregando…';
  $('detailBody').innerHTML = '';
  $('modalDetail').classList.remove('hidden');
  const { data: v, error } = await sb.from('vistorias').select('*, vistoria_itens(*), avarias!avarias_vistoria_origem_id_fkey(*)').eq('id', id).single();
  if (error) { toast(friendlyError(error), 'err'); return; }
  const { data: confs } = await sb.from('avaria_confirmacoes').select('created_at, avarias(local, descricao, status)').eq('vistoria_id', id);
  const itens = (v.vistoria_itens || []).sort((a, b) => a.item_titulo.localeCompare(b.item_titulo));
  const extras = v.avarias || [];
  const urls = await signed([v.foto_frente, v.foto_traseira, v.foto_esquerda, v.foto_direita, v.assinatura_path, ...itens.map((i) => i.foto_path), ...extras.map((a) => a.foto_path)]);
  const img = (p, alt) => urls[p] ? `<a href="${urls[p]}" target="_blank" rel="noopener"><img src="${urls[p]}" alt="${esc(alt)}" class="w-full aspect-video object-cover rounded-lg border border-slate-700"></a>` : '<div class="aspect-video bg-slate-800 rounded-lg"></div>';
  const alts = itens.filter((i) => i.status === 'ALTERACAO');
  $('detailTitle').textContent = `${v.protocolo} • ${vtrById(v.viatura_id)?.prefixo || ''}`;
  $('detailBody').innerHTML = `
    <div class="grid grid-cols-2 gap-1.5 bg-slate-950 p-3 rounded-xl border border-slate-800 text-[11px]">
      <div>Registrada em: <b class="text-white">${esc(fmtDT(v.created_at))}</b></div>
      <div>Condutor: <b class="text-white">${esc(v.condutor_posto)} ${esc(v.condutor_nome_guerra)}</b> (${esc(v.condutor_matricula)})</div>
      <div>KM: <b class="text-white font-mono">${fmtKm(v.km_odometro)}</b> (anterior ${fmtKm(v.km_anterior)})</div>
      <div>Combustível: <b class="text-white">${esc(v.nivel_combustivel)}</b> • Tel.: <b class="text-white">${esc(v.telefone_escala)}</b></div>
    </div>
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">${[['Frente', v.foto_frente], ['Traseira', v.foto_traseira], ['Esquerda', v.foto_esquerda], ['Direita', v.foto_direita]].map(([l, p]) => `<div><span class="text-[10px] text-slate-400 font-bold">${l}</span>${img(p, l)}</div>`).join('')}</div>
    <div><span class="font-bold text-white">Alterações (${alts.length})</span>
      ${alts.length ? alts.map((i) => `<div class="mt-2 bg-slate-800/80 border border-red-500/30 rounded-lg p-2 flex gap-2"><div class="flex-1"><b class="text-red-400">${esc(i.item_titulo)}</b>: ${esc(i.observacao)}</div>${i.foto_path ? `<div class="w-24">${img(i.foto_path, i.item_titulo)}</div>` : ''}</div>`).join('') : '<p class="text-emerald-400 mt-1">Nenhuma.</p>'}
    </div>
    ${extras.length ? `<div><span class="font-bold text-white">Avarias registradas nesta vistoria (${extras.length})</span>
      ${extras.map((a) => `<div class="mt-2 bg-slate-800/80 border border-red-500/30 rounded-lg p-2 flex gap-2"><div class="flex-1"><b class="text-red-400">${esc(a.local)}</b>: ${esc(a.descricao)} <span class="text-[10px] text-slate-500">(${esc(a.status)})</span></div><div class="w-24">${img(a.foto_path, a.local)}</div></div>`).join('')}</div>` : ''}
    ${confs?.length ? `<div><span class="font-bold text-white">Avarias já registradas que o condutor confirmou (${confs.length})</span>
      ${confs.map((c) => `<div class="mt-2 bg-emerald-500/10 border border-emerald-500/30 rounded-lg p-2"><b class="text-emerald-300">${esc(c.avarias?.local)}</b>: ${esc(c.avarias?.descricao)}</div>`).join('')}</div>` : ''}
    <div><span class="font-bold text-white block mb-1">Assinatura</span><div class="bg-slate-950 p-1 rounded-lg border border-slate-800">${urls[v.assinatura_path] ? `<img src="${urls[v.assinatura_path]}" alt="Assinatura" class="h-16 mx-auto">` : ''}</div></div>`;
  icons();
}

// ----- Registro de avarias da VTR -----
async function openAvarias(vid) {
  S.avariasVtr = vid;
  const v = vtrById(vid);
  const list = S.admin.avarias.filter((a) => a.viatura_id === vid);
  $('avariasTitle').textContent = `Avarias em aberto • ${v?.prefixo || ''}`;
  $('modalAvarias').classList.remove('hidden');
  if (!list.length) { $('avariasBody').innerHTML = '<p class="text-slate-500 text-center py-4">Nenhuma avaria em aberto nesta VTR.</p>'; return; }
  const urls = await signed(list.map((a) => a.foto_path));
  $('avariasBody').innerHTML = list.map((a) => `
    <div class="bg-slate-800/80 border border-slate-700 rounded-xl p-3 flex gap-3">
      ${urls[a.foto_path] ? `<a href="${urls[a.foto_path]}" target="_blank" rel="noopener" class="w-28 shrink-0"><img src="${urls[a.foto_path]}" alt="" class="w-full aspect-video object-cover rounded-lg border border-slate-600"></a>` : ''}
      <div class="flex-1 space-y-1.5">
        <div><b class="text-amber-300">${esc(a.local)}</b>: ${esc(a.descricao)}</div>
        <div class="text-[10px] text-slate-400">Apontada por ${esc(a.apontada_por)} em ${esc(fmtDT(a.created_at))}</div>
        ${(() => { const cs = S.admin.confirmacoes.filter((c) => c.avaria_id === a.id); return cs.length ? `<div class="text-[10px] text-emerald-300">Confirmada por ${cs.length} condutor(es). Última: ${esc(cs[0].condutor)} (Mat. ${esc(cs[0].matricula)}) em ${esc(fmtDT(cs[0].created_at))}</div>` : '<div class="text-[10px] text-slate-500">Nenhuma confirmação posterior.</div>'; })()}
        <input data-avobs="${a.id}" maxlength="300" placeholder="Obs. da baixa (ex.: reparada na oficina, OS 123)" class="inp">
        <div class="flex gap-1.5">
          <button data-avbaixa="${a.id}" data-st="reparada" class="text-[10px] bg-emerald-500 text-slate-950 font-black px-2.5 py-1 rounded-lg">Marcar reparada</button>
          <button data-avbaixa="${a.id}" data-st="descartada" class="text-[10px] bg-slate-700 text-white font-bold px-2.5 py-1 rounded-lg">Descartar (registro indevido)</button>
          <button data-insp="${a.vistoria_origem_id}" class="text-[10px] bg-slate-700 text-white font-bold px-2.5 py-1 rounded-lg">Ver vistoria</button>
        </div>
      </div>
    </div>`).join('');
  icons();
}

async function baixaAvaria(id, status) {
  const obs = document.querySelector(`[data-avobs="${id}"]`)?.value.trim() || null;
  if (status === 'descartada' && !obs) { toast('Informe o motivo do descarte na observação.', 'err'); return; }
  const { error } = await sb.from('avarias').update({ status, baixa_obs: obs, baixa_em: new Date().toISOString() }).eq('id', id);
  if (error) { toast(friendlyError(error), 'err'); return; }
  toast(status === 'reparada' ? 'Avaria marcada como reparada.' : 'Avaria descartada.', 'ok');
  await loadAdmin();
}

// ----- Avarias não comunicadas -----
function renderSinistros() {
  const pend = S.admin.sinistros.filter((s) => s.status === 'aguardando_despacho').length;
  const badge = $('badgePendingAlerts');
  badge.textContent = pend; badge.classList.toggle('hidden', !pend);
  $('adminSinistrosList').innerHTML = S.admin.sinistros.length ? S.admin.sinistros.map((s) => `
    <div class="bg-slate-800/90 border ${s.status === 'aguardando_despacho' ? 'border-red-500/50' : 'border-slate-700'} rounded-xl p-3.5 space-y-2 text-xs">
      <div class="flex justify-between items-center gap-2 text-red-400 font-black">
        <span class="flex items-center gap-1.5"><i data-lucide="alert-circle" class="w-4 h-4"></i>${esc(vtrById(s.viatura_id)?.prefixo || '?')} • ${esc(s.item_titulo)}</span>
        <span class="text-[10px] bg-slate-700 text-slate-200 px-2 py-0.5 rounded font-bold shrink-0">${STATUS_SIN[s.status]}</span>
      </div>
      ${s.observacao ? `<p class="text-slate-300 text-[11px]">“${esc(s.observacao)}”</p>` : ''}
      <div class="grid grid-cols-2 gap-2 text-slate-300 text-[11px] bg-slate-900/70 p-2 rounded-lg">
        <div>Condutor anterior: <b class="text-tactical-gold block">${esc(s.responsavel_nome)} (Mat. ${esc(s.responsavel_matricula)})</b></div>
        <div>Apontado por: <b class="text-white block">${esc(s.comunicante_nome)} (Mat. ${esc(s.comunicante_matricula)})</b></div>
      </div>
      <div class="flex flex-wrap gap-1.5">
        <button data-insp="${s.vistoria_anterior_id}" class="text-[10px] bg-slate-700 text-white font-bold px-2.5 py-1 rounded-lg">Vistoria anterior</button>
        <button data-insp="${s.vistoria_detectora_id}" class="text-[10px] bg-slate-700 text-white font-bold px-2.5 py-1 rounded-lg">Vistoria que apontou</button>
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 pt-1 border-t border-slate-700/60">
        <select data-sinstatus="${s.id}" class="inp">${Object.entries(STATUS_SIN).map(([k, l]) => `<option value="${k}" ${k === s.status ? 'selected' : ''}>${l}</option>`).join('')}</select>
        <input data-sindesp="${s.id}" maxlength="1000" value="${esc(s.despacho || '')}" placeholder="Despacho / providência" class="inp sm:col-span-2">
      </div>
      <div class="flex items-center justify-between"><span class="text-[10px] text-slate-400">${esc(fmtDT(s.created_at))}</span>
        <button data-sinsave="${s.id}" class="text-[10px] bg-tactical-gold text-slate-950 font-black px-3 py-1 rounded-lg">Salvar despacho</button></div>
    </div>`).join('') : '<p class="text-xs text-slate-500 text-center py-4">Nenhuma avaria não comunicada.</p>';
  icons();
}

async function saveSinistro(id) {
  const status = document.querySelector(`[data-sinstatus="${id}"]`).value;
  const despacho = document.querySelector(`[data-sindesp="${id}"]`).value.trim() || null;
  const { error } = await sb.from('sinistros').update({ status, despacho }).eq('id', id);
  if (error) { toast(friendlyError(error), 'err'); return; }
  toast('Despacho salvo.', 'ok');
  await loadAdmin();
}

// ----- Checklist -----
function renderAdminItems() {
  const items = S.admin.itens;
  $('adminTotalItemsCount').textContent = items.filter((i) => i.ativo).length;
  $('adminItemsListContainer').innerHTML = items.map((it) => `
    <div class="bg-slate-800 p-2.5 rounded-xl border border-slate-700 flex items-center justify-between text-xs ${it.ativo ? '' : 'opacity-50'}">
      <div><b class="text-white">${esc(it.titulo)}</b><span class="text-[10px] text-slate-400 block">${esc(it.categoria)}${it.exige_foto ? ' • Exige foto' : ''}${it.ativo ? '' : ' • DESATIVADO'}</span></div>
      <button data-itemtoggle="${it.id}" class="text-[10px] font-bold px-2 py-1 rounded-lg border ${it.ativo ? 'border-red-500/40 text-red-300' : 'border-emerald-500/40 text-emerald-300'}">${it.ativo ? 'Desativar' : 'Reativar'}</button>
    </div>`).join('');
}

async function addItem() {
  const titulo = $('adminNewItemTitle').value.trim();
  if (titulo.length < 2) { toast('Digite o título do item.', 'err'); return; }
  if (S.admin.itens.some((i) => i.ativo && i.titulo.toLowerCase() === titulo.toLowerCase())) { toast('Já existe um item ativo com esse título.', 'err'); return; }
  const ordem = Math.max(0, ...S.admin.itens.map((i) => i.ordem)) + 10;
  const { error } = await sb.from('checklist_itens').insert({ titulo, categoria: $('adminNewItemCategory').value, exige_foto: $('adminNewItemRequirePhoto').checked, ordem });
  if (error) { toast(friendlyError(error), 'err'); return; }
  $('adminNewItemTitle').value = '';
  toast(`Item "${titulo}" adicionado. Já aparece para os motoristas.`, 'ok');
  await loadAdmin();
}

async function toggleItem(id) {
  const it = S.admin.itens.find((i) => i.id === id); if (!it) return;
  if (it.ativo && !confirm(`Desativar "${it.titulo}"? Ele some do checklist, mas o histórico é mantido.`)) return;
  const { error } = await sb.from('checklist_itens').update({ ativo: !it.ativo }).eq('id', id);
  if (error) { toast(friendlyError(error), 'err'); return; }
  await loadAdmin();
}

// ----- Avisos -----
function renderAdminNotices() {
  $('adminNoticesList').innerHTML = S.admin.avisos.length ? S.admin.avisos.map((a) => `
    <div class="bg-slate-800 p-2.5 rounded-xl border border-slate-700 flex items-start justify-between gap-2 text-xs">
      <div><b class="text-tactical-gold font-mono">${esc(vtrById(a.viatura_id)?.prefixo || '?')}</b> <span class="text-slate-300">${esc(a.mensagem)}</span>
        <span class="text-[10px] text-slate-500 block">${esc(fmtDT(a.created_at))}</span></div>
      <button data-noticeoff="${a.id}" class="text-slate-400 hover:text-red-400 p-1 shrink-0" title="Remover"><i data-lucide="trash-2" class="w-4 h-4"></i></button>
    </div>`).join('') : '<p class="text-xs text-slate-500">Nenhum aviso ativo.</p>';
  icons();
}

async function saveNotice() {
  const viatura_id = $('adminNoticeTargetVtr').value;
  const mensagem = $('adminNoticeMessageInput').value.trim();
  if (!viatura_id) { toast('Selecione a viatura.', 'err'); return; }
  if (mensagem.length < 2) { toast('Digite a mensagem.', 'err'); return; }
  const { error } = await sb.from('avisos').insert({ viatura_id, mensagem });
  if (error) { toast(friendlyError(error), 'err'); return; }
  $('adminNoticeMessageInput').value = '';
  toast('Aviso publicado.', 'ok');
  await loadAdmin();
}

async function removeNotice(id) {
  if (!confirm('Remover este aviso do mural?')) return;
  const { error } = await sb.from('avisos').update({ ativo: false }).eq('id', id);
  if (error) { toast(friendlyError(error), 'err'); return; }
  await loadAdmin();
}

// =============================================================================
// Papel (motorista / chefe)
// =============================================================================
async function switchRole(role) {
  document.querySelectorAll('.role-btn').forEach((b) => b.classList.toggle('active', b.dataset.role === role));
  $('driverSection').classList.toggle('hidden', role !== 'driver');
  $('adminSection').classList.toggle('hidden', role !== 'admin');
  $('adminSection').classList.toggle('flex', role === 'admin');
  if (role === 'admin') await showAdmin();
  else await loadDriverData();
}

// =============================================================================
// Eventos
// =============================================================================
function bind() {
  document.querySelectorAll('.role-btn').forEach((b) => b.addEventListener('click', () => switchRole(b.dataset.role)));
  $('vehiclePrefixSelect').addEventListener('change', () => onVehicleChange(true));
  $('vehicleKmInput').addEventListener('input', renderOilCard);
  $('btnNextStep').addEventListener('click', nextStep);
  $('btnPrevStep').addEventListener('click', () => S.step > 1 && setStep(S.step - 1));
  $('btnClearSig').addEventListener('click', clearSignature);
  $('btnCloseTermo').addEventListener('click', closeTermo);
  $('photoGrid').addEventListener('change', (e) => e.target.dataset.side && onSidePhoto(e.target));

  const cl = $('dynamicChecklistContainer');
  cl.addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]'); if (!b) return;
    const a = (S.answers[b.dataset.id] ||= {});
    a.status = b.dataset.act;
    renderChecklist();
    if (a.status === 'ALTERACAO') document.querySelector(`[data-obs="${b.dataset.id}"]`)?.focus();
  });
  cl.addEventListener('input', (e) => { const id = e.target.dataset.obs; if (id) (S.answers[id] ||= { status: 'ALTERACAO' }).obs = e.target.value; });
  cl.addEventListener('change', (e) => e.target.dataset.itemphoto && onItemPhoto(e.target));
  $('btnAddAvaria').addEventListener('click', () => {
    if (S.avariasNovas.length >= 20) { toast('Máximo de 20 avarias por vistoria.', 'err'); return; }
    S.avariasNovas.push({ local: '', desc: '', photo: null }); renderAvarias();
  });
  const av = $('avariasSection');
  av.addEventListener('click', (e) => {
    const c = e.target.closest('[data-avconf]');
    if (c) {
      const id = c.dataset.avconf;
      if (S.confirmadas.has(id)) S.confirmadas.delete(id); else S.confirmadas.add(id);
      renderAvarias(); return;
    }
    const z = e.target.closest('[data-avzoom]');
    if (z) { window.open(z.dataset.avzoom, '_blank', 'noopener'); return; }
    const b = e.target.closest('[data-avrm]'); if (!b) return;
    const a = S.avariasNovas.splice(Number(b.dataset.avrm), 1)[0];
    if (a?.photo) URL.revokeObjectURL(a.photo.url);
    renderAvarias();
  });
  av.addEventListener('input', (e) => { const i = e.target.dataset.avdesc; if (i != null) S.avariasNovas[Number(i)].desc = e.target.value; });
  av.addEventListener('change', (e) => {
    if (e.target.dataset.avlocal != null) { S.avariasNovas[Number(e.target.dataset.avlocal)].local = e.target.value; renderAvarias(); }
    else if (e.target.dataset.avphoto != null) onAvariaPhoto(e.target);
  });
  $('btnAllOk').addEventListener('click', () => { S.itens.forEach((it) => { if (!S.answers[it.id]?.status) S.answers[it.id] = { status: 'OK' }; }); renderChecklist(); });

  // Chefe
  $('formLogin').addEventListener('submit', onLogin);
  $('btnLogout').addEventListener('click', onLogout);
  document.querySelectorAll('.tab-btn').forEach((b) => b.addEventListener('click', () => {
    if (b.dataset.tab === 'newVtr' && !$('vtrEditId').value) resetVtrForm();
    switchTab(b.dataset.tab);
  }));
  $('formNewVehicle').addEventListener('submit', onSaveVtr);
  $('btnCancelEdit').addEventListener('click', () => { resetVtrForm(); switchTab('fleet'); });
  $('btnRefreshFleet').addEventListener('click', loadAdmin);
  $('btnConfirmOil').addEventListener('click', confirmOil);
  $('btnAddItem').addEventListener('click', addItem);
  $('btnSaveNotice').addEventListener('click', saveNotice);
  $('inspFilterVtr').addEventListener('change', loadInspections);
  $('modalAvarias').addEventListener('click', (e) => {
    const t = e.target.closest('button'); if (!t) return;
    if (t.dataset.avbaixa) baixaAvaria(t.dataset.avbaixa, t.dataset.st);
    else if (t.dataset.insp) openInspection(t.dataset.insp);
  });
  document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => $(b.dataset.close).classList.add('hidden')));

  $('adminPanel').addEventListener('click', (e) => {
    const t = e.target.closest('button'); if (!t) return;
    if (t.dataset.avarias) openAvarias(t.dataset.avarias);
    else if (t.dataset.edit) editVtr(t.dataset.edit);
    else if (t.dataset.oil) openOil(t.dataset.oil);
    else if (t.dataset.insp) openInspection(t.dataset.insp);
    else if (t.dataset.sinsave) saveSinistro(t.dataset.sinsave);
    else if (t.dataset.itemtoggle) toggleItem(t.dataset.itemtoggle);
    else if (t.dataset.noticeoff) removeNotice(t.dataset.noticeoff);
  });

  window.addEventListener('online', () => loadDriverData());
  window.addEventListener('offline', () => setNet(false, 'Sem internet'));
  window.addEventListener('beforeunload', (e) => {
    if (S.step > 1 || Object.keys(S.photos).length || S.avariasNovas.length) { e.preventDefault(); e.returnValue = ''; }
  });
}

// =============================================================================
// Início
// =============================================================================
async function init() {
  bind();
  initSignature();
  renderPhotoGrid();
  resetVtrForm();
  $('dutyPhoneInput').value = localStorage.getItem('sischeck_tel') || '';
  switchTab('fleet');
  await switchRole('driver');
  icons();
}

init();
