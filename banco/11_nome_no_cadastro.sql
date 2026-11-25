-- =====================================================================
-- 11 · Nome informado no cadastro
-- Ao criar a conta, a pessoa informa o nome (guardado como metadado "nome"
-- da conta). Ele aparece na lista de pedidos e já vem preenchido na
-- aprovação. É só um dado de exibição: perfil e acesso continuam sendo
-- decididos pelo Administrador.
-- =====================================================================
drop function if exists public.acessos_pendentes();
create function public.acessos_pendentes()
returns table(email text, nome text, criado_em timestamptz, confirmado boolean)
language sql stable security definer set search_path = '' as $$
  select lower(u.email)::text,
         nullif(left(btrim(u.raw_user_meta_data ->> 'nome'), 80), '')::text,
         u.created_at, u.email_confirmed_at is not null
  from auth.users u
  where (select private.e_admin())
    and u.email is not null
    and not exists (select 1 from public.colaboradores c where c.email = lower(u.email))
  order by u.created_at;
$$;
revoke all on function public.acessos_pendentes() from public, anon;
grant execute on function public.acessos_pendentes() to authenticated;

create or replace function public.primeiro_acesso_admin()
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_email text; v_ok boolean; v_nome text;
begin
  select lower(u.email), u.email_confirmed_at is not null,
         nullif(left(btrim(u.raw_user_meta_data ->> 'nome'), 80), '')
    into v_email, v_ok, v_nome
  from auth.users u where u.id = (select auth.uid());
  if v_email is null or not v_ok then return false; end if;
  lock table public.colaboradores in share row exclusive mode;
  if exists (select 1 from public.colaboradores) then return false; end if;
  insert into public.colaboradores (email, nome, papel, ativo) values (v_email, v_nome, 'admin', true);
  return true;
end $$;
revoke all on function public.primeiro_acesso_admin() from public, anon;
grant execute on function public.primeiro_acesso_admin() to authenticated;
