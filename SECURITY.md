# Segurança do Sistema de Qualidade JSP

Este documento descreve como o sistema é protegido, o que roda automaticamente, o que depende de configuração manual e o que fazer em caso de incidente. Ele serve de checklist para quem assumir o sistema na JSP Brasil.

## Como reportar um problema de segurança

Não abra uma issue pública: o repositório é público. Avise diretamente o responsável pelo sistema na JSP: **[preencher: nome e e-mail do responsável na JSP]**. Inclua o que foi observado, quando e em qual tela.

## Como o sistema está montado

- **Site:** um único arquivo `index.html`, publicado pelo GitHub Pages em https://jsp-qualidade.github.io/. Todo o código é público por natureza.
- **Banco:** PostgreSQL no Supabase. O navegador usa apenas a **chave publicável**, que também é pública. Quem protege os dados é a **RLS (Row Level Security)**: regras no próprio banco que dizem o que cada perfil pode ler e alterar.
- **Perfis:** Inspetor, Gestor e Administrador. O perfil fica na tabela `colaboradores`, que só o Administrador altera, e não no perfil editável do usuário (`user_metadata`).

> **Regra que não muda:** a chave `service_role` (ou "secret key") do Supabase **nunca** vai para o `index.html`, para o repositório, para um workflow ou para um print. Ela ignora todas as regras de acesso. Se ela aparecer em qualquer commit, mesmo antigo, gere uma nova imediatamente em Supabase > Settings > API Keys.

## O que está implementado

### No banco (Supabase)

| Proteção | Arquivo | Situação |
|---|---|---|
| RLS em todas as 8 tabelas, com regras por perfil | `banco/01` a `banco/06` | Ativo |
| Funções de verificação em esquema privado, com `search_path` fixo | `banco/01`, `banco/04` | Ativo |
| Exclusão lógica (o registro excluído fica guardado com motivo e usuário) | `banco/01` | Ativo |
| Registro de auditoria: quem incluiu, alterou ou excluiu cada registro, com o conteúdo antes e depois | `banco/08_auditoria.sql` | Ativo desde 25/11/2026 |
| Verificação em duas etapas exigida pelo banco para quem a ativou | `banco/09_exige_segunda_etapa.sql` | Ativo desde 25/11/2026 |
| Teste automatizado das permissões de cada perfil | `banco/testes/teste_permissoes.sql` | Rodado em 25/11/2026: tudo conforme |

**Security Advisor do Supabase (25/11/2026):** zero erros. Restam avisos que são intencionais ou dependem de plano pago:

- `acessos_pendentes`, `excluir_usuario` e `auditoria_recente` são funções `SECURITY DEFINER` que usuários logados podem chamar. É proposital: cada uma confere no início se quem chama é Administrador e não devolve nada para os outros perfis (comprovado no teste de permissões).
- "Leaked password protection" (bloquear senhas que já vazaram na internet) só existe no plano Pro. Risco aceito, compensado pela senha mínima de 8 caracteres e pela verificação em duas etapas.

### No sistema (index.html)

| Proteção | Como funciona |
|---|---|
| Escape de todo texto vindo do banco | A função `esc()` transforma `<`, `>`, aspas e `&` antes de qualquer texto entrar na página. Testado em 25/11/2026 com código malicioso gravado em 304 campos e abertura de 25 telas: nada executou. |
| Content Security Policy (meta tag) | Só permite scripts do próprio site (e do Cloudflare Turnstile), conexões só com `*.supabase.co`, bloqueia plugins (`object-src 'none'`) e troca da base (`base-uri 'none'`). |
| Política de referência | `strict-origin-when-cross-origin`: o endereço completo das páginas não vaza para outros sites. |
| Senha mínima de 8 caracteres | Exigida no cadastro e na troca de senha. |
| Verificação em duas etapas (TOTP) | Em Dados e configuração > Verificação em duas etapas. Funciona com Google Authenticator, Microsoft Authenticator e similares. **Obrigatória para administradores**: o sistema mostra um aviso até ser ativada. |
| CAPTCHA no login (Cloudflare Turnstile) | Chave do site publicada em 25/11/2026. Fica ativo quando a chave secreta é cadastrada no Supabase. Se a verificação não carregar (rede bloqueada), o login não trava: o Supabase decide. |
| Biblioteca do Supabase embutida | O `supabase-js` está dentro do próprio arquivo, e não num CDN externo. Não existe script de terceiros que possa ser trocado sem passar pelo repositório. |
| Fontes no próprio site | A fonte IBM Plex Sans (licença SIL OFL) fica na pasta `fontes/`. O site não chama o Google Fonts, então o IP dos usuários não vai para terceiros e não há folha de estilo externa sem verificação de integridade. |
| Registro de auditoria | O Administrador vê as 100 alterações mais recentes em Dados e configuração > Registro de auditoria. |

### No GitHub (rotinas automáticas)

| Rotina | Arquivo | Quando roda | O que faz |
|---|---|---|---|
| Segredos vazados (TruffleHog) | `.github/workflows/seguranca-segredos.yml` | Cada envio, pull request e toda segunda | Procura chaves válidas em todo o histórico. Fica vermelha se achar. |
| Análise do código (CodeQL) | `.github/workflows/seguranca-codigo.yml` | Cada envio, pull request e toda terça | Procura padrões vulneráveis no JavaScript e nos workflows. Alertas em Security > Code scanning. |
| Varredura do site (OWASP ZAP baseline) | `.github/workflows/seguranca-site.yml` | Toda quarta | Visita o site publicado e gera um relatório (Actions > Artifacts). Não abre issues públicas. Primeira execução (25/11/2026): nenhuma falha; os avisos restantes são limites do GitHub Pages ou falsos positivos, explicados um a um em `.zap/rules.tsv`. |
| Atualização das ações (Dependabot) | `.github/dependabot.yml` | Toda segunda | Abre pull request quando sai versão nova das ações usadas. |
| Backup semanal criptografado | `.github/workflows/backup-banco.yml` | Todo domingo | Exporta o banco, criptografa com AES-256 e guarda por 30 dias. Precisa de configuração (abaixo). |
| Manter o Supabase ativo | `.github/workflows/manter-supabase-ativo.yml` | Todo dia | Evita que o plano gratuito pause o banco. Usa só a chave publicável. |

Todas as rotinas têm permissão mínima (`contents: read`) e usam as ações fixadas pelo código exato da versão (SHA), não por um nome que possa mudar.

## Configuração manual (fazer uma vez)

Estes itens não podem ser ligados pelo código e precisam de alguém com acesso ao painel.

1. **Supabase > Authentication > Sign In / Providers > Email > Minimum password length:** mudar de 6 para **8**. O sistema já exige 8 na tela; isso garante a regra também no servidor.
2. **Supabase > Authentication > Rate Limits:** conferir os limites de envio de e-mail e de tentativas de login (os padrões são adequados para o uso atual).
3. **GitHub > Settings > Advanced Security:** ativar *Secret scanning* e *Push protection*. Eles bloqueiam o envio de um commit que contenha uma chave conhecida.
4. **Backup:** em GitHub > Settings > Secrets and variables > Actions, criar:
   - `SUPABASE_DB_URL`: a conexão do *Session pooler* (Supabase > botão Connect > Session pooler), com a senha do banco.
   - `BACKUP_PASSPHRASE`: uma frase longa usada só para criptografar o backup. **Guarde essa frase fora do GitHub** (ex.: cofre de senhas da JSP). Sem ela, o backup não abre.
   - Depois, rodar Actions > "Backup semanal do banco" > Run workflow e **testar a restauração uma vez** num projeto Supabase de teste.
5. **CAPTCHA (opcional, recomendado):**
   - Criar um site em Cloudflare > Turnstile (gratuito) para o domínio `jsp-qualidade.github.io`.
   - Colar a **Site Key** na linha `const TURNSTILE_SITE_KEY="";` do `index.html`.
   - Só depois de publicar essa mudança, colar a **Secret Key** em Supabase > Authentication > Attack Protection > Enable CAPTCHA (provedor Turnstile). Fazer na ordem inversa bloqueia todos os logins.
6. **Verificação em duas etapas dos administradores:** cada administrador entra no sistema e ativa em Dados e configuração.

## Riscos aceitos e limites conhecidos

- **Cabeçalhos HTTP:** o GitHub Pages não permite configurar cabeçalhos. A CSP por meta tag não cobre `frame-ancestors` (proteção contra o site ser embutido em outro). Se a JSP quiser essa proteção, o caminho é usar um domínio próprio atrás do Cloudflare ou publicar no Cloudflare Pages.
- **`'unsafe-inline'` na CSP:** o JavaScript está dentro do próprio `index.html`, então a CSP precisa aceitar script embutido. A proteção contra XSS vem do escape de todo texto (testado). Separar o JavaScript num arquivo `app.js` permitiria uma CSP mais estrita (trabalho futuro).
- **Senhas vazadas:** a checagem contra a base Have I Been Pwned só existe no plano Pro do Supabase.
- **Backup no plano gratuito:** o Supabase Free não faz backup automático. O backup semanal do GitHub cobre os esquemas `public`, `private` e `audit` (dados do sistema). As contas de login (`auth`) não entram: em caso de restauração, os usuários criam a conta de novo e o Administrador libera.
- **Dados de demonstração:** os registros marcados como DEMO são fictícios e devem ser apagados antes do uso real.

## Rotina de manutenção

| Quando | O quê |
|---|---|
| Toda semana | Olhar Actions: as rotinas de segurança devem estar verdes. Ver o relatório do ZAP se houver alerta novo. |
| Todo mês | Rodar o Security Advisor do Supabase. Conferir se há versão nova do `supabase-js` (a biblioteca embutida no `index.html`). |
| A cada mudança no banco | Rodar o Security Advisor e o `banco/testes/teste_permissoes.sql`. |
| A cada 3 meses | Testar a restauração de um backup. Revisar a lista de usuários ativos e bloquear quem saiu da empresa. |

## LGPD

O sistema trata dados pessoais de colaboradores: nome, e-mail e o registro de quem inspecionou, decidiu ou alterou cada item. A LGPD (Lei 13.709/2018) pede medidas de segurança "aptas a proteger os dados pessoais de acessos não autorizados" desde a concepção do sistema (art. 46). As medidas acima (controle de acesso por perfil, verificação em duas etapas, auditoria e backup) atendem às recomendações do *Guia Orientativo de Segurança da Informação para Agentes de Tratamento de Pequeno Porte* da ANPD.

**Em caso de incidente** (acesso indevido, vazamento ou perda de dados):

1. Bloquear o acesso suspeito: Administrador > Cadastros > Usuários (bloquear) e, se for o caso, gerar novas chaves no Supabase.
2. Consultar o registro de auditoria para saber o que foi acessado ou alterado e por quem.
3. Avisar o responsável pela proteção de dados da JSP. Pela Resolução CD/ANPD nº 15/2024, a comunicação à ANPD e aos titulares, quando o incidente puder causar risco ou dano relevante, deve ser feita em até **3 dias úteis**. O enquadramento da JSP (inclusive como agente de pequeno porte, que tem prazo em dobro) é decisão do jurídico da empresa.

## Ambiente industrial (IEC 62443)

O sistema é um aplicativo web de gestão e **não comanda máquinas**, então a série IEC 62443 (segurança de automação industrial) não se aplica diretamente. Duas recomendações:

- Celulares e computadores que acessam o sistema devem usar a rede corporativa ou de visitantes, e não a mesma rede das máquinas.
- Se no futuro uma balança ou outro equipamento for ligado direto ao sistema, essa ligação deve ser avaliada pela TI/automação da JSP como uma ligação entre a zona industrial e a nuvem.

## Referências

- OWASP Top 10:2025 — https://owasp.org/Top10/2025/
- OWASP ASVS 5.0 (nível 1 usado como checklist) — https://github.com/OWASP/ASVS
- OWASP Cheat Sheet Series — https://github.com/OWASP/CheatSheetSeries
- Supabase: Row Level Security, Database Linter (splinter), MFA (TOTP), CAPTCHA — https://supabase.com/docs
- Supabase: "Postgres Auditing in 150 lines of SQL" — https://supabase.com/blog/postgres-audit
- TruffleHog — https://github.com/trufflesecurity/trufflehog
- CodeQL Action — https://github.com/github/codeql-action
- OWASP ZAP baseline — https://github.com/zaproxy/action-baseline
- Lei 13.709/2018 (LGPD) — https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm
- ANPD, Guia de Segurança para Agentes de Pequeno Porte — https://www.gov.br/anpd
- ISA/IEC 62443 — https://www.isa.org/standards-and-publications/isa-standards/isa-iec-62443-series-of-standards
