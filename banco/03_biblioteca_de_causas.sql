-- JSP · Biblioteca causa/efeito editável (já aplicado no projeto em 12/11/2026)
-- Guarda só as causas incluídas, alteradas ou removidas pela JSP; as originais ficam no sistema.
-- Leitura: colaboradores ativos. Gravação: somente administradores.
create table if not exists public.causas (
  id             text primary key,
  dados          jsonb not null default '{}'::jsonb,
  excluido       boolean not null default false,
  atualizado_em  timestamptz not null default now(),
  atualizado_por text
);
create index if not exists causas_atualizado_em_idx on public.causas (atualizado_em);
drop trigger if exists causas_marca on public.causas;
create trigger causas_marca before insert or update on public.causas
  for each row execute function private.marca_atualizacao();
alter table public.causas enable row level security;
drop policy if exists "colaboradores leem" on public.causas;
drop policy if exists "admin inclui" on public.causas;
drop policy if exists "admin altera" on public.causas;
create policy "colaboradores leem" on public.causas for select to authenticated
  using ((select private.e_colaborador()));
create policy "admin inclui" on public.causas for insert to authenticated
  with check ((select private.e_admin()));
create policy "admin altera" on public.causas for update to authenticated
  using ((select private.e_admin())) with check ((select private.e_admin()));
revoke all on public.causas from anon;
grant select, insert, update on public.causas to authenticated;
