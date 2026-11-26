"""
Gera a versão piloto do sistema, para compartilhar com quem quer conhecer e testar.

    python ferramentas/gerar_piloto.py [pasta_de_saida]
    python ferramentas/gerar_piloto.py piloto --site   (versão do site: piloto/index.html)

A versão piloto é o mesmo index.html com três mudanças:
  - abre direto no modo local (sem tela de login e sem banco na nuvem);
  - não tem o endereço nem a chave do banco: não consegue ler nem gravar nos dados da JSP;
  - guarda os dados num banco local com outro nome, para não misturar com o sistema oficial
    aberto no mesmo computador.
Na primeira abertura, carrega a demonstração (lotes, árvores e pesagens fictícios, marcados DEMO).

Saída: Sistema_JSP_Piloto.html, com as pastas fontes/ e manual/img/ ao lado
(o arquivo precisa delas para as letras e as imagens do manual).
"""
import pathlib, re, shutil, sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
args = [a for a in sys.argv[1:] if not a.startswith("--")]
saida = pathlib.Path(args[0]) if args else RAIZ / "piloto"
s = (RAIZ / "index.html").read_text(encoding="utf-8")

def troca(antigo, novo):
    global s
    if s.count(antigo) != 1:
        sys.exit(f"Trecho não encontrado (ou repetido) no index.html: {antigo[:60]}")
    s = s.replace(antigo, novo)

troca("const PILOTO=false;", "const PILOTO=true;")
s, n = re.subn(r'const CLOUD_CFG=\{url:"[^"]*",key:"[^"]*"\};', 'const CLOUD_CFG={url:"",key:""};', s)
if n != 1: sys.exit("CLOUD_CFG não encontrado")
troca('const DBNAME="jsp-qualidade-amostragem"', 'const DBNAME="jsp-qualidade-piloto"')
s, n = re.subn(r"<title>([^<]*)</title>", r"<title>\1 · Piloto</title>", s, count=1)

saida.mkdir(parents=True, exist_ok=True)
(saida / "Sistema_JSP_Piloto.html").write_text(s, encoding="utf-8")
if "--site" in sys.argv:  # versão publicada no site (jsp-qualidade.github.io/piloto/)
    (saida / "index.html").write_text(s, encoding="utf-8")
    (saida / "Sistema_JSP_Piloto.html").unlink()
for pasta in ["fontes", "manual/img"]:
    destino = saida / pasta
    shutil.copytree(RAIZ / pasta, destino, dirs_exist_ok=True)
print("Versão piloto gerada em", saida)
