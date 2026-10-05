# Extract Me Honey — Apiário Vivo

Jogo incremental em Ruby2D com cenário e sprites ilustrados a partir de `image.png`.

```bash
ruby main.rb
```

Requer Ruby e Ruby2D 1.0. As dependências estão no `Gemfile` (`bundle install`).
O cenário, as fontes e todos os sprites ficam em `assets/`; mantenha essa pasta junto do código.
O jogo pode ser iniciado de outro diretório, usando o caminho completo de `main.rb`.

Para ver o apiário com doze colmeias e melhorias de exemplo:

```bash
ruby main.rb --demo
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
SDL_AUDIODRIVER=dummy SDL_VIDEODRIVER=offscreen ruby main.rb --smoke
```

O teste verifica renderização, compras e saves acima de 12 colmeias, agrupamento visual, cliques proporcionais à produção e ao ritmo, luvas, abas, árvore de melhorias, renascimento, redimensionamento, aumento do teto de ritmo, cadência e alvos da AbelhIA e compatibilidade dos perks com saves antigos. As capturas ficam em `tmp/smoke/`.

Detalhes das artes, prompts e licenças: [assets/ART.md](assets/ART.md).
