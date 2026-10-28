# Bolso

<p align="center"><img src="Assets/Bolso-icon.png" width="128" alt="Ícone do Bolso"></p>

Histórico da área de transferência para macOS, inspirado no Win + V do Windows. Fica na barra de menus, guarda os últimos 25 itens copiados e abre com **⌘⇧V** perto do cursor para colar qualquer um deles.

Feito para uso pessoal, em Swift + Swift Package Manager, sem Xcode, sem dependências externas e sem App Sandbox.

## O que ele faz

- Roda em segundo plano, sem ícone no Dock, só com um ícone na barra de menus.
- Guarda até 25 itens **somente em memória**: nada é gravado em disco, e o histórico zera quando o app fecha.
- Aceita textos (com formatação RTF), imagens (original para colar/editar e miniatura de até 256 px para a lista) e arquivos copiados no Finder (referência; WebP também guarda uma cópia para edição).
- Itens repetidos sobem para o topo em vez de duplicar.
- Ignora o que gerenciadores de senha marcam como sigiloso (`org.nspasteboard.ConcealedType`).
- Ao escolher um item, coloca na área de transferência, volta para o app anterior e cola sozinho.
- Prints entram no histórico quando o macOS está configurado para mandá-los à área de transferência (⌘⇧5 → Opções → Salvar em → Área de Transferência).

## Atalhos

| Tecla | Ação |
| --- | --- |
| ⌘⇧V | Abrir/fechar o painel |
| ⌘⇧2 | Capturar uma área da tela e marcar no lugar |
| ↑ ↓ | Selecionar |
| Enter ou clique no texto da linha | Colar |
| Clique na foto/lápis ou ⌘E | Editar a imagem selecionada |
| ⌘1–⌘9 | Colar o item daquela posição |
| Option + Enter/⌘número/clique | Colar como texto puro (arquivos colam o caminho) |
| Arrastar a miniatura | Levar a imagem ou o arquivo para outro app (WhatsApp, Slack, Mail, Finder) |
| Esc | Fechar |

O menu do ícone tem **Abrir Bolso**, **Capturar área da tela**, **Pausar captura**, **Limpar histórico**, **Abrir ao iniciar o Mac** e **Sair**.

## Editor de imagens

Clique na miniatura ou no lápis de uma imagem do histórico (ou selecione-a e use **⌘E**). As ferramentas:

| Ferramenta | Uso |
| --- | --- |
| Desenhar | Traço livre; clique simples faz um ponto |
| Marcador | Marca-texto translúcido (use o amarelo); texto escuro por baixo continua legível |
| Seta, Caixa, Círculo | Arraste entre dois pontos; Shift faz um círculo perfeito |
| Texto | Digite no campo da barra e clique (ou arraste) para posicionar; **Fundo** põe o texto numa caixa da cor escolhida |
| Número | Cada clique cria o próximo passo (1, 2, 3…), na cor escolhida |
| Desfocar | Arraste sobre CPF, e-mails ou valores para pixelar; o controle **Intensidade** define o tamanho dos blocos |

Seis cores, espessura/tamanho e tamanho do texto. Ferramenta, cor, espessura e a opção Fundo são lembradas entre um uso e outro; o texto digitado não.

Use **⌘Z / ⌘⇧Z** para desfazer/refazer. As marcações concluídas podem ser desfeitas, mas não movidas individualmente nesta versão.

**Copiar imagem** cria um item no histórico e coloca o PNG na área de transferência; cole com ⌘V. **Salvar cópia…** grava um PNG no local escolhido. A saída mantém as dimensões originais e a transparência. O original permanece no histórico, sujeito aos limites normais. As marcações passam a fazer parte dos pixels na cópia exportada.

O editor fica aberto ao trocar de aplicativo. Enquanto ele estiver aberto, ⌘⇧V traz a janela de volta. Ao fechar com alterações ainda não copiadas ou salvas, o app pede confirmação. Não há salvamento automático em disco. No editor, **⌘C** copia, **⌘⇧C** copia o texto e **⌘S** salva quando o campo de texto não está em edição.

**Copiar texto** reconhece o texto da imagem com o OCR do próprio macOS, sem internet, em português e inglês, e coloca o resultado na área de transferência. Áreas pixeladas continuam ilegíveis também para o OCR. A alça com a mão (✋) arrasta a imagem direto para outro app (WhatsApp, Slack, Mail, Finder).

## Captura de tela

**⌘⇧2** congela todas as telas. Arraste para escolher a área em qualquer uma delas, ou passe o mouse sobre uma janela (ela fica destacada) e clique para capturá-la inteira. Esc cancela. A área continua no mesmo lugar e uma barra flutuante oferece as mesmas ferramentas do editor.

Até a primeira marcação dá para ajustar a área: arraste as alças das bordas e cantos, mova a área inteira pela alça com setas no topo, ou arraste fora dela para escolher outra. Depois de marcar, a área fica fixa (desfaça tudo para ajustar de novo).

**Copiar** (⌘C) coloca o print em resolução total na área de transferência e no histórico; **Copiar texto** (⌘⇧C) copia só o texto reconhecido; **Salvar…** (⌘S) grava um PNG; a alça ✋ arrasta o print para outro app (a tela congelada some durante o arraste para você soltar onde quiser). Todas essas ações fecham a captura; copiar o texto mantém a captura aberta se houver marcações não entregues. **Cancelar** ou Esc fecha; se houver marcações não copiadas, a própria barra pergunta antes (Esc de novo ou **Descartar** confirma). A captura nunca abre diálogos por cima da tela congelada, e Cancelar continua funcionando enquanto o texto é lido. A seleção fica dentro de um monitor; as outras telas voltam ao normal assim que a área é escolhida.

## Instalar

Requisitos: macOS 13 ou mais novo e as Command Line Tools (`xcode-select --install`).

```sh
./build.sh
ditto dist/Bolso.app /Applications/Bolso.app
open /Applications/Bolso.app
```

O `build.sh` compila em release, monta `dist/Bolso.app` com o ícone e sem ícone no Dock (`LSUIElement`), assina e confere a assinatura.

Na primeira vez:

1. **Acessibilidade:** o Bolso pede a permissão ao abrir. Clique em **Abrir Ajustes do Sistema** e ligue o Bolso em **Privacidade e Segurança → Acessibilidade**. Sem ela, o item escolhido vai para a área de transferência e você cola com ⌘V.
2. **Gravação da Tela:** no primeiro ⌘⇧2 o macOS pede a permissão. Ligue o Bolso em **Privacidade e Segurança → Gravação da Tela** e tente de novo; o macOS pode pedir para reabrir o app. Só é necessária para a captura com ⌘⇧2.
3. **Abrir ao iniciar o Mac:** marque no menu do ícone. Se o macOS pedir, aprove em **Ajustes do Sistema → Geral → Itens de Início**.

### Atualizar

O app instalado não se recompila sozinho. Quando o código mudar, rode `./build.sh --install`: ele compila, pede para o Bolso sair (se houver edição pendente, o app pergunta e a instalação é cancelada), copia para `/Applications` e abre de novo. Sem `--install`, só gera `dist/Bolso.app`.

## Assinatura

O app é assinado com um certificado autoassinado do Acesso às Chaves chamado **Gaveta DEV** (nome antigo do projeto). Ele mantém a mesma identidade entre builds, então o macOS não pede Acessibilidade de novo a cada atualização. Não precisa de conta Apple Developer e não serve para distribuir o app para outros Macs.

<details>
<summary>Criar o certificado em outro Mac</summary>

1. Abra o **Acesso às Chaves** e vá em **Acesso às Chaves → Assistente de Certificado → Criar um Certificado…**
2. Nome **Gaveta DEV**, identidade **Raiz Autoassinada**, tipo **Assinatura de Código**, no chaveiro **login**.
3. Abra o certificado, expanda **Confiança** e marque **Assinatura de Código → Confiar Sempre**.
4. Confira com `security find-identity -v -p codesigning`.

Para compilar sem certificado (assinatura ad hoc): `SIGN_IDENTITY=- ./build.sh`. Nesse caso o macOS pode pedir Acessibilidade de novo a cada build.

</details>

## Consumo e privacidade

- A área de transferência é conferida a cada 0,5 s pelo `changeCount`; o conteúdo só é lido quando muda. Pausado, não há timer.
- O painel é criado ao abrir e liberado ao fechar. Os atalhos usam `RegisterEventHotKey` do Carbon, sem monitorar o teclado inteiro.
- O OCR é preparado em segundo plano quando o app abre. Na primeira abertura de cada versão instalada o macOS leva até cerca de um minuto para preparar o modelo; depois ele fica pronto em fração de segundo e ocupa por volta de 15 MB.
- Arrastar uma imagem para outro app (do editor, da captura ou do histórico) grava um PNG temporário numa pasta própria do Bolso; ele é apagado 2 minutos depois (na hora, se o arraste for cancelado) e a pasta é limpa ao abrir o app. Arquivos copiados vão como estão, sem cópia. Fora isso, nada vai para o disco sem você escolher Salvar.
- A captura usa ScreenCaptureKit (macOS 14+; `CGDisplayCreateImage` no 13) só ao apertar ⌘⇧2, sem gravação contínua. As imagens das telas ficam em memória e são liberadas ao copiar, salvar ou cancelar.
- Textos de até 1 MiB por item; maiores são ignorados. Arquivos guardam só as URLs (até 1.024 por cópia).
- Sem banco de dados, cache, telemetria ou logs do que você copia.
- O histórico limita os dados de imagens a 128 MiB; ao atingir o limite, remove as imagens mais antigas. A imagem decodificada e os buffers do editor consomem memória adicional enquanto a janela está aberta.

## Limitações

- Imagens acima de 32 MiB ou 24 milhões de pixels ficam somente em miniatura, sem edição.
- O editor aceita PNG, TIFF e WebP copiados como imagem. Um arquivo WebP copiado no Finder também ganha miniatura e edição (até 32 MiB); colar a linha continua colando o arquivo. Outros formatos de arquivo e seleções de vários arquivos continuam como referências. WebP animado abre apenas o primeiro quadro e a saída é PNG estático.
- Cópias feitas em menos de 0,5 s uma da outra podem se perder.
- Senhas sem a marca `ConcealedType` não são reconhecidas.

## Estrutura

```
Sources/BolsoCore/     modelo testável: Clip (leitura/escrita da área de transferência) e History
Sources/Bolso/         app: barra de menus, atalho, painel SwiftUI e colagem
Tests/BolsoCoreTests/  verificações executáveis (BolsoChecks)
Assets/                ícone e script que gera o .icns
build.sh               compila, empacota e assina
```

## Testes

As Command Line Tools não trazem XCTest, então as verificações são executáveis com `precondition`:

```sh
swift run -c release BolsoChecks           # histórico, tipos e limites
swift run -c release Bolso --self-test     # captura real, pausa, limpeza e liberação de memória
swift run -c release Bolso --ui-self-test  # abre e fecha 5 painéis reais, atalhos ⌘1–9, arrastar do histórico
swift run -c release Bolso --editor-self-test # editor, cópia e liberação de 5 janelas
swift run -c release Bolso --capture-self-test # seleção, janela, alças, arraste, OCR, cópia e liberação; captura real se houver permissão e a tela estiver desbloqueada
```

Usam áreas de transferência temporárias, sem tocar no seu clipboard.
