# Extract Me Honey — Apiário Vivo

Jogo incremental em Ruby2D com cenário e sprites ilustrados a partir de `image.png`.

**No navegador / GitHub Pages**

A versão web compila o mesmo jogo Ruby para WebAssembly com Ruby2D 1.0 e Emscripten.
O GitHub Pages publica os arquivos compilados; enviar apenas `main.rb` não executa o jogo no navegador.

Para publicar em <https://zeraiden56.github.io/extract-me-honey/>:

1. Envie estes arquivos para a branch `main` (ou `master`) do repositório `extract-me-honey`, incluindo `.github/workflows/pages.yml`, `scripts/`, `web/`, `lib/` e `assets/`.
2. No GitHub, abra **Settings → Pages → Build and deployment → Source → GitHub Actions**.
3. Na aba **Actions**, acompanhe **Publicar jogo no GitHub Pages**. Se necessário, use **Run workflow**. Ao concluir, abra o endereço acima.

O workflow instala as ferramentas, testa o jogo, compila e publica somente `build/web/`.
Novos pushes em `main` ou `master` atualizam a versão publicada. A primeira compilação leva alguns minutos.
O botão **Tela cheia** amplia o campo; em celulares, prefira jogar na horizontal.

O save web fica no armazenamento local do navegador, separado do save desktop e de outros dispositivos.
Compras e cliques são salvos imediatamente; a produção é salva a cada oito segundos.
Ao voltar ao jogo ou a uma aba suspensa, os ganhos offline usam produção normal, limitados a oito horas.
**Baixar save** exporta o progresso em JSON. Limpar os dados do site apaga o save local.
Para experimentar sem alterar seu progresso, abra o endereço com `?demo=1`.

Para compilar e testar localmente, instale o [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html), ative a versão `6.0.11` e carregue `emsdk_env.sh`. Com as gems instaladas:

```bash
# No Linux, rode uma vez para preparar SDL3 e o compilador mruby:
bundle exec ruby2d setup

bundle exec ruby scripts/build_web.rb
python3 -m http.server 8080 --directory build/web
```

Abra <http://localhost:8080/>. Use um servidor HTTP; abrir o HTML por `file://` não funciona.
O script reúne os arquivos Ruby locais e inclui as artes, gerando `index.html`, `app.js`, `app.wasm` e `app.data` em `build/web/`.
`build/` e `tmp/` são saídas temporárias e não precisam ser enviadas ao GitHub.

Referências: [compilação web do Ruby2D](https://www.ruby2d.com/learn/building/) e [publicação por GitHub Actions](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).

**No desktop**

Requer **Ruby 4.0 ou superior** e Ruby2D 1.0. Ruby 3.4 não é compatível.
As dependências estão no `Gemfile`. Dentro da pasta do projeto:

```bash
bundle config set --local path vendor/bundle
bundle install
bundle exec ruby main.rb
```

No **Arch Linux**, instale as bibliotecas e ferramentas de compilação:

```bash
sudo pacman -Syu --needed base-devel git openssl libyaml readline zlib gmp libffi sdl3 sdl3_image sdl3_mixer sdl3_ttf
```

Se `ruby -v` mostrar uma versão inferior a 4.0 (ou o comando não existir),
instale o Ruby do projeto com [rbenv](https://github.com/rbenv/rbenv#installation).
Para uma instalação nova do rbenv:

```bash
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
~/.rbenv/bin/rbenv init
```

Abra outro terminal, entre na pasta do projeto e execute:

```bash
rbenv install -s "$(cat .ruby-version)"
gem install bundler -v 4.0.20 --no-document
bundle config set --local path vendor/bundle
bundle install
bundle exec ruby main.rb
```

O arquivo `.ruby-version` seleciona o Ruby deste projeto automaticamente com rbenv.
O cenário, as fontes e todos os sprites ficam em `assets/`; mantenha essa pasta junto do código.
O jogo pode ser iniciado de outro diretório, usando o caminho completo de `main.rb`.

Para ver o apiário com doze colmeias e melhorias de exemplo:

```bash
bundle exec ruby main.rb --demo
```

A demonstração é jogável e temporária: não lê nem altera seu progresso salvo.
Ela já inclui Ritmo Máximo no nível 2 e AbelhIA no nível 1 para experimentar.
No modo normal, você começa com uma colmeia ou continua seu save anterior.

- Clique no campo para coletar mel e aumentar o ritmo. Cada toque rende **1 mel + 25% da produção passiva por segundo**, antes dos bônus. O ritmo multiplica tanto o clique quanto a produção; clicar em uma colmeia rende mais **50%**. O indicador **TOQUE** mostra o valor atual do clique no campo.
- **Luvas:** cada nível acrescenta 2 de mel ao toque e mais 5 pontos percentuais da produção passiva (25% → 30% → 35%…). Mãos Firmes multiplica todo o ganho do clique. Assim, aumentar a produção também fortalece seus cliques, inclusive os da AbelhIA.
- **Colmeias sem limite:** continue comprando depois da 12ª. Todas produzem mel e contam para Mente-Colmeia, inclusive offline. O cenário mantém 12 espaços; acima disso, cada placa `xN` mostra quantas colmeias aquele grupo representa. Os preços continuam aumentando a cada compra e o save preserva o total.
- Compre colmeias e melhorias na Loja; Bento e as abelhas trabalham automaticamente.
- Clique na abelha dourada quando ela aparecer para ganhar mel extra.
- A aba Legado permite renascer e gastar pólen em melhorias permanentes. Passe o mouse sobre uma melhoria bloqueada para ver os requisitos.
- **Herança:** concede uma colmeia inicial extra por nível ao renascer, até 21 colmeias no nível 20.
- **Ritmo Máximo:** aumenta o teto do multiplicador em +2 por nível: x8 → x10 → x12… O teto atual aparece no topo. O primeiro nível custa 5 de pólen.
- **AbelhIA:** cada nível acrescenta um clique automático por segundo nas colmeias, rendendo mel com o bônus de colmeia e alimentando o ritmo. O primeiro nível custa 6 de pólen. A cadência usa segundos reais e não acelera com o multiplicador.
- Os dois novos perks exigem **Segundo Fôlego nível 1**, que requer **Mãos Firmes nível 2**. Com esses requisitos, um clique automático por segundo repõe mais ritmo do que o decaimento consome. Os perks persistem no renascimento; o ritmo recomeça em x1.
- AbelhIA funciona enquanto o jogo estiver aberto e aparece no campo com seu nome. O modo offline continua calculando apenas a produção passiva normal. Todos os perks têm limite de 20 níveis.
- A janela pode ser redimensionada mantendo a proporção da imagem. `Esc` fecha o jogo.

O save continua em `~/.local/share/extract-me-honey-deluxe/save.json`, com salvamento automático a cada oito segundos e ganhos offline limitados a oito horas. Para usar outro arquivo, configure `HONEY_SAVE_PATH`.

Teste de integração sem abrir uma janela ou alterar o save:

```bash
SDL_AUDIODRIVER=dummy SDL_VIDEODRIVER=offscreen bundle exec ruby main.rb --smoke
```

O teste verifica renderização, compras e saves acima de 12 colmeias, agrupamento visual, cliques proporcionais à produção e ao ritmo, luvas, abas, árvore de melhorias, renascimento, redimensionamento, aumento do teto de ritmo, cadência e alvos da AbelhIA e compatibilidade dos perks com saves antigos. As capturas ficam em `tmp/smoke/`.

Detalhes das artes, prompts e licenças: [assets/ART.md](assets/ART.md).
