-- =====================================================================
-- 09 · Verificação em duas etapas (TOTP) exigida pelo banco
-- Quem ativou a verificação em duas etapas só acessa os dados com a sessão
-- verificada (aal2), ou seja, depois de digitar o código do aplicativo.
-- Quem ainda não ativou continua entrando só com a senha. O sistema avisa os
-- administradores para ativarem (obrigatória para eles).
-- =====================================================================
create or replace function private.sessao_ok(p_uid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select auth.jwt()) ->> 'aal', 'aal1') = 'aal2'
      or not exists (select 1 from auth.mfa_factors f where f.user_id = p_uid and f.status = 'verified');
$$;
revoke all on function private.sessao_ok(uuid) from public, anon;
grant execute on function private.sessao_ok(uuid) to authenticated;

create or replace function private.e_colaborador()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u join public.colaboradores c on c.email = lower(u.email)
    where u.id = (select auth.uid()) and u.email_confirmed_at is not null and c.ativo
      and private.sessao_ok(u.id));
$$;
create or replace function private.e_gestor()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u join public.colaboradores c on c.email = lower(u.email)
    where u.id = (select auth.uid()) and u.email_confirmed_at is not null and c.ativo and c.papel in ('admin','gestor')
      and private.sessao_ok(u.id));
$$;
create or replace function private.e_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u join public.colaboradores c on c.email = lower(u.email)
    where u.id = (select auth.uid()) and u.email_confirmed_at is not null and c.ativo and c.papel = 'admin'
      and private.sessao_ok(u.id));
$$;
