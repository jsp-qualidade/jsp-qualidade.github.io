"""
Gera as capturas de tela do Manual de uso (pasta manual/img).

Como usar (precisa de Python 3, Playwright e Pillow):
    pip install playwright pillow
    python -m playwright install chromium
    python manual/gerar_capturas.py            # todas
    python manual/gerar_capturas.py op_passo1  # só uma

O script abre o index.html local em modo local, carrega a demonstração e
simula o papel de cada perfil (Inspetor, Gestor, Administrador) sem tocar no
banco. Para cada imagem declarada nos tópicos do MANUAL (index.html), abre a
tela, prepara o estado e desenha os marcadores numerados dos campos que têm
seletor ("m"). Rode de novo sempre que uma tela mudar.
"""
import asyncio, io, json, pathlib, sys
from playwright.async_api import async_playwright
from PIL import Image

RAIZ = pathlib.Path(__file__).resolve().parent.parent
URL = (RAIZ / "index.html").as_uri()
SAIDA = RAIZ / "manual" / "img"

# Simula o login de um perfil, sem banco: substitui o cliente do Supabase por um
# objeto que devolve listas vazias e grava nada.
STUB = r"""(papel)=>{
  const colabs=[{email:"chefe@jsp.com",nome:"Carlos Mendes",papel:"admin",ativo:true},{email:"gestora@jsp.com",nome:"Gestora",papel:"gestor",ativo:true},{email:"ana@jsp.com",nome:"Ana Paula Souza",papel:"inspetor",ativo:true}];
  const me={a:colabs[0],g:colabs[1],i:colabs[2]}[papel];
  const chain=(table)=>{const st={single:false};const p=new Proxy(function(){}, {get(_,k){
      if(k==="then"){const res={data:table==="colaboradores"?(st.single?me:colabs):(st.single?null:[]),error:null,count:0};return (r,j)=>Promise.resolve(res).then(r,j)}
      return (...a)=>{if(k==="maybeSingle"||k==="single")st.single=true;return p}}});return p};
  sb={from:t=>chain(t),rpc:async(n)=>({data:n==="acessos_pendentes"?(window.__pend||[]):[],error:null}),
    auth:{getSession:async()=>({data:{session:null}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),signOut:async()=>({}),
      mfa:{listFactors:async()=>({data:{totp:[],all:[]},error:null})}},
    channel:()=>({on(){return this},subscribe(){return this}}),removeChannel(){}};
  user={email:me.email};colab={...me};cloudState="ok";pendentes=window.__pend||[];
  sessionStorage.removeItem("jsp-modo-local");
}"""

# Desenha um marcador numerado sobre cada elemento. Dentro de um <dialog>, o
# marcador vai dentro dele (camada superior); fora, fica no documento.
MARCAR = r"""(lista)=>{
  document.querySelectorAll(".mkr").forEach(e=>e.remove());
  const vis=e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(e).visibility!=="hidden"};
  const acha=s=>{
    const [q,up]=s.split("@");let e=null;
    if(q.startsWith("text=")){const t=q.slice(5);
      document.querySelectorAll("#page *,dialog *,#topright *,#nav *,#actionbar *").forEach(x=>{const tx=(x.textContent||"").trim();if(tx.startsWith(t)&&vis(x)){if(!e||e.contains(x))e=x}})}
    else e=[...document.querySelectorAll(q)].find(vis)||null;
    return e&&up?e.closest(up):e};
  const falta=[];
  lista.forEach(([n,s])=>{const e=acha(s);if(!e){falta.push(s);return}
    const dlg=e.closest("dialog"),r=e.getBoundingClientRect(),sx=dlg?0:scrollX,sy=dlg?0:scrollY,pos=dlg?"fixed":"absolute",host=dlg||document.body;
    const box=document.createElement("div");box.className="mkr";
    box.style.cssText=`position:${pos};left:${r.left+sx-4}px;top:${r.top+sy-4}px;width:${r.width+8}px;height:${r.height+8}px;border:2.5px solid #D9480F;border-radius:9px;z-index:2147483646;pointer-events:none;box-sizing:border-box`;
    const b=document.createElement("div");b.className="mkr";b.textContent=n;
    const peq=r.height<34,esq=r.left>36;
    const bx=peq?(esq?r.left+sx-34:r.right+sx+8):Math.min(innerWidth-30,Math.max(2,r.right+sx-14)),by=peq?r.top+sy+r.height/2-13:Math.max(2,r.top+sy-14);
    b.style.cssText=`position:${pos};left:${bx}px;top:${by}px;width:26px;height:26px;border-radius:50%;background:#D9480F;color:#fff;font:700 14px/26px "IBM Plex Sans",Arial,sans-serif;text-align:center;box-shadow:0 0 0 2.5px #fff,0 2px 6px rgba(0,0,0,.35);z-index:2147483647;pointer-events:none`;
    host.appendChild(box);host.appendChild(b)});
  return falta}"""

VP_OP = {"width": 820, "height": 1180}
VP_G = {"width": 1280, "height": 820}

def js_ids():
    return """({
      rej:(S.inspecoes.find(x=>lotStage(x).k==="disp"&&lotTrees(x).every(treeFilled)&&lotTrees(x).some(v=>probable(v).length))||S.inspecoes.find(x=>lotStage(x).k==="disp")||{}).id,
      arvMulti:(S.investigacoes.find(v=>v.inspecaoId&&treeFilled(v)&&S.investigacoes.filter(w=>w.inspecaoId===v.inspecaoId).length>1)||{}).id,
      arvOp:(S.investigacoes.find(v=>v.inspecaoId&&treeFilled(v)&&presenceQs(v).length&&origin(v))||S.investigacoes.find(v=>v.inspecaoId&&treeFilled(v))||{}).id,
      causa:(CAUSES.find(c=>(c.defs||[]).includes("rebarba"))||CAUSES[0]).id,
      p:S.produtos[0].id, m:S.maquinas[0].codigo })"""

async def prep(pg, nome, ids):
    """Estado de cada captura. Tudo em memória: nada é gravado."""
    p, m = ids["p"], ids["m"]
    base = f'OP=opNovo();Object.assign(OP,{{ponto:"FL",productId:"{p}",maquina:"{m}",lote:"2611-03",N:"500"}});'
    if nome == "opPasso1": await pg.evaluate(base + 'go("opnova")')
    elif nome == "opPasso2": await pg.evaluate(base + 'Object.assign(OP,{step:2,nc:"1",defs:["rebarba"],confirmado:true});go("opnova");pgOpNova()')
    elif nome == "opPasso3": await pg.evaluate(base + 'Object.assign(OP,{step:3,nc:"1",defs:["rebarba"],confirmado:true,obs:"Rebarba na lateral, peça da cavidade 2."});go("opnova");pgOpNova()')
    elif nome == "opArvore":
        await pg.evaluate(f'''(()=>{{const v=S.investigacoes.find(i=>i.id==="{ids["arvOp"]}");
          stagesFor(v).filter(s=>stageActive(v,s)).flatMap(s=>causesFor(v,s)).forEach((c,i)=>{{v.respostas[c.id]={{a:i===0?"S":"N"}}}});go("oparvore",v.id)}})()''')
    elif nome == "opLote": await pg.evaluate(f'go("oplote","{ids["rej"]}")')
    elif nome == "opCem":
        await pg.evaluate(f'''(()=>{{const x=S.inspecoes.find(i=>lotStage(i).k==="cem")||S.inspecoes.find(i=>i.id==="{ids["rej"]}");
          if(lotStage(x).k!=="cem"){{x.disp={{tipo:"segregar",motivo:"",just:"",em:new Date().toISOString(),por:"Gestora",amostragem:"R",arvores:[]}};x.c100={{status:"andamento",inicio:new Date().toISOString(),por:"Gestora",N:x.N,qtd:{{}},novos:[]}}}}
          x.c100.modo="qtd";x.c100.r="16";go("opcem",x.id);pgOpCem()}})()''')
    elif nome == "opOcorr": await pg.evaluate(f'OC=ocNovo();Object.assign(OC,{{ponto:"MOLD",productId:"{p}",maquina:"{m}",lote:"RACK-43",qtd:"4",defs:["rebarba"],obs:"Rebarba grossa saindo da cavidade 2 desde o começo do turno."}});go("opocorr");pgOpOcorr()')
    elif nome == "opPeso":
        await pg.evaluate('go("oppeso","seco")')
        await pg.wait_for_timeout(300)
        await pg.evaluate('psForm.v=["1,214","1,198","1,221","1,206","1,210"];psForm.lote="128";psForm.turno="2º";render()')
    elif nome == "carta":
        await pg.evaluate('go("painel")'); await pg.wait_for_timeout(400)
        await pg.evaluate('document.getElementById("cepCard").scrollIntoView({block:"start"})'); await pg.wait_for_timeout(200)
        pt = pg.locator('#cepCard .cep-hit[data-sn="1"] .cep-pt').first
        if not await pt.count(): pt = pg.locator('#cepCard .cep-hit .cep-pt').nth(10)
        bb = await pt.bounding_box(); await pg.mouse.move(bb["x"] + bb["width"] / 2, bb["y"] + bb["height"] / 2); await pg.wait_for_timeout(900)
    elif nome == "loteRej": await pg.evaluate(f'go("inspecao","{ids["rej"]}")')
    elif nome == "decisao": await pg.evaluate(f'dispDraft["{ids["rej"]}"]={{tipo:"aceitar",motivo:"oculto",just:"Rebarba de 4 mm na aba inferior, escondida pelo carpete do porta-malas.",por:""}};go("disposicao","{ids["rej"]}")')
    elif nome == "arvore": await pg.evaluate(f'go("arvore","{ids["arvMulti"]}")')
    elif nome == "biblioteca":
        await pg.evaluate('go("biblioteca")'); await pg.wait_for_timeout(300)
        await pg.locator('#page button:has-text("Rebarba acima")').first.click()
    elif nome == "causa": await pg.evaluate(f'go("causa","{ids["causa"]}")')
    elif nome == "produto": await pg.evaluate(f'go("produto","{p}")')
    elif nome == "maquinas":
        await pg.evaluate('go("cadastros")'); await pg.wait_for_timeout(300)
        await pg.click('[data-ct="maquinas"]'); await pg.wait_for_timeout(200); await pg.click('#newM'); await pg.wait_for_timeout(200)
        await pg.fill('#mq_cod', 'K1020'); await pg.fill('#mq_tipo', 'Moldadora K1020')
    elif nome == "falha": await pg.evaluate('go("falha","rebarba")')
    elif nome == "usuarios":
        await pg.evaluate('go("cadastros")'); await pg.wait_for_timeout(300)
        await pg.click('[data-ct="usuarios"]')
    elif nome == "excluir":
        await pg.evaluate(f'go("inspecao","{ids["rej"]}")'); await pg.wait_for_timeout(300)
        await pg.click('#delI'); await pg.wait_for_timeout(200)
        await pg.fill('#dlg textarea', 'Registrado no lote 2611-03; o correto é 2611-04.')
    elif nome == "mfa":
        await pg.evaluate('go("dados")'); await pg.wait_for_timeout(500)
        await pg.evaluate('document.getElementById("mfaBox").scrollIntoView({block:"center"})')
    elif nome == "boasvindas":
        await pg.evaluate('go("painel")'); await pg.wait_for_timeout(300); await pg.evaluate('orientAbrir()')

async def main(so):
    SAIDA.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as pw:
        nav = await pw.chromium.launch()
        pg0 = await nav.new_page()
        await pg0.goto(URL); await pg0.wait_for_timeout(600)
        imagens = await pg0.evaluate("""MANUAL.flatMap(t=>{const im=t.img?(Array.isArray(t.img)?t.img:[t.img]):[];let n=0;
          const marc=(t.campos||[]).filter(c=>c.m).map(c=>({n:++n,m:c.m,i:c.i||0}));
          return im.map((x,k)=>({...x,marcas:marc.filter(c=>c.i===k).map(c=>[c.n,c.m])}))})""")
        await pg0.close()
        relatorio = []
        for im in imagens:
            if so and im["id"] not in so: continue
            op = im["perfil"] == "i"
            ctx = await nav.new_context(viewport=VP_OP if op else VP_G, device_scale_factor=1.5 if op else 1.25)
            pg = await ctx.new_page(); erros = []; pg.on("pageerror", lambda e: erros.append(str(e)))
            pg.on("dialog", lambda d: asyncio.ensure_future(d.dismiss()))
            await pg.goto(URL); await pg.wait_for_timeout(800)
            if im["perfil"] == "login":
                await pg.click('[data-lm="criar"]'); await pg.wait_for_timeout(200)
                await pg.fill('#lgNome', 'Ana Paula Souza'); await pg.fill('#lgEmail', 'ana.souza@jsp.com.br'); await pg.fill('#lgPass', 'senha-exemplo')
            else:
                await pg.click('summary'); await pg.click('#lgLocal'); await pg.wait_for_timeout(500)
                await pg.evaluate('go("dados")'); await pg.wait_for_timeout(200)
                await pg.evaluate('loadDemo()'); await pg.wait_for_timeout(2600)
                if im.get("prep") == "usuarios":
                    await pg.evaluate('window.__pend=[{email:"bruno.lima@jsp.com.br",nome:"Bruno Lima",criado_em:new Date().toISOString(),confirmado:true}]')
                await pg.evaluate(STUB, im["perfil"])
                ids = await pg.evaluate(js_ids())
                if im.get("prep"): await prep(pg, im["prep"], ids)
                else: await pg.evaluate(f'go({json.dumps(im["rota"].split("/")[0])},{json.dumps(im["rota"].split("/")[1]) if "/" in im["rota"] else "null"})')
            await pg.wait_for_timeout(700)
            await pg.evaluate('document.getElementById("demoBanner")?.remove()')
            if im.get("prep") not in ("carta", "mfa"): await pg.evaluate('window.scrollTo(0,0)')
            await pg.add_style_tag(content=".ceptip{transition:none!important;opacity:1!important;visibility:visible!important}")
            dialogo = await pg.evaluate('!!document.querySelector("dialog[open]")')
            inteira = not im.get("alvo") and not dialogo
            if inteira:
                # A tela inteira cabe numa janela da altura do conteúdo (com limite): a barra fixa
                # do rodapé fica no fim da imagem, como o usuário vê.
                vp = VP_OP if op else VP_G
                alt = await pg.evaluate("Math.max(560,Math.ceil(document.getElementById('page').getBoundingClientRect().bottom+scrollY+(document.getElementById('actionbar').hidden?24:110)))")
                await pg.set_viewport_size({"width": vp["width"], "height": min(alt, 1500 if op else 1200)})
                await pg.wait_for_timeout(300); await pg.evaluate("window.scrollTo(0,0)")
            falta = await pg.evaluate(MARCAR, im["marcas"])
            if im.get("alvo"):
                el = pg.locator(im["alvo"]).first; bb = await el.bounding_box()
                vw = (VP_OP if op else VP_G)["width"]
                clip = {"x": max(0, bb["x"] - 18), "y": max(0, bb["y"] - 18), "width": min(vw, bb["width"] + 36), "height": bb["height"] + 36}
                png = await pg.screenshot(clip=clip)
            else:
                png = await pg.screenshot()
            img = Image.open(io.BytesIO(png)).convert("RGB")
            img.save(SAIDA / f'{im["id"]}.webp', "WEBP", quality=80, method=6)
            relatorio.append((im["id"], img.size, falta, erros[:2]))
            await ctx.close()
        await nav.close()
    for r in relatorio:
        print(f"{r[0]:<14} {r[1][0]}x{r[1][1]}" + (f"  FALTOU: {r[2]}" if r[2] else "") + (f"  ERRO: {r[3]}" if r[3] else ""))

if __name__ == "__main__":
    asyncio.run(main(set(sys.argv[1:])))
