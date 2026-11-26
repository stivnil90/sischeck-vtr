// SisCheck-VTR — envia e-mail ao Chefe de Transporte quando uma vistoria
// aponta avaria/alteração não comunicada pelo condutor anterior.
// Disparada pelo trigger public.tg_notificar_sinistro (pg_net), 1 vez por vistoria.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import nodemailer from "npm:nodemailer@6.9.16";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const GMAIL_USER = Deno.env.get("GMAIL_USER") ?? "transporte39batalhao@gmail.com";
const GMAIL_APP_PASSWORD = Deno.env.get("GMAIL_APP_PASSWORD") ?? "";
const NOTIFY_TO = Deno.env.get("NOTIFY_TO") ?? "transporte39batalhao@gmail.com";
const APP_URL = "https://sischeck-vtr.vercel.app";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const dt = (iso: string) =>
  new Date(iso).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo", dateStyle: "short", timeStyle: "short" });
const km = (n: number) => Number(n || 0).toLocaleString("pt-BR");
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function claim(vistoriaId: string): Promise<boolean> {
  const { error } = await sb.from("notificacoes").insert({ vistoria_id: vistoriaId, status: "enviando" });
  if (!error) return true;
  // Já existe: só tenta de novo se a anterior deu erro (no máximo 5 tentativas)
  const { data } = await sb.from("notificacoes").select("status, tentativas").eq("vistoria_id", vistoriaId).single();
  if (!data || data.status !== "erro" || data.tentativas >= 5) return false;
  const { data: upd } = await sb.from("notificacoes")
    .update({ status: "enviando", tentativas: data.tentativas + 1, erro: null })
    .eq("vistoria_id", vistoriaId).eq("status", "erro").select("vistoria_id");
  return !!upd?.length;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { erro: "método não permitido" });
  const { vistoria_id } = await req.json().catch(() => ({}));
  if (typeof vistoria_id !== "string" || !UUID_RE.test(vistoria_id)) return json(400, { erro: "vistoria_id inválido" });

  if (!(await claim(vistoria_id))) return json(200, { ok: true, ignorado: "já processada" });

  try {
    const { data: sins, error: e1 } = await sb.from("sinistros").select("*")
      .eq("vistoria_detectora_id", vistoria_id).order("created_at");
    if (e1) throw e1;
    if (!sins?.length) {
      await sb.from("notificacoes").update({ status: "sem_avarias" }).eq("vistoria_id", vistoria_id);
      return json(200, { ok: true, ignorado: "sem avarias" });
    }

    const [{ data: atual }, { data: ant }, { data: vtr }] = await Promise.all([
      sb.from("vistorias").select("*").eq("id", vistoria_id).single(),
      sb.from("vistorias").select("*").eq("id", sins[0].vistoria_anterior_id).single(),
      sb.from("viaturas").select("prefixo, placa, modelo").eq("id", sins[0].viatura_id).single(),
    ]);
    if (!atual || !ant || !vtr) throw new Error("dados da vistoria não encontrados");

    // Fotos das avarias como anexos (aparecem no corpo do e-mail)
    const attachments: { filename: string; content: Uint8Array; contentType: string; cid: string }[] = [];
    for (const [i, s] of sins.entries()) {
      if (!s.foto_path) continue;
      const { data: blob } = await sb.storage.from("vistorias").download(s.foto_path);
      if (blob) {
        attachments.push({
          filename: `avaria-${i + 1}.jpg`,
          content: new Uint8Array(await blob.arrayBuffer()),
          contentType: blob.type || "image/jpeg",
          cid: `avaria${i + 1}@sischeck`,
        });
      }
    }

    const linhas = sins.map((s, i) => `
      <tr>
        <td style="padding:10px;border-bottom:1px solid #e2e8f0;vertical-align:top">
          <b style="color:#b91c1c">${esc(s.item_titulo)}</b><br>
          <span style="color:#334155">${esc(s.observacao || "Sem descrição")}</span>
        </td>
        <td style="padding:10px;border-bottom:1px solid #e2e8f0;width:180px">
          ${attachments.find((a) => a.cid === `avaria${i + 1}@sischeck`)
            ? `<img src="cid:avaria${i + 1}@sischeck" width="170" style="border-radius:6px;display:block">`
            : '<span style="color:#94a3b8;font-size:12px">sem foto</span>'}
        </td>
      </tr>`).join("");

    const html = `
<div style="font-family:Arial,Helvetica,sans-serif;max-width:640px;margin:auto;color:#0f172a">
  <div style="background:#0b1329;color:#fff;padding:16px 20px;border-radius:10px 10px 0 0">
    <div style="font-size:12px;color:#f59e0b;font-weight:bold;letter-spacing:1px">SISCHECK-VTR • 39º BPM</div>
    <div style="font-size:18px;font-weight:bold;margin-top:4px">Avaria não comunicada — VTR ${esc(vtr.prefixo)}</div>
  </div>
  <div style="border:1px solid #e2e8f0;border-top:0;padding:18px 20px;border-radius:0 0 10px 10px">
    <p style="margin:0 0 14px">Na assunção da viatura <b>${esc(vtr.prefixo)}</b> (${esc(vtr.modelo)} • placa ${esc(vtr.placa)}),
    o motorista apontou <b>${sins.length} alteração(ões)/avaria(s)</b> que <b>não constavam</b> na vistoria do condutor anterior.</p>

    <table style="width:100%;border-collapse:collapse;font-size:14px;margin-bottom:14px">
      <tr><td style="padding:10px;background:#fef2f2;border:1px solid #fecaca;border-radius:6px">
        <div style="font-size:11px;color:#991b1b;font-weight:bold">CONDUTOR ANTERIOR (RESPONSÁVEL A APURAR)</div>
        <div style="font-size:16px;font-weight:bold;margin-top:2px">${esc(ant.condutor_posto)} ${esc(ant.condutor_nome_guerra)} — Mat. ${esc(ant.condutor_matricula)}</div>
        <div style="color:#475569;font-size:13px">Entregou em ${esc(dt(ant.created_at))} com ${km(ant.km_odometro)} km • Tel. escala ${esc(ant.telefone_escala)} • Protocolo ${esc(ant.protocolo)}</div>
      </td></tr>
      <tr><td style="height:8px"></td></tr>
      <tr><td style="padding:10px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:6px">
        <div style="font-size:11px;color:#475569;font-weight:bold">APONTADO POR</div>
        <div style="font-size:15px;font-weight:bold;margin-top:2px">${esc(atual.condutor_posto)} ${esc(atual.condutor_nome_guerra)} — Mat. ${esc(atual.condutor_matricula)}</div>
        <div style="color:#475569;font-size:13px">Registrado pelo servidor em ${esc(dt(atual.created_at))} com ${km(atual.km_odometro)} km • Protocolo ${esc(atual.protocolo)}</div>
      </td></tr>
    </table>

    <table style="width:100%;border-collapse:collapse;font-size:14px">${linhas}</table>

    <p style="margin:18px 0 6px">
      <a href="${APP_URL}" style="background:#f59e0b;color:#0b1329;text-decoration:none;font-weight:bold;padding:10px 16px;border-radius:8px;display:inline-block">
        Abrir o painel do Chefe</a>
    </p>
    <p style="color:#64748b;font-size:12px;margin-top:14px">Indício para apuração, não conclusão: confira as fotos e as duas vistorias antes do despacho.
    Data e hora registradas pelo servidor; o motorista não consegue alterar o registro.</p>
  </div>
</div>`;

    if (!GMAIL_APP_PASSWORD) throw new Error("GMAIL_APP_PASSWORD não configurada");
    const transporter = nodemailer.createTransport({
      host: "smtp.gmail.com", port: 465, secure: true,
      auth: { user: GMAIL_USER, pass: GMAIL_APP_PASSWORD },
    });
    await transporter.sendMail({
      from: `"SisCheck-VTR 39º BPM" <${GMAIL_USER}>`,
      to: NOTIFY_TO,
      subject: `[SisCheck-VTR] Avaria não comunicada • VTR ${vtr.prefixo} • resp. ${ant.condutor_posto} ${ant.condutor_nome_guerra}`,
      html,
      attachments,
    });

    await sb.from("notificacoes").update({ status: "enviado", enviado_em: new Date().toISOString() }).eq("vistoria_id", vistoria_id);
    return json(200, { ok: true, enviados: sins.length });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("notificar-avaria:", msg);
    await sb.from("notificacoes").update({ status: "erro", erro: msg.slice(0, 500) }).eq("vistoria_id", vistoria_id);
    return json(500, { ok: false, erro: msg });
  }
});
