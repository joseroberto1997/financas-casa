# 🏠 Finanças da Casa

App simples para o casal lançar gastos, acompanhar contas do mês, faturas dos cartões, dívidas de terceiros (ex.: Gilberto) e o dinheiro guardado para pagar as contas. Cada lançamento mostra **quem adicionou** e quando.

- **Site:** GitHub Pages (grátis) → `https://joseroberto1997.github.io/financas-casa/`
- **Dados e login:** [Supabase](https://supabase.com) (grátis)

## Funcionalidades

- **Resumo** do mês: entradas, despesas, já pago, falta pagar, sobra prevista, VR/VA separado, histórico por mês.
- **Contas**: contas fixas e entradas, status Pago / A pagar, faturas calculadas automaticamente a partir dos cartões.
- **Gastos**: lance qualquer gasto escolhendo como foi pago — **Crédito** (entra na fatura do cartão: Itaú, C6, Nubank…), **Débito**, **Pix** ou **Dinheiro** (já conta como pago no mês). Compras únicas, parceladas ou de todo mês.
- **Dívida de terceiros** em qualquer gasto (ex.: Gilberto): a parte da outra pessoa sai da conta da casa e vai para “a receber”, com botão “Recebi tudo”.
- **Guardado** em duas caixinhas: **Contas e dívidas** e **Emergência**, com transferência entre elas; ao marcar algo como pago dá para tirar automaticamente da caixinha.
- **Terceiros** (aba própria): saldo em aberto de cada pessoa, compras no nome dela, **pagamentos parciais** (ex.: “mandou R$ 1.000”) e histórico mês a mês. O pagamento pode entrar direto no guardado para contas.
- **Atividade**: histórico de quem lançou/editou o quê.
- **Visitante (somente leitura)**: um terceiro (ex.: Gilberto) entra com o próprio e-mail e vê **apenas** a parte dele em cada gasto, por mês, com o que está pago e pendente. Ele não vê as outras despesas e não edita nada. Libere com `insert into public.visitantes (email, nome) values ('email', 'Gilberto');` — o nome tem que ser igual ao usado em “Dívida de terceiros”.
- **Começar mês**: copia contas, entradas, recorrentes e a próxima parcela das compras parceladas do mês anterior.
- Atualiza em tempo real entre os dois celulares. Pode ser instalado na tela inicial (“Adicionar à tela de início”).

## Configuração (uma vez só)

### 1. Supabase
1. Crie um projeto em supabase.com (região São Paulo).
2. **SQL Editor → New query**: cole o conteúdo de [`supabase/schema.sql`](supabase/schema.sql) e clique **Run**.
3. Ainda no SQL Editor, libere os e-mails da casa:
   ```sql
   insert into public.membros (email) values ('seu-email@exemplo.com'), ('email-da-esposa@exemplo.com');
   ```
4. (Opcional) Importe o histórico da planilha rodando o arquivo `importar-planilha.sql` (não fica no GitHub por conter dados pessoais).
5. **Authentication → URL Configuration**: em *Site URL* coloque `https://joseroberto1997.github.io/financas-casa/`.
6. **Project Settings → API**: copie a *Project URL* e a chave *anon / publishable*.

### 2. config.js
Edite o arquivo [`config.js`](config.js) aqui no GitHub (ícone de lápis) e cole a URL e a chave anon. Faça o commit.
A chave anon é pública por natureza; quem protege os dados são as regras (RLS) do `schema.sql` — só e-mails da tabela `membros` conseguem ver ou lançar. **Nunca** coloque a chave `service_role` aqui.

### 3. GitHub Pages
**Settings → Pages → Build and deployment**: *Source* = **Deploy from a branch**, *Branch* = **main** / **(root)** → Save. Em 1–2 minutos o site fica no ar.

### 4. Primeiro acesso
Abra o link, toque em **Criar conta**, coloque nome, e-mail (um dos liberados) e senha, e confirme pelo e-mail recebido.
