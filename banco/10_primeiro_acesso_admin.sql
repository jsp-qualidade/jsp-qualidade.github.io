-- =====================================================================
-- 10 · Primeiro acesso vira Administrador
-- Quando não existe NENHUM usuário cadastrado (tabela colaboradores vazia),
-- a primeira pessoa que confirma o e-mail e entra no sistema é cadastrada
-- como Administrador, sem pré-cadastro. A partir daí, todo novo acesso
-- depende da aprovação de um Administrador.
-- =====================================================================
create or replace function public.primeiro_acesso_admin()
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_email text; v_ok boolean;
begin
  select lower(u.email), u.email_confirmed_at is not null into v_email, v_ok
  from auth.users u where u.id = (select auth.uid());
  if v_email is null or not v_ok then return false; end if;
  lock table public.colaboradores in share row exclusive mode;
  if exists (select 1 from public.colaboradores) then return false; end if;
  insert into public.colaboradores (email, papel, ativo) values (v_email, 'admin', true);
  return true;
end $$;
revoke all on function public.primeiro_acesso_admin() from public, anon;
grant execute on function public.primeiro_acesso_admin() to authenticated;
