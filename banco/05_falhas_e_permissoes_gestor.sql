-- 05 · Cadastro de falhas e permissões do Gestor
-- Falhas: guarda só as falhas incluídas pela JSP e as alterações/desativações das falhas da FS 070
-- (as originais ficam no sistema, como na Biblioteca de causas).
-- Gestor passa a alterar produtos, máquinas, falhas e causas. Só o Administrador mexe no cadastro de usuários.
create table if not exists public.falhas (
  id             text primary key,
  dados          jsonb not null default '{}'::jsonb,
  excluido       boolean not null default false,
  atualizado_em  timestamptz not null default now(),
  atualizado_por text
);
create index if not exists falhas_atualizado_em_idx on public.falhas (atualizado_em);
drop trigger if exists falhas_marca on public.falhas;
create trigger falhas_marca before insert or update on public.falhas
  for each row execute function private.marca_atualizacao();
alter table public.falhas enable row level security;
create policy "colaboradores leem" on public.falhas for select to authenticated
  using ((select private.e_colaborador()));
create policy "gestor inclui" on public.falhas for insert to authenticated
  with check ((select private.e_gestor()));
create policy "gestor altera" on public.falhas for update to authenticated
  using ((select private.e_gestor())) with check ((select private.e_gestor()));
revoke all on public.falhas from anon;
grant select, insert, update on public.falhas to authenticated;

-- Produtos e máquinas: Administrador e Gestor
drop policy if exists "admin inclui" on public.produtos;
drop policy if exists "admin altera" on public.produtos;
create policy "gestor inclui" on public.produtos for insert to authenticated with check ((select private.e_gestor()));
create policy "gestor altera" on public.produtos for update to authenticated using ((select private.e_gestor())) with check ((select private.e_gestor()));
drop policy if exists "admin inclui" on public.maquinas;
drop policy if exists "admin altera" on public.maquinas;
create policy "gestor inclui" on public.maquinas for insert to authenticated with check ((select private.e_gestor()));
create policy "gestor altera" on public.maquinas for update to authenticated using ((select private.e_gestor())) with check ((select private.e_gestor()));
