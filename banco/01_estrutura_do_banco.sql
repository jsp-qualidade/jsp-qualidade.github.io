-- =====================================================================
-- JSP · Inspeção por Amostragem e Análise de Falhas
-- Banco de dados compartilhado (Supabase / PostgreSQL)
--
-- Acesso: somente usuários com e-mail CONFIRMADO e cadastrado (ativo)
-- na tabela "colaboradores". Administradores gerenciam essa lista.
-- Exclusões são lógicas (coluna "excluido"), para manter a rastreabilidade.
-- =====================================================================

-- Colaboradores autorizados ------------------------------------------------
create table if not exists public.colaboradores (
  email      text primary key check (email = lower(email)),
  nome       text,
  papel      text not null default 'inspetor' check (papel in ('admin','inspetor')),
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

-- Funções de verificação em esquema não exposto pela API --------------------
create schema if not exists private;

create or replace function private.e_colaborador()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from auth.users u
    join public.colaboradores c on c.email = lower(u.email)
    where u.id = (select auth.uid())
      and u.email_confirmed_at is not null
      and c.ativo
  );
$$;

create or replace function private.e_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from auth.users u
    join public.colaboradores c on c.email = lower(u.email)
    where u.id = (select auth.uid())
      and u.email_confirmed_at is not null
      and c.ativo
      and c.papel = 'admin'
  );
$$;

revoke all on function private.e_colaborador() from public, anon;
revoke all on function private.e_admin() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.e_colaborador() to authenticated;
grant execute on function private.e_admin() to authenticated;

-- Tabelas de dados (o registro completo fica em "dados", em JSON) -----------
create or replace function private.marca_atualizacao()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.atualizado_em := now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['produtos','inspecoes','investigacoes'] loop
    execute format($f$
      create table if not exists public.%1$I (
        id             text primary key,
        dados          jsonb not null default '{}'::jsonb,
        excluido       boolean not null default false,
        atualizado_em  timestamptz not null default now(),
        atualizado_por text
      );
      create index if not exists %1$s_atualizado_em_idx on public.%1$I (atualizado_em);
      drop trigger if exists %1$s_marca on public.%1$I;
      create trigger %1$s_marca before insert or update on public.%1$I
        for each row execute function private.marca_atualizacao();
      alter table public.%1$I enable row level security;
      drop policy if exists "colaboradores leem" on public.%1$I;
      drop policy if exists "colaboradores incluem" on public.%1$I;
      drop policy if exists "colaboradores alteram" on public.%1$I;
      create policy "colaboradores leem" on public.%1$I for select to authenticated
        using ((select private.e_colaborador()));
      create policy "colaboradores incluem" on public.%1$I for insert to authenticated
        with check ((select private.e_colaborador()));
      create policy "colaboradores alteram" on public.%1$I for update to authenticated
        using ((select private.e_colaborador()))
        with check ((select private.e_colaborador()));
      revoke all on public.%1$I from anon;
      grant select, insert, update on public.%1$I to authenticated;
    $f$, t);
  end loop;
end $$;

-- Regras de acesso à lista de colaboradores ---------------------------------
alter table public.colaboradores enable row level security;
drop policy if exists "ve o proprio cadastro ou admin ve todos" on public.colaboradores;
drop policy if exists "admin inclui" on public.colaboradores;
drop policy if exists "admin altera" on public.colaboradores;
drop policy if exists "admin remove" on public.colaboradores;
create policy "ve o proprio cadastro ou admin ve todos" on public.colaboradores for select to authenticated
  using (email = lower((select auth.jwt() ->> 'email')) or (select private.e_admin()));
create policy "admin inclui" on public.colaboradores for insert to authenticated
  with check ((select private.e_admin()));
create policy "admin altera" on public.colaboradores for update to authenticated
  using ((select private.e_admin())) with check ((select private.e_admin()));
create policy "admin remove" on public.colaboradores for delete to authenticated
  using ((select private.e_admin()));
revoke all on public.colaboradores from anon;
grant select, insert, update, delete on public.colaboradores to authenticated;

-- Primeiro administrador (troque pelo e-mail do responsável na JSP) ----------
-- insert into public.colaboradores (email, nome, papel) values ('responsavel@jsp.com', 'Nome', 'admin');

-- Fila de pedidos de acesso (contas criadas que ainda não estão em "colaboradores") ---
create or replace function public.acessos_pendentes()
returns table (email text, criado_em timestamptz, confirmado boolean)
language sql stable security definer set search_path = ''
as $$
  select lower(u.email)::text, u.created_at, u.email_confirmed_at is not null
  from auth.users u
  where (select private.e_admin())
    and u.email is not null
    and not exists (select 1 from public.colaboradores c where c.email = lower(u.email))
  order by u.created_at;
$$;
revoke all on function public.acessos_pendentes() from public, anon;
grant execute on function public.acessos_pendentes() to authenticated;

-- Cadastro de máquinas: mesma estrutura de produtos/inspecoes/investigacoes (tabela public.maquinas,
-- políticas "colaboradores leem/incluem/alteram"), aplicada na migração maquinas_e_exclusao_de_usuario.

-- Exclusão de usuário (somente administradores): remove a conta e o cadastro
create or replace function public.excluir_usuario(p_email text)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_email text := lower(trim(p_email));
begin
  if not (select private.e_admin()) then
    raise exception 'Somente administradores podem excluir usuários';
  end if;
  if v_email = lower((select auth.jwt() ->> 'email')) then
    raise exception 'Você não pode excluir a sua própria conta';
  end if;
  delete from public.colaboradores where email = v_email;
  delete from auth.users where lower(email) = v_email;
  return true;
end $$;
revoke all on function public.excluir_usuario(text) from public, anon;
grant execute on function public.excluir_usuario(text) to authenticated;
