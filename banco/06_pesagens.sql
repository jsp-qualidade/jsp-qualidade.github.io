-- 06 · Pesagem (CEP, carta X̄-R do peso seco e do peso úmido)
-- Cada linha é um subgrupo de pesagem (5 peças pesadas no mesmo horário).
-- As linhas com id "base_seco" / "base_umido" guardam a base dos limites de controle; só o Gestor altera.
create table if not exists public.pesagens (
  id             text primary key,
  dados          jsonb not null default '{}'::jsonb,
  excluido       boolean not null default false,
  atualizado_em  timestamptz not null default now(),
  atualizado_por text
);
create index if not exists pesagens_atualizado_em_idx on public.pesagens (atualizado_em);
drop trigger if exists pesagens_marca on public.pesagens;
create trigger pesagens_marca before insert or update on public.pesagens
  for each row execute function private.marca_atualizacao();
alter table public.pesagens enable row level security;
drop policy if exists "colaboradores leem" on public.pesagens;
drop policy if exists "colaboradores incluem" on public.pesagens;
drop policy if exists "colaboradores alteram" on public.pesagens;
create policy "colaboradores leem" on public.pesagens for select to authenticated
  using ((select private.e_colaborador()));
create policy "colaboradores incluem" on public.pesagens for insert to authenticated
  with check (((select private.e_colaborador()) and id not like 'base\_%') or (select private.e_gestor()));
create policy "colaboradores alteram" on public.pesagens for update to authenticated
  using (((select private.e_colaborador()) and id not like 'base\_%') or (select private.e_gestor()))
  with check (((select private.e_colaborador()) and id not like 'base\_%') or (select private.e_gestor()));
revoke all on public.pesagens from anon;
grant select, insert, update on public.pesagens to authenticated;
