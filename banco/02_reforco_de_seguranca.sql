-- =====================================================================
-- JSP · Inspeção por Amostragem · REFORÇO DE SEGURANÇA DO BANCO
--
-- O que faz:
--  1) O campo "atualizado_por" passa a ser preenchido pelo próprio banco,
--     com o e-mail de quem está logado (não dá para gravar em nome de outro).
--  2) Só administradores incluem ou alteram PRODUTOS e MÁQUINAS.
--     Inspetores continuam lendo os cadastros e registrando inspeções e árvores.
--
-- Já aplicado no projeto JSP Qualidade Amostragem em 12/11/2026.
-- Como reaplicar em outro projeto (Owner):
--   Supabase > SQL Editor > New query > colar tudo > Run.
-- É seguro rodar mais de uma vez. Não apaga nem altera dados.
-- O site já funciona antes e depois deste script.
-- =====================================================================

-- 1) Quem alterou: definido pelo banco -----------------------------------
create or replace function private.marca_atualizacao()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.atualizado_em := now();
  new.atualizado_por := coalesce(lower((select auth.jwt() ->> 'email')), new.atualizado_por);
  return new;
end $$;

-- 2) Cadastros: gravação só por administradores --------------------------
do $$
declare t text;
begin
  foreach t in array array['produtos','maquinas'] loop
    execute format($f$
      drop policy if exists "colaboradores incluem" on public.%1$I;
      drop policy if exists "colaboradores alteram" on public.%1$I;
      drop policy if exists "admin inclui" on public.%1$I;
      drop policy if exists "admin altera" on public.%1$I;
      create policy "admin inclui" on public.%1$I for insert to authenticated
        with check ((select private.e_admin()));
      create policy "admin altera" on public.%1$I for update to authenticated
        using ((select private.e_admin())) with check ((select private.e_admin()));
    $f$, t);
  end loop;
end $$;

-- 3) Lista de colaboradores: a regra de leitura avalia o usuário uma vez só por consulta ---
drop policy if exists "ve o proprio cadastro ou admin ve todos" on public.colaboradores;
create policy "ve o proprio cadastro ou admin ve todos" on public.colaboradores for select to authenticated
  using (email = lower(((select auth.jwt()) ->> 'email')) or (select private.e_admin()));

-- Conferência: deve listar "admin inclui" e "admin altera" em produtos e maquinas
select tablename, policyname, cmd from pg_policies
where schemaname = 'public' and tablename in ('produtos','maquinas') order by 1, 2;
