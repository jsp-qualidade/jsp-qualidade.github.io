-- 04 · Três papéis de acesso
--   admin    = Administrador do sistema: tudo, inclusive cadastros (produtos, máquinas, usuários)
--   gestor   = Gestor da qualidade: tudo, menos os cadastros (pode editar a Biblioteca causa/efeito)
--   inspetor = Inspetor(a) de qualidade: inspeções, árvores de falha e destino do lote

alter table public.colaboradores drop constraint colaboradores_papel_check;
alter table public.colaboradores add constraint colaboradores_papel_check check (papel in ('admin','gestor','inspetor'));

create or replace function private.e_gestor()
 returns boolean language sql stable security definer set search_path to ''
as $$
  select exists (select 1 from auth.users u join public.colaboradores c on c.email = lower(u.email)
    where u.id = (select auth.uid()) and u.email_confirmed_at is not null and c.ativo and c.papel in ('admin','gestor'));
$$;
revoke all on function private.e_gestor() from public;
grant execute on function private.e_gestor() to authenticated;

-- Biblioteca causa/efeito: administrador do sistema e gestor da qualidade
drop policy "admin inclui" on public.causas;
drop policy "admin altera" on public.causas;
create policy "gestor inclui" on public.causas for insert to authenticated with check ((select private.e_gestor()));
create policy "gestor altera" on public.causas for update to authenticated using ((select private.e_gestor())) with check ((select private.e_gestor()));

-- O administrador do sistema não pode tirar o próprio acesso total nem se bloquear (evita ficar sem ninguém com acesso total)
create or replace function private.protege_proprio_admin()
 returns trigger language plpgsql security definer set search_path to ''
as $$
begin
  if old.email = lower((select auth.jwt()) ->> 'email') and old.papel = 'admin'
     and (new.papel <> 'admin' or not new.ativo or new.email <> old.email) then
    raise exception 'Você não pode tirar o seu próprio acesso de administrador do sistema';
  end if;
  return new;
end $$;
drop trigger if exists protege_proprio_admin on public.colaboradores;
create trigger protege_proprio_admin before update on public.colaboradores for each row execute function private.protege_proprio_admin();
