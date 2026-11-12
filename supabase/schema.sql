-- =========================================================
-- Finanças da Casa — estrutura do banco (Supabase)
-- Rode este arquivo inteiro no Supabase: SQL Editor → New query → colar → Run
-- =========================================================

-- 1) Quem pode usar o app (lista de e-mails da casa)
create table if not exists public.membros (
  email text primary key
);

-- 2) Perfis (nome de quem lança)
create table if not exists public.perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null default ''
);

-- 3) Todos os lançamentos (contas, entradas, cartão, faturas, reserva, config)
create table if not exists public.registros (
  col text not null check (col in ('contas','entradas','cartao','faturas','reserva','config')),
  id text not null,
  data jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (col, id)
);
create index if not exists registros_mes_idx on public.registros ((data->>'mes'));

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists registros_touch on public.registros;
create trigger registros_touch before update on public.registros
for each row execute function public.touch_updated_at();

-- 4) Função: o usuário logado está na lista de membros?
create or replace function public.eh_membro() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.membros m where lower(m.email) = lower(auth.jwt()->>'email'));
$$;

-- 5) Cria o perfil automaticamente quando alguém se cadastra
create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfis (id, nome)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'nome',''), split_part(new.email,'@',1)))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.novo_usuario();

-- 6) Segurança (RLS): só membros leem/escrevem
alter table public.membros  enable row level security;
alter table public.perfis   enable row level security;
alter table public.registros enable row level security;

drop policy if exists "ver meu email" on public.membros;
create policy "ver meu email" on public.membros for select to authenticated
  using (lower(email) = lower(auth.jwt()->>'email'));

drop policy if exists "membros veem perfis" on public.perfis;
create policy "membros veem perfis" on public.perfis for select to authenticated
  using (public.eh_membro() or id = auth.uid());
drop policy if exists "editar meu perfil" on public.perfis;
create policy "editar meu perfil" on public.perfis for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "membros leem" on public.registros;
create policy "membros leem" on public.registros for select to authenticated using (public.eh_membro());
drop policy if exists "membros inserem" on public.registros;
create policy "membros inserem" on public.registros for insert to authenticated with check (public.eh_membro());
drop policy if exists "membros alteram" on public.registros;
create policy "membros alteram" on public.registros for update to authenticated using (public.eh_membro()) with check (public.eh_membro());
drop policy if exists "membros apagam" on public.registros;
create policy "membros apagam" on public.registros for delete to authenticated using (public.eh_membro());

-- 7) Atualização em tempo real (um vê o que o outro lançou na hora)
alter table public.registros replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.registros;
exception when duplicate_object then null; end $$;

-- =========================================================
-- 8) LIBERE OS E-MAILS DA CASA (troque pelos e-mails reais e rode):
-- insert into public.membros (email) values ('seu-email@exemplo.com'), ('email-da-michelle@exemplo.com');
-- =========================================================

-- =========================================================
-- 9) VISITANTES (somente leitura das próprias dívidas, ex.: Gilberto)
--    O visitante NÃO lê a tabela registros: ele só chama a função
--    minhas_dividas(), que devolve apenas a parte dele em cada gasto.
-- =========================================================
create table if not exists public.visitantes (
  email text primary key,
  nome  text not null          -- igual ao nome usado em "Dívida de terceiros" (ex.: Gilberto)
);
alter table public.visitantes enable row level security;
drop policy if exists "ver meu cadastro de visitante" on public.visitantes;
create policy "ver meu cadastro de visitante" on public.visitantes for select to authenticated
  using (lower(email) = lower(auth.jwt()->>'email'));

create or replace function public.nome_visitante() returns text
language sql stable security definer set search_path = public as $$
  select nome from public.visitantes where lower(email) = lower(auth.jwt()->>'email') limit 1;
$$;

create or replace function public.minhas_dividas()
returns table (id text, mes text, descricao text, meio text, parc_atual int, parc_total int, valor numeric, recebido boolean)
language sql stable security definer set search_path = public as $$
  select r.id,
         r.data->>'mes',
         r.data->>'descricao',
         case when coalesce(r.data->>'forma','credito') = 'credito' then 'Cartão ' || coalesce(r.data->>'cartao','')
              else initcap(r.data->>'forma') end,
         nullif(r.data->>'parcAtual','')::int,
         nullif(r.data->>'parcTotal','')::int,
         (t->>'valor')::numeric,
         coalesce((t->>'recebido')::boolean, false)
  from public.registros r
  cross join lateral jsonb_array_elements(coalesce(r.data->'terceiros','[]'::jsonb)) t
  where r.col = 'cartao'
    and public.nome_visitante() is not null
    and lower(trim(t->>'nome')) = lower(trim(public.nome_visitante()))
  order by 2 desc, 3;
$$;
revoke all on function public.minhas_dividas() from public, anon;
grant execute on function public.minhas_dividas() to authenticated;

-- Para liberar um visitante (troque e rode):
-- insert into public.visitantes (email, nome) values ('email-do-visitante@exemplo.com', 'Gilberto');

-- =========================================================
-- 10) PAGAMENTOS DE TERCEIROS (parciais) + caixinhas do guardado
-- =========================================================
alter table public.registros drop constraint if exists registros_col_check;
alter table public.registros add constraint registros_col_check
  check (col in ('contas','entradas','cartao','faturas','reserva','config','recebimentos'));

create or replace function public.meus_pagamentos()
returns table (id text, mes text, data text, valor numeric, descricao text)
language sql stable security definer set search_path = public as $$
  select r.id, r.data->>'mes', r.data->>'data', (r.data->>'valor')::numeric, r.data->>'descricao'
  from public.registros r
  where r.col = 'recebimentos'
    and public.nome_visitante() is not null
    and lower(trim(r.data->>'pessoa')) = lower(trim(public.nome_visitante()))
  order by 3 desc;
$$;
revoke all on function public.meus_pagamentos() from public, anon;
grant execute on function public.meus_pagamentos() to authenticated;
