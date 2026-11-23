-- 07 · Manter o projeto ativo
-- O plano gratuito do Supabase pausa o projeto depois de 7 dias sem uso.
-- A rotina .github/workflows/manter-supabase-ativo.yml chama esta função todo dia,
-- com a chave publicável (a mesma do index.html). A função só devolve a hora do
-- servidor: faz o banco trabalhar sem ler nem expor nenhum dado.
create or replace function public.manter_ativo()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('ok', true, 'hora', now());
$$;
revoke all on function public.manter_ativo() from public;
grant execute on function public.manter_ativo() to anon, authenticated;
