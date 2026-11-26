-- =====================================================================
-- 12 · Orientação de primeiro acesso (manual)
-- Guarda, para cada usuário, quando ele viu a mensagem de boas-vindas que
-- recomenda a leitura do manual. Fica ligada à conta (auth.users), não ao
-- aparelho: quem já viu num computador não vê de novo no celular.
-- Só o próprio usuário lê e grava a sua linha. Nada além do id e da data.
-- =====================================================================
create table if not exists public.orientacao_usuario (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  visto_em timestamptz not null default now()
);
comment on table public.orientacao_usuario is 'Data em que cada usuário viu a orientação de primeiro acesso (manual do sistema).';

alter table public.orientacao_usuario enable row level security;
alter table public.orientacao_usuario force row level security;

revoke all on public.orientacao_usuario from public, anon, authenticated;
grant select, insert on public.orientacao_usuario to authenticated;

drop policy if exists "le a propria orientacao" on public.orientacao_usuario;
create policy "le a propria orientacao" on public.orientacao_usuario
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "registra a propria orientacao" on public.orientacao_usuario;
create policy "registra a propria orientacao" on public.orientacao_usuario
  for insert to authenticated
  with check (user_id = (select auth.uid()) and (select private.e_colaborador()));
