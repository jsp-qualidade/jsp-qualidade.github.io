# JSP · Qualidade e Amostragem

Sistema de inspeção por amostragem (NBR 5426, por atributos) e árvores de falha da JSP Brasil.

Acesse: https://jsp-qualidade.github.io/

O site é publicado automaticamente pelo GitHub Pages a partir do arquivo `index.html` da branch `main`.

## Manual de uso

O manual fica dentro do sistema (menu **Manual de uso**; na Tela do operador, botão **Manual**). Cada perfil (Inspetor, Gestor, Administrador) vê só as telas a que tem acesso. No primeiro acesso de cada pessoa aparece uma mensagem de boas-vindas recomendando a leitura; o registro de que ela já viu fica no banco (tabela `orientacao_usuario`, script `banco/12_orientacao_primeiro_acesso.sql`), então a mensagem não volta em outro aparelho.

O texto do manual fica no `index.html`, na constante `MANUAL`. As capturas de tela ficam em `manual/img` e são geradas a partir das telas reais, com os marcadores numerados:

```
pip install playwright pillow
python -m playwright install chromium
python manual/gerar_capturas.py
```

Ao mudar uma tela, atualize o tópico correspondente em `MANUAL` e rode o script de novo.

## Segurança

Veja [SECURITY.md](SECURITY.md): o que protege o sistema, as rotinas automáticas do GitHub, a configuração manual pendente e o que fazer em caso de incidente.
