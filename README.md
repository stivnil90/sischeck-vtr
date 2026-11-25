# SisCheck-VTR

Vistoria operacional de viaturas (check-in do motorista) e gestão da frota pelo Chefe de Transporte.

## Estrutura

```
site/                 # o que vai para o ar (Vercel serve esta pasta)
  index.html
  js/app.js           # lógica do app
  js/config.js        # URL e chave pública do Supabase
  assets/app.css      # gerado no build (Tailwind) — não editar
src/input.css         # estilos-fonte (Tailwind)
supabase/             # SQL do banco (referência; já aplicado no projeto)
tailwind.config.js
vercel.json
```

## Como funciona o acesso

- **Motorista (sem conta):** escolhe a VTR, se identifica, fotografa os 4 lados, responde o checklist e assina.
  Só consegue *enviar* vistorias. Não lê nem altera nada além de viaturas, checklist e avisos.
- **Servidor (função `finalizar_vistoria`):** valida KM (não pode diminuir nem pular mais de 5.000 km), fotos,
  respostas e assinatura; grava a hora oficial, gera o protocolo, atualiza o KM da VTR e registra
  as alterações não apontadas pelo condutor anterior.
- **Chefe de Transporte (login):** cadastra/edita VTRs, registra troca de óleo, vê vistorias e fotos,
  despacha avarias, mantém checklist e avisos. Precisa ter o usuário cadastrado em `public.admins`.

## Dar acesso a um Chefe

1. Supabase → Authentication → Users → **Add user** (e-mail + senha).
2. SQL Editor:
   ```sql
   insert into public.admins (user_id, nome)
   select id, 'Nome do Chefe' from auth.users where email = 'chefe@exemplo.com';
   ```

## Rodar localmente

```bash
npm install
npm run dev          # gera site/assets/app.css e observa mudanças
npx serve site       # abre em http://localhost:3000
```

## Pasta `legado/`
Versões anteriores (HTML v1, app Flutter e SQL antigo), guardadas só como referência. Não são publicadas.
