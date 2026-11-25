-- =====================================================================
-- 08 · Registro de auditoria
-- Toda inclusão, alteração ou exclusão nas tabelas do sistema fica gravada
-- em audit.registro, com o usuário (auth.uid e e-mail), a data e o conteúdo
-- antes e depois. O esquema "audit" não é exposto pela API do navegador.
-- O Administrador consulta os registros recentes em "Dados e configuração"
-- (função public.auditoria_recente, que só responde para administradores).
-- Baseado no artigo "Postgres Auditing in 150 lines of SQL" (Supabase), já que
-- a extensão supa_audit foi arquivada em fev/2025.
-- =====================================================================
create schema if not exists audit;
revoke all on schema audit from public, anon, authenticated;

create table if not exists audit.registro (
  id          bigint generated always as identity primary key,
  tabela      text        not null,
  operacao    text        not null check (operacao in ('INSERT','UPDATE','DELETE')),
  registro_id text,
  usuario_id  uuid,
  usuario_email text,
  em          timestamptz not null default now(),
  antes       jsonb,
  depois      jsonb
);
create index if not exists registro_tabela_em on audit.registro (tabela, em desc);
create index if not exists registro_registro_id on audit.registro (registro_id);
revoke all on audit.registro from public, anon, authenticated;

create or replace function audit.grava()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_old jsonb; v_new jsonb;
begin
  if tg_op in ('UPDATE','DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('INSERT','UPDATE') then v_new := to_jsonb(new); end if;
  if tg_op = 'UPDATE' and v_old = v_new then return new; end if;
  insert into audit.registro (tabela, operacao, registro_id, usuario_id, usuario_email, antes, depois)
  values (tg_table_name, tg_op,
          coalesce(v_new ->> 'id', v_old ->> 'id', v_new ->> 'email', v_old ->> 'email'),
          (select auth.uid()), lower((select auth.jwt()) ->> 'email'), v_old, v_new);
  return coalesce(new, old);
end $$;
revoke all on function audit.grava() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['colaboradores','produtos','maquinas','falhas','causas','inspecoes','investigacoes','pesagens'] loop
    execute format('drop trigger if exists auditoria on public.%I', t);
    execute format('create trigger auditoria after insert or update or delete on public.%I for each row execute function audit.grava()', t);
  end loop;
end $$;

create or replace function public.auditoria_recente(p_limite int default 200)
returns table(em timestamptz, tabela text, operacao text, registro_id text, usuario_email text)
language sql stable security definer set search_path = '' as $$
  select r.em, r.tabela, r.operacao, r.registro_id, r.usuario_email
  from audit.registro r
  where (select private.e_admin())
  order by r.em desc
  limit least(greatest(coalesce(p_limite,200),1),1000);
$$;
revoke all on function public.auditoria_recente(int) from public, anon;
grant execute on function public.auditoria_recente(int) to authenticated;
