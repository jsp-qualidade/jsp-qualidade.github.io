-- =====================================================================
-- Teste das permissões por perfil (RLS). Rode no SQL Editor do Supabase.
-- O teste simula cada tipo de usuário, mostra o que ele consegue fazer e,
-- no fim, DESFAZ tudo (a mensagem de "erro" final é proposital: ela traz o
-- resultado e cancela a transação, então nenhum dado é alterado).
--
-- Resultado esperado (testado em 25/11/2026):
--   anônimo: bloqueado · usuário não cadastrado: lê 0 e não inclui nada
--   inspetor: lê os registros, não altera produtos nem outros usuários,
--             não lê a auditoria e não exclui usuários
--   gestor:   altera produtos, não altera usuários, não lê a auditoria
--   admin:    tudo, inclusive auditoria e usuários
--   quem ativou a verificação em duas etapas: lê 0 só com a senha (aal1)
--             e lê tudo depois do código (aal2)
-- =====================================================================
do $$
declare r text := ''; n int; u record;
begin
  perform set_config('role','anon',true);
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  begin select count(*) into n from public.inspecoes; r := r||'anônimo lê inspeções: '||n||E'\n';
  exception when others then r := r||'anônimo lê inspeções: bloqueado'||E'\n'; end;
  perform set_config('role','postgres',true);

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","email":"estranho@exemplo.com"}',true);
  select count(*) into n from public.inspecoes; r := r||'não cadastrado lê inspeções: '||n||E'\n';
  begin insert into public.maquinas(id) values ('teste_x'); r := r||'não cadastrado inclui máquina: PERMITIDO (ERRO!)'||E'\n';
  exception when others then r := r||'não cadastrado inclui máquina: bloqueado'||E'\n'; end;
  perform set_config('role','postgres',true);

  for u in select c.papel, c.email, au.id from public.colaboradores c join auth.users au on lower(au.email)=c.email
           where c.ativo order by c.papel loop
    perform set_config('role','authenticated',true);
    perform set_config('request.jwt.claims', json_build_object('sub',u.id,'role','authenticated','email',u.email,'aal','aal2')::text, true);
    select count(*) into n from public.inspecoes; r := r||u.papel||' lê inspeções: '||n||E'\n';
    with x as (update public.produtos set atualizado_em = atualizado_em returning 1) select count(*) into n from x;
    r := r||u.papel||' altera produtos: '||n||' linha(s)'||E'\n';
    with x as (update public.colaboradores set nome = nome where email <> u.email returning 1) select count(*) into n from x;
    r := r||u.papel||' altera outros usuários: '||n||' linha(s)'||E'\n';
    select count(*) into n from public.auditoria_recente(5); r := r||u.papel||' lê auditoria: '||n||' linha(s)'||E'\n';
    begin perform public.excluir_usuario('ninguem@exemplo.com'); r := r||u.papel||' excluir usuário: permitido'||E'\n';
    exception when others then r := r||u.papel||' excluir usuário: bloqueado'||E'\n'; end;
    perform set_config('role','postgres',true);
  end loop;

  select au.id, c.email into u from public.colaboradores c join auth.users au on lower(au.email)=c.email where c.ativo limit 1;
  insert into auth.mfa_factors(id,user_id,friendly_name,factor_type,status,created_at,updated_at)
    values (gen_random_uuid(),u.id,'teste','totp','verified',now(),now());
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims', json_build_object('sub',u.id,'role','authenticated','email',u.email,'aal','aal1')::text, true);
  select count(*) into n from public.inspecoes; r := r||'com 2 etapas, só a senha (aal1): '||n||E'\n';
  perform set_config('request.jwt.claims', json_build_object('sub',u.id,'role','authenticated','email',u.email,'aal','aal2')::text, true);
  select count(*) into n from public.inspecoes; r := r||'com 2 etapas, com o código (aal2): '||n||E'\n';

  raise exception E'RESULTADO DO TESTE (nada foi alterado)\n%', r;
end $$;
