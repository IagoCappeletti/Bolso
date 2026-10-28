# Bolso

<p align="center"><img src="Assets/Bolso-icon.png" width="128" alt="Ícone do Bolso"></p>

Histórico da área de transferência e captura de tela para macOS. Fica na barra de menus, guarda os últimos 25 itens copiados e tem um editor para marcar imagens e prints.

Feito para uso pessoal, em Swift, sem Xcode e sem dependências.

## Atalhos

| Tecla | Ação |
| --- | --- |
| ⌘⇧V | Abrir o histórico |
| ⌘⇧2 | Capturar uma área da tela |
| ↑ ↓ e Enter | Escolher e colar |
| ⌘1–⌘9 | Colar o item daquela posição |
| ⌥ + Enter, ⌘número ou clique | Colar como texto puro |
| ⌘E ou clique na foto | Editar a imagem |
| Arrastar a miniatura | Levar para outro app |
| Esc | Fechar |

## Histórico

- Guarda textos (com formatação), imagens e arquivos copiados; itens repetidos sobem para o topo.
- Fica só na memória: o histórico zera quando o app fecha.
- Ignora o que gerenciadores de senha marcam como sigiloso.
- Ao escolher um item, volta para o app anterior e cola sozinho.

## Captura e editor

**⌘⇧2** congela a tela: clique numa janela ou arraste uma área. Até a primeira marcação dá para ajustar pelas alças ou mover pela alça do topo. O editor de imagens do histórico tem as mesmas ferramentas: desenhar, marcador, seta, caixa, círculo, texto (com fundo opcional), números (1, 2, 3…) e desfocar.

- **Copiar** (⌘C) põe a imagem na área de transferência e no histórico.
- **Copiar texto** (⌘⇧C) lê o texto com o OCR do macOS; áreas desfocadas continuam ilegíveis.
- **Salvar** (⌘S) grava um PNG, e a alça ✋ arrasta a imagem para outro app.
- ⌘Z e ⌘⇧Z desfazem e refazem. Esc cancela; se houver marcações, a barra pergunta antes.

## Instalar e atualizar

Precisa do macOS 13 ou mais novo e das Command Line Tools (`xcode-select --install`).

```sh
./build.sh --install
```

Compila, fecha o Bolso aberto, instala em `/Applications` e abre de novo. O mesmo comando atualiza (o histórico zera). Só `./build.sh` gera `dist/Bolso.app` sem instalar.

Na primeira vez, ligue o Bolso em **Ajustes do Sistema → Privacidade e Segurança**:

- **Acessibilidade**, para colar sozinho (sem ela, cole com ⌘V);
- **Gravação da Tela**, para o ⌘⇧2.

Para abrir junto com o Mac, marque **Abrir ao iniciar o Mac** no menu do ícone.

<details>
<summary>Assinatura</summary>

O `build.sh` assina o app com um certificado autoassinado do Acesso às Chaves, para o macOS não pedir as permissões de novo a cada atualização. Em outro Mac, crie um em **Acesso às Chaves → Assistente de Certificado → Criar um Certificado…** (Raiz Autoassinada, Assinatura de Código, depois **Confiar Sempre**) e rode `SIGN_IDENTITY="nome do certificado" ./build.sh`. Sem certificado, use `SIGN_IDENTITY=- ./build.sh`; aí o macOS pede as permissões a cada build.

</details>

## Limites

- Imagens acima de 32 MiB ou 24 milhões de pixels ficam só em miniatura, sem edição. O histórico guarda até 128 MiB de imagens.
- Cópias feitas a menos de 0,5 s uma da outra podem se perder.
- Na primeira abertura de cada versão, o OCR leva cerca de um minuto para ficar pronto.
- Arrastar uma imagem cria um PNG temporário, apagado em 2 minutos. Fora isso, nada vai para o disco sem você salvar.

## Testes

As Command Line Tools não trazem XCTest, então os testes são executáveis e usam áreas de transferência temporárias:

```sh
swift run -c release BolsoChecks                # modelo, imagens, geometria e OCR
swift run -c release Bolso --self-test          # histórico e memória
swift run -c release Bolso --ui-self-test       # painel
swift run -c release Bolso --editor-self-test   # editor
swift run -c release Bolso --capture-self-test  # captura
```
