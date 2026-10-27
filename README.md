# Bolso

<p align="center"><img src="Assets/Bolso-icon.png" width="128" alt="Ícone do Bolso"></p>

Histórico da área de transferência para macOS, inspirado no Win + V do Windows. Fica na barra de menus, guarda os últimos 25 itens copiados e abre com **⌘⇧V** perto do cursor para colar qualquer um deles.

Feito para uso pessoal, em Swift + Swift Package Manager, sem Xcode, sem dependências externas e sem App Sandbox.

## O que ele faz

- Roda em segundo plano, sem ícone no Dock, só com um ícone na barra de menus.
- Guarda até 25 itens **somente em memória**: nada é gravado em disco, e o histórico zera quando o app fecha.
- Aceita textos (com formatação RTF), imagens (só uma miniatura de até 256 px) e arquivos copiados no Finder (só a referência).
- Itens repetidos sobem para o topo em vez de duplicar.
- Ignora o que gerenciadores de senha marcam como sigiloso (`org.nspasteboard.ConcealedType`).
- Ao escolher um item, coloca na área de transferência, volta para o app anterior e cola sozinho.
- Prints entram no histórico quando o macOS está configurado para mandá-los à área de transferência (⌘⇧5 → Opções → Salvar em → Área de Transferência).

## Atalhos

| Tecla | Ação |
| --- | --- |
| ⌘⇧V | Abrir/fechar o painel |
| ↑ ↓ | Selecionar |
| Enter ou clique | Colar |
| 1–9 | Colar o item daquela posição |
| Option + Enter/número/clique | Colar como texto puro (arquivos colam o caminho) |
| Digitar | Filtrar (ignora maiúsculas e acentos) |
| Esc | Fechar |

O menu do ícone tem **Abrir Bolso**, **Pausar captura**, **Limpar histórico**, **Abrir ao iniciar o Mac** e **Sair**.

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
2. **Abrir ao iniciar o Mac:** marque no menu do ícone. Se o macOS pedir, aprove em **Ajustes do Sistema → Geral → Itens de Início**.

### Atualizar

O app instalado não se recompila sozinho. Só é preciso rodar `./build.sh` de novo quando o código mudar. Antes de copiar a nova versão para `/Applications`, saia do Bolso pelo menu.

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
- O painel é criado ao abrir e liberado ao fechar. O atalho usa `RegisterEventHotKey` do Carbon, sem monitorar o teclado inteiro.
- Textos de até 1 MiB por item; maiores são ignorados. Arquivos guardam só as URLs (até 1.024 por cópia).
- Sem banco de dados, cache, telemetria ou logs do que você copia.
- Em repouso, cerca de 50 MB de memória e 0% de CPU.

## Limitações

- Imagens coladas do histórico saem na resolução da miniatura, não na original.
- A busca não lê texto dentro de imagens (sem OCR).
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
swift run -c release BolsoChecks           # histórico, busca, tipos e limites
swift run -c release Bolso --self-test     # captura real, pausa, limpeza e liberação de memória
swift run -c release Bolso --ui-self-test  # abre e fecha 5 painéis reais
```

Usam áreas de transferência temporárias, sem tocar no seu clipboard.
