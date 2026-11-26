-- Teste das regras da tabela orientacao_usuario (12_orientacao_primeiro_acesso.sql).
-- Simula um colaborador e um usuário estranho. No fim, o bloco lança uma exceção
-- de propósito com o resultado: assim tudo é desfeito e nada fica gravado.
-- Resultado esperado: propria_visivel=1 | repetir_ok | outro=bloqueado | update=bloqueado | estranho_ve=0 | nao_colab=bloqueado
do $$
declare uid uuid; outro uuid := gen_random_uuid(); n int; r text := '';
begin
  select u.id into uid from auth.users u join public.colaboradores c on c.email=lower(u.email) where c.ativo limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated','aal','aal2')::text, true);
  set local role authenticated;
  insert into public.orientacao_usuario default values;
  select count(*) into n from public.orientacao_usuario; r := r||'propria_visivel='||n;
  insert into public.orientacao_usuario default values on conflict do nothing; r:=r||' | repetir_ok';
  begin insert into public.orientacao_usuario(user_id) values (outro); r:=r||' | outro=PERMITIDO(ERRO)';
  exception when others then r:=r||' | outro=bloqueado'; end;
  begin update public.orientacao_usuario set visto_em=now(); r:=r||' | update=permitido(ERRO)';
  exception when others then r:=r||' | update=bloqueado'; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',gen_random_uuid(),'role','authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.orientacao_usuario; r:=r||' | estranho_ve='||n;
  begin insert into public.orientacao_usuario default values; r:=r||' | nao_colab_insere(ERRO)';
  exception when others then r:=r||' | nao_colab=bloqueado'; end;
  reset role;
  raise exception 'RESULTADO: %', r;
end $$;
