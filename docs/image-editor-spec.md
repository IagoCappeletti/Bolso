# Editor de imagens do Bolso

Status: primeira versão implementada em SwiftUI/AppKit. A simulação de referência está em [Prototypes/editor.html](../Prototypes/editor.html). Validação: checks de modelo/renderização, clipboard, painel e ciclo de vida do editor; o app é gerado em `dist/Bolso.app`.

## Objetivo e referência visual

Permitir clicar numa imagem do histórico, abrir uma janela e desenhar sobre ela, como num Paint simples. O resultado pode ser copiado ou salvo como PNG, preservando o item original.

Usar a disposição da simulação: cabeçalho com ações, barra horizontal de ferramentas, imagem central sobre fundo neutro e controles de desfazer/refazer no rodapé. Implementar com SwiftUI e AppKit, respeitando aparência clara/escura do macOS, sem navegador embutido ou dependências externas. Não haverá a página inicial nem a paisagem de exemplo da simulação dentro do app.

## Fluxo de uso

1. O usuário abre o Bolso com ⌘⇧V.
2. Clica na miniatura de uma imagem ou no botão “Editar” da linha.
3. O painel do histórico fecha e a janela “Editar imagem” abre com a imagem ajustada à área disponível.
4. O usuário escolhe a ferramenta, a cor e a espessura e faz as marcações.
5. Escolhe “Copiar imagem” ou “Salvar cópia…”. A janela permanece aberta e apresenta confirmação da ação concluída.
6. Fecha a janela quando terminar.

Separar os alvos da linha: miniatura e botão Editar abrem o editor; o restante da linha continua colando. Evitar botão dentro de botão ou propagação de clique que também execute a colagem. Exibir ajuda “Editar imagem” na miniatura e identificar a ação de colagem no restante da linha.

Enter e números 1–9 continuam colando o item selecionado. Adicionar ⌘E para editar uma imagem selecionada; desabilitar para outros tipos. Option continua com o comportamento atual de texto puro e não se aplica à edição. Textos e referências de arquivos do Finder mantêm a colagem existente. Um único arquivo WebP recebe uma cópia em memória para edição, dentro dos mesmos limites; outros arquivos permanecem como referências. WebP também é aceito diretamente no clipboard (UTI ou MIME). A edição usa o primeiro quadro e exporta PNG estático.

## Ferramentas da primeira versão

| Ferramenta | Interação e resultado |
| --- | --- |
| Desenhar | Arrastar cria um traço contínuo; clique simples cria um ponto. |
| Seta | Arrastar define origem e ponta; prévia durante o gesto. |
| Caixa | Arrastar entre dois cantos cria um retângulo sem preenchimento. |
| Círculo | Arrastar define a área de uma elipse sem preenchimento; Shift restringe a círculo. |
| Texto | Digitar no campo da barra e clicar na imagem para posicionar; tamanho independente da espessura do traço. |

Oferecer vermelho, amarelo, roxo, verde, branco e preto, com nomes acessíveis; vermelho selecionado inicialmente. Espessura de 2 a 16 pixels da imagem, padrão 5. Texto com fonte do sistema, tamanho de 12 a 96 pixels, padrão 28. Cor e espessura afetam novas marcações; não alteram as anteriores.

Cada gesto concluído ou texto inserido constitui uma operação. Desfazer (⌘Z) e refazer (⌘⇧Z) atuam nas marcações; uma nova operação invalida a pilha de refazer. Enquanto um campo de texto estiver em edição, os atalhos pertencem ao campo. Texto vazio não cria marcação. Texto desta versão é de uma linha, sem caixa de fundo.

Escape cancela o gesto em andamento ou a edição de texto; fora desses contextos, solicita fechar a janela. Gestos começam somente dentro da imagem e ficam recortados aos seus limites. Caixas, elipses e setas de tamanho zero são descartadas. Ao perder foco durante um gesto, cancelar a marcação incompleta.

Selecionar, mover ou redimensionar marcações já concluídas, borracha, recorte, rotação, zoom manual, OCR, desfoque e camadas ficam fora desta versão. Para corrigir uma marcação, usar desfazer e desenhá-la novamente.

## Janela, foco e fechamento

Janela nativa redimensionável, tamanho inicial aproximado de 1.040 × 760 pontos, limitado à área útil da tela. A barra deve se adaptar à largura disponível. A imagem mantém a proporção e ocupa a maior área possível; mostrar suas dimensões em pixels. Transparência aparece sobre um padrão quadriculado discreto.

Manter apenas uma sessão do editor por vez. Enquanto houver editor aberto, ⌘⇧V traz essa janela para frente. Trocar de aplicativo não fecha o editor. Fechar o histórico para editar não deve reativar o aplicativo anterior nem disparar colagem.

Após abrir, fechar sem alterações não exige confirmação. Com alterações ainda não copiadas ou salvas, apresentar “Descartar alterações?” com “Continuar editando” e “Descartar”. Cancelar o seletor de arquivo ou falhar ao exportar não marca o documento como salvo. Copiar ou salvar com sucesso registra a revisão atual como entregue; novas alterações voltam a exigir confirmação. O mesmo cuidado se aplica a sair do Bolso com uma edição pendente.

O foco retorna ao aplicativo anterior ao fechar o editor somente se o Bolso ainda estiver ativo. Liberar janela, imagem decodificada, modelo, histórico de comandos e observadores ao encerrar a sessão.

## Resolução e memória

Hoje `Clip.Payload.image(Data)` contém somente um PNG de até 256 pixels. É necessário mudar esse modelo antes da integração do editor; ampliar essa miniatura não recupera detalhes.

Introduzir `ImagePayload` com dados originais codificados, formato, dimensões orientadas e miniatura PNG de até 256 pixels. A lista usa apenas a miniatura. A sessão decodifica a imagem original sob demanda. Respeitar a orientação da imagem na exibição e na exportação, inclusive imagens com dimensões Retina: dimensões de saída são pixels, não pontos da janela.

Limites iniciais propostos, centralizados em constantes:

- Até 32 MiB de dados codificados por imagem e até 24 milhões de pixels após considerar a orientação.
- Até 128 MiB de dados de imagem retidos pelo histórico, contando originais e miniaturas, além do limite atual de 25 itens.
- Ao exceder o orçamento do histórico, remover os itens de imagem mais antigos até ficar dentro do limite; manter a ordem dos demais itens.
- Uma imagem acima do limite individual mantém apenas a miniatura e recebe o rótulo “Somente miniatura”; desabilitar edição e explicar o limite na ajuda. A colagem continua disponível na resolução da miniatura.
- Uma sessão aberta mantém referência ao seu próprio conteúdo mesmo que o histórico seja limpo ou o item removido. Essa retenção adicional deve ser considerada nas medições de memória.

Inspecionar metadados e limites antes de decodificar o bitmap. Os orçamentos de dados comprimidos não são um teto de RAM: buffers de decodificação e exportação também consomem memória. Executar decodificação e exportação fora da thread principal; publicar estado na thread principal e evitar trabalhos simultâneos desnecessários. Mostrar estado de carregamento e falha recuperável, mantendo o histórico utilizável.

Guardar originais apenas em memória, sem cache em disco. A única gravação de imagem feita pelo recurso ocorre quando o usuário escolhe “Salvar cópia…”. Manter a exclusão atual de conteúdo marcado como sigiloso. Não há migração em disco, pois o histórico atual é volátil.

## Modelo de edição e renderização

Criar um `ImageEditorDocument` com imagem base imutável, dimensões em pixels, lista ordenada de `Annotation`, pilha de refazer e revisão da última saída bem-sucedida.

`Annotation` contém identificador, tipo, cor, espessura e geometria: lista de pontos para desenho livre; origem/destino para seta; retângulo para caixa/elipse; posição, conteúdo e tamanho de fonte para texto. Não armazenar uma cópia do bitmap a cada gesto. A operação em andamento permanece separada da lista confirmada.

Usar coordenadas em pixels com origem no canto superior esquerdo. Converter a posição do ponteiro a partir do retângulo real ocupado pela imagem, descontando as margens do ajuste proporcional. Redimensionar a janela não altera as coordenadas. Normalizar retângulos para aceitar arrasto em qualquer direção.

Um renderizador compartilhado desenha a base e as anotações tanto na prévia quanto na exportação, para evitar diferenças de posição, espessura, ponta de seta e texto. Corrigir explicitamente a orientação dos eixos entre AppKit, Core Graphics e texto. Exportar em PNG nas dimensões orientadas originais, preservando transparência; não exportar o fundo quadriculado nem elementos da interface. Normalizar a saída em sRGB para previsibilidade desta versão.

## Copiar e salvar

**Copiar imagem:** renderizar PNG, criar um novo `Clip` por uma fábrica que aceita imagem renderizada e enviá-lo a `ClipboardStore.write`. Essa ação atualiza `lastChange`, insere o resultado no histórico e evita recaptura duplicada pelo timer. Não disparar colagem automática. Preservar o original, sujeito apenas às regras normais de deduplicação e limites do histórico. A operação explícita funciona mesmo com captura pausada.

**Salvar cópia…:** abrir `NSSavePanel`, sugerir `Bolso-editado.png`, limitar saída a PNG e gravar de forma atômica no destino escolhido. A confirmação nativa trata substituição de arquivo existente. Não modificar o histórico nem a área de transferência nessa ação.

Desabilitar saídas concorrentes durante renderização. Em caso de erro, preservar a sessão e mostrar uma mensagem com possibilidade de tentar novamente. Só apresentar sucesso após confirmar escrita. A imagem salva/copied é achatada: reabri-la permite novas marcações, mas as anteriores já fazem parte dos pixels. Não há formato de projeto editável nesta versão.

Ao colar imagens com original retido, `Clip.write` usa a representação em resolução original. Para itens apenas com miniatura, usa o PNG reduzido. Ajustar rótulos e mensagens atuais que afirmam que toda imagem é miniatura. A identidade de imagens originais continua baseada no conteúdo codificado; imagens renderizadas usam o PNG final, sem deduplicar pela miniatura.

## Organização proposta do código

| Arquivo / componente | Responsabilidade |
| --- | --- |
| `Sources/BolsoCore/Clip.swift` | Integrar `ImagePayload`, leitura, escrita e fábrica de imagem renderizada. |
| `Sources/BolsoCore/ImagePayload.swift` (novo) | Metadados, validação de limites, original e miniatura. |
| `Sources/BolsoCore/ImageEditorDocument.swift` (novo) | Anotações, revisões, comandos de desfazer/refazer e geometria testável. |
| `Sources/BolsoCore/ImageAnnotationRenderer.swift` (novo) | Renderização comum e geração de PNG. |
| `Sources/Bolso/ClipboardStore.swift` | Aplicar orçamento de imagens e reutilizar a escrita explícita para copiar o resultado. |
| `Sources/Bolso/HistoryPanel.swift` | Alvos separados de editar/colar, ação `onEdit`, ⌘E e motivo de fechamento. |
| `Sources/Bolso/ImageEditorSession.swift` (novo) | Ciclo de vida da janela, carregamento, exportação, confirmação e retorno de foco. |
| `Sources/Bolso/ImageEditorView.swift` (novo) | Barra de ferramentas, controles, mensagens e acessibilidade. |
| `Sources/Bolso/ImageEditorCanvas.swift` (novo) | `NSView` integrado ao SwiftUI, ponteiro, prévia e transformação de coordenadas. |
| `Sources/Bolso/main.swift` | Reter a sessão, transferir foco do histórico e tratar atalho global/saída do app. |

O fechamento atual de `PanelSession` chama `onClose`, que reativa o aplicativo anterior. Introduzir um motivo explícito de fechamento, como `dismiss`, `paste` e `edit`, e definir o destino do foco no coordenador. Criar/reter a sessão do editor antes de liberar a sessão do histórico. O editor usa janela normal e não herda o fechamento automático ao perder foco do painel atual.

## Ordem de implementação

1. Evoluir armazenamento de imagens e orçamento de memória; atualizar verificações de leitura, escrita e histórico.
2. Implementar documento, geometria, desfazer/refazer e renderizador, verificando resultados sem depender da interface.
3. Construir janela nativa e ferramentas seguindo a simulação.
4. Integrar clique, ⌘E, transição de foco e sessão única ao histórico.
5. Implementar copiar, salvar, estados de erro e proteção contra descarte acidental.
6. Executar verificações, testar visualmente e atualizar README com novos gestos, limites e consumo medido.

## Validação e critérios de aceite

Usar os executáveis de verificações já existentes no projeto, com novas verificações significativas de modelo e renderização, sem introduzir uma dependência de XCTest.

- Clicar na miniatura abre o editor exatamente uma vez e não cola; Enter, números e clique no restante da linha continuam colando.
- Texto e arquivos mantêm o comportamento anterior; ⌘E só atua em imagens editáveis.
- Uma imagem 3.000 × 2.000 gera saída 3.000 × 2.000, com marcações nas mesmas posições após redimensionar a janela.
- Exercitar imagens verticais, horizontais, transparentes, Retina e com orientação embutida; comparar posição e cor de amostras do resultado, com tolerância de antialiasing.
- Desenho, ponto, seta em qualquer direção, retângulo com arrasto invertido, elipse, círculo e texto com acentos funcionam; desfazer/refazer preserva ordem e limpa refazer após nova ação.
- Exportação mantém transparência e não inclui fundo, barras ou bordas da interface.
- Copiar em uma pasteboard temporária insere um único resultado, atualiza o controle de captura e mantém a resolução; testar também captura pausada.
- Cancelar salvamento e simular erro de escrita não descarta a edição nem apresenta sucesso.
- Validar os limites individuais e agregados, remoção dos mais antigos e manutenção do documento aberto após limpar o histórico.
- Fechar, trocar de app, abrir seletor de cores/arquivo, usar ⌘⇧V durante edição e sair do Bolso não provocam perda inesperada de alterações ou colagem no aplicativo errado.
- Conferir rótulos de acessibilidade, foco de teclado, aparência clara/escura e janela em telas menores. As ações devem ter nomes, sem depender apenas de cor ou ícone.
- Abrir e fechar repetidamente uma imagem grande e verificar que sessões e buffers são liberados, sem crescimento acumulado de memória.

Executar `swift run -c release BolsoChecks`, `swift run -c release Bolso --self-test` e `swift run -c release Bolso --ui-self-test`, ampliando os checks pertinentes ao novo fluxo. Os testes automatizados de clipboard devem continuar usando pasteboards temporárias. Fazer uma rodada manual da edição, exportação e foco no app empacotado antes de considerar a entrega pronta.
