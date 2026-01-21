# VMAPP (HTML/JS + Supabase + Vercel)

## Rodar local
1) Copie `env.example.js` para `env.js` e preencha.
2) Inicie um servidor local:

```bash
npx serve .
```

Abra a URL indicada no terminal.

## Supabase
Execute os scripts SQL em `sql/` na ordem:
1) `01_schema.sql`
2) `02_rpcs.sql`
3) `03_constraints_fechamento.sql`

> Obs.: para CPF criptografado, no Supabase SQL Editor, para testes, rode antes:

```sql
set app.cpf_key = 'TROQUE_POR_UMA_CHAVE_FORTE_COM_32+_CHARS';
```

## Deploy Vercel
- Suba este repositório ao GitHub.
- Importe na Vercel como projeto **Other**.
