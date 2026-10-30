# FiveM on Linux — CachyOS / KDE

Assistente visual para preparar **FiveM para GTA V Enhanced** no CachyOS com Steam nativa e Proton. Detecta bibliotecas Steam, inclusive em outros discos, verifica o prefixo correto, instala o WebView2, abre o instalador oficial do FiveM Enhanced e registra um atalho não-Steam.

> **Estado experimental.** Cfx.re não oferece suporte oficial a Linux. O launcher já foi aberto por outros usuários, mas há relatos recentes de falha ao conectar a servidores no Enhanced. Este projeto não contorna anti-cheat e não promete que o multiplayer funcionará.

## Instalar com um comando

Abra o terminal e execute:

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/VitorMartinsAlves/FiveM-on-Linux/main/install.sh | bash
\`\`\`

O instalador pode pedir sua senha para instalar o pacote \`tk\` pelo pacman, caso o Python do sistema não tenha Tkinter. Depois abre o aplicativo visual.

## O que o aplicativo faz

- Procura o GTA V Enhanced (Steam App ID \`3240220\`) nas bibliotecas Steam registradas, inclusive bibliotecas em outro HD.
- Permite escolher manualmente a pasta do jogo.
- Verifica se o prefixo Proton foi criado; se ainda não foi, abre o jogo pela Steam para você iniciar uma vez.
- Instala o WebView2 no prefixo correto e abre o instalador oficial do FiveM Enhanced.
- Detecta Proton/GE-Proton e oferece instalar a versão GE mais recente do projeto oficial.
- Pode registrar o FiveM como jogo não-Steam, preservando os atalhos existentes. A Steam precisa estar totalmente fechada para editar esse arquivo.
- Gera as opções necessárias e deixa copiá-las para as propriedades do GTA V.

## Fluxo recomendado

1. Instale o GTA V Enhanced normalmente pela Steam, mesmo que esteja no HD secundário.
2. Na Steam, force a mesma versão de Proton/GE-Proton para o GTA V Enhanced e para o atalho FiveM.
3. Inicie o GTA V Enhanced pela Steam uma vez, entre no modo história e feche o jogo. Isso cria o prefixo e os dados de primeiro início.
4. Abra o aplicativo e clique em **Preparar FiveM**. Complete a instalação que aparecer na tela.
5. Feche a Steam por completo, use **Registrar atalho no Steam**, reabra a Steam e ative a mesma versão de Proton nas propriedades do atalho.
6. Para o primeiro início, teste o launcher antes de concluir que servidores públicos funcionam.

O aplicativo não modifica os arquivos de instalação do GTA V. Instaladores e arquivos de cache ficam no prefixo Proton do jogo e em \`~/.cache/fivem-linux\`.

## Opções do jogo

O botão **Copiar opções do GTA** copia esta linha para colar em Propriedades → Geral → Opções de inicialização do GTA V Enhanced:

\`\`\`bash
PROTON_USE_XALIA=0 bash -c 'exec "\${@//waitforexitandrun/run}" -- %command%
\`\`\`

A sintaxe é a mesma da configuração experimental de referência. O app também mostra as opções do atalho FiveM.

## Segurança e limites

- Baixa instaladores somente de endpoints oficiais do projeto Cfx.re e da Microsoft.
- A versão GE-Proton é obtida das releases oficiais de GloriousEggroll.
- Não pede sua senha da Rockstar nem armazena credenciais.
- Não inclui DLL modificada nem tenta esconder Wine/Proton de sistemas anti-cheat.
- Você pode cancelar a qualquer momento. Nenhum comando de instalação do jogo é executado como root.
- FiveM Enhanced está em Early Access e o funcionamento sob Linux varia por versão do launcher, Proton e servidor.

## Solução de problemas

- **Jogo não encontrado:** use **Escolher pasta** e selecione a pasta que contém \`GTA5_Enhanced.exe\`.
- **Prefixo ausente:** abra o GTA V Enhanced pela Steam, aguarde entrar no modo história e feche.
- **Janela FiveM preta:** verifique se o WebView2 concluiu a instalação e clique em **Atualizar status**.
- **Steam não lista o atalho:** feche Steam por completo antes de registrar; reabra depois.
- **Launcher abre, mas não conecta:** isso pode ser a incompatibilidade do cliente Enhanced com Linux, não um caminho incorreto do jogo. Consulte os registros e as notas atuais do projeto.

## Desenvolvimento

Aplicação em Python/Tkinter, sem dependências Python de terceiros. Licença MIT para os arquivos deste repositório. FiveM, GTA V, Steam, Proton e WebView2 continuam sob suas respectivas licenças.
